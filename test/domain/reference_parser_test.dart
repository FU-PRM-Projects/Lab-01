import 'package:flutter_test/flutter_test.dart';

import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/domain/reference_parser.dart';

PaperChunk chunk({
  required String id,
  required int page,
  required int ordinal,
  required String section,
  required int startChar,
  required String text,
}) {
  return PaperChunk(
    id: id,
    vectorId: 0,
    page: page,
    ordinal: ordinal,
    section: section,
    startChar: startChar,
    endChar: startChar + text.runes.length,
    text: text,
  );
}

void main() {
  group('ReferenceParser.parse', () {
    test('splits a bracket-numbered bibliography and pulls identifiers out', () {
      const text = '''
References

[1] A. Vaswani, N. Shazeer, and N. Parmar. Attention is all you need. In
Advances in Neural Information Processing Systems, 2017. arXiv:1706.03762.
[2] J. Devlin and M. Chang. BERT: pre-training of deep bidirectional
transformers. NAACL, 2019. doi:10.18653/v1/N19-1423
[3] T. Brown et al. Language models are few-shot learners. 2020.
https://openai.com/research/language-models
''';

      final references = ReferenceParser.parse(text);

      expect(references, hasLength(3));
      expect(references.first.marker, '[1]');
      expect(references.first.arxivId, '1706.03762');
      expect(
        references.first.resolvedUrl,
        'https://arxiv.org/abs/1706.03762',
      );
      expect(references[0].year, 2017);

      expect(references[1].doi, '10.18653/v1/N19-1423');
      expect(references[1].resolvedUrl, 'https://doi.org/10.18653/v1/N19-1423');

      expect(references[2].url, 'https://openai.com/research/language-models');
      expect(references[2].hasDirectLink, isTrue);
    });

    test('falls back to Google Scholar when no identifier is present', () {
      const text = '''
References
[1] K. He, X. Zhang, S. Ren, and J. Sun. Deep residual learning for image
recognition. In CVPR, pages 770-778, 2016.
[2] S. Hochreiter and J. Schmidhuber. Long short-term memory. Neural
Computation, 9(8):1735-1780, 1997.
''';

      final references = ReferenceParser.parse(text);

      expect(references, hasLength(2));
      expect(references.first.hasDirectLink, isFalse);
      expect(references.first.searchUrl, startsWith('https://scholar.google.com/scholar?q='));
      expect(references.first.title, contains('Deep residual learning'));
    });

    test('handles "1." style numbering', () {
      const text = '''
Bibliography
1. Smith, J. A survey of retrieval augmented generation. ACM Computing
Surveys, 2024.
2. Doe, J. and Roe, R. Dense passage retrieval for open domain QA. EMNLP,
2020.
''';

      final references = ReferenceParser.parse(text);

      expect(references, hasLength(2));
      expect(references.first.marker, '1.');
      expect(references[1].year, 2020);
    });

    test('ignores inline cross-references inside a single entry', () {
      const text = '''
References
[1] A. Author. Building on the work of [2] and [3], we show a new bound.
Journal of Results, 2021.
[2] B. Author. An earlier bound. Journal of Results, 2019.
''';

      final references = ReferenceParser.parse(text);

      expect(references, hasLength(2));
      expect(references.first.raw, contains('[2] and [3]'));
    });

    test('returns nothing when there is no bibliography text', () {
      expect(ReferenceParser.parse(''), isEmpty);
      expect(ReferenceParser.parse('References\n\n'), isEmpty);
    });
  });

  group('ReferenceParser.fromChunks', () {
    test('only reads chunks tagged as the references section', () {
      final chunks = [
        chunk(
          id: 'doc:p1:c0',
          page: 1,
          ordinal: 0,
          section: 'Introduction',
          startChar: 0,
          text: 'We build on [1] to motivate the approach taken here.',
        ),
        chunk(
          id: 'doc:p9:c0',
          page: 9,
          ordinal: 1,
          section: 'References',
          startChar: 0,
          text:
              '[1] A. Author. A cited paper title. Journal of Things, 2020.\n'
              '[2] B. Author. Another cited paper. Conference on Work, 2021.\n',
        ),
      ];

      final references = ReferenceParser.fromChunks(chunks);

      expect(ReferenceParser.hasReferenceSection(chunks), isTrue);
      expect(references, hasLength(2));
      expect(references.first.title, contains('A cited paper title'));
    });

    test('de-duplicates the overlap between consecutive chunks', () {
      const pageText =
          '[1] A. Author. The first cited work with a long enough title. '
          'Journal of Things, 2020. '
          '[2] B. Author. The second cited work also long enough. '
          'Conference on Work, 2021.';

      // Mirrors the Rust chunker: the second chunk restarts inside the first.
      const splitAt = 90;
      const overlap = 20;
      final chunks = [
        chunk(
          id: 'doc:p9:c0',
          page: 9,
          ordinal: 0,
          section: 'References',
          startChar: 0,
          text: pageText.substring(0, splitAt),
        ),
        chunk(
          id: 'doc:p9:c1',
          page: 9,
          ordinal: 1,
          section: 'References',
          startChar: splitAt - overlap,
          text: pageText.substring(splitAt - overlap),
        ),
      ];

      final references = ReferenceParser.fromChunks(chunks);

      expect(references, hasLength(2));
      expect(references.first.raw, contains('The first cited work'));
      expect(references[1].raw, contains('The second cited work'));
      // The duplicated overlap must not survive into the rebuilt text.
      final rebuilt = '${references[0].raw} ${references[1].raw}';
      expect('|'.allMatches(rebuilt.replaceAll('Journal of Things', '|')), hasLength(1));
    });
  });

  group('PaperReference serialization', () {
    test('toJson and fromJson roundtrip cleanly', () {
      const ref = PaperReference(
        index: 1,
        marker: '[1]',
        raw: 'A. Vaswani et al. Attention is All You Need. NeurIPS 2017.',
        authors: 'A. Vaswani et al.',
        title: 'Attention is All You Need',
        year: 2017,
        doi: '10.1234/example',
        arxivId: '1706.03762',
        url: 'https://arxiv.org/abs/1706.03762',
      );

      final json = ref.toJson();
      final recovered = PaperReference.fromJson(json);

      expect(recovered.index, ref.index);
      expect(recovered.marker, ref.marker);
      expect(recovered.raw, ref.raw);
      expect(recovered.authors, ref.authors);
      expect(recovered.title, ref.title);
      expect(recovered.year, ref.year);
      expect(recovered.doi, ref.doi);
      expect(recovered.arxivId, ref.arxivId);
      expect(recovered.url, ref.url);
      expect(recovered.resolvedUrl, 'https://doi.org/10.1234/example');
      expect(recovered.hasDirectLink, isTrue);
    });
  });
}
