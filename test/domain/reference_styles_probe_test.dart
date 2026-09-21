import 'package:flutter_test/flutter_test.dart';

import 'package:lab_05/domain/reference_parser.dart';

/// Probe: run the parser over the citation styles it will actually meet.
void main() {
  const samples = <String, String>{
    'IEEE numbered': '''
References
[1] A. Vaswani, N. Shazeer, and N. Parmar, "Attention is all you need," in
NeurIPS, 2017, pp. 5998-6008.
[2] K. He, X. Zhang, S. Ren, and J. Sun, "Deep residual learning," in CVPR,
2016, pp. 770-778.
''',
    'Vancouver (trailing initials)': '''
References
1. Smith J, Jones A. Effects of the treatment on outcomes. N Engl J Med.
2020;382(10):945-53. doi:10.1056/NEJMoa1900000
2. Brown K, Davis L, Wilson M. A randomised controlled trial. Lancet.
2019;394(10201):881-91.
''',
    'APA 7 (unnumbered, hanging indent)': '''
References
Smith, J. A., & Jones, B. C. (2020). Retrieval augmented generation for
    scientific question answering. Journal of Machine Learning Research,
    21(140), 1-45. https://doi.org/10.5555/jmlr.2020.140
Brown, T. B., Mann, B., & Ryder, N. (2020). Language models are few-shot
    learners. Advances in Neural Information Processing Systems, 33.
''',
    'MLA 9 (unnumbered)': '''
Works Cited
Vaswani, Ashish, et al. "Attention Is All You Need." Advances in Neural
    Information Processing Systems, vol. 30, 2017, pp. 5998-6008.
Devlin, Jacob, and Ming-Wei Chang. "BERT: Pre-Training of Deep Bidirectional
    Transformers." NAACL, 2019, pp. 4171-86.
''',
    'Chicago notes-bibliography': '''
Bibliography
Hochreiter, Sepp, and Jurgen Schmidhuber. "Long Short-Term Memory." Neural
    Computation 9, no. 8 (1997): 1735-80.
LeCun, Yann, Yoshua Bengio, and Geoffrey Hinton. "Deep Learning." Nature 521
    (2015): 436-44.
''',
    'Parenthesised numbering (1)': '''
References
(1) Smith, J. A survey of dense retrieval. ACM Computing Surveys, 2024.
(2) Doe, J. Passage ranking with transformers. EMNLP, 2020.
''',
    'Superscript / plain numbered no punctuation': '''
References
1 Smith J. A survey of dense retrieval. ACM Comput Surv 2024.
2 Doe J. Passage ranking with transformers. EMNLP 2020.
''',
    'Numbered, entries wrapped over many lines': '''
References
[1] Jane Q. Researcher, Karl Mustermann, Li Wei, and Maria Garcia. A very
long paper title that wraps across more than one line in the two column
layout. In Proceedings of the International Conference on Something,
pages 1-12, 2022.
[2] Someone Else. Short one. Venue, 2021.
''',
  };

  samples.forEach((style, text) {
    test('probe: $style', () {
      final references = ReferenceParser.parse(text);
      // ignore: avoid_print
      print('\n=== $style -> ${references.length} entries ===');
      for (final reference in references) {
        // ignore: avoid_print
        print(
          '  marker=${reference.marker} year=${reference.year} '
          'link=${reference.resolvedUrl ?? "-"}\n'
          '    title: ${reference.title}\n'
          '    raw  : ${reference.raw.length > 90 ? "${reference.raw.substring(0, 90)}..." : reference.raw}',
        );
      }
    });
  });
}
