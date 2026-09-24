import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/app_settings.dart';
import 'package:lab_05/data/models/chat.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/repositories/paper_repository.dart';
import 'package:lab_05/data/services/collection_index.dart';
import 'package:lab_05/data/services/local_storage.dart';
import 'package:lab_05/ui/chat/chat_controller.dart';

void main() {
  late Directory directory;
  late _Storage storage;
  late ProviderContainer container;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('controller_test');
    storage = _Storage(directory);
    final collection = Collection(
      id: 'collection',
      name: 'Test',
      createdAt: DateTime.utc(2026),
      embeddingProfile: const EmbeddingProfile(id: 'test'),
    );
    final chat = Chat(
      id: 'chat',
      collectionId: collection.id,
      title: 'Test',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      messages: [],
    );
    container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(storage),
        settingsProvider.overrideWith(
          (ref) => SettingsNotifier(
            storage,
            const AppSettings(openRouterApiKey: 'test'),
          ),
        ),
        currentCollectionProvider.overrideWith((ref) => collection),
        currentChatProvider.overrideWith((ref) => chat),
        paperRepositoryProvider(collection.id)
            .overrideWith((ref) => _Repository(storage)),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'Double-send and stop while saving cannot start a paid request',
    () async {
      storage.pending = Completer<void>();
      final controller = container.read(chatControllerProvider.notifier);
      final first = controller.sendMessage('First');
      await controller.sendMessage('Second');
      expect(storage.chatWrites, 1);
      expect(container.read(chatControllerProvider).isStreaming, isTrue);
      await controller.stop();
      storage.pending!.complete();
      await first;
      expect(storage.chatWrites, 1);
      expect(container.read(chatControllerProvider).isStreaming, isFalse);
      expect(container.read(chatControllerProvider).streamingText, isNull);
    },
  );

  test(
    'Stop saves the partial answer once and clears streaming state',
    () async {
      final bytes = StreamController<List<int>>();
      final requested = Completer<void>();
      final client = MockClient.streaming((request, body) async {
        await body.drain<void>();
        requested.complete();
        return http.StreamedResponse(
          bytes.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      await http.runWithClient(() async {
        final controller = container.read(chatControllerProvider.notifier);
        await controller.sendMessage('Question');
        await requested.future;
        final rendered = Completer<void>();
        final subscription = container.listen(chatControllerProvider, (
          _,
          state,
        ) {
          if (state.streamingText == 'Partial answer' &&
              !rendered.isCompleted) {
            rendered.complete();
          }
        });
        bytes.add(
          utf8.encode(
            'data: ${jsonEncode({
              'id': 'response',
              'object': 'chat.completion.chunk',
              'created': 1,
              'model': 'test',
              'choices': [
                {
                  'index': 0,
                  'delta': {'content': 'Partial answer'},
                  'finish_reason': null,
                },
              ],
            })}\n\n',
          ),
        );
        await rendered.future.timeout(const Duration(seconds: 5));
        await controller.stop();
        await controller.stop();
        subscription.close();
        final saved = await storage.loadChat('collection', 'chat');
        expect(saved!.messages.map((message) => message.role), [
          'user',
          'assistant',
        ]);
        expect(saved.messages.last.content, 'Partial answer');
        expect(saved.messages.last.status, 'cancelled');
        expect(storage.chatWrites, 2);
        expect(container.read(chatControllerProvider).isStreaming, isFalse);
        expect(container.read(chatControllerProvider).streamingText, isNull);
        await bytes.close();
      }, () => client);
    },
  );

  test(
    'panel export creates a review card without writing artifact files',
    () async {
      final paper = PaperDocument(
        id: 'doc_1',
        fileName: 'paper.pdf',
        title: 'Paper',
        sha256: 'hash',
        pageCount: 1,
        status: DocumentStatus.ready,
        createdAt: DateTime.utc(2026),
        embeddingProfileId: 'test',
        sections: const [
          DocumentSection(
            id: 'section_1',
            ordinal: 0,
            name: 'Introduction',
            rawHeading: '1 Introduction',
            level: 1,
            kind: SectionKind.body,
            startPage: 1,
            endPage: 1,
            startChar: 0,
            endChar: 12,
            text: 'Introduction',
          ),
        ],
      );
      await storage.savePaper('collection', paper);
      final result = await container
          .read(chatControllerProvider.notifier)
          .exportSectionsFromPanel(paper, format: 'markdown');

      expect(result.type, 'sectionDraft');
      expect(result.status, 'pending');
      expect(result.artifactId, isNull);
      expect(result.revisionId, isNotNull);
      expect(
        await Directory(storage.artifactsDir('collection', 'doc_1')).exists(),
        isFalse,
      );
      final revision = await storage.loadRevision(
        'collection',
        'doc_1',
        result.revisionId!,
      );
      expect(revision!.createdBy, 'export_review');
      final saved = await storage.loadChat('collection', 'chat');
      expect(saved!.messages.map((message) => message.role), [
        'user',
        'assistant',
      ]);
      expect(saved.messages.last.artifacts.single.documentId, 'doc_1');
      expect(saved.messages.last.artifacts.single.requestedFormat, 'markdown');
      expect(container.read(chatControllerProvider).isStreaming, isFalse);

      await container
          .read(chatControllerProvider.notifier)
          .saveDraftRevision(result);
      final afterSave = await storage.loadChat('collection', 'chat');
      final exported = afterSave!.messages
          .expand((message) => message.artifacts)
          .single;
      expect(exported.type, 'sectionExport');
      expect(exported.status, 'saved');
      expect(exported.artifactId, isNotNull);
      expect(
        await File(
          storage.sectionsMarkdownPath(
            'collection',
            'doc_1',
            exported.artifactId,
          ),
        ).exists(),
        isTrue,
      );
    },
  );
}

class _Storage extends LocalStorage {
  _Storage(Directory directory) : super(rootDir: directory);
  int chatWrites = 0;
  Completer<void>? pending;
  @override
  Future<void> saveChat(String collectionId, Chat chat) async {
    chatWrites++;
    if (pending != null) await pending!.future;
    await super.saveChat(collectionId, chat);
  }
}

class _Repository extends PaperRepository {
  _Repository(LocalStorage storage)
    : super(storage: storage, collectionId: 'collection');
  @override
  Future<CollectionIndex> openIndex() async => CollectionIndex();
}
