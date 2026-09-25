import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/services/collection_index.dart';
import 'package:lab_05/data/services/embedding_client.dart';
import 'package:lab_05/data/services/local_storage.dart';
import 'package:lab_05/domain/retrieval.dart';

void main() {
  test('retrieval allowlist follows the active revision', () async {
    final directory = await Directory.systemTemp.createTemp('revision_search');
    addTearDown(() => directory.delete(recursive: true));
    final storage = LocalStorage(rootDir: directory);
    final collection = Collection(
      id: 'collection',
      name: 'Test',
      createdAt: DateTime.utc(2026),
      embeddingProfile: const EmbeddingProfile(id: 'profile', dimensions: 4),
    );
    await storage.saveCollection(collection);
    final paper = PaperDocument(
      id: 'doc',
      fileName: 'paper.pdf',
      title: 'Paper',
      sha256: 'hash',
      pageCount: 1,
      status: DocumentStatus.ready,
      createdAt: DateTime.utc(2026),
      embeddingProfileId: 'profile',
      sections: const [
        DocumentSection(
          id: 'doc:s0',
          ordinal: 0,
          name: 'Results',
          kind: SectionKind.body,
          startPage: 1,
          endPage: 1,
          startChar: 0,
          endChar: 8,
          text: 'Original',
        ),
      ],
      chunks: const [
        PaperChunk(
          id: 'doc:s0:c0',
          vectorId: 10,
          page: 1,
          ordinal: 0,
          section: 'Results',
          sectionId: 'doc:s0',
          startChar: 0,
          endChar: 8,
          text: 'Original',
        ),
      ],
    );
    await storage.savePaper(collection.id, paper);
    await storage.ensureOriginalRevision(collection.id, paper);
    final draft = await storage.createPendingRevision(
      collectionId: collection.id,
      paper: paper,
      sectionId: 'doc:s0',
      revisedContent: 'Revised',
      instruction: 'Edit',
    );
    final indexed = draft.copyWith(
      status: 'saved',
      indexStatus: 'indexed',
      chunks: const [
        PaperChunk(
          id: 'doc:revision:s0:c0',
          vectorId: 20,
          page: 1,
          ordinal: 0,
          section: 'Results',
          sectionId: 'doc:s0',
          startChar: 0,
          endChar: 7,
          text: 'Revised',
        ),
      ],
    );
    await storage.saveRevision(collection.id, indexed);
    await storage.activateRevision(collection.id, paper.id, indexed.id);

    final matches = await retrieve(
      collection.id,
      'results',
      storage: storage,
      embeddings: _Embedding(),
      index: _Index(),
    );

    expect(matches.single.text, 'Revised');
    expect(matches.single.vectorId, 20);
  });
}

class _Embedding extends EmbeddingClient {
  _Embedding() : super(apiKey: 'test', dimensions: 4);

  @override
  Future<List<double>> embedText(String text) async => [1, 0, 0, 0];
}

class _Index extends CollectionIndex {
  _Index() : super(dimensions: 4);

  @override
  Future<List<SearchResult>> search(
    List<double> query, {
    int topK = 15,
    List<int>? allowlist,
  }) async => [
    for (final id in [10, 20])
      if (allowlist?.contains(id) ?? true) SearchResult(vectorId: id, score: 1),
  ];
}
