import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

import 'package:lab_05/data/models/app_settings.dart';

/// OCR for one rendered PDF page using a vision chat model on OpenRouter.
///
/// HTTP setup and error handling follow [EmbeddingClient]: same retry policy
/// (429 and 5xx, 2 retries), abortable requests, and [HttpException] with the
/// status code and body for non-200 responses. Base URL and API key come from
/// [AppSettings].
class VisionOcrService {
  VisionOcrService({
    required this.settings,
    this.timeout = const Duration(minutes: 3),
    this.maxTokens = 4096,
    http.Client? client,
  }) : _client = RetryClient(
         client ?? http.Client(),
         retries: 2,
         when: (response) =>
             response.statusCode == 429 || response.statusCode >= 500,
       );

  final AppSettings settings;
  final Duration timeout;

  /// Output cap per page. Without it OpenRouter reserves the model's full
  /// output limit (65k-131k tokens) and rejects the call with 402 when the
  /// account balance cannot cover that reservation. A dense page of Markdown
  /// is typically well under this.
  final int maxTokens;
  final http.Client _client;
  final _abort = Completer<void>();

  /// Models cannot reliably return an empty message, so they answer with this
  /// marker for blank pages and [ocrPage] turns it into an empty string.
  static const blankPageMarker = '[[BLANK_PAGE]]';

  static const _prompt =
      'Transcribe all text on this scanned document page into Markdown.\n'
      'Rules:\n'
      '- Output only the transcription. No introduction, explanation or closing remarks.\n'
      '- Do not describe the layout, images or formatting.\n'
      '- Keep headings as Markdown headings (#, ##, ###) and tables as Markdown tables.\n'
      '- Keep the original language and reading order. Do not translate, summarize or fix the text.\n'
      '- Do not wrap the output in a code block.\n'
      '- If the page has no readable text, output exactly: $blankPageMarker';

  String get endpoint => settings.chatCompletionsUrl;

  /// Returns the page text as Markdown, or an empty string for a blank page.
  Future<String> ocrPage(Uint8List pngBytes, {required String modelId}) async {
    if (_abort.isCompleted) throw StateError('OCR request cancelled');
    final request =
        http.AbortableRequest(
            'POST',
            Uri.parse(endpoint),
            abortTrigger: _abort.future,
          )
          ..headers.addAll({
            'Authorization': 'Bearer ${settings.openRouterApiKey}',
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode({
            'model': modelId,
            'temperature': 0,
            'max_tokens': maxTokens,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': _prompt},
                  {
                    'type': 'image_url',
                    'image_url': {
                      'url': 'data:image/png;base64,${base64Encode(pngBytes)}',
                    },
                  },
                ],
              },
            ],
          });

    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed).timeout(timeout);
    // Decode as UTF-8 explicitly: Response.body falls back to latin1 when the
    // server omits the charset, which would corrupt non-ASCII text.
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      throw HttpException(
        'OpenRouter OCR error (${response.statusCode}): ${_errorMessage(body)}',
      );
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    final error = json['error'];
    if (error != null) {
      throw HttpException(
        'OpenRouter OCR error: ${_errorMessage(jsonEncode({'error': error}))}',
      );
    }
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const FormatException('OCR response has no choices');
    }
    final choice = choices.first as Map<String, dynamic>;
    if (choice['finish_reason'] == 'length') {
      debugPrint(
        '[ocr] output hit max_tokens=$maxTokens; page text may be truncated',
      );
    }
    final message = choice['message'] as Map<String, dynamic>?;
    final content = message?['content'];
    final text = switch (content) {
      String s => s,
      List<dynamic> parts =>
        parts
            .whereType<Map<String, dynamic>>()
            .map((part) => part['text'])
            .whereType<String>()
            .join(),
      _ => '',
    };
    return _clean(text);
  }

  /// Keeps only `error.message` from an OpenRouter error body, capped in
  /// length, so the snackbar stays readable.
  static String _errorMessage(String body) {
    var message = body;
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        final error = json['error'];
        if (error is Map<String, dynamic> && error['message'] is String) {
          message = error['message'] as String;
        }
      }
    } on FormatException {
      // Not JSON: fall back to the raw body.
    }
    const maxLength = 300;
    return message.length > maxLength
        ? '${message.substring(0, maxLength)}...'
        : message;
  }

  static final _fence = RegExp(r'^```(?:markdown|md)?[ \t]*\n([\s\S]*?)\n?```$');

  static String _clean(String raw) {
    var text = raw.trim();
    final match = _fence.firstMatch(text);
    if (match != null) text = match.group(1)!.trim();
    if (text == blankPageMarker) return '';
    return text;
  }

  void close() {
    if (_abort.isCompleted) return;
    _abort.complete();
    _client.close();
  }
}
