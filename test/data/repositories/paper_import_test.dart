@Tags(['native'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lab_05/data/models/app_settings.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/repositories/paper_repository.dart';
import 'package:lab_05/data/services/embedding_client.dart';
import 'package:lab_05/data/services/indexing_pipeline.dart';
import 'package:lab_05/data/services/instruct_document_service.dart';
import 'package:lab_05/data/services/local_storage.dart';
import 'package:lab_05/data/services/page_render_service.dart';
import 'package:lab_05/data/services/page_transcription_service.dart';
import 'package:lab_05_rust/paper_native.dart';

/// A PDF that never touches pdfrx: one byte per page, which the fake
/// transcription client reads back as the page number.
class FakePageImages implements PdfPageImages {
  FakePageImages(this.pageCount);

  final int pageCount;

  @override
  Future<int> open(String filePath) async => pageCount;

  @override
  Future<Uint8List> renderPage(int pageNumber) async =>
      Uint8List.fromList([pageNumber]);

  @override
  Future<void> close() async {}
}

http.Response completionOf(String content) {
  return http.Response(
    jsonEncode({
      'choices': [
        {
          'finish_reason': 'stop',
          'message': {'content': content},
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

/// The page number the fake renderer encoded into the image it was asked for.
int pageOf(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  final parts = (body['messages'] as List).first['content'] as List<dynamic>;
  final url =
      (parts.last as Map<String, dynamic>)['image_url']['url'] as String;
  return base64Decode(url.split(',').last).single;
}

/// Unit vectors, one per input, so the native index has something to store.
http.Response embeddingsFor(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  final inputs = (body['input'] as List<dynamic>).length;
  final dimensions = body['dimensions'] as int;
  return http.Response(
    jsonEncode({
      'data': [
        for (var i = 0; i < inputs; i++)
          {
            'index': i,
            'embedding': [
              for (var d = 0; d < dimensions; d++) ((i + d) % 7) + 1.0,
            ],
          },
      ],
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeNative(
      libraryPath: 'packages/paper_native/rust/target/release/lab_05_rust.dll',
    );
  });

  group('PaperRepository.importPaper', () {
    late Directory tempDir;
    late LocalStorage storage;

    const pageTexts = [
      'A Very Good Paper\nJane Doe\n\n## Abstract\nWe present a method here.',
      '## 1 Introduction\nPrior work is vast and varied in its approaches.',
      '## References\n[1] Author A. A Paper. NeurIPS, 2020.',
    ];

    final analysisJson = jsonEncode({
      'title': 'A Very Good Paper',
      'authors': ['Jane Doe'],
      'sections': [
        {'name': 'Abstract', 'rawHeading': 'Abstract', 'page': 1},
        {'name': 'Introduction', 'rawHeading': '1 Introduction', 'page': 2},
        {'name': 'References', 'rawHeading': 'References', 'page': 3},
      ],
      'references': [
        {
          'index': 1,
          'marker': '[1]',
          'raw': 'Author A. A Paper. NeurIPS, 2020.',
          'title': 'A Paper',
          'venue': 'NeurIPS',
          'year': 2020,
        },
      ],
    });

    IndexingPipeline workingPipeline(AppSettings settings) {
      return IndexingPipeline(
        settings: settings,
        openPageImages: () => FakePageImages(3),
        transcriberFactory: (_) => PageTranscriptionService(
          settings: settings,
          client: MockClient(
            (request) async => completionOf(pageTexts[pageOf(request) - 1]),
          ),
        ),
        instructFactory: (_) => InstructDocumentService(
          settings: settings,
          client: MockClient((_) async => completionOf(analysisJson)),
        ),
      );
    }

    EmbeddingClient fakeEmbeddings() => EmbeddingClient(
      apiKey: 'test-key',
      dimensions: 8,
      client: MockClient((request) async => embeddingsFor(request)),
    );

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('import_test');
      storage = LocalStorage(rootDir: tempDir);
      await storage.saveSettings(
        const AppSettings(openRouterApiKey: 'test-key'),
      );
      await storage.saveCollection(
        Collection(
          id: 'col_1',
          name: 'Test',
          createdAt: DateTime.now().toUtc(),
          embeddingProfile: EmbeddingProfile(
            id: 'profile',
            model: 'test/embed',
            dimensions: 8,
          ),
        ),
      );
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
      'stores sections, chunks and references and marks the paper ready',
      () async {
        final repository = PaperRepository(
          storage: storage,
          collectionId: 'col_1',
          pipelineFactory: workingPipeline,
        );
        addTearDown(repository.close);

        final source = File('${tempDir.path}/paper.pdf')
          ..writeAsBytesSync([1, 2, 3]);

        final paper = await repository.importPaper(
          sourcePdfFile: source,
          embeddings: fakeEmbeddings(),
        );

        expect(paper.status, DocumentStatus.ready);
        expect(paper.title, 'A Very Good Paper');
        expect(paper.authors, ['Jane Doe']);
        expect(paper.pageCount, 3);
        expect(paper.sections.map((s) => s.name), contains('Introduction'));
        expect(paper.referencesSection, isNotNull);
        expect(paper.references.single.title, 'A Paper');
        expect(paper.chunks, isNotEmpty);
        expect(
          paper.chunks.map((c) => c.vectorId).toSet(),
          hasLength(paper.chunks.length),
        );

        final reloaded = (await storage.listPapers('col_1')).single;
        expect(reloaded.sections.length, paper.sections.length);
        expect(reloaded.chunks.first.sectionId, isNotEmpty);
        expect(reloaded.status, DocumentStatus.ready);
      },
    );

    test('a pipeline failure marks the paper failed with the reason', () async {
      final repository = PaperRepository(
        storage: storage,
        collectionId: 'col_1',
        pipelineFactory: (settings) => IndexingPipeline(
          settings: settings,
          openPageImages: () => FakePageImages(1),
          transcriberFactory: (_) => PageTranscriptionService(
            settings: settings,
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'error': {'message': 'Insufficient credits'},
                }),
                402,
              ),
            ),
          ),
          instructFactory: (_) => InstructDocumentService(
            settings: settings,
            client: MockClient((_) async => completionOf(analysisJson)),
          ),
        ),
      );
      addTearDown(repository.close);

      final source = File('${tempDir.path}/broken.pdf')
        ..writeAsBytesSync([9, 9]);

      await expectLater(
        repository.importPaper(
          sourcePdfFile: source,
          embeddings: fakeEmbeddings(),
        ),
        throwsA(anything),
      );

      final stored = (await storage.listPapers('col_1')).single;
      expect(stored.status, DocumentStatus.failed);
      expect(stored.error, contains('Insufficient credits'));
      expect(stored.chunks, isEmpty);
    });
  });
}
