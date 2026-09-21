import 'package:lab_05/data/models/paper.dart';

/// A single bibliography entry recovered from a paper's "References" section.
class PaperReference {
  /// 1-based position within the bibliography.
  final int index;

  /// The marker printed in the paper, e.g. "[12]" or "12." — null when the
  /// bibliography is unnumbered.
  final String? marker;

  /// The whole entry with whitespace normalised.
  final String raw;

  final String? authors;
  final String? title;
  final int? year;
  final String? doi;
  final String? arxivId;
  final String? url;

  const PaperReference({
    required this.index,
    required this.raw,
    this.marker,
    this.authors,
    this.title,
    this.year,
    this.doi,
    this.arxivId,
    this.url,
  });

  /// Canonical link for the cited work, preferring stable identifiers.
  String? get resolvedUrl {
    if (doi != null) return 'https://doi.org/$doi';
    if (arxivId != null) return 'https://arxiv.org/abs/$arxivId';
    return url;
  }

  /// Fallback lookup when the entry carries no identifier at all.
  String get searchUrl {
    final query = title ?? raw;
    final trimmed = query.length > 220 ? query.substring(0, 220) : query;
    return 'https://scholar.google.com/scholar?q=${Uri.encodeQueryComponent(trimmed)}';
  }

  String get linkLabel {
    if (doi != null) return 'doi.org/$doi';
    if (arxivId != null) return 'arXiv:$arxivId';
    if (url != null) return url!;
    return 'Search on Google Scholar';
  }

  bool get hasDirectLink => resolvedUrl != null;

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'marker': marker,
      'raw': raw,
      'authors': authors,
      'title': title,
      'year': year,
      'doi': doi,
      'arxivId': arxivId,
      'url': url,
    };
  }

  factory PaperReference.fromJson(Map<String, dynamic> json) {
    return PaperReference(
      index: json['index'] as int? ?? 1,
      marker: json['marker'] as String?,
      raw: json['raw'] as String? ?? '',
      authors: json['authors'] as String?,
      title: json['title'] as String?,
      year: json['year'] as int?,
      doi: json['doi'] as String?,
      arxivId: json['arxivId'] as String?,
      url: json['url'] as String?,
    );
  }
}

/// Extracts bibliography entries out of already-chunked paper text.
///
/// The Rust extractor tags every chunk with the last section heading it saw, so
/// the references live in the chunks whose section matches "References" or
/// "Bibliography". Those chunks overlap on purpose for retrieval quality, so
/// the page text is rebuilt from the char offsets before parsing.
class ReferenceParser {
  static final RegExp _sectionPattern = RegExp(
    r'referenc|bibliograph',
    caseSensitive: false,
  );

  static final RegExp _bracketMarker = RegExp(r'\[(\d{1,3})\]');
  static final RegExp _numberMarker = RegExp(r'(?:^|\n)[ \t]*(\d{1,3})[.)]\s+');
  static final RegExp _doiPattern = RegExp(
    r'\b10\.\d{4,9}/[-._;()/:A-Z0-9]+',
    caseSensitive: false,
  );
  static final RegExp _arxivPattern = RegExp(
    r'arxiv[:\s/]*(\d{4}\.\d{4,5}(?:v\d+)?)',
    caseSensitive: false,
  );
  static final RegExp _urlPattern = RegExp(r'https?://[^\s<>()\[\]]+');
  static final RegExp _yearPattern = RegExp(r'\b(?:19|20)\d{2}\b');
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _trailingPunctuation = RegExp(r'[.,;]+$');

  /// True when the document carries a detectable bibliography at all.
  static bool hasReferenceSection(List<PaperChunk> chunks) =>
      chunks.any((chunk) => _sectionPattern.hasMatch(chunk.section));

  static List<PaperReference> fromChunks(List<PaperChunk> chunks) {
    final referenceChunks = chunks
        .where((chunk) => _sectionPattern.hasMatch(chunk.section))
        .toList();
    if (referenceChunks.isEmpty) return const [];
    return parse(rebuildText(referenceChunks));
  }

