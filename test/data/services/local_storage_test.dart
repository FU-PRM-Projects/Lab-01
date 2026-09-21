import 'package:lab_05/data/models/app_settings.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/services/local_storage.dart';

void main() {
  group('LocalStorage Tests', () {
    late Directory tempDir;
    late LocalStorage storage;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('storage_test');
      storage = LocalStorage(rootDir: tempDir);
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('Collection persistence and listing', () async {
      final col1 = Collection(
        id: 'col_1',
        name: 'Collection Alpha',
        createdAt: DateTime.utc(2026, 9, 14, 1, 0, 0),
        embeddingProfile: const EmbeddingProfile(id: 'p1'),
      );
      final col2 = Collection(
        id: 'col_2',
        name: 'Collection Beta',
        createdAt: DateTime.utc(2026, 9, 14, 2, 0, 0),
        embeddingProfile: const EmbeddingProfile(id: 'p2'),
      );

      await storage.saveCollection(col1);
      await storage.saveCollection(col2);

      final list = await storage.listCollections();
      expect(list.length, equals(2));
      expect(list.map((c) => c.id), containsAll(['col_1', 'col_2']));

      final loaded = await storage.loadCollection('col_1');
      expect(loaded?.name, equals('Collection Alpha'));

      await storage.deleteCollection('col_1');
      final remaining = await storage.listCollections();
      expect(remaining.length, equals(1));
      expect(remaining.first.id, equals('col_2'));
    });

    test('Paper metadata save, list, and delete', () async {
      final col = Collection(
        id: 'col_docs',
        name: 'Docs Collection',
        createdAt: DateTime.now().toUtc(),
        embeddingProfile: const EmbeddingProfile(id: 'p'),
      );
      await storage.saveCollection(col);

      final doc = PaperDocument(
        id: 'doc_1',
        fileName: 'sample.pdf',
        title: 'Sample Paper',
        sha256: 'hash123',
        pageCount: 8,
        status: DocumentStatus.ready,
        createdAt: DateTime.now().toUtc(),
        embeddingProfileId: 'p',
      );

      await storage.savePaper(col.id, doc);

      final papers = await storage.listPapers(col.id);
      expect(papers.length, equals(1));
      expect(papers.first.title, equals('Sample Paper'));

      final loaded = await storage.loadPaper(col.id, 'doc_1');
      expect(loaded?.sha256, equals('hash123'));

      await storage.deletePaper(col.id, 'doc_1');
      final emptyPapers = await storage.listPapers(col.id);
      expect(emptyPapers.isEmpty, isTrue);
    });

    test(
      'Settings save and load with openRouterBaseUrl and openRouterApiKey',
      () async {
        final settings = const AppSettings(
          chatModel: 'custom/model-id',
          theme: 'dark',
          openRouterBaseUrl: 'https://custom.openrouter.proxy/v1',
          openRouterApiKey: 'sk-or-test-456',
          pinnedCollectionIds: ['col_1', 'col_2'],
        );
        await storage.saveSettings(settings);

        final loaded = await storage.loadSettings();
        expect(loaded.chatModel, equals('custom/model-id'));
        expect(
          loaded.openRouterBaseUrl,
          equals('https://custom.openrouter.proxy/v1'),
        );
        expect(loaded.openRouterApiKey, equals('sk-or-test-456'));
        expect(loaded.pinnedCollectionIds, equals(['col_1', 'col_2']));
        expect(
          loaded.chatCompletionsUrl,
          equals('https://custom.openrouter.proxy/v1/chat/completions'),
        );
        expect(
          loaded.embeddingsUrl,
          equals('https://custom.openrouter.proxy/v1/embeddings'),
        );

        // Verify the raw JSON file content contains the fields
        final rawJson = await storage.readJsonSafely(storage.settingsFilePath);
        expect(rawJson, isNotNull);
        expect(
          rawJson!['openRouterBaseUrl'],
          equals('https://custom.openrouter.proxy/v1'),
        );
        expect(rawJson['openRouterApiKey'], equals('sk-or-test-456'));
      },
    );

    test(
      'Legacy API key is migrated once and clearing it stays cleared',
      () async {
        final legacy = File('${tempDir.path}/.key_store');
        await legacy.writeAsString('legacy-test-key');
        final settings = await storage.loadSettings();
        expect(settings.openRouterApiKey, 'legacy-test-key');
        expect(await legacy.exists(), isFalse);
        await storage.saveSettings(settings.copyWith(openRouterApiKey: ''));
        expect((await storage.loadSettings()).openRouterApiKey, isEmpty);
      },
    );

    test('Failed replacement preserves the existing target', () async {
      await storage.writeJsonSafely('${tempDir.path}/value.json', {'value': 1});
      await storage.writeJsonSafely('${tempDir.path}/value.json', {'value': 2});
      expect(await storage.readJsonSafely('${tempDir.path}/value.json'), {
        'value': 2,
      });
      final target = Directory('${tempDir.path}/blocked.json')..createSync();
      await expectLater(
        storage.writeJsonSafely(target.path, {'value': 3}),
        throwsA(isA<FileSystemException>()),
      );
      expect(await target.exists(), isTrue);
      expect(
        tempDir.listSync().where((file) => file.path.contains('.tmp_')),
        isEmpty,
      );
    });
    test('Legacy TVEC index is retired and its papers marked for re-import',
        () async {
      final collection = Collection(
        id: 'col_legacy',
        name: 'Legacy',
        createdAt: DateTime.utc(2026),
        embeddingProfile: const EmbeddingProfile(id: 'profile_1'),
      );
      await storage.saveCollection(collection);

      PaperDocument paper(String id, DocumentStatus status) => PaperDocument(
        id: id,
        fileName: '$id.pdf',
        title: id,
        sha256: 'hash_$id',
        pageCount: 1,
        status: status,
        createdAt: DateTime.utc(2026),
        embeddingProfileId: 'profile_1',
      );

      await storage.savePaper('col_legacy', paper('doc_ready', DocumentStatus.ready));
      await storage.savePaper('col_legacy', paper('doc_failed', DocumentStatus.failed));

      final legacyVectors = File(storage.legacyIndexVectorsPath('col_legacy'));
      legacyVectors.parent.createSync(recursive: true);
      legacyVectors.writeAsBytesSync([0x54, 0x56, 0x45, 0x43]);
      await storage.writeJsonSafely(
        storage.legacyIndexStatePath('col_legacy'),
        {'status': 'clean'},
      );

      await storage.runStartupRecovery();

      expect(legacyVectors.existsSync(), isFalse);
      expect(File(storage.legacyIndexStatePath('col_legacy')).existsSync(), isFalse);

      final reloaded = await storage.listPapers('col_legacy');
      final ready = reloaded.firstWhere((p) => p.id == 'doc_ready');
      final failed = reloaded.firstWhere((p) => p.id == 'doc_failed');
      expect(ready.status, equals(DocumentStatus.needsReindex));
      expect(ready.error, contains('Re-import'));
      expect(failed.status, equals(DocumentStatus.failed));

      // Idempotent: a second pass leaves the marked paper alone.
      await storage.runStartupRecovery();
      final again = await storage.listPapers('col_legacy');
      expect(
        again.firstWhere((p) => p.id == 'doc_ready').status,
        equals(DocumentStatus.needsReindex),
      );
    });

    test('lanceDbDir resolves inside the collection index directory', () {
      expect(
        storage.lanceDbDir('col_1'),
        equals('${storage.indexDir('col_1')}${Platform.pathSeparator}lance'),
      );
    });
  });
}
