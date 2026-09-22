import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/domain/indexing/document_transcript.dart';

DocumentTranscript transcriptOf(List<String> pageTexts) {
  return DocumentTranscript.fromPages([
    for (var i = 0; i < pageTexts.length; i++)
      PageTranscript(page: i + 1, text: pageTexts[i]),
  ]);
}

void main() {
  group('DocumentTranscript', () {
    test('joins pages and maps offsets back to their page', () {
      final transcript = transcriptOf([
        'Page one.',
        'Page two.',
        'Page three.',
      ]);

      expect(transcript.text, 'Page one.\n\nPage two.\n\nPage three.');
      expect(transcript.pageForOffset(0), 1);
      expect(transcript.pageForOffset(8), 1);
      expect(transcript.pageForOffset(transcript.startOfPage(2)), 2);
      expect(transcript.pageForOffset(transcript.text.length - 1), 3);
    });

    test('an offset inside a page separator belongs to the page before it', () {
      final transcript = transcriptOf(['A', 'B']);
      // 'A' is at 0, the separator at 1-2, 'B' at 3.
      expect(transcript.pageForOffset(1), 1);
      expect(transcript.pageForOffset(3), 2);
    });

    test('blank pages keep the numbering of the pages after them', () {
      final transcript = transcriptOf(['First', '', 'Third']);

      expect(transcript.pages[1].isEmpty, isTrue);
      expect(transcript.pageForOffset(transcript.startOfPage(3)), 3);
      expect(transcript.text, contains('Third'));
    });

    test('markedMarkdown carries one marker per page, in order', () {
      final marked = transcriptOf(['One', '', 'Three']).markedMarkdown;

      expect(marked, contains('<!-- PAGE 1 -->\nOne'));
      expect(marked, contains('<!-- PAGE 2 -->'));
      expect(marked, contains('<!-- PAGE 3 -->\nThree'));
      expect(
        marked.indexOf('<!-- PAGE 2 -->'),
        lessThan(marked.indexOf('<!-- PAGE 3 -->')),
      );
    });

    test('finds a heading despite markdown decoration and numbering', () {
      final transcript = transcriptOf([
        'Title\n\n## Abstract\nWe present a method.',
        '**3.2 Threat Model**\nAn attacker may...',
      ]);

      final abstract = transcript.findHeading('Abstract', page: 1);
      expect(abstract, isNotNull);
      expect(transcript.text.substring(abstract!), startsWith('## Abstract'));

      final threat = transcript.findHeading('3.2 Threat Model', page: 2);
      expect(threat, isNotNull);
      expect(
        transcript.text.substring(threat!),
        startsWith('**3.2 Threat Model**'),
      );
    });

    test('finds a heading the model placed one page off', () {
      final transcript = transcriptOf([
        'Body text.',
        '## Results\nWe measure.',
      ]);

      expect(transcript.findHeading('Results', page: 1), isNotNull);
      expect(transcript.findHeading('Results', page: 3), isNotNull);
    });

    test('does not mistake prose for a heading', () {
      final transcript = transcriptOf([
        'Our results show that the method described in the related work of '
            'prior authors does not hold under these conditions at all.',
      ]);

      expect(transcript.findHeading('Results', page: 1), isNull);
    });

    test('an unknown heading returns null rather than an offset', () {
      final transcript = transcriptOf(['## Introduction\nText.']);
      expect(transcript.findHeading('Appendix B', page: 1), isNull);
    });
  });
}
