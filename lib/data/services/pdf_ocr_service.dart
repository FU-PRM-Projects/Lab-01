import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

import 'package:lab_05/data/models/app_settings.dart';
import 'package:lab_05/data/services/page_transcription_service.dart';

/// One image mistral-ocr lifted out of the PDF.
class OcrFigure {
  /// Placeholder name as it appears in the page Markdown, e.g. `img-0.jpeg`.
  final String name;

  /// 1-based page the placeholder was found on, or 0 when no page referenced
  /// it (the parser then leaves it unplaced rather than guessing).
  final int page;

  /// Decoded image bytes, usually JPEG.
  final Uint8List bytes;

  /// Media type from the data URL, e.g. `image/jpeg`.
  final String mediaType;

  const OcrFigure({
    required this.name,
    required this.page,
    required this.bytes,
    required this.mediaType,
  });

  bool get isPlaced => page > 0;
}

/// What one OCR pass recovered from a PDF.
class OcrResult {
  /// Page Markdown in document order; index 0 is page 1.
  final List<String> pages;

  /// Images extracted from the document.
  final List<OcrFigure> figures;

  /// OpenRouter's content hash for the parsed file. Sending the annotation
  /// back on a later request skips re-parsing (and re-billing) the same PDF.
  final String hash;

  const OcrResult({
    required this.pages,
    required this.figures,
    required this.hash,
  });

  int get pageCount => pages.length;

  bool get isEmpty => pages.every((page) => page.trim().isEmpty);
}

/// Parses a whole PDF in one OpenRouter request using the `file-parser`
/// plugin.
///
/// This replaces rendering and transcribing every page separately: the PDF
/// goes up once as base64 and comes back as per-page Markdown. For an N-page
/// paper that is one request instead of N, which is where nearly all of the
/// import time was going.
///
/// The PDF handed in has already had its figures lifted out natively, so what
/// goes over the wire is text-only and a fraction of the original size. Any
/// image the native pass could not decode is still in there, and mistral-ocr
/// returns up to [maxExtractedImages] of those — [OcrResult.figures] carries
/// them so those figures are not lost.
///
/// The parsed document arrives in `message.annotations`, not in the assistant
/// message — the model itself is only along for the ride, so it is asked for a
/// single token and its reply is discarded.
class PdfOcrService {
  PdfOcrService({
    required this.settings,
    this.engine = 'mistral-ocr',
    this.timeout = const Duration(minutes: 10),
    http.Client? client,
  }) : _client = RetryClient(
         client ?? http.Client(),
         retries: 2,
         when: (response) =>
             response.statusCode == 429 || response.statusCode >= 500,
       );

  final AppSettings settings;

  /// `mistral-ocr` handles scanned and image-heavy papers; `cloudflare-ai` is
  /// free but markdown-only; `native` bills the PDF as model input tokens.
  final String engine;

  final Duration timeout;
  final http.Client _client;
  final _abort = Completer<void>();

  /// Mistral OCR extracts at most this many images per document; text is
  /// always returned in full. Figures are pulled out natively before upload
  /// precisely so this ceiling never applies to them — it only bounds the
  /// leftovers the native pass could not decode.
  static const maxExtractedImages = 8;

  String get endpoint => settings.chatCompletionsUrl;

