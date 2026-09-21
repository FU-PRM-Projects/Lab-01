import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/models/reference.dart';

void main() {
  group('PaperDocument references serialization', () {
    test('serializes and deserializes references field cleanly', () {
      final doc = PaperDocument(
        id: 'doc_123',
        fileName: 'paper.pdf',
        title: 'Sample Paper',
        sha256: 'abc123hash',
        pageCount: 10,
        status: DocumentStatus.ready,
        createdAt: DateTime.utc(2026, 3, 20),
        embeddingProfileId: 'test-profile',
        references: const [
          PaperReference(
            index: 1,
            marker: '[1]',
            raw: 'Author A. Title. 2020.',
            title: 'Title',
            year: 2020,
          ),
          PaperReference(
            index: 2,
            marker: '[2]',
            raw: 'Author B. Title 2. 2021. doi:10.1000/182',
            title: 'Title 2',
            year: 2021,
            doi: '10.1000/182',
          ),
        ],
      );

      final json = doc.toJson();
      expect(json['references'], isList);
      expect((json['references'] as List).length, 2);

      final recovered = PaperDocument.fromJson(json);
      expect(recovered.references, hasLength(2));
      expect(recovered.references[0].title, 'Title');
      expect(recovered.references[1].doi, '10.1000/182');
    });

    test('defaults references to empty list when missing in JSON', () {
      final json = {
        'id': 'doc_old',
        'fileName': 'old.pdf',
        'title': 'Old Document',
        'sha256': 'hash',
        'pageCount': 5,
        'status': 'ready',
        'createdAt': '2025-01-01T00:00:00.000Z',
        'embeddingProfileId': 'profile',
      };

      final doc = PaperDocument.fromJson(json);
      expect(doc.references, isEmpty);
    });

    test('copyWith updates references cleanly', () {
      final doc = PaperDocument(
        id: 'doc_1',
        fileName: 'a.pdf',
        title: 'Title',
        sha256: 'hash',
        pageCount: 1,
        status: DocumentStatus.ready,
        createdAt: DateTime.now(),
        embeddingProfileId: 'profile',
      );

      expect(doc.references, isEmpty);

      final updated = doc.copyWith(
        references: const [PaperReference(index: 1, raw: 'Citation')],
      );

      expect(updated.references, hasLength(1));
      expect(updated.references.first.raw, 'Citation');
      expect(doc.references, isEmpty);
    });
  });
}
