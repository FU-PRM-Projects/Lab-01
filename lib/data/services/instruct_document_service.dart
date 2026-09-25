import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

import 'package:lab_05/data/models/app_settings.dart';
import 'package:lab_05/data/models/reference.dart';
import 'package:lab_05/data/services/page_transcription_service.dart';

/// A section heading found by the instruct model (heading only, never body text).
class SectionOutline {
  final String name;
  final int page;
  final String? rawHeading;
  final int level;

  const SectionOutline({
    required this.name,
    required this.page,
    this.rawHeading,
    this.level = 1,
  });

  factory SectionOutline.fromJson(Map<String, dynamic> json) {
    return SectionOutline(
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Section',
      page: (json['page'] as num?)?.toInt() ?? 1,
      rawHeading: (json['rawHeading'] as String?)?.trim().isNotEmpty == true
          ? (json['rawHeading'] as String).trim()
          : null,
      level: ((json['level'] as num?)?.toInt() ?? 1).clamp(1, 6),
    );
  }
}

/// The paper's identity and structure, from the first instruct call.
class DocumentOutline {
  final String? title;
  final List<String> authors;
  final List<SectionOutline> sections;

  const DocumentOutline({
    this.title,
    this.authors = const [],
    this.sections = const [],
  });
}

/// Thrown when the model ran out of output budget and returned partial JSON.
class InstructTruncatedException implements Exception {
  final String stage;
  final int maxTokens;

  const InstructTruncatedException(this.stage, this.maxTokens);

  @override
  String toString() =>
      'The model hit its $maxTokens-token output limit while returning the '
      '$stage, so the JSON was cut off.';
}

/// Reads page transcripts with an OpenRouter instruct model.
///
/// The outline and the bibliography are extracted in separate calls (the
/// bibliography window by window) so long reference lists never overrun the
/// output budget. Body text is never requested, keeping sections verbatim.
class InstructDocumentService {
  InstructDocumentService({
    required this.settings,
    this.timeout = const Duration(minutes: 5),
    this.outlineMaxTokens = 8192,
    this.referencesMaxTokens = 8192,
    this.maxConcurrentWindows = 8,
    http.Client? client,
  }) : _client = RetryClient(
         client ?? http.Client(),
         retries: 2,
         when: (response) =>
             response.statusCode == 429 || response.statusCode >= 500,
       );

  final AppSettings settings;
  final Duration timeout;

  /// Output cap for the outline call. Headings are cheap; this is generous.
  final int outlineMaxTokens;

  /// Output cap per bibliography window. [bibliographyWindowChars] is sized so
  /// a window's entries fit well inside this.
  final int referencesMaxTokens;

  /// How many bibliography windows run concurrently.
  final int maxConcurrentWindows;

  final http.Client _client;
  final _abort = Completer<void>();

  /// How many times a window may be halved and retried on truncated/invalid JSON.
  static const maxBibliographyRetries = 3;

  /// Bibliography text per call (~20 entries), kept well under [referencesMaxTokens].
  static const bibliographyWindowChars = 6000;

  String get endpoint => settings.chatCompletionsUrl;

  static const outlineSystemPrompt = '''
You are an expert scientific paper analyzer. You are given the full text of a
paper, transcribed page by page, with `<!-- PAGE N -->` markers separating the
pages.

Report the paper's identity and structure. Return a JSON object with this
EXACT structure:
{
  "title": "Title of the paper",
  "authors": ["First Author", "Second Author"],
  "sections": [
    {
      "name": "Clean Title Case section name with leading numbering stripped",
      "rawHeading": "The heading exactly as printed, including its numbering",
      "page": 1,
      "level": 1
    }
  ]
}

Rules:
- List EVERY heading the authors actually printed, in reading order, including
  paper-specific ones (e.g. "System Architecture", "Threat Model", "Case
  Study", "Limitations and Societal Impact") as well as standard ones
  (Abstract, Introduction, Related Work, Methodology, Experiments, Results,
  Discussion, Conclusion, References, Appendix).
- Do not invent headings that are not printed in the paper, and do not merge or
  split the author's headings.
- "rawHeading" MUST be copied character for character from the transcript,
  including numbering, so it can be located in the text. Omit the Markdown
  "#" characters.
- "name" is "rawHeading" cleaned up: numbering stripped, Title Case.
- "level" is 1 for a top-level section, 2 for a subsection ("3.2 Setup"), and
  so on.
- "page" MUST be the integer of the `<!-- PAGE N -->` marker the heading
  appears under.
- If the paper has a bibliography, you MUST include its heading, named
  "References" whatever the paper calls it.
- Do NOT return the bibliography entries themselves. Headings only.

Output ONLY the JSON object.''';

