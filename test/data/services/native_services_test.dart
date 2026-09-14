@Tags(['native'])
library;

import 'dart:typed_data';

import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/repositories/paper_repository.dart';
import 'package:lab_05/data/services/local_storage.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/data/services/collection_index.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05_rust/paper_native.dart' as rust_pdf;
import 'package:lab_05_rust/paper_native.dart';

void main() {
  setUpAll(() async {
    await initializeNative(
      libraryPath: 'packages/paper_native/rust/target/release/lab_05_rust.dll',
    );
  });

  group('Native collection index integration', () {
    late Directory tempDir;
    late String indexPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('turbovec_test');
      indexPath = '${tempDir.path}/test_vectors.tvec';
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
      'Create, insert, search, remove, save, and reload vector index',
      () async {
        final index = CollectionIndex(dimensions: 3, bitWidth: 4);
        addTearDown(index.close);
        await index.openOrCreate(indexPath);

        expect(index.isOpen, isTrue);
        expect(index.length, equals(0));
        expect(index.dim, equals(3));

        // Create 3 test chunks with 3-dimensional embeddings
        final chunks = [
          PaperChunk(
            id: 'doc:p1:c0',
            vectorId: 10,
            page: 1,
            ordinal: 0,
            section: 'Introduction',
            startChar: 0,
            endChar: 50,
            text: 'Chunk 1 aligned with X axis',
          ),
          PaperChunk(
            id: 'doc:p1:c1',
            vectorId: 20,
            page: 1,
            ordinal: 1,
            section: 'Methodology',
            startChar: 51,
            endChar: 100,
            text: 'Chunk 2 aligned with Y axis',
          ),
          PaperChunk(
            id: 'doc:p1:c2',
            vectorId: 30,
            page: 1,
            ordinal: 2,
            section: 'Results',
            startChar: 101,
            endChar: 150,
            text: 'Chunk 3 diagonal between X and Y',
          ),
        ];

        final vectors = [
          [1.0, 0.0, 0.0], // id 10
          [0.0, 1.0, 0.0], // id 20
          [0.7071, 0.7071, 0.0], // id 30
        ];

        await index.add(chunks, vectors);
        expect(index.length, equals(3));

        // Query aligned with X axis
        final searchResults = await index.search([1.0, 0.0, 0.0], topK: 2);
        expect(searchResults.length, equals(2));
        expect(searchResults[0].vectorId, equals(10));
        expect((searchResults[0].score - 1.0).abs(), lessThan(1e-4));
        expect(searchResults[1].vectorId, equals(30));
        expect((searchResults[1].score - 0.7071).abs(), lessThan(1e-3));

        // Test allowlist
        final filteredResults = await index.search(
          [1.0, 0.0, 0.0],
          topK: 5,
          allowlist: [20, 30],
        );
        expect(filteredResults.length, equals(2));
        expect(filteredResults[0].vectorId, equals(30));
        expect(filteredResults[1].vectorId, equals(20));

        // Save index to disk
        await index.save();
        expect(File(indexPath).existsSync(), isTrue);

        // Remove a vector
        await index.removeVectors([10]);
        expect(index.length, equals(2));

        // Reload index from file
        final reloadedIndex = CollectionIndex(dimensions: 3, bitWidth: 4);
        addTearDown(reloadedIndex.close);
        await reloadedIndex.openOrCreate(indexPath);
        expect(reloadedIndex.length, equals(3));

        final reloadSearch = await reloadedIndex.search([
          0.0,
          1.0,
          0.0,
        ], topK: 1);
        expect(reloadSearch.length, equals(1));
        expect(reloadSearch[0].vectorId, equals(20));
        expect((reloadSearch[0].score - 1.0).abs(), lessThan(1e-4));
      },
    );
  });

  test('Existing TVEC v1 files remain readable', () async {
    final directory = await Directory.systemTemp.createTemp('legacy_index');
    addTearDown(() => directory.delete(recursive: true));
    // Legacy header: magic, u32 version, u64 dimensions/bitWidth/count,
    // then u64 ID and f32 components, all little endian.
    final bytes = ByteData(48)
      ..setUint32(0, 0x43455654, Endian.little)
      ..setUint32(4, 1, Endian.little)
      ..setUint64(8, 2, Endian.little)
      ..setUint64(16, 4, Endian.little)
      ..setUint64(24, 1, Endian.little)
      ..setUint64(32, 42, Endian.little)
      ..setFloat32(40, 1, Endian.little)
      ..setFloat32(44, 0, Endian.little);
    final file = File('${directory.path}/vectors.tvim');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    final index = CollectionIndex(dimensions: 2);
    addTearDown(index.close);
    await index.openOrCreate(file.path);
    expect((await index.search([1, 0])).single.vectorId, 42);
    await index.save();
    await index.openOrCreate(file.path);
    expect(index.length, 1);
  });

  test(
    'Collection repositories isolate indexes and respect their profiles',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'repository_test',
      );
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
      const chunk = PaperChunk(
        id: 'doc:p1:c0',
        vectorId: 1,
        page: 1,
        ordinal: 0,
        section: '',
        startChar: 0,
        endChar: 1,
        text: 'a',
      );
      await indexA.add(
        [chunk],
        [
          [1, 0],
        ],
      );
      expect(indexA.length, 1);
      expect(indexB.length, 0);
      await expectLater(
        indexA.add(
          [chunk],
          [
            [1, 0],
          ],
        ),
        throwsA(anything),
      );
      expect(indexA.length, 1);
      await expectLater(
        indexB.add(
          [chunk],
          [
            [1, 0],
          ],
        ),
        throwsArgumentError,
      );
      expect(indexB.length, 0);
    },
  );

  test(
    'Corrupt indexes are surfaced without replacing the saved file',
    () async {
      final directory = await Directory.systemTemp.createTemp('corrupt_index');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/vectors.tvim');
      await file.writeAsString('broken-index');
      final index = CollectionIndex();
      addTearDown(index.close);
      await expectLater(index.openOrCreate(file.path), throwsA(anything));
      expect(await file.readAsString(), 'broken-index');
      expect(index.isOpen, isFalse);
    },
  );

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
