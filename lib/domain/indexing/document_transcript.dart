/// The Markdown transcription of one PDF page.
class PageTranscript {
  /// 1-based page number.
  final int page;

  /// Markdown for the page, or empty when the page carries no readable text.
  final String text;

  const PageTranscript({required this.page, required this.text});

  bool get isEmpty => text.trim().isEmpty;

  factory PageTranscript.fromJson(Map<String, dynamic> json) => PageTranscript(
    page: (json['page'] as num?)?.toInt() ?? 1,
    text: json['text'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'page': page, 'text': text};
}

/// All pages joined into one Markdown string, with per-page spans for offset lookup.
/// [markedMarkdown] adds `<!-- PAGE N -->` markers for the instruct model.
class DocumentTranscript {
  const DocumentTranscript._(
    this._starts,
    this._ends, {
    required this.pages,
    required this.text,
  });

  /// Page separator in [text]. Kept to two newlines so a page break also reads
  /// as a paragraph break to the chunker.
  static const pageSeparator = '\n\n';

  final List<PageTranscript> pages;

  /// The whole document as Markdown, without page markers.
  final String text;

  final List<int> _starts;
  final List<int> _ends;

  int get pageCount => pages.length;

  int get length => text.length;

  factory DocumentTranscript.fromPages(List<PageTranscript> pages) {
    final ordered = [...pages]..sort((a, b) => a.page.compareTo(b.page));
    final buffer = StringBuffer();
    final starts = <int>[];
    final ends = <int>[];
    var offset = 0;

    for (var i = 0; i < ordered.length; i++) {
      final body = ordered[i].text.trim();
      starts.add(offset);
      buffer.write(body);
      offset += body.length;
      ends.add(offset);
      if (i != ordered.length - 1) {
        buffer.write(pageSeparator);
        offset += pageSeparator.length;
      }
    }

    return DocumentTranscript._(
      starts,
      ends,
      pages: ordered,
      text: buffer.toString(),
    );
  }

  /// The transcript with `<!-- PAGE N -->` markers, for the instruct prompt.
  String get markedMarkdown {
    final buffer = StringBuffer();
    for (final page in pages) {
      buffer.writeln('<!-- PAGE ${page.page} -->');
      final body = page.text.trim();
      if (body.isNotEmpty) buffer.writeln(body);
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  /// Offset in [text] where [page] begins, clamped into range.
  int startOfPage(int page) {
    final index = _indexOfPage(page);
    if (index == null) {
      return page <= (pages.firstOrNull?.page ?? 1) ? 0 : length;
    }
    return _starts[index];
  }

  /// The 1-based page an [offset] into [text] falls on.
  int pageForOffset(int offset) {
    if (pages.isEmpty) return 1;
    final clamped = offset.clamp(0, length);
    // Page spans are ordered and non-overlapping, so the last page that starts
    // at or before the offset owns it — including offsets inside a separator.
    var low = 0;
    var high = pages.length - 1;
    var found = 0;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (_starts[mid] <= clamped) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return pages[found].page;
  }

  /// Finds the line offset of [heading] on [page] or its neighbours; null if not found.
  int? findHeading(String heading, {required int page}) {
    final needle = normalizeHeading(heading);
    if (needle.isEmpty) return null;

    for (final candidate in [page, page - 1, page + 1, page + 2]) {
      final match = _findHeadingOnPage(needle, candidate);
      if (match != null) return match;
    }
    return null;
  }

  /// Finds the last page carrying [heading] (fallback for the references section).
  int? findLastHeading(String heading) {
    final needle = normalizeHeading(heading);
    if (needle.isEmpty) return null;
    for (final page in pages.reversed) {
      final match = _findHeadingOnPage(needle, page.page);
      if (match != null) return match;
    }
    return null;
  }

  int? _findHeadingOnPage(String needle, int page) {
    final index = _indexOfPage(page);
    if (index == null) return null;
    final start = _starts[index];
    final body = text.substring(start, _ends[index]);

    int? looseMatch;
    var offset = 0;
    for (final line in body.split('\n')) {
      final normalized = normalizeHeading(line);
      if (normalized.isNotEmpty) {
        if (normalized == needle) return start + offset;
        // A heading line is short; prose that merely mentions the words is not
        // a heading, so only consider brief lines for the loose pass.
        if (looseMatch == null &&
            normalized.length <= 80 &&
            (normalized.endsWith(needle) || needle.endsWith(normalized))) {
          looseMatch = start + offset;
        }
      }
      offset += line.length + 1;
    }
    return looseMatch;
  }

  int? _indexOfPage(int page) {
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].page == page) return i;
    }
    return null;
  }

  static final _numbering = RegExp(r'^\d+(?:\.\d+)*\.?\s+');
  static final _whitespace = RegExp(r'\s+');

  /// Strips Markdown decoration, leading numbering and casing so a heading
  /// reported by the model can be matched against the transcript line.
  static String normalizeHeading(String raw) {
    var value = raw.trim();
    value = value.replaceAll(RegExp(r'<[^>]*>'), '');
    value = value.replaceAll(RegExp(r'[#*_`~|]'), '');
    value = value.replaceAll(_whitespace, ' ').trim();
    value = value.replaceAll(_numbering, '');
    value = value.replaceAll(RegExp(r'^[\-•:.\s]+|[\-•:.\s]+$'), '');
    return value.toLowerCase();
  }
}