  static const referencesSystemPrompt = '''
You are an expert at parsing bibliographies. You are given part of the
reference list of one paper, transcribed verbatim.

Return a JSON object with this EXACT structure:
{
  "references": [
    {
      "marker": "[1]",
      "raw": "The complete citation exactly as printed",
      "authors": "Author names as printed",
      "title": "Title of the cited work",
      "venue": "Journal, conference or publisher",
      "year": 2023,
      "doi": "10.xxxx/xxxxx",
      "arxivId": "2301.00000",
      "url": "https://..."
    }
  ]
}

Rules:
- Transcribe EVERY entry in the given text, in the order it appears. Do not
  skip entries and do not add entries that are not there.
- "raw" is the entry verbatim, with newlines collapsed to single spaces.
- Split the entry into "authors", "title", "venue" and "year" exactly as
  printed. Do not translate, expand or correct them, and do not supply values
  from your own knowledge of the cited work.
- Set a field to null when the entry does not print it. Never guess a doi,
  arxivId or url.
- "marker" is the printed label such as "[12]" or "12.", or null if the
  bibliography is unnumbered.
- If the text contains no bibliography entries, return {"references": []}.

Output ONLY the JSON object.''';

  /// First pass: the paper's title, authors and heading outline.
  Future<DocumentOutline> analyzeOutline(
    String markedMarkdown, {
    required String modelId,
  }) async {
    final text = await _complete(
      systemPrompt: outlineSystemPrompt,
      reasoningEffort: settings.indexingReasoningEffort,
      userContent: 'Here is the transcribed paper:\n\n$markedMarkdown',
      modelId: modelId,
      maxTokens: outlineMaxTokens,
      stage: 'outline',
    );
    return parseOutline(text);
  }

  /// Second pass: extracts the bibliography window by window, renumbering entries.
  /// [onProgress] reports finished windows (0..[windowCount]).
  Future<List<PaperReference>> extractReferences(
    String bibliographyText, {
    required String modelId,
    void Function(int done, int windowCount)? onProgress,
  }) async {
    final windows = splitBibliography(bibliographyText);
    if (windows.isEmpty) return const [];

    // Results are kept per window and flattened afterwards, so the finished
    // bibliography is in printed order however the calls interleave.
    final parsed = List<List<PaperReference>>.filled(windows.length, const []);
    var next = 0;
    var done = 0;
    Object? failure;
    StackTrace? failureStack;

    Future<void> worker() async {
      while (failure == null && next < windows.length) {
        final window = next++;
        try {
          parsed[window] = await _referencesIn(windows[window], modelId);
          onProgress?.call(++done, windows.length);
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
      }
    }

    onProgress?.call(0, windows.length);
    await Future.wait([
      for (var i = 0; i < min(maxConcurrentWindows, windows.length); i++)
        worker(),
    ]);

    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack ?? StackTrace.current);
    }

    final references = <PaperReference>[];
    for (final window in parsed) {
      for (final reference in window) {
        references.add(
          PaperReference(
            index: references.length + 1,
            marker: reference.marker,
            raw: reference.raw,
            authors: reference.authors,
            title: reference.title,
            venue: reference.venue,
            year: reference.year,
            doi: reference.doi,
            arxivId: reference.arxivId,
            url: reference.url,
          ),
        );
      }
    }

