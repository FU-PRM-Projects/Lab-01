import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:lab_05/data/models/app_settings.dart';
import 'package:lab_05/domain/reference_parser.dart';

/// A section boundary detected in the paper by the instruct model.
class DocumentSection {
  final String name;
  final int page;
  final String? rawHeading;

  const DocumentSection({
    required this.name,
    required this.page,
    this.rawHeading,
  });

  factory DocumentSection.fromJson(Map<String, dynamic> json) {
    return DocumentSection(
      name: json['name'] as String? ?? 'Section',
      page: (json['page'] as num?)?.toInt() ?? 1,
      rawHeading: json['rawHeading'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'page': page,
        if (rawHeading != null) 'rawHeading': rawHeading,
      };
}

/// The structured result returned by the instruct model.
class ParsedStructureResult {
  final List<DocumentSection> sections;
  final List<PaperReference> references;

  const ParsedStructureResult({
    required this.sections,
    required this.references,
  });
}

/// Service that assembles document pages into unified Markdown and invokes
/// an instruct model on OpenRouter to parse document sections and bibliography references.
class InstructDocumentService {
  InstructDocumentService({
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
  final int maxTokens;
  final http.Client _client;
  final _abort = Completer<void>();

  String get endpoint => settings.chatCompletionsUrl;

  /// Assembles per-page text into a single Markdown document with explicit
  /// `<!-- PAGE N -->` markers so the instruct model knows page boundaries.
  static String assembleMarkdown(Map<int, String> pageTexts, int totalPages) {
    final buffer = StringBuffer();
    for (var page = 1; page <= totalPages; page++) {
      final text = pageTexts[page]?.trim() ?? '';
      buffer.writeln('<!-- PAGE $page -->');
      if (text.isNotEmpty) {
        buffer.writeln(text);
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  static const _systemPrompt = '''
You are an expert scientific paper analyzer.
Analyze the provided paper text (which contains <!-- PAGE N --> markers) and extract:
1. The structural sections of the paper and the page on which each section starts.
   Identify ALL sections present in the paper, including:
   - Standard sections (e.g. Abstract, Introduction, Background, Related Work, Methodology, Experiments, Results, Discussion, Conclusion, References, Appendix).
   - Any paper-specific or custom sections (e.g. "System Architecture", "Theoretical Analysis", "Threat Model", "Optimization Algorithm", "Case Study", "Hardware Setup", "Limitations & Societal Impact", "Ethical Considerations", etc.).
   Do NOT limit yourself to a fixed list—extract whatever sections the author actually defined in the paper.
2. The bibliographic entries from the "References" or "Bibliography" section.

You MUST return a JSON object with this EXACT structure:
{
  "sections": [
    {
      "name": "Clean, Title Case section name without leading numbering (e.g. 'Introduction' from '1. Introduction', 'Threat Model' from '3.2 THREAT MODEL', 'References' from 'REFERENCES')",
      "page": 1,
      "rawHeading": "Exact heading as appeared in paper"
    }
  ],
  "references": [
    {
      "index": 1,
      "marker": "[1]",
      "raw": "Complete citation text",
      "authors": "Author names",
      "title": "Paper/book title",
      "year": 2023,
      "doi": "10.xxx/xxx",
      "arxivId": "2301.xxxxx",
      "url": "https://..."
    }
  ]
}

Rules:
- 'name' should be the clean Title Case name of the section with numbering stripped (e.g. 'Threat Model' rather than '3. Threat Model').
- For bibliography/reference sections, always use 'References' as the 'name'.
- 'page' MUST be an integer matching the <!-- PAGE N --> marker where that section appears.
- If there is no bibliography or references section in the paper, return an empty array for "references": [].
- If fields like 'doi', 'arxivId', 'url', 'marker', or 'year' are not present in a citation, set them to null.
- Output ONLY valid JSON.
''';

  /// Sends the assembled Markdown to the configured OpenRouter instruct model.
  /// Throws immediately if OpenRouter returns an error, status != 200, or invalid JSON.
  Future<ParsedStructureResult> parseStructure(
    String assembledMarkdown, {
    String? modelId,
  }) async {
    if (_abort.isCompleted) {
      throw StateError('Instruct parsing request cancelled');
    }

    final apiKey = settings.openRouterApiKey.trim();
    if (apiKey.isEmpty) {
      throw StateError('OpenRouter API key is required for instruct model parsing.');
    }

    final targetModel = modelId ?? settings.chatModel;

    final request = http.AbortableRequest(
      'POST',
      Uri.parse(endpoint),
      abortTrigger: _abort.future,
    )
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode({
        'model': targetModel,
        'temperature': 0,
        'max_tokens': maxTokens,
        'response_format': {'type': 'json_object'},
        'messages': [
          {'role': 'system', 'content': _systemPrompt},
          {
            'role': 'user',
            'content': 'Here is the assembled paper text:\n\n$assembledMarkdown',
          },
        ],
      });

    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed).timeout(timeout);
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);

    if (response.statusCode != 200) {
      throw HttpException(
        'OpenRouter instruct error (${response.statusCode}): ${_errorMessage(body)}',
      );
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    final error = json['error'];
    if (error != null) {
      throw HttpException(
        'OpenRouter instruct error: ${_errorMessage(jsonEncode({'error': error}))}',
      );
    }

    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const FormatException('OpenRouter instruct response has no choices');
    }

    final choice = choices.first as Map<String, dynamic>;
    if (choice['finish_reason'] == 'length') {
      debugPrint(
        '[instruct] output hit max_tokens=$maxTokens; structure or references may be truncated',
      );
    }

    final message = choice['message'] as Map<String, dynamic>?;
    final content = message?['content'];
    final text = switch (content) {
      String s => s,
      List<dynamic> parts => parts
          .whereType<Map<String, dynamic>>()
          .map((p) => p['text'])
          .whereType<String>()
          .join(),
      _ => '',
    };

    return parseJsonResult(text);
  }

  /// Parses the raw LLM output text into [ParsedStructureResult].
  static ParsedStructureResult parseJsonResult(String rawText) {
    var cleaned = rawText.trim();
    // Strip markdown code fences if model enclosed JSON in ```json ... ```
    final fence = RegExp(r'^```(?:json)?[ \t]*\n([\s\S]*?)\n?```$', caseSensitive: false);
    final match = fence.firstMatch(cleaned);
    if (match != null) {
      cleaned = match.group(1)!.trim();
    }

    if (cleaned.isEmpty) {
      throw const FormatException('Instruct model returned empty output');
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('Failed to parse instruct model JSON: $e\nOutput was: $cleaned');
    }

    final rawSections = (data['sections'] as List<dynamic>?) ?? [];
    final sections = rawSections
        .whereType<Map<String, dynamic>>()
        .map(DocumentSection.fromJson)
        .toList();

    final rawReferences = (data['references'] as List<dynamic>?) ?? [];
    final references = <PaperReference>[];
    for (var i = 0; i < rawReferences.length; i++) {
      final item = rawReferences[i];
      if (item is Map<String, dynamic>) {
        references.add(
          PaperReference(
            index: (item['index'] as num?)?.toInt() ?? (i + 1),
            marker: item['marker'] as String?,
            raw: item['raw'] as String? ?? '',
            authors: item['authors'] as String?,
            title: item['title'] as String?,
            year: (item['year'] as num?)?.toInt(),
            doi: item['doi'] as String?,
            arxivId: item['arxivId'] as String?,
            url: item['url'] as String?,
          ),
        );
      }
    }

    return ParsedStructureResult(
      sections: sections,
      references: references,
    );
  }

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
      // Not JSON: keep raw body
    }
    const maxLength = 300;
    return message.length > maxLength
        ? '${message.substring(0, maxLength)}...'
        : message;
  }

  void close() {
    if (_abort.isCompleted) return;
    _abort.complete();
    _client.close();
  }
}
