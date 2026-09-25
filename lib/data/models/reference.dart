/// A bibliography entry: verbatim [raw] text plus its structured fields.
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
  final String? venue;
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
    this.venue,
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
      'venue': venue,
      'year': year,
      'doi': doi,
      'arxivId': arxivId,
      'url': url,
    };
  }

  factory PaperReference.fromJson(Map<String, dynamic> json) {
    return PaperReference(
      index: (json['index'] as num?)?.toInt() ?? 1,
      marker: _text(json['marker']),
      raw: json['raw'] as String? ?? '',
      authors: _text(json['authors']),
      title: _text(json['title']),
      venue: _text(json['venue']),
      year: (json['year'] as num?)?.toInt(),
      doi: _text(json['doi']),
      arxivId: _text(json['arxivId']),
      url: _text(json['url']),
    );
  }

  /// Models answer missing fields with `null`, `""` or the literal `"null"`;
  /// all three mean "not present".
  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return null;
    return trimmed;
  }
}