    return references;
  }

  /// Reads one window, halving and retrying if the model truncates or returns bad JSON.
  Future<List<PaperReference>> _referencesIn(
    String window,
    String modelId, {
    int depth = 0,
  }) async {
    try {
      final text = await _complete(
        systemPrompt: referencesSystemPrompt,
        userContent: 'Here is part of the reference list:\n\n$window',
        modelId: modelId,
        maxTokens: referencesMaxTokens,
        stage: 'bibliography',
        reasoningEffort: settings.referenceReasoningEffort,
      );
      return parseReferences(text);
    } on Object catch (error) {
      final recoverable =
          error is InstructTruncatedException || error is FormatException;
      // A window of one entry cannot be split further, so there is nothing
      // left to try.
      if (!recoverable ||
          depth >= maxBibliographyRetries ||
          !window.trimRight().contains('\n')) {
        rethrow;
      }

      final halves = splitBibliography(
        window,
        maxChars: (window.length / 2).ceil(),
      );
      if (halves.length < 2) rethrow;

      final references = <PaperReference>[];
      for (final half in halves) {
        references.addAll(await _referencesIn(half, modelId, depth: depth + 1));
      }
      return references;
    }
  }

  /// Splits a reference list into chunks of at most [bibliographyWindowChars],
  /// breaking only at line ends so an entry is never cut in half.
  static List<String> splitBibliography(
    String text, {
    int maxChars = bibliographyWindowChars,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed.length <= maxChars) return [trimmed];

    final windows = <String>[];
    final buffer = StringBuffer();
    for (final line in trimmed.split('\n')) {
      if (buffer.isNotEmpty && buffer.length + line.length + 1 > maxChars) {
        windows.add(buffer.toString().trim());
        buffer.clear();
      }
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(line);
    }
    if (buffer.toString().trim().isNotEmpty) {
      windows.add(buffer.toString().trim());
    }
    return windows;
  }

  Future<String> _complete({
    required String systemPrompt,
    required String userContent,
    required String modelId,
    required int maxTokens,
    required String stage,
    String reasoningEffort = '',
  }) async {
    if (_abort.isCompleted) {
      throw StateError('Instruct parsing request cancelled');
    }

    final apiKey = settings.openRouterApiKey.trim();
    if (apiKey.isEmpty) {
      throw StateError(
        'OpenRouter API key is required for instruct model parsing.',
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
            'response_format': {'type': 'json_object'},
            // Omitted entirely when empty: a model that does not take the
            // parameter rejects the request rather than ignoring it.
            if (reasoningEffort.isNotEmpty)
              'reasoning': {'effort': reasoningEffort},
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userContent},
            ],
          });

    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed).timeout(timeout);
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);

    if (response.statusCode != 200) {
      throw HttpException(
        'OpenRouter instruct error (${response.statusCode}): '
        '${openRouterErrorMessage(body)}',
      );
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    final error = json['error'];
    if (error != null) {
      throw HttpException(
        'OpenRouter instruct error: '
        '${openRouterErrorMessage(jsonEncode({'error': error}))}',
      );
    }

    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const FormatException(
        'OpenRouter instruct response has no choices',
      );
    }

    final choice = choices.first as Map<String, dynamic>;
    // Parsing a cut-off object only produces a confusing "unterminated string"
    // error many lines in, so name the real cause here.
    if (choice['finish_reason'] == 'length') {
      throw InstructTruncatedException(stage, maxTokens);
    }

    return openRouterMessageText(choice);
  }

  static final _fence = RegExp(
    r'^```(?:json)?[ \t]*\n([\s\S]*?)\n?```$',
    caseSensitive: false,
  );

  static Map<String, dynamic> _decode(String rawText) {
    var cleaned = rawText.trim();
    final fenced = _fence.firstMatch(cleaned);
    if (fenced != null) cleaned = fenced.group(1)!.trim();

    if (cleaned.isEmpty) {
      throw const FormatException('Instruct model returned empty output');
    }

    try {
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      final preview = cleaned.length > 500
          ? '${cleaned.substring(0, 500)}...'
          : cleaned;
      throw FormatException(
        'Failed to parse instruct model JSON: $e\nOutput was: $preview',
      );
    }
  }

  /// Parses the outline call's output.
  static DocumentOutline parseOutline(String rawText) {
    final data = _decode(rawText);

    final title = (data['title'] as String?)?.trim();
    final authors =
        (data['authors'] as List<dynamic>?)
            ?.map((author) => author.toString().trim())
            .where((author) => author.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];

    final sections =
        (data['sections'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(SectionOutline.fromJson)
            .toList() ??
        <SectionOutline>[];

    return DocumentOutline(
      title: title == null || title.isEmpty ? null : title,
      authors: authors,
      sections: sections,
    );
  }

  /// Parses one bibliography window's output. Indices are assigned by the
  /// caller, which is the only place that knows the order across windows.
  static List<PaperReference> parseReferences(String rawText) {
    final data = _decode(rawText);
    final raw = (data['references'] as List<dynamic>?) ?? const [];

    final references = <PaperReference>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map<String, dynamic>) continue;
      final reference = PaperReference.fromJson({...item, 'index': i + 1});
      if (reference.raw.trim().isEmpty && reference.title == null) continue;
      references.add(reference);
    }
    return references;
  }

  void close() {
    if (_abort.isCompleted) return;
    _abort.complete();
    _client.close();
  }
}