  /// Rebuilds the original page text from overlapping chunks, page by page.
  static String rebuildText(List<PaperChunk> chunks) {
    final byPage = <int, List<PaperChunk>>{};
    for (final chunk in chunks) {
      byPage.putIfAbsent(chunk.page, () => []).add(chunk);
    }

    final pages = byPage.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final page in pages) {
      final pageChunks = byPage[page]!
        ..sort((a, b) => a.startChar.compareTo(b.startChar));
      var cursor = 0;
      for (final chunk in pageChunks) {
        if (chunk.endChar <= cursor) continue;
        final runes = chunk.text.runes.toList();
        final skip = cursor > chunk.startChar ? cursor - chunk.startChar : 0;
        if (skip >= runes.length) {
          cursor = chunk.endChar;
          continue;
        }
        buffer.write(String.fromCharCodes(runes.sublist(skip)));
        cursor = chunk.endChar;
      }
      buffer.write('\n');
    }
    return buffer.toString();
  }

  static List<PaperReference> parse(String text) {
    final body = _stripHeading(text);
    if (body.trim().isEmpty) return const [];

    var entries = _splitOnBracketMarkers(body);
    if (entries.isEmpty) entries = _splitOnNumberMarkers(body);
    if (entries.isEmpty) entries = _splitOnLines(body);

    final references = <PaperReference>[];
    for (final entry in entries) {
      final reference = _buildReference(references.length + 1, entry);
      if (reference != null) references.add(reference);
    }
    return references;
  }

  static String _stripHeading(String text) {
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim().replaceAll(RegExp(r'^#+\s*'), '');
      final normalised = line.replaceAll(RegExp(r'^\d+(?:\.\d+)*\s*'), '').trim();
      if (normalised.length <= 20 && _sectionPattern.hasMatch(normalised)) {
        return lines.sublist(i + 1).join('\n');
      }
    }
    return text;
  }

  static List<_RawEntry> _splitOnBracketMarkers(String body) {
    // Inline "[3]" cross-references appear mid-sentence, so bracket markers
    // that open a line are the reliable entry starts.
    var starts = _bracketMarker.allMatches(body).where((match) {
      final before = body.substring(0, match.start);
      final lineStart = before.lastIndexOf('\n') + 1;
      return before.substring(lineStart).trim().isEmpty;
    }).toList();

    // Some extractions flow the whole bibliography onto one line. There the
    // only usable signal is a marker sequence that counts up by one.
    if (starts.length < 2) starts = _sequentialBracketMarkers(body);
    if (starts.length < 2) return const [];

    final entries = <_RawEntry>[];
    for (var i = 0; i < starts.length; i++) {
      final match = starts[i];
      final end = i + 1 < starts.length ? starts[i + 1].start : body.length;
      entries.add(
        _RawEntry(
          marker: '[${match.group(1)}]',
          text: body.substring(match.end, end),
        ),
      );
    }
    return entries;
  }

  static List<RegExpMatch> _sequentialBracketMarkers(String body) {
    final chain = <RegExpMatch>[];
    int? expected;
    for (final match in _bracketMarker.allMatches(body)) {
      final number = int.parse(match.group(1)!);
      if (expected == null) {
        if (number != 1) continue;
      } else if (number != expected) {
        continue;
      }
      chain.add(match);
      expected = number + 1;
    }
    return chain;
  }

  static List<_RawEntry> _splitOnNumberMarkers(String body) {
    final matches = _numberMarker.allMatches(body).toList();
    if (matches.length < 2) return const [];

    final entries = <_RawEntry>[];
    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      final end = i + 1 < matches.length ? matches[i + 1].start : body.length;
      entries.add(
        _RawEntry(
          marker: '${match.group(1)}.',
          text: body.substring(match.end, end),
        ),
      );
    }
    return entries;
  }

  static List<_RawEntry> _splitOnLines(String body) {
    return body
        .split('\n')
        .map((line) => _RawEntry(marker: null, text: line))
        .toList();
  }

  /// Abbreviations whose full stop does not end the author list.
  static const Set<String> _abbreviations = {
    'al',
    'ed',
    'eds',
    'jr',
    'sr',
    'vol',
    'no',
    'pp',
    'inc',
    'ltd',
    'univ',
    'dept',
    'st',
    'mr',
    'ms',
    'dr',
    'prof',
  };

  static final RegExp _sentenceBreak = RegExp(r'[.?!](?=\s)');
  static final RegExp _wordBeforeBreak = RegExp(r'([A-Za-z]+)$');

  /// Splits "A. Vaswani, N. Shazeer. Attention is all you need. NeurIPS, 2017."
  /// into its real sentences: author initials and common abbreviations keep
  /// their full stop instead of starting a new segment.
  static List<String> _splitSentences(String raw) {
    final segments = <String>[];
    var start = 0;
    for (final match in _sentenceBreak.allMatches(raw)) {
      final head = raw.substring(start, match.start);
      final word = _wordBeforeBreak.firstMatch(head)?.group(1);
      if (word != null &&
          (word.length == 1 || _abbreviations.contains(word.toLowerCase()))) {
        continue;
      }
      final segment = raw.substring(start, match.end).trim();
      if (segment.isNotEmpty) segments.add(segment);
      start = match.end;
    }
    final tail = raw.substring(start).trim();
    if (tail.isNotEmpty) segments.add(tail);
    return segments;
  }

  static PaperReference? _buildReference(int index, _RawEntry entry) {
    final raw = entry.text.replaceAll(_whitespace, ' ').trim();
    // Page furniture and stray line breaks leave fragments behind; a real
    // bibliography entry always carries at least an author and a venue.
    if (raw.length < 25 || !raw.contains(' ')) return null;

    final doi = _doiPattern
        .firstMatch(raw)
        ?.group(0)
        ?.replaceAll(_trailingPunctuation, '');
    final arxivId = _arxivPattern.firstMatch(raw)?.group(1);
    final url = _urlPattern
        .firstMatch(raw)
        ?.group(0)
        ?.replaceAll(_trailingPunctuation, '');
    final year = int.tryParse(_yearPattern.firstMatch(raw)?.group(0) ?? '');

    final segments = _splitSentences(raw);

    String? authors;
    String? title;
    if (segments.length >= 2) {
      authors = segments.first;
      title = segments[1];
    } else if (segments.length == 1) {
      title = segments.first;
    }

    return PaperReference(
      index: index,
      marker: entry.marker,
      raw: raw,
      authors: authors,
      title: title,
      year: year,
      doi: doi,
      arxivId: arxivId,
      url: url,
    );
  }
}

class _RawEntry {
  const _RawEntry({required this.marker, required this.text});
  final String? marker;
  final String text;
}
