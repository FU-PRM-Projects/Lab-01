import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/repositories/paper_repository.dart';
import 'package:lab_05/data/services/local_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PaperRepository & Project Chats Tests', () {
    late Directory tempDir;
    late LocalStorage storage;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('repo_test');
      storage = LocalStorage(rootDir: tempDir);
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('deletePaper removes metadata, PDF file, and cleans index state', () async {
      final col = Collection(
        id: 'col_del',
        name: 'Delete Test',
        createdAt: DateTime.now().toUtc(),
        embeddingProfile: const EmbeddingProfile(id: 'p1', dimensions: 4),
      );
      await storage.saveCollection(col);

      final paper = PaperDocument(
        schemaVersion: 1,
        id: 'doc_del_1',
        fileName: 'test.pdf',
        title: 'Test Paper',
        sha256: 'fakehash',
        pageCount: 1,
        status: DocumentStatus.ready,
        createdAt: DateTime.now().toUtc(),
        embeddingProfileId: 'p1',
        chunks: const [
          PaperChunk(
            id: 'doc_del_1:p1:c0',
            vectorId: 100,
            page: 1,
            ordinal: 0,
            section: 'Intro',
            startChar: 0,
            endChar: 10,
            text: 'Hello world',
          ),
        ],
      );
      await storage.savePaper(col.id, paper);

      // Create fake PDF file
      final pdfFile = File(storage.paperPdfPath(col.id, paper.id));
      await pdfFile.parent.create(recursive: true);
      await pdfFile.writeAsString('fake pdf bytes');
      expect(pdfFile.existsSync(), isTrue);

      final repo = PaperRepository(storage: storage, collectionId: col.id);
      addTearDown(repo.close);

      // Verify paper is listed
      var papers = await storage.listPapers(col.id);
      expect(papers.length, equals(1));

      // Delete paper
      await repo.deletePaper(paper.id);

      // Verify paper is removed from listing and disk
      papers = await storage.listPapers(col.id);
      expect(papers.isEmpty, isTrue);
      expect(pdfFile.existsSync(), isFalse);
    });

    test('ChatsNotifier isolates chats per project collection', () async {
      final col1 = Collection(
        id: 'col_chats_1',
        name: 'Project 1',
        createdAt: DateTime.now().toUtc(),
        embeddingProfile: const EmbeddingProfile(id: 'p1'),
      );
      final col2 = Collection(
        id: 'col_chats_2',
        name: 'Project 2',
        createdAt: DateTime.now().toUtc(),
        embeddingProfile: const EmbeddingProfile(id: 'p2'),
      );
      await storage.saveCollection(col1);
      await storage.saveCollection(col2);

      final notifier1 = ChatsNotifier(storage, col1.id);
      final notifier2 = ChatsNotifier(storage, col2.id);

      final chat1 = await notifier1.createNewChat('Project 1 Chat');
      final chat2 = await notifier2.createNewChat('Project 2 Chat');

      expect(notifier1.state.length, equals(1));
      expect(notifier1.state.first.id, equals(chat1.id));
      expect(notifier1.state.first.title, equals('Project 1 Chat'));

      expect(notifier2.state.length, equals(1));
      expect(notifier2.state.first.id, equals(chat2.id));
      expect(notifier2.state.first.title, equals('Project 2 Chat'));

      // Delete chat from Project 1
      await notifier1.deleteChat(chat1.id);
      expect(notifier1.state.isEmpty, isTrue);
      expect(notifier2.state.length, equals(1)); // Project 2 untouched
    });
  });
}
