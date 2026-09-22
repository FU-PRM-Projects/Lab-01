import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/domain/indexing/document_transcript.dart';
import 'package:lab_05/domain/indexing/section_chunker.dart';

DocumentTranscript transcriptOf(List<String> pageTexts) {
  return DocumentTranscript.fromPages([
    for (var i = 0; i < pageTexts.length; i++)
      PageTranscript(page: i + 1, text: pageTexts[i]),
  ]);
}

/// Sections covering the whole transcript, split at [boundaries].
List<DocumentSection> sectionsOver(
  DocumentTranscript transcript,
  List<({String name, int start})> boundaries,
) {
  return [
    for (var i = 0; i < boundaries.length; i++)
      () {
        final start = boundaries[i].start;
        final end = i + 1 < boundaries.length
            ? boundaries[i + 1].start
            : transcript.length;
        return DocumentSection(
          id: 'doc_1:s$i',
          ordinal: i,
          name: boundaries[i].name,
          kind: classifySection(boundaries[i].name),
          startPage: transcript.pageForOffset(start),
          endPage: transcript.pageForOffset(end - 1),
          startChar: start,
          endChar: end,
          text: transcript.text.substring(start, end),
        );
      }(),
  ];
}

void main() {
  group('SectionChunker', () {
    test('a short section becomes exactly one chunk', () {
      final transcript = transcriptOf(['## Introduction\nA short section.']);
      final chunks = SectionChunker.chunk(
        documentId: 'doc_1',
        transcript: transcript,
        sections: sectionsOver(transcript, [(name: 'Introduction', start: 0)]),
      );

      expect(chunks, hasLength(1));
      expect(chunks.single.id, 'doc_1:s0:c0');
      expect(chunks.single.text, transcript.text);
      expect(chunks.single.section, 'Introduction');
      expect(chunks.single.sectionId, 'doc_1:s0');
      expect(chunks.single.page, 1);
    });

    test('chunks never span two sections', () {
      final intro = 'Introductory sentence. ' * 200;
      final method = 'Methodological sentence. ' * 200;
      final full = transcriptOf([
        '## Introduction\n$intro',
        '## Methodology\n$method',
      ]);
      final boundary = full.text.indexOf('## Methodology');
      final chunks = SectionChunker.chunk(
        documentId: 'doc_1',
        transcript: full,
        sections: sectionsOver(full, [
          (name: 'Introduction', start: 0),
          (name: 'Methodology', start: boundary),
        ]),
      );

      expect(chunks.length, greaterThan(2));
      for (final chunk in chunks) {
        if (chunk.section == 'Introduction') {
          expect(chunk.endChar, lessThanOrEqualTo(boundary));
        } else {
          expect(chunk.startChar, greaterThanOrEqualTo(boundary));
        }
      }
    });

    test('long sections split with overlap and stay verbatim', () {
      final body = List.generate(
        120,
        (i) => 'Paragraph $i explains one idea in a complete sentence.',
      ).join('\n\n');
      final transcript = transcriptOf(['## Results\n$body']);
      final chunks = SectionChunker.chunk(
        documentId: 'doc_1',
        transcript: transcript,
        sections: sectionsOver(transcript, [(name: 'Results', start: 0)]),
      );

      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(
          chunk.text,
          transcript.text.substring(chunk.startChar, chunk.endChar),
        );
        expect(chunk.endChar - chunk.startChar, lessThanOrEqualTo(4000));
      }
      // Consecutive chunks repeat their seam, and together cover the section.
      for (var i = 1; i < chunks.length; i++) {
        expect(chunks[i].startChar, lessThan(chunks[i - 1].endChar));
      }
      expect(chunks.last.endChar, transcript.length);
    });

    test('ordinals run across the document and ids restart per section', () {
      final transcript = transcriptOf([
        '## Introduction\nFirst section body.',
        '## Methodology\nSecond section body.',
      ]);
      final boundary = transcript.text.indexOf('## Methodology');
      final chunks = SectionChunker.chunk(
        documentId: 'doc_1',
        transcript: transcript,
        sections: sectionsOver(transcript, [
          (name: 'Introduction', start: 0),
          (name: 'Methodology', start: boundary),
        ]),
      );

      expect(chunks.map((c) => c.ordinal), [0, 1]);
      expect(chunks.map((c) => c.id), ['doc_1:s0:c0', 'doc_1:s1:c0']);
      expect(chunks.last.page, 2);
    });

    test('the bibliography is not indexed by default', () {
      final transcript = transcriptOf([
        '## Discussion\nWe discuss the finding at some length here.',
        '## References\n[1] Author A. A Paper. 2020.',
      ]);
      final boundary = transcript.text.indexOf('## References');
      final sections = sectionsOver(transcript, [
        (name: 'Discussion', start: 0),
        (name: 'References', start: boundary),
      ]);

      final withoutRefs = SectionChunker.chunk(
        documentId: 'doc_1',
        transcript: transcript,
        sections: sections,
      );
      expect(withoutRefs.map((c) => c.section), ['Discussion']);

      final withRefs = SectionChunker.chunk(
        documentId: 'doc_1',
        transcript: transcript,
        sections: sections,
        indexReferences: true,
      );
      expect(withRefs.map((c) => c.section), ['Discussion', 'References']);
    });

    test('empty and heading-only sections produce no chunks', () {
      final transcript = transcriptOf([
        '## A\n\n## Results\nReal body text here.',
      ]);
      final boundary = transcript.text.indexOf('## Results');
      final chunks = SectionChunker.chunk(
        documentId: 'doc_1',
        transcript: transcript,
        sections: sectionsOver(transcript, [
          (name: 'A', start: 0),
          (name: 'Results', start: boundary),
        ]),
      );

      expect(chunks.map((c) => c.section), ['Results']);
    });

    test('the section name is prepended for embedding only', () {
      final transcript = transcriptOf(['## Methodology\nWe train a model.']);
      final chunk = SectionChunker.chunk(
        documentId: 'doc_1',
        transcript: transcript,
        sections: sectionsOver(transcript, [(name: 'Methodology', start: 0)]),
      ).single;

      expect(chunk.embeddingText, startsWith('Methodology\n\n'));
      expect(chunk.text, isNot(startsWith('Methodology\n\n')));
    });
  });
}
