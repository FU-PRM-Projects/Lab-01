import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

import 'package:lab_05/data/models/app_settings.dart';

/// Transcribes rendered PDF pages to Markdown with a multimodal OpenRouter model.
/// Uses the same retry policy as [EmbeddingClient].
class PageTranscriptionService {
  PageTranscriptionService({
    required this.settings,
    this.timeout = const Duration(minutes: 3),
    this.maxTokens = 8192,
    http.Client? client,
  }) : _client = RetryClient(
         client ?? http.Client(),
         retries: 2,
         when: (response) =>
             response.statusCode == 429 || response.statusCode >= 500,
       );

  final AppSettings settings;
  final Duration timeout;

  /// Output token cap per page (avoids 402s from reserving the model's full limit).
  final int maxTokens;
  final http.Client _client;
  final _abort = Completer<void>();

  /// Models cannot reliably return an empty message, so they answer with this
  /// marker for blank pages and [transcribePage] turns it into an empty string.
  static const blankPageMarker = '[[BLANK_PAGE]]';

  static const prompt =
      'Transcribe this page of a research paper into Markdown.\n'
      'Rules:\n'
      '- Output only the transcription. No introduction, explanation or closing remarks.\n'
      '- Do not describe the layout, images or formatting.\n'
      '- Keep section headings as Markdown headings (#, ##, ###), including their '
      'original numbering, e.g. "## 3.2 Threat Model".\n'
      '- Transcribe multi-column pages in reading order: finish the left column '
      'before starting the right one.\n'
      '- Keep tables as Markdown tables and render formulas as LaTeX.\n'
      '- Transcribe bibliography entries one per line, keeping their markers, e.g. "[12] ...".\n'
      '- Drop running headers, footers and standalone page numbers.\n'
      '- Keep the original language and reading order. Do not translate, summarize or fix the text.\n'
      '- Do not wrap the output in a code block.\n'
      '- If the page has no readable text, output exactly: $blankPageMarker';

  String get endpoint => settings.chatCompletionsUrl;

  /// Returns the page text as Markdown, or an empty string for a blank page.
  Future<String> transcribePage(
    Uint8List pngBytes, {
    required String modelId,
  }) async {
    if (_abort.isCompleted) {
      throw StateError('Page transcription cancelled');
    }
    final apiKey = settings.openRouterApiKey.trim();
    if (apiKey.isEmpty) {
      throw StateError(
        'OpenRouter API key is required to transcribe PDF pages.',
      );
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
            'max_tokens': maxTokens,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': prompt},
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
        'OpenRouter transcription error (${response.statusCode}): '
        '${openRouterErrorMessage(body)}',
      );
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    final error = json['error'];
    if (error != null) {
      throw HttpException(
        'OpenRouter transcription error: '
        '${openRouterErrorMessage(jsonEncode({'error': error}))}',
      );
    }
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const FormatException('Transcription response has no choices');
    }
    final choice = choices.first as Map<String, dynamic>;
    if (choice['finish_reason'] == 'length') {
      debugPrint(
        '[transcribe] output hit max_tokens=$maxTokens; '
        'page text may be truncated',
      );
    }
    return clean(openRouterMessageText(choice));
  }

  static final _fence = RegExp(
    r'^```(?:markdown|md)?[ \t]*\n([\s\S]*?)\n?```$',
  );
  static final _strayPageMarker = RegExp(r'<!--\s*PAGE\s+\d+\s*-->');

  static String clean(String raw) {
    var text = raw.trim();
    final match = _fence.firstMatch(text);
    if (match != null) text = match.group(1)!.trim();
    if (text == blankPageMarker) return '';
    // A page marker left in the body would be read as a real page boundary
    // when the transcript is assembled for the instruct model.
    return text.replaceAll(_strayPageMarker, '').trim();
  }

  void close() {
    if (_abort.isCompleted) return;
    _abort.complete();
    _client.close();
  }
}

/// Flattens an OpenRouter choice's message content, which is either a string
/// or a list of typed parts, into plain text.
String openRouterMessageText(Map<String, dynamic> choice) {
  final message = choice['message'] as Map<String, dynamic>?;
  final content = message?['content'];
  return switch (content) {
    String s => s,
    List<dynamic> parts =>
      parts
          .whereType<Map<String, dynamic>>()
          .map((part) => part['text'])
          .whereType<String>()
          .join(),
    _ => '',
  };
}

/// Keeps only `error.message` from an OpenRouter error body, capped in length,
/// so the snackbar stays readable.
String openRouterErrorMessage(String body) {
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