  /// Runs [pdfBytes] through the parser and returns its pages and any figures
  /// the native strip pass had to leave behind.
  Future<OcrResult> parse(Uint8List pdfBytes, {required String modelId}) async {
    if (_abort.isCompleted) {
      throw StateError('PDF parsing cancelled');
    }
    final apiKey = settings.openRouterApiKey.trim();
    if (apiKey.isEmpty) {
      throw StateError('OpenRouter API key is required to parse PDFs.');
    }

    final request =
        http.AbortableRequest(
            'POST',
            Uri.parse(endpoint),
            abortTrigger: _abort.future,
          )
          ..headers.addAll({
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode({
            'model': modelId,
            'temperature': 0,
            // The reply is discarded; only the file annotation is read.
            'max_tokens': 16,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': 'Reply with OK.'},
                  {
                    'type': 'file',
                    'file': {
                      'filename': 'document.pdf',
                      'file_data':
                          'data:application/pdf;base64,${base64Encode(pdfBytes)}',
                    },
                  },
                ],
              },
            ],
            'plugins': [
              {
                'id': 'file-parser',
                'pdf': {'engine': engine},
              },
            ],
          });

    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed).timeout(timeout);
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      throw HttpException(
        'OpenRouter PDF parsing error (${response.statusCode}): '
        '${openRouterErrorMessage(body)}',
      );
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    final error = json['error'];
    if (error != null) {
      throw HttpException(
        'OpenRouter PDF parsing error: '
        '${openRouterErrorMessage(jsonEncode({'error': error}))}',
      );
    }

    final result = parseAnnotations(json);
    debugPrint(
      '[ocr] $engine: ${result.pageCount} pages, '
      '${(pdfBytes.lengthInBytes / 1024).round()}KB uploaded, '
      '${result.figures.length} undecodable figures recovered',
    );
    return result;
  }

  /// Pulls the parsed document out of a chat completion response.
  ///
  /// The annotation's `content` is a flat list: a `<file name="...">` opener,
  /// one text part per page in document order, the extracted images, and a
  /// `</file>` closer. Images arrive after the text rather than beside the
  /// page they came from, so each one is placed by looking for its
  /// `![img-N.jpeg](img-N.jpeg)` placeholder in the page Markdown.
  @visibleForTesting
  static OcrResult parseAnnotations(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const FormatException('PDF parsing response has no choices');
    }
    final message =
        (choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>?;
    final annotations = message?['annotations'] as List<dynamic>?;
    final fileAnnotation = annotations
        ?.whereType<Map<String, dynamic>>()
        .where((a) => a['type'] == 'file')
        .map((a) => a['file'])
        .whereType<Map<String, dynamic>>()
        .firstOrNull;

    if (fileAnnotation == null) {
      throw const FormatException(
        'PDF parsing response carried no file annotation. The file-parser '
        'plugin may not have run.',
      );
    }

    final parts = (fileAnnotation['content'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    final pages = <String>[];
    final images = <({String mediaType, Uint8List bytes})>[];

    for (final part in parts) {
      switch (part['type']) {
        case 'text':
          final text = part['text'] as String? ?? '';
          // Skip the <file ...> / </file> envelope; everything else is a page.
          if (_envelope.hasMatch(text.trim())) continue;
          pages.add(text);
        case 'image_url':
          final url =
              (part['image_url'] as Map<String, dynamic>?)?['url'] as String?;
          final decoded = _decodeDataUrl(url);
          if (decoded != null) images.add(decoded);
      }
    }

    if (pages.isEmpty) {
      throw const FormatException('PDF parsing returned no page content.');
    }

    final figures = <OcrFigure>[];
    for (var i = 0; i < images.length; i++) {
      final name = _figureName(pages, i);
      figures.add(
        OcrFigure(
          name: name.label,
          page: name.page,
          bytes: images[i].bytes,
          mediaType: images[i].mediaType,
        ),
      );
    }

    return OcrResult(
      pages: pages,
      figures: figures,
      hash: fileAnnotation['hash'] as String? ?? '',
    );
  }

  static final _envelope = RegExp(r'^</?file\b[^>]*>$');

  /// Finds the page whose Markdown references the [index]-th extracted image.
  ///
  /// The parser names them `img-0`, `img-1`, ... in the order they are
  /// returned, so the index doubles as the placeholder number. The extension
  /// is matched loosely in case the parser emits png for some images.
  static ({String label, int page}) _figureName(List<String> pages, int index) {
    final pattern = RegExp(
      r'!\[[^\]]*\]\(\s*(img-' + index.toString() + r'\.\w+)\s*\)',
    );
    for (var i = 0; i < pages.length; i++) {
      final match = pattern.firstMatch(pages[i]);
      if (match != null) {
        return (label: match.group(1)!, page: i + 1);
      }
    }
    return (label: 'img-$index', page: 0);
  }

  static ({String mediaType, Uint8List bytes})? _decodeDataUrl(String? url) {
    if (url == null) return null;
    final comma = url.indexOf(',');
    if (comma < 0 || !url.startsWith('data:')) return null;
    final header = url.substring(5, comma);
    if (!header.contains('base64')) return null;
    final mediaType = header.split(';').first;
    try {
      return (
        mediaType: mediaType.isEmpty ? 'image/jpeg' : mediaType,
        bytes: base64Decode(url.substring(comma + 1)),
      );
    } on FormatException {
      return null;
    }
  }

  void close() {
    if (_abort.isCompleted) return;
    _abort.complete();
    _client.close();
  }
}
