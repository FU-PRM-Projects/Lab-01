import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/services/section_artifact_service.dart';

void main() {
  test('exports faithful Markdown and hierarchical reusable JSON', () {
    final paper = PaperDocument(
      id: 'doc-1',
      fileName: 'paper.pdf',
      title: 'A Structured Paper',
      authors: const ['Ada Author'],
      sha256: 'source-hash',
      pageCount: 4,
      status: DocumentStatus.ready,
      createdAt: DateTime.utc(2026),
      embeddingProfileId: 'embedding',
      sections: const [
        DocumentSection(
          id: 'doc-1:s0',
          ordinal: 0,
          name: 'Methods',
          rawHeading: '2 Methods',
          level: 1,
          kind: SectionKind.body,
          startPage: 2,
          endPage: 3,
          startChar: 100,
          endChar: 180,
          text: '## 2 Methods\n\nExact body with \$x^2\$.',
        ),
        DocumentSection(
          id: 'doc-1:s1',
          ordinal: 1,
          name: 'Dataset',
          rawHeading: '2.1 Dataset',
          level: 2,
          kind: SectionKind.body,
          startPage: 3,
          endPage: 3,
          startChar: 180,
          endChar: 240,
          text: '### 2.1 Dataset\n\nRows stay verbatim.',
        ),
      ],
    );

    final bundle = SectionArtifactService.build(paper);

    expect(bundle.markdown, contains('artifact_type: "paper-sections"'));
    expect(bundle.markdown, contains('Exact body with \$x^2\$.'));
    expect(bundle.markdown, contains('Rows stay verbatim.'));

    final sections = bundle.json['sections'] as List<dynamic>;
    expect(sections, hasLength(2));
    expect(sections.first['parentId'], isNull);
    expect(sections.first['path'], ['Methods']);
    expect(sections[1]['parentId'], 'doc-1:s0');
    expect(sections[1]['path'], ['Methods', 'Dataset']);
    expect(sections[1]['text'], '### 2.1 Dataset\n\nRows stay verbatim.');
    expect(sections[1]['contentSha256'], hasLength(64));
    expect(bundle.json['offsetUnit'], 'utf16CodeUnit');
  });
}
