@Tags(['native'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/repositories/paper_repository.dart';
import 'package:lab_05/data/services/collection_index.dart';
import 'package:lab_05/data/services/local_storage.dart';
import 'package:lab_05_rust/paper_native.dart' as rust_pdf;
import 'package:lab_05_rust/paper_native.dart';

PaperChunk chunk(
  String id, {
  String documentId = 'doc',
  int page = 1,
  int ordinal = 0,
  String section = 'Results',
  String text = 'passage',
}) => PaperChunk(
  id: id,
  documentId: documentId,
  page: page,
  ordinal: ordinal,
  section: section,
  startChar: 0,
  endChar: text.length,
  text: text,
);

void main() {
  setUpAll(() async {
    await initializeNative(
      libraryPath: 'packages/paper_native/rust/target/release/lab_05_rust.dll',
    );
  });

  group('Native collection index integration', () {
    late Directory tempDir;
    late String storePath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('lance_test');
      storePath = '${tempDir.path}/lance';
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('Chunks, scores and metadata survive a reopen', () async {
      final index = CollectionIndex(dimensions: 3);
      await index.open(storePath);

      await index.add(
        [
          chunk('doc:p1:c0', page: 1, text: 'on the x axis'),
          chunk('doc:p2:c0', page: 2, ordinal: 1, text: 'on the y axis'),
          chunk('doc:p3:c0', page: 3, ordinal: 2, text: 'between them'),
        ],
        [
          [1, 0, 0],
          [0, 1, 0],
          [0.7071, 0.7071, 0],
        ],
      );
      expect(index.length, 3);

      final hits = await index.search([1, 0, 0], topK: 2);
      expect(hits.length, 2);
      expect(hits[0].chunk.id, 'doc:p1:c0');
      // The hit carries everything retrieval needs; nothing is read from disk.
      expect(hits[0].chunk.text, 'on the x axis');
      expect(hits[0].chunk.page, 1);
      expect(hits[0].chunk.section, 'Results');
      expect(hits[0].chunk.parentDocId, 'doc');
      expect(hits[0].score, closeTo(1.0, 1e-4));
      expect(hits[1].chunk.id, 'doc:p3:c0');
      expect(hits[1].score, closeTo(0.7071, 1e-3));

      index.close();

      final reopened = CollectionIndex(dimensions: 3);
      addTearDown(reopened.close);
      await reopened.open(storePath);
      expect(reopened.length, 3);
      final again = await reopened.search([1, 0, 0], topK: 1);
      expect(again.single.chunk.text, 'on the x axis');
    });

    test('Page lookups return one page in reading order', () async {
      final index = CollectionIndex(dimensions: 2);
      addTearDown(index.close);
      await index.open(storePath);

      await index.add(
        [
          chunk('doc:p1:c1', page: 1, ordinal: 1, text: 'second'),
          chunk('doc:p1:c0', page: 1, ordinal: 0, text: 'first'),
          chunk('doc:p2:c0', page: 2, ordinal: 2, text: 'other page'),
          chunk('other:p1:c0', documentId: 'other', text: 'other doc'),
        ],
        [
          [1, 0],
          [0, 1],
          [1, 1],
          [0.5, 0.5],
        ],
      );

      final page = await index.chunksForPage('doc', 1);
      expect(page.map((c) => c.text), ['first', 'second']);
    });

    test('Deleting a document drops exactly its rows', () async {
      final index = CollectionIndex(dimensions: 2);
      addTearDown(index.close);
      await index.open(storePath);

      await index.add(
        [
          chunk('doc:p1:c0', text: 'keep me'),
          chunk('other:p1:c0', documentId: 'other', text: 'drop me'),
        ],
        [
          [1, 0],
          [0, 1],
        ],
      );
      expect(index.length, 2);

      await index.deleteDocument('other');
      expect(index.length, 1);
      final remaining = await index.search([1, 0], topK: 5);
      expect(remaining.single.chunk.text, 'keep me');
    });

    test('Retaining documents sweeps orphans and is a no-op when clean',
        () async {
      final index = CollectionIndex(dimensions: 2);
      addTearDown(index.close);
      await index.open(storePath);

      await index.add(
        [
          chunk('doc:p1:c0', text: 'ready'),
          chunk('orphan:p1:c0', documentId: 'orphan', text: 'orphan'),
        ],
        [
          [1, 0],
          [0, 1],
        ],
      );

      expect(await index.retainDocuments(['doc']), 1);
      expect(index.length, 1);
      // Nothing stale the second time, so nothing is written.
      expect(await index.retainDocuments(['doc']), 0);
      expect(index.length, 1);
    });

    test('A table built for another profile is rejected', () async {
      final first = CollectionIndex(dimensions: 3);
      await first.open(storePath);
      first.close();

      final mismatched = CollectionIndex(dimensions: 4);
      addTearDown(mismatched.close);
      await expectLater(
        mismatched.open(storePath),
        throwsA(isA<StateError>()),
      );
      expect(mismatched.isOpen, isFalse);
    });

    test('Wrong-width embeddings are rejected before they reach the store',
        () async {
      final index = CollectionIndex(dimensions: 3);
      addTearDown(index.close);
      await index.open(storePath);

      await expectLater(
        index.add(
          [chunk('doc:p1:c0')],
          [
            [1, 0],
          ],
        ),
        throwsArgumentError,
      );
      expect(index.length, 0);
    });
  });

  test('Collection repositories isolate stores and respect their profiles',
      () async {
    final directory = await Directory.systemTemp.createTemp('repository_test');
    addTearDown(() => directory.delete(recursive: true));
    final storage = LocalStorage(rootDir: directory);
    for (final (id, dimensions) in [('a', 2), ('b', 3)]) {
      await storage.saveCollection(
        Collection(
          id: id,
          name: id,
          createdAt: DateTime.utc(2026),
          embeddingProfile: EmbeddingProfile(id: id, dimensions: dimensions),
        ),
      );
    }
    final a = PaperRepository(storage: storage, collectionId: 'a');
    final b = PaperRepository(storage: storage, collectionId: 'b');
    addTearDown(a.close);
    addTearDown(b.close);

    final indexA = await a.openIndex();
    final indexB = await b.openIndex();
    expect(indexA.dim, 2);
    expect(indexB.dim, 3);
    expect(await a.openIndex(), same(indexA));

    await indexA.add(
      [chunk('doc:p1:c0')],
      [
        [1, 0],
      ],
    );
    expect(indexA.length, 1);
    expect(indexB.length, 0);

    // The store has no unique constraint; re-adding the same chunk appends.
    await indexA.add(
      [chunk('doc:p1:c0')],
      [
        [1, 0],
      ],
    );
    expect(indexA.length, 2);
    await indexA.deleteDocument('doc');
    expect(indexA.length, 0);

    await expectLater(
      indexB.add(
        [chunk('doc:p1:c0')],
        [
          [1, 0],
        ],
      ),
      throwsArgumentError,
    );
    expect(indexB.length, 0);
  });

  test('Opening a repository sweeps rows for documents that are not ready',
      () async {
    final directory = await Directory.systemTemp.createTemp('gc_test');
    addTearDown(() => directory.delete(recursive: true));
    final storage = LocalStorage(rootDir: directory);
    await storage.saveCollection(
      Collection(
        id: 'c',
        name: 'c',
        createdAt: DateTime.utc(2026),
        embeddingProfile: const EmbeddingProfile(id: 'c', dimensions: 2),
      ),
    );

    PaperDocument paper(String id, DocumentStatus status) => PaperDocument(
      id: id,
      fileName: '$id.pdf',
      title: id,
      sha256: 'hash_$id',
      pageCount: 1,
      status: status,
      createdAt: DateTime.utc(2026),
      embeddingProfileId: 'c',
    );

    await storage.savePaper('c', paper('doc_ready', DocumentStatus.ready));
    await storage.savePaper('c', paper('doc_failed', DocumentStatus.failed));

    final first = PaperRepository(storage: storage, collectionId: 'c');
    final index = await first.openIndex();
    await index.add(
      [
        chunk('doc_ready:p1:c0', documentId: 'doc_ready'),
        chunk('doc_failed:p1:c0', documentId: 'doc_failed'),
      ],
      [
        [1, 0],
        [0, 1],
      ],
    );
    expect(index.length, 2);
    first.close();

    // Reopening runs the sweep: only the ready document keeps its rows.
    final second = PaperRepository(storage: storage, collectionId: 'c');
    addTearDown(second.close);
    final reopened = await second.openIndex();
    expect(reopened.length, 1);
    final hits = await reopened.search([1, 0], topK: 5);
    expect(hits.single.chunk.parentDocId, 'doc_ready');
  });

  test('A corrupt store is surfaced without replacing what is on disk',
      () async {
    final directory = await Directory.systemTemp.createTemp('corrupt_index');
    addTearDown(() => directory.delete(recursive: true));
    // A file where the dataset directory belongs.
    final file = File('${directory.path}/lance/chunks.lance');
    file.parent.createSync(recursive: true);
    await file.writeAsString('broken-index');

    final index = CollectionIndex();
    addTearDown(index.close);
    await expectLater(
      index.open('${directory.path}/lance'),
      throwsA(anything),
    );
    expect(await file.readAsString(), 'broken-index');
    expect(index.isOpen, isFalse);
  });

  group('Rust PDF Chunking Tests', () {
    test('chunkText splits text preserving offsets and section', () async {
      const shortText = 'Antigravity Rust PDF Inspector pipeline.';
      final chunks = await rust_pdf.chunkText(
        pageText: shortText,
        pageNum: 1,
        documentId: 'doc_test',
        section: 'Introduction',
        startOrdinal: 0,
      );

      expect(chunks.length, equals(1));
      expect(chunks[0].id, equals('doc_test:p1:c0'));
      expect(chunks[0].text, equals(shortText));
      expect(chunks[0].page, equals(1));
      expect(chunks[0].section, equals('Introduction'));
      expect(chunks[0].startChar, equals(0));
      expect(chunks[0].endChar, equals(shortText.length));
    });
  });
}
