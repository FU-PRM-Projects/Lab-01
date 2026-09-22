import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/services/instruct_document_service.dart';
import 'package:lab_05/domain/indexing/document_transcript.dart';
import 'package:lab_05/domain/indexing/section_resolver.dart';

DocumentTranscript transcriptOf(List<String> pageTexts) {
  return DocumentTranscript.fromPages([
    for (var i = 0; i < pageTexts.length; i++)
      PageTranscript(page: i + 1, text: pageTexts[i]),
  ]);
}

void main() {
  group('SectionResolver', () {
    final transcript = transcriptOf([
      'A Very Good Paper\nJane Doe, John Roe\n\n'
          '## Abstract\nWe present a method.\n\n'
          '## 1 Introduction\nPrior work is vast.',
      '## 2 Methodology\nWe train a model.\n\n'
          '### 2.1 Setup\nEight GPUs.',
      '## References\n[1] Author A. A Paper. 2020.',
    ]);

    const outlines = [
      SectionOutline(name: 'Abstract', rawHeading: 'Abstract', page: 1),
      SectionOutline(
        name: 'Introduction',
        rawHeading: '1 Introduction',
        page: 1,
      ),
      SectionOutline(name: 'Methodology', rawHeading: '2 Methodology', page: 2),
      SectionOutline(name: 'Setup', rawHeading: '2.1 Setup', page: 2, level: 2),
      SectionOutline(name: 'References', rawHeading: 'References', page: 3),
    ];

    test('sections tile the transcript with no gaps or overlap', () {
      final sections = SectionResolver.resolve(
        documentId: 'doc_1',
        transcript: transcript,
        outlines: outlines,
      );

      expect(sections.first.startChar, 0);
      expect(sections.last.endChar, transcript.length);
      for (var i = 1; i < sections.length; i++) {
        expect(sections[i].startChar, sections[i - 1].endChar);
      }
      expect(sections.map((s) => s.text).join(), transcript.text);
    });

    test('text before the first heading becomes the front matter', () {
      final sections = SectionResolver.resolve(
        documentId: 'doc_1',
        transcript: transcript,
        outlines: outlines,
      );

      expect(sections.first.name, SectionResolver.frontMatterName);
      expect(sections.first.kind, SectionKind.frontMatter);
      expect(sections.first.text, contains('Jane Doe'));
      expect(sections[1].name, 'Abstract');
    });

    test('each section owns its body and knows its pages', () {
      final sections = SectionResolver.resolve(
        documentId: 'doc_1',
        transcript: transcript,
        outlines: outlines,
      );
      final methodology = sections.firstWhere((s) => s.name == 'Methodology');

      expect(methodology.text, contains('We train a model'));
      expect(methodology.text, isNot(contains('Prior work is vast')));
      expect(methodology.startPage, 2);
      expect(methodology.id, 'doc_1:s${methodology.ordinal}');
    });

    test('subsections keep their level and split the parent', () {
      final sections = SectionResolver.resolve(
        documentId: 'doc_1',
        transcript: transcript,
        outlines: outlines,
      );
      final setup = sections.firstWhere((s) => s.name == 'Setup');

      expect(setup.level, 2);
      expect(setup.text, contains('Eight GPUs'));
      final methodology = sections.firstWhere((s) => s.name == 'Methodology');
      expect(methodology.endChar, setup.startChar);
    });

    test('the bibliography is classified as references', () {
      final sections = SectionResolver.resolve(
        documentId: 'doc_1',
        transcript: transcript,
        outlines: outlines,
      );
      final references = sections.singleWhere((s) => s.isReferences);

      expect(references.kind, SectionKind.references);
      expect(references.text, contains('[1] Author A'));
    });

    test('a heading that cannot be found falls back to its page start', () {
      final sections = SectionResolver.resolve(
        documentId: 'doc_1',
        transcript: transcript,
        outlines: const [
          SectionOutline(name: 'Abstract', rawHeading: 'Abstract', page: 1),
          SectionOutline(
            name: 'Ethics Statement',
            rawHeading: 'A Heading Not In The Paper',
            page: 3,
          ),
        ],
      );
      final ethics = sections.firstWhere((s) => s.name == 'Ethics Statement');

      expect(ethics.startChar, transcript.startOfPage(3));
      expect(ethics.startPage, 3);
    });

    test('an empty outline still yields one whole-document section', () {
      final sections = SectionResolver.resolve(
        documentId: 'doc_1',
        transcript: transcript,
        outlines: const [],
      );

      expect(sections, hasLength(1));
      expect(sections.single.name, SectionResolver.wholeDocumentName);
      expect(sections.single.text, transcript.text);
    });

    test('an empty transcript yields no sections', () {
      expect(
        SectionResolver.resolve(
          documentId: 'doc_1',
          transcript: transcriptOf(const ['', '']),
          outlines: const [],
        ),
        isEmpty,
      );
    });

    test('duplicate or out-of-order anchors are dropped', () {
      final sections = SectionResolver.resolve(
        documentId: 'doc_1',
        transcript: transcript,
        outlines: const [
          SectionOutline(name: 'Abstract', rawHeading: 'Abstract', page: 1),
          SectionOutline(
            name: 'Abstract Again',
            rawHeading: 'Abstract',
            page: 1,
          ),
        ],
      );

      expect(sections.where((s) => s.name == 'Abstract Again'), isEmpty);
      for (var i = 1; i < sections.length; i++) {
        expect(sections[i].startChar, greaterThan(sections[i - 1].startChar));
      }
    });
  });

  group('classifySection', () {
    test('recognises bibliographies under any of their names', () {
      expect(classifySection('References'), SectionKind.references);
      expect(classifySection('Bibliography'), SectionKind.references);
      expect(classifySection('Works Cited'), SectionKind.references);
    });

    test('recognises appendices and back matter', () {
      expect(classifySection('Appendix A'), SectionKind.appendix);
      expect(classifySection('Supplementary Material'), SectionKind.appendix);
      expect(classifySection('Acknowledgments'), SectionKind.backMatter);
      expect(classifySection('Data Availability'), SectionKind.backMatter);
    });

    test('treats anything else as body', () {
      expect(classifySection('Threat Model'), SectionKind.body);
      expect(classifySection('Results'), SectionKind.body);
    });
  });
}
