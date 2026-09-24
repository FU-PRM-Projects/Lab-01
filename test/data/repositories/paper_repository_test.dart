import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/repositories/paper_repository.dart';
import 'package:lab_05/data/services/collection_index.dart';
import 'package:lab_05/data/services/embedding_client.dart';
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

    test(
      'deletePaper removes metadata, PDF file, and cleans index state',
      () async {
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
      },
    );

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

    test(
      'saving a draft indexes and activates a new immutable revision',
      () async {
        final collection = Collection(
          id: 'col_revision',
          name: 'Revision Test',
          createdAt: DateTime.utc(2026),
          embeddingProfile: const EmbeddingProfile(
            id: 'profile',
            dimensions: 4,
          ),
        );
        await storage.saveCollection(collection);
        final paper = PaperDocument(
          id: 'doc_revision',
          fileName: 'paper.pdf',
          title: 'Paper',
          sha256: 'hash',
          pageCount: 1,
          status: DocumentStatus.ready,
          createdAt: DateTime.utc(2026),
          embeddingProfileId: 'profile',
          sections: const [
            DocumentSection(
              id: 'doc_revision:s0',
              ordinal: 0,
              name: 'Results',
              kind: SectionKind.body,
              startPage: 1,
              endPage: 1,
              startChar: 0,
              endChar: 20,
              text: '## Results\n\nOriginal.',
            ),
          ],
          chunks: const [
            PaperChunk(
              id: 'doc_revision:s0:c0',
              vectorId: 1,
              page: 1,
              ordinal: 0,
              section: 'Results',
              sectionId: 'doc_revision:s0',
              startChar: 0,
              endChar: 20,
              text: '## Results\n\nOriginal.',
            ),
          ],
        );
        await storage.savePaper(collection.id, paper);
        await storage.ensureOriginalRevision(collection.id, paper);
        final draft = await storage.createPendingRevision(
          collectionId: collection.id,
          paper: paper,
          sectionId: 'doc_revision:s0',
          revisedContent: '## Results\n\nRevised and clearer.',
          instruction: 'Clarify results',
        );
        final index = _FakeIndex();
        final repository = _RevisionRepository(
          storage: storage,
          collectionId: collection.id,
          index: index,
        );

        final result = await repository.saveDraftRevision(
          documentId: paper.id,
          revisionId: draft.id,
          embeddings: _FakeEmbeddings(),
        );

        expect(result.revision.status, 'saved');
        expect(result.revision.indexStatus, 'indexed');
        expect(result.revision.chunks, isNotEmpty);
        expect(index.added, result.revision.chunks.length);
        expect(
          (await storage.loadActiveRevision(collection.id, paper))!.id,
          draft.id,
        );
        expect(await File(result.markdownPath).exists(), isTrue);

        await repository.revertToRevision(
          documentId: paper.id,
          revisionId: 'rev_original',
        );
        expect(
          (await storage.loadActiveRevision(collection.id, paper))!.id,
          'rev_original',
        );
      },
    );
  });
}

class _RevisionRepository extends PaperRepository {
  final CollectionIndex index;

  _RevisionRepository({
    required super.storage,
    required super.collectionId,
    required this.index,
  });

  @override
  Future<CollectionIndex> openIndex() async => index;
}

class _FakeIndex extends CollectionIndex {
  int added = 0;

  _FakeIndex() : super(dimensions: 4);

  @override
  bool get isOpen => true;

  @override
  int get length => added;

  @override
  Future<void> add(List<PaperChunk> chunks, List<List<double>> vectors) async {
    expect(chunks.length, vectors.length);
    added += chunks.length;
  }

  @override
  Future<void> save([String? targetPath]) async {}
}

class _FakeEmbeddings extends EmbeddingClient {
  _FakeEmbeddings() : super(apiKey: 'test', dimensions: 4);

  @override
  Future<List<List<double>>> embedTexts(
    List<String> texts, {
    int batchSize = 16,
  }) async => [
    for (final _ in texts) [1, 0, 0, 0],
  ];
}
