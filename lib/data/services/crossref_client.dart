import 'dart:convert';

import 'package:http/http.dart' as http;

/// A bibliography entry matched against Crossref's metadata registry.
class CrossrefMatch {
  final String doi;
  final String? title;
  final String? containerTitle;
  final List<String> authors;
  final int? year;

  /// Crossref's own confidence score for the bibliographic query.
  final double score;

  const CrossrefMatch({
    required this.doi,
    this.title,
    this.containerTitle,
    this.authors = const [],
    this.year,
    this.score = 0,
  });

  String get url => 'https://doi.org/$doi';

  factory CrossrefMatch.fromJson(Map<String, dynamic> json) {
    final titles = (json['title'] as List<dynamic>?) ?? const [];
    final containers = (json['container-title'] as List<dynamic>?) ?? const [];
    final rawAuthors = (json['author'] as List<dynamic>?) ?? const [];

    final authors = rawAuthors
        .whereType<Map<String, dynamic>>()
        .map((author) {
          final family = (author['family'] as String?)?.trim() ?? '';
          final given = (author['given'] as String?)?.trim() ?? '';
          if (family.isEmpty && given.isEmpty) {
            return (author['name'] as String?)?.trim() ?? '';
          }
          return given.isEmpty ? family : '$given $family';
        })
        .where((name) => name.isNotEmpty)
        .toList(growable: false);

    int? year;
    final issued = json['issued'] as Map<String, dynamic>?;
    final dateParts = (issued?['date-parts'] as List<dynamic>?)?.firstOrNull;
    if (dateParts is List && dateParts.isNotEmpty) {
      year = (dateParts.first as num?)?.toInt();
    }

    return CrossrefMatch(
      doi: (json['DOI'] as String? ?? '').toLowerCase(),
      title: titles.isEmpty ? null : titles.first.toString(),
      containerTitle: containers.isEmpty ? null : containers.first.toString(),
      authors: authors,
      year: year,
      score: (json['score'] as num?)?.toDouble() ?? 0,
    );
  }

  factory CrossrefMatch.fromCache(Map<String, dynamic> json) {
    return CrossrefMatch(
      doi: json['doi'] as String? ?? '',
      title: json['title'] as String?,
      containerTitle: json['containerTitle'] as String?,
      authors:
          (json['authors'] as List<dynamic>?)
              ?.map((a) => a.toString())
              .toList(growable: false) ??
          const [],
      year: json['year'] as int?,
      score: (json['score'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'doi': doi,
    'title': title,
    'containerTitle': containerTitle,
    'authors': authors,
    'year': year,
    'score': score,
  };
}

/// Resolves raw bibliography strings to DOIs through the free Crossref API.
///
/// Crossref asks callers to identify themselves; no key or account is needed
/// and nothing but the reference string itself leaves the machine.
class CrossrefClient {
  static const String _userAgent =
      'PaperChat/1.0 (research reference resolver)';

  /// Per-request ceiling. Entries are resolved one at a time, so this also
  /// bounds how long a stalled endpoint can hold up one bibliography entry.
  static const Duration _requestTimeout = Duration(seconds: 20);

  /// Below this Crossref score a "match" is usually a different paper.
  static const double minimumScore = 55;

  final http.Client _client;
  final Uri _baseUri;
  bool _closed = false;

  CrossrefClient({
    http.Client? client,
    String baseUrl = 'https://api.crossref.org',
  }) : _client = client ?? http.Client(),
       _baseUri = Uri.parse(baseUrl);

  Future<CrossrefMatch?> resolve(String bibliographicText) async {
    final query = bibliographicText.trim();
    if (query.length < 25) return null;

    final uri = _baseUri.replace(
      path: '${_baseUri.path}/works',
      queryParameters: {
        'query.bibliographic': query.length > 400
            ? query.substring(0, 400)
            : query,
        'rows': '1',
        'select': 'DOI,title,container-title,author,issued,score',
      },
    );

    // Crossref can accept the connection and then stall; without a bound the
    // bibliography stays in the resolving state for as long as it does.
    final response = await _client
        .get(
          uri,
          headers: const {
            'User-Agent': _userAgent,
            'Accept': 'application/json',
          },
        )
        .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Crossref responded ${response.statusCode}',
        uri,
      );
    }

    // A response that does not carry a message/items envelope is a broken
    // endpoint, not a paper Crossref does not know about. Reporting it as
    // "no match" would hide an outage behind an empty bibliography.
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw http.ClientException('Crossref returned a malformed body', uri);
    }
    final message = decoded['message'];
    if (message is! Map<String, dynamic> || message['items'] is! List) {
      throw http.ClientException(
        'Crossref returned an unexpected response shape',
        uri,
      );
    }
    final items = message['items'] as List<dynamic>;
    if (items.isEmpty) return null;

    final first = items.first;
    if (first is! Map<String, dynamic>) {
      throw http.ClientException('Crossref returned an unexpected item', uri);
    }
    final match = CrossrefMatch.fromJson(first);
    if (match.doi.isEmpty || match.score < minimumScore) return null;
    return match;
  }

  /// Resolves entries one at a time; Crossref's public pool throttles bursts.
  Future<Map<int, CrossrefMatch>> resolveAll(
    Map<int, String> entries, {
    void Function(int done, int total)? onProgress,
  }) async {
    final results = <int, CrossrefMatch>{};
    var done = 0;
    var attempted = 0;
    var failed = 0;
    Object? lastError;
    for (final entry in entries.entries) {
      if (_closed) break;
      attempted++;
      try {
        final match = await resolve(entry.value);
        if (match != null) results[entry.key] = match;
      } catch (error) {
        // One unresolvable entry must not abort the whole bibliography.
        failed++;
        lastError = error;
      }
      onProgress?.call(++done, entries.length);
    }
    // Every entry failing is an outage or a broken endpoint rather than a
    // bibliography Crossref happens not to know, so the caller hears about it
    // instead of being handed an empty result that looks like success.
    if (attempted > 0 && failed == attempted) throw lastError!;
    return results;
  }

  void close() {
    _closed = true;
    _client.close();
  }
}
