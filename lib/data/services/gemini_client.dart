import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

/// One turn of a Gemini conversation ('user', 'model', or 'function').
class GeminiContent {
  GeminiContent({required this.role, required this.parts});

  final String role;
  final List<Map<String, dynamic>> parts;

  Map<String, dynamic> toJson() => {'role': role, 'parts': parts};

  static Map<String, dynamic> textPart(String text) => {'text': text};

  static Map<String, dynamic> functionCallPart({
    required String name,
    required Map<String, dynamic> args,
  }) => {
    'functionCall': {'name': name, 'args': args},
  };

  static Map<String, dynamic> functionResponsePart({
    required String name,
    required Map<String, dynamic> response,
  }) => {
    'functionResponse': {'name': name, 'response': response},
  };
}

/// One callable tool exposed to Gemini. Field names intentionally mirror
/// langchain_core's `ToolSpec` so the app's existing tool catalog
/// (name / description / inputJsonSchema) can be reused unchanged for both
/// the OpenRouter and Gemini chat paths.
class GeminiFunctionDeclaration {
  GeminiFunctionDeclaration({
    required this.name,
    required this.description,
    required this.parametersJsonSchema,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parametersJsonSchema;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'parameters': _upperCaseSchemaTypes(parametersJsonSchema),
  };

  /// Gemini's function-calling schema expects OpenAPI-style type casing
  /// ("OBJECT", "STRING", "INTEGER"...) while the tool specs elsewhere in
  /// the app are written in plain lower-case JSON Schema. This walks the
  /// schema tree once so the same schema literal can be shared as-is.
  static dynamic _upperCaseSchemaTypes(dynamic node) {
    if (node is Map) {
      final result = <String, dynamic>{};
      node.forEach((key, value) {
        result[key as String] = (key == 'type' && value is String)
            ? value.toUpperCase()
            : _upperCaseSchemaTypes(value);
      });
      return result;
    }
    if (node is List) return node.map(_upperCaseSchemaTypes).toList();
    return node;
  }
}

/// Events streamed back while one Gemini turn is generated.
sealed class GeminiStreamEvent {}

class GeminiTextDelta extends GeminiStreamEvent {
  GeminiTextDelta(this.text);
  final String text;
}

class GeminiFunctionCallRequested extends GeminiStreamEvent {
  GeminiFunctionCallRequested({
    required this.id,
    required this.name,
    required this.args,
  });
  final String id;
  final String name;
  final Map<String, dynamic> args;
}

class GeminiTurnFinished extends GeminiStreamEvent {
  GeminiTurnFinished(this.finishReason);
  final String? finishReason;
}

/// Thin adapter around Google's Generative Language ("Gemini") REST API.
///
/// Mirrors the shape of [EmbeddingClient] elsewhere in `lib/data/services`:
/// a small, dependency-light HTTP wrapper so the rest of the app never has
/// to know Gemini's wire format. Supports streaming text generation and
/// function calling, which is all [ResearchAgent] needs to plug Gemini in
/// as an alternative chat provider next to OpenRouter.
class GeminiClient {
  GeminiClient({
    required this.apiKey,
    this.model = 'gemini-2.5-flash',
    this.baseUrl = defaultBaseUrl,
    http.Client? client,
  }) : _client = RetryClient(
         client ?? http.Client(),
         retries: 2,
         when: (response) =>
             response.statusCode == 429 || response.statusCode >= 500,
       );

  static const String defaultBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  final String apiKey;
  final String model;
  final String baseUrl;
  final http.Client _client;
  final _abort = Completer<void>();
  int _callCounter = 0;

  /// Streams one assistant turn for [contents]. Callers append the
  /// resulting model/function turns back onto [contents] themselves before
  /// calling this again — same contract as the OpenAI-compatible path.
  Stream<GeminiStreamEvent> streamGenerateContent({
    required List<GeminiContent> contents,
    String? systemInstruction,
    List<GeminiFunctionDeclaration> tools = const [],
  }) async* {
    if (_abort.isCompleted) throw StateError('Gemini request cancelled');
    final uri = Uri.parse(
      '$baseUrl/models/$model:streamGenerateContent?alt=sse',
    );
    final body = <String, dynamic>{
      'contents': contents.map((c) => c.toJson()).toList(),
      'generationConfig': {'maxOutputTokens': 4096},
      if (systemInstruction != null && systemInstruction.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction},
          ],
        },
      if (tools.isNotEmpty)
        'tools': [
          {'functionDeclarations': tools.map((t) => t.toJson()).toList()},
        ],
    };

    final request =
        http.AbortableRequest('POST', uri, abortTrigger: _abort.future)
          ..headers.addAll({
            'Content-Type': 'application/json',
            // Gemini accepts the key either as a query param or this header;
            // the header keeps it out of logs/proxies that record URLs.
            'x-goog-api-key': apiKey,
          })
          ..body = jsonEncode(body);

    final response = await _client.send(request);
    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      throw HttpException(
        'Gemini API error (${response.statusCode}): $errorBody',
      );
    }

    var buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      if (_abort.isCompleted) return;
      buffer += chunk;
      final lines = buffer.split('\n');
      // The last element may be an incomplete line; keep it for next chunk.
      buffer = lines.removeLast();
      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty || !line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        final json = jsonDecode(payload) as Map<String, dynamic>;
        for (final event in _parseChunk(json)) {
          if (_abort.isCompleted) return;
          yield event;
        }
      }
    }
  }

  List<GeminiStreamEvent> _parseChunk(Map<String, dynamic> json) {
    final events = <GeminiStreamEvent>[];
    final candidates = json['candidates'] as List<dynamic>? ?? const [];
    if (candidates.isEmpty) return events;
    final candidate = candidates.first as Map<String, dynamic>;
    final content = candidate['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>? ?? const [];
    for (final rawPart in parts) {
      final part = rawPart as Map<String, dynamic>;
      final text = part['text'] as String?;
      if (text != null && text.isNotEmpty) events.add(GeminiTextDelta(text));
      final functionCall = part['functionCall'] as Map<String, dynamic>?;
      if (functionCall != null) {
        events.add(
          GeminiFunctionCallRequested(
            id: 'call_${_callCounter++}',
            name: functionCall['name'] as String,
            args:
                (functionCall['args'] as Map<String, dynamic>?) ?? const {},
          ),
        );
      }
    }
    final finishReason = candidate['finishReason'] as String?;
    if (finishReason != null) events.add(GeminiTurnFinished(finishReason));
    return events;
  }

  void close() {
    if (_abort.isCompleted) return;
    _abort.complete();
    _client.close();
  }
}
