@Tags(['native'])
library;

import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/repositories/paper_repository.dart';
import 'package:lab_05/data/services/local_storage.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/data/services/collection_index.dart';
import 'package:lab_05/data/models/paper.dart';
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

    // Quantized search needs realistic dimensionality to rank meaningfully,
    // so the fixtures are generated rather than hand-written axis vectors.
    const dimensions = 128;

    List<double> synth(int seed) {
      var state = seed | 1;
      return List<double>.generate(dimensions, (_) {
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
        return state / 0x3FFFFFFF - 1.0;
      });
    }

    PaperChunk chunkFor(int vectorId, int ordinal) => PaperChunk(
      id: 'doc:p1:c$ordinal',
      vectorId: vectorId,
      page: 1,
      ordinal: ordinal,
      section: 'Section $ordinal',
      startChar: ordinal * 50,
      endChar: (ordinal + 1) * 50,
      text: 'Chunk $ordinal',
    );

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('turbovec_test');
      indexPath = '${tempDir.path}/test_vectors.tvim';
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
      'Create, insert, search, remove, save, and reload vector index',
      () async {
        final index = CollectionIndex(dimensions: dimensions, bitWidth: 4);
        addTearDown(index.close);
        await index.openOrCreate(indexPath);

        expect(index.isOpen, isTrue);
        expect(index.length, equals(0));
        expect(index.dim, equals(dimensions));

        final chunks = [chunkFor(10, 0), chunkFor(20, 1), chunkFor(30, 2)];
        final vectors = [synth(11), synth(22), synth(33)];

        await index.add(chunks, vectors);
        expect(index.length, equals(3));

        // Querying with a stored vector ranks that vector first.
        final searchResults = await index.search(vectors[0], topK: 2);
        expect(searchResults.length, equals(2));
        expect(searchResults[0].vectorId, equals(10));
        // Scores come back sorted best-first.
        expect(
          searchResults[0].score,
          greaterThanOrEqualTo(searchResults[1].score),
        );

        // The allowlist restricts the candidate set.
        final filteredResults = await index.search(
          vectors[0],
          topK: 5,
          allowlist: [20, 30],
        );
        expect(filteredResults.length, equals(2));
        expect(
          filteredResults.map((r) => r.vectorId).toSet(),
          equals({20, 30}),
        );

        await index.save();
        expect(File(indexPath).existsSync(), isTrue);

        await index.removeVectors([10]);
        expect(index.length, equals(2));
        final afterRemoval = await index.search(vectors[0], topK: 2);
        expect(afterRemoval.every((r) => r.vectorId != 10), isTrue);

        // The saved snapshot predates the removal and still holds 3 vectors.
        final reloadedIndex = CollectionIndex(
          dimensions: dimensions,
          bitWidth: 4,
        );
        addTearDown(reloadedIndex.close);
        await reloadedIndex.openOrCreate(indexPath);
        expect(reloadedIndex.length, equals(3));

        final reloadSearch = await reloadedIndex.search(vectors[1], topK: 1);
        expect(reloadSearch.length, equals(1));
        expect(reloadSearch[0].vectorId, equals(20));
      },
    );
  });

  test(
    'Collection repositories isolate indexes and respect their profiles',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'repository_test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final storage = LocalStorage(rootDir: directory);
      // TurboVec requires a dimension that is a positive multiple of 8.
      for (final (id, dimensions) in [('a', 8), ('b', 16)]) {
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
      expect(indexA.dim, 8);
      expect(indexB.dim, 16);
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
      await indexA.add([chunk], [List<double>.filled(8, 0.5)]);
      expect(indexA.length, 1);
      expect(indexB.length, 0);
      await expectLater(
        indexA.add([chunk], [List<double>.filled(8, 0.5)]),
        throwsA(anything),
      );
      expect(indexA.length, 1);
      await expectLater(
        indexB.add([chunk], [List<double>.filled(8, 0.5)]),
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
}
