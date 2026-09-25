import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lab_05/data/models/app_settings.dart';
import 'package:lab_05/data/services/indexing_pipeline.dart';
import 'package:lab_05/data/services/instruct_document_service.dart';
import 'package:lab_05/data/services/page_render_service.dart';
import 'package:lab_05/data/services/page_transcription_service.dart';
import 'package:lab_05/data/services/pdf_ocr_service.dart';
import 'package:lab_05/domain/indexing/section_resolver.dart';
import 'package:lab_05_rust/paper_native.dart' as native;

const _settings = AppSettings(
  openRouterApiKey: 'test-key',
  chatModel: 'test/model',
);

/// Stripper that reports the native extractor as unavailable (forces the fallback path).
Future<native.StrippedPdf> unavailableStripper({
  required String pdfPath,
  required int minWidth,
  required int minHeight,
}) async => throw StateError('native library not loaded');

/// An OCR client whose request always fails, forcing the fallback.
PdfOcrService failingOcr() => PdfOcrService(
  settings: _settings,
  client: MockClient(
    (request) async =>
        http.Response('{"error": {"message": "parser unavailable"}}', 502),
  ),
);

/// An OCR client that returns [pages] as a parsed document, plus any [figures]
/// the parser extracted itself.
PdfOcrService fakeOcr(
  List<String> pages, {
  List<({int page, String name})> figures = const [],
  void Function(int uploadedBytes)? onUpload,
  void Function(String modelId)? onModel,
}) => PdfOcrService(
  settings: _settings,
  client: MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    onModel?.call(body['model'] as String);
    final content = (body['messages'] as List).first['content'] as List;
    final data =
        (content.last as Map<String, dynamic>)['file']['file_data'] as String;
    onUpload?.call(base64Decode(data.split(',').last).length);

    return http.Response(
      jsonEncode({
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {
              'content': 'OK.',
              'annotations': [
                {
                  'type': 'file',
                  'file': {
                    'hash': 'test-hash',
                    'name': 'document.pdf',
                    'content': [
                      {'type': 'text', 'text': '<file name="document.pdf">'},
                      for (final page in pages) {'type': 'text', 'text': page},
                      for (final _ in figures)
                        {
                          'type': 'image_url',
                          'image_url': {
                            'url':
                                'data:image/jpeg;base64,${base64Encode(const [1, 2, 3])}',
                          },
                        },
                      {'type': 'text', 'text': '</file>'},
                    ],
                  },
                },
              ],
            },
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

/// A stripper that reports [images] and a shrunken PDF.
PdfStripper stripperWith(
  List<native.ExtractedImage> images, {
  int originalBytes = 4000,
  int strippedBytes = 1000,
}) =>
    ({
      required String pdfPath,
      required int minWidth,
      required int minHeight,
    }) async => native.StrippedPdf(
      pdf: Uint8List(strippedBytes),
      images: images,
      pageCount: 0,
      originalBytes: BigInt.from(originalBytes).toInt(),
      skipped: 0,
    );

native.ExtractedImage fakeImage({
  required int page,
  int indexOnPage = 0,
  String mediaType = 'image/png',
}) => native.ExtractedImage(
  page: page,
  indexOnPage: indexOnPage,
  name: 'Im$indexOnPage',
  width: 400,
  height: 300,
  mediaType: mediaType,
  bytes: Uint8List.fromList([1, 2, 3, 4]),
);

/// Stands in for a PDF: each entry is what the model will "read" off that page.
class FakePageImages implements PdfPageImages {
  FakePageImages(this.pageCount);

  final int pageCount;
  final rendered = <int>[];
  var closed = false;

  @override
  Future<int> open(String filePath) async => pageCount;

  @override
  Future<Uint8List> renderPage(int pageNumber) async {
    rendered.add(pageNumber);
    // The bytes only have to survive base64 encoding; the fake transcriber
    // answers from the page number it is asked about.
    return Uint8List.fromList([pageNumber]);
  }

  @override
  Future<void> close() async => closed = true;
}

/// A transcription client whose HTTP layer replies with [pageTexts], picked by
/// the single byte the fake renderer produced.
PageTranscriptionService fakeTranscriber(
  List<String> pageTexts, {
  Set<int> failOnPages = const {},
  void Function(String modelId)? onModel,
}) {
  return PageTranscriptionService(
    settings: _settings,
    client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      onModel?.call(body['model'] as String);
      final content =
          (body['messages'] as List).first['content'] as List<dynamic>;
      final url =
          (content.last as Map<String, dynamic>)['image_url']['url'] as String;
      final page = base64Decode(url.split(',').last).single;

      if (failOnPages.contains(page)) {
        return http.Response('{"error": {"message": "rate limited"}}', 429);
      }
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {'content': pageTexts[page - 1]},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

/// Fake instruct model answering the outline and bibliography prompts separately.
InstructDocumentService fakeInstruct({
  required Object outlineReply,
  Object referencesReply = const {'references': <Object>[]},
  void Function(String prompt)? onPrompt,
  void Function(String modelId)? onModel,
  void Function(String stage)? onStage,
}) {
  return InstructDocumentService(
    settings: _settings,
    client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      final system = messages.first['content'] as String;
      final isOutline = system == InstructDocumentService.outlineSystemPrompt;

      onModel?.call(body['model'] as String);
      onStage?.call(isOutline ? 'outline' : 'references');
      onPrompt?.call(messages.last['content'] as String);

      final reply = isOutline ? outlineReply : referencesReply;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {
                'content': reply is String ? reply : jsonEncode(reply),
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

void main() {
  const pageTexts = [
    'A Very Good Paper\nJane Doe\n\n## Abstract\nWe present a method.',
    '## 1 Introduction\nPrior work is vast and varied in its approaches.',
    '## References\n[1] Author A. A Paper. NeurIPS, 2020.',
  ];

  final outline = {
    'title': 'A Very Good Paper',
    'authors': ['Jane Doe'],
    'sections': [
      {'name': 'Abstract', 'rawHeading': 'Abstract', 'page': 1, 'level': 1},
      {
        'name': 'Introduction',
        'rawHeading': '1 Introduction',
        'page': 2,
        'level': 1,
      },
      {'name': 'References', 'rawHeading': 'References', 'page': 3, 'level': 1},
    ],
  };

  final bibliography = {
    'references': [
      {
        'marker': '[1]',
        'raw': 'Author A. A Paper. NeurIPS, 2020.',
        'authors': 'Author A',
        'title': 'A Paper',
        'venue': 'NeurIPS',
        'year': 2020,
      },
    ],
  };

  IndexingPipeline pipelineFor(
    FakePageImages images, {
    List<String>? texts,
    Object? outlineReply,
    Object? referencesReply,
    Set<int> failOnPages = const {},
    void Function(String prompt)? onPrompt,
    void Function(String modelId)? onTranscriptionModel,
    void Function(String modelId)? onIndexingModel,
    void Function(String stage)? onStage,
    AppSettings settings = _settings,
  }) {
    return IndexingPipeline(
      settings: settings,
      openPageImages: () => images,
      stripPdfImages: unavailableStripper,
      ocrFactory: (_) => failingOcr(),
      transcriberFactory: (_) => fakeTranscriber(
        texts ?? pageTexts,
        failOnPages: failOnPages,
        onModel: onTranscriptionModel,
      ),
      instructFactory: (_) => fakeInstruct(
        outlineReply: outlineReply ?? outline,
        referencesReply: referencesReply ?? bibliography,
        onPrompt: onPrompt,
        onModel: onIndexingModel,
        onStage: onStage,
      ),
    );
  }

  group('IndexingPipeline', () {
    test(
      'transcribes every page and builds sections, chunks, references',
      () async {
        final images = FakePageImages(3);
        final stages = <String>[];

        final indexed = await pipelineFor(images).run(
          pdfPath: 'paper.pdf',
          documentId: 'doc_1',
          onProgress: (stage, _) => stages.add(stage),
        );

        expect(images.rendered..sort(), [1, 2, 3]);
        expect(images.closed, isTrue);
        expect(indexed.pageCount, 3);
        expect(indexed.title, 'A Very Good Paper');
        expect(indexed.authors, ['Jane Doe']);

        expect(indexed.sections.map((s) => s.name), [
          SectionResolver.frontMatterName,
          'Abstract',
          'Introduction',
          'References',
        ]);
        expect(indexed.referencesSection, isNotNull);
        expect(indexed.references.single.venue, 'NeurIPS');

        // The bibliography is kept as structured references, not as chunks.
        expect(
          indexed.chunks.map((c) => c.section),
          isNot(contains('References')),
        );
        expect(indexed.chunks, isNotEmpty);
        expect(
          stages.where((s) => s.contains('Transcribing page')),
          hasLength(3),
        );
      },
    );

    test('each step calls its own configured model', () async {
      final transcriptionModels = <String>{};
      final indexingModels = <String>{};

      await pipelineFor(
        FakePageImages(3),
        settings: const AppSettings(
          openRouterApiKey: 'test-key',
          chatModel: 'chat/model',
          transcriptionModel: 'qwen/qwen3-vl-235b-a22b-instruct',
          indexingModel: 'qwen/qwen3-235b-a22b-2507',
          referenceModel: 'fast/reference-model',
        ),
        onTranscriptionModel: transcriptionModels.add,
        onIndexingModel: indexingModels.add,
      ).run(pdfPath: 'paper.pdf', documentId: 'doc_1');

      // Pages go to the vision model; outline and bibliography use separate models.
      expect(transcriptionModels, {'qwen/qwen3-vl-235b-a22b-instruct'});
      expect(indexingModels, {
        'qwen/qwen3-235b-a22b-2507',
        'fast/reference-model',
      });
    });

    test('defaults route each stage to its own model', () {
      const settings = AppSettings();
      final pipeline = IndexingPipeline(settings: settings);

      expect(pipeline.transcriptionModel, 'qwen/qwen3-vl-235b-a22b-instruct');
      // The outline and the bibliography are both short structured reads, so
      // they share a fast model rather than a frontier one.
      expect(pipeline.indexingModel, 'z-ai/glm-5.3-flashx');
      expect(pipeline.referenceModel, 'z-ai/glm-5.3-flashx');
    });

    test(
      'the bibliography is read from the references section alone',
      () async {
        final prompts = <String>[];
        final stages = <String>[];

        final indexed = await pipelineFor(
          FakePageImages(3),
          onPrompt: prompts.add,
          onStage: stages.add,
        ).run(pdfPath: 'paper.pdf', documentId: 'doc_1');

        // One outline call over the whole paper, then the bibliography windows.
        expect(stages, ['outline', 'references']);
        expect(prompts.first, contains('<!-- PAGE 1 -->'));

        // The reference call never resends the body of the paper, which is what
        // kept the old single call from overrunning its output budget.
        expect(prompts.last, contains('[1] Author A'));
        expect(prompts.last, isNot(contains('Prior work is vast')));
        expect(indexed.references.single.title, 'A Paper');
      },
    );

    test('a long bibliography is read in several windows', () async {
      final entries = List.generate(
        400,
        (i) => '[${i + 1}] Author $i. A Paper Titled Something. Venue, 2020.',
      );
      var windows = 0;

      final indexed = await pipelineFor(
        FakePageImages(3),
        texts: [
          pageTexts[0],
          pageTexts[1],
          '## References\n${entries.join('\n')}',
        ],
        referencesReply: {
          'references': [
            {'marker': '[1]', 'raw': 'One entry from this window.'},
          ],
        },
        onStage: (stage) {
          if (stage == 'references') windows++;
        },
      ).run(pdfPath: 'paper.pdf', documentId: 'doc_1');

      expect(windows, greaterThan(1));
      expect(indexed.references, hasLength(windows));
      expect(
        indexed.references.map((r) => r.index),
        List.generate(windows, (i) => i + 1),
      );
    });

    test(
      'the bibliography survives an outline that missed its heading',
      () async {
        final indexed = await pipelineFor(
          FakePageImages(3),
          outlineReply: {
            'title': 'A Very Good Paper',
            'sections': [
              {'name': 'Abstract', 'rawHeading': 'Abstract', 'page': 1},
            ],
          },
        ).run(pdfPath: 'paper.pdf', documentId: 'doc_1');

        expect(indexed.referencesSection, isNull);
        expect(indexed.references.single.title, 'A Paper');
      },
    );

    test('a paper with no bibliography makes no reference calls', () async {
      final stages = <String>[];

      final indexed = await pipelineFor(
        FakePageImages(2),
        texts: [pageTexts[0], pageTexts[1]],
        outlineReply: {
          'title': 'A Very Good Paper',
          'sections': [
            {'name': 'Abstract', 'rawHeading': 'Abstract', 'page': 1},
            {'name': 'Introduction', 'rawHeading': '1 Introduction', 'page': 2},
          ],
        },
        onStage: stages.add,
      ).run(pdfPath: 'paper.pdf', documentId: 'doc_1');

      expect(stages, ['outline']);
      expect(indexed.references, isEmpty);
    });

    test('chunks stay verbatim slices of the transcript', () async {
      final indexed = await pipelineFor(FakePageImages(3))
          .run(pdfPath: 'paper.pdf', documentId: 'doc_1');

      for (final chunk in indexed.chunks) {
        expect(
          chunk.text,
          indexed.transcript.text.substring(chunk.startChar, chunk.endChar),
        );
        expect(chunk.page, inInclusiveRange(1, 3));
        expect(chunk.sectionId, isNotEmpty);
      }
    });

    test('the outline call is given page markers, not raw pages', () async {
      final prompts = <String>[];
      await pipelineFor(
        FakePageImages(3),
        onPrompt: prompts.add,
      ).run(pdfPath: 'paper.pdf', documentId: 'doc_1');

      expect(prompts.first, contains('<!-- PAGE 1 -->'));
      expect(prompts.first, contains('<!-- PAGE 3 -->'));
    });

    test('blank pages are reported but do not shift page numbers', () async {
      final indexed = await pipelineFor(
        FakePageImages(3),
        texts: [
          pageTexts[0],
          PageTranscriptionService.blankPageMarker,
          pageTexts[2],
        ],
        outlineReply: {
          'title': 'A Very Good Paper',
          'sections': [
            {'name': 'Abstract', 'rawHeading': 'Abstract', 'page': 1},
            {'name': 'References', 'rawHeading': 'References', 'page': 3},
          ],
        },
      ).run(pdfPath: 'paper.pdf', documentId: 'doc_1');

      expect(indexed.blankPages, [2]);
      expect(indexed.pageCount, 3);
      final references = indexed.referencesSection!;
      expect(references.startPage, 3);
    });

    test('a failed page fails the whole import and closes the PDF', () async {
      final images = FakePageImages(3);

      await expectLater(
        pipelineFor(
          images,
          failOnPages: {2},
        ).run(pdfPath: 'paper.pdf', documentId: 'doc_1'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Transcription failed on page 2'),
          ),
        ),
      );
      expect(images.closed, isTrue);
    });

    test(
      'a document with no readable text fails rather than indexing empty',
      () async {
        await expectLater(
          pipelineFor(
            FakePageImages(2),
            texts: List.filled(2, PageTranscriptionService.blankPageMarker),
          ).run(pdfPath: 'paper.pdf', documentId: 'doc_1'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('No readable text'),
            ),
          ),
        );
      },
    );

    test(
      'an empty outline still indexes the document as one section',
      () async {
        final indexed =
            await pipelineFor(
              FakePageImages(3),
              outlineReply: {'sections': <Object>[]},
            ).run(
              pdfPath: 'paper.pdf',
              documentId: 'doc_1',
              fallbackTitle: 'paper',
            );

        expect(indexed.sections, hasLength(1));
        expect(indexed.title, 'paper');
        expect(indexed.chunks, isNotEmpty);
      },
    );

    test('a missing API key fails before any page is rendered', () async {
      final images = FakePageImages(3);
      final pipeline = IndexingPipeline(
        settings: const AppSettings(),
        openPageImages: () => images,
        stripPdfImages: unavailableStripper,
        ocrFactory: (_) => failingOcr(),
        transcriberFactory: (_) => fakeTranscriber(pageTexts),
        instructFactory: (_) => fakeInstruct(outlineReply: outline),
      );

      await expectLater(
        pipeline.run(pdfPath: 'paper.pdf', documentId: 'doc_1'),
        throwsA(isA<StateError>()),
      );
      expect(images.rendered, isEmpty);
    });
  });

  group('IndexingPipeline OCR fast path', () {
    const outline =
        '{"title":"Widget Dynamics","authors":["Jane Roe"],"sections":'
        '[{"name":"1 Introduction","page":1},{"name":"3 Results","page":2}]}';

    // Page 2 carries two figures and two captions, so caption pairing has
    // something to get right (or wrong).
    const pages = [
      '# 1 Introduction\n\nWidgets bend under load.',
      '# 3 Results\n\nFigure 1: Accuracy versus training steps.\n\n'
          'Throughput also improved.\n\nFigure 2: Throughput by regime.',
    ];

    IndexingPipeline build({
      List<native.ExtractedImage> images = const [],
      void Function(int uploadedBytes)? onUpload,
      List<String> ocrPages = pages,
    }) => IndexingPipeline(
      settings: _settings,
      openPageImages: () => FakePageImages(2),
      stripPdfImages: stripperWith(images),
      ocrFactory: (_) => fakeOcr(ocrPages, onUpload: onUpload),
      transcriberFactory: (_) => fakeTranscriber(const ['should not', 'run']),
      instructFactory: (_) => fakeInstruct(outlineReply: outline),
    );

    test('reads the whole paper without rendering a single page', () async {
      final images = FakePageImages(2);
      final pipeline = IndexingPipeline(
        settings: _settings,
        openPageImages: () => images,
        stripPdfImages: stripperWith(const []),
        ocrFactory: (_) => fakeOcr(pages),
        transcriberFactory: (_) => fakeTranscriber(const ['no', 'no']),
        instructFactory: (_) => fakeInstruct(outlineReply: outline),
      );

      final indexed = await pipeline.run(
        pdfPath: 'paper.pdf',
        documentId: 'doc_1',
      );

      expect(indexed.pageCount, 2);
      expect(indexed.transcript.pages[1].text, contains('Figure 1'));
      // The whole point of the change: no page was rendered or transcribed.
      expect(images.rendered, isEmpty);
    });

    test(
      'addresses the parse to the carrier model, not the chat model',
      () async {
        var addressedTo = '';
        const settings = AppSettings(
          openRouterApiKey: 'test-key',
          chatModel: 'expensive/chat-model',
        );
        final pipeline = IndexingPipeline(
          settings: settings,
          openPageImages: () => FakePageImages(2),
          stripPdfImages: stripperWith(const []),
          ocrFactory: (_) => fakeOcr(pages, onModel: (m) => addressedTo = m),
          transcriberFactory: (_) => fakeTranscriber(const ['no', 'no']),
          instructFactory: (_) => fakeInstruct(outlineReply: outline),
        );

        await pipeline.run(pdfPath: 'paper.pdf', documentId: 'doc_1');

        // The parser's reply is discarded, so the chat model's price must not
        // ride along on every import.
        expect(addressedTo, AppSettings.defaultOcrCarrierModel);
        expect(addressedTo, isNot('expensive/chat-model'));
      },
    );

    test('uploads the stripped PDF, not the original', () async {
      var uploaded = -1;
      final pipeline = build(onUpload: (bytes) => uploaded = bytes);

      await pipeline.run(pdfPath: 'paper.pdf', documentId: 'doc_1');

      expect(uploaded, 1000, reason: 'should send the stripped copy');
    });

    test('pairs figures with the captions on their page', () async {
      final pipeline = build(
        images: [
          fakeImage(page: 2, indexOnPage: 0),
          fakeImage(page: 2, indexOnPage: 1),
        ],
      );

      final indexed = await pipeline.run(
        pdfPath: 'paper.pdf',
        documentId: 'doc_1',
      );

      expect(indexed.figures, hasLength(2));
      expect(
        indexed.figures[0].caption,
        'Figure 1: Accuracy versus training steps.',
      );
      expect(indexed.figures[1].caption, 'Figure 2: Throughput by regime.');
      // Both sit on page 2, which the outline puts in "3 Results".
      expect(indexed.figures.map((f) => f.page), everyElement(2));
      expect(indexed.figures[0].section, '3 Results');
    });

    test('carries more figures than the parser would return', () async {
      // The parser caps extraction at 8 images; the native pass does not.
      final pipeline = build(
        images: [
          for (var i = 0; i < 12; i++) fakeImage(page: 2, indexOnPage: i),
        ],
      );

      final indexed = await pipeline.run(
        pdfPath: 'paper.pdf',
        documentId: 'doc_1',
      );

      expect(indexed.figures, hasLength(12));
      expect(
        indexed.figures.length,
        greaterThan(PdfOcrService.maxExtractedImages),
      );
    });

    test('a figure with no caption still embeds under its section', () async {
      final pipeline = build(
        images: [fakeImage(page: 1)],
        ocrPages: const ['# 1 Introduction\n\nNo captions here.', 'Page two.'],
      );

      final indexed = await pipeline.run(
        pdfPath: 'paper.pdf',
        documentId: 'doc_1',
      );

      expect(indexed.figures, hasLength(1));
      expect(indexed.figures.single.caption, isEmpty);
      expect(indexed.figures.single.embeddingText, contains('1 Introduction'));
      expect(indexed.figures.single.embeddingText, contains('page 1'));
    });

    test('figures survive a parser failure via the fallback', () async {
      final pipeline = IndexingPipeline(
        settings: _settings,
        openPageImages: () => FakePageImages(2),
        stripPdfImages: stripperWith([fakeImage(page: 2)]),
        ocrFactory: (_) => failingOcr(),
        transcriberFactory: (_) => fakeTranscriber(pages),
        instructFactory: (_) => fakeInstruct(outlineReply: outline),
      );

      final indexed = await pipeline.run(
        pdfPath: 'paper.pdf',
        documentId: 'doc_1',
      );

      expect(indexed.pageCount, 2);
      expect(indexed.figures, hasLength(1));
    });
  });

  group('PdfOcrService.parseAnnotations', () {
    Map<String, dynamic> response(List<Map<String, dynamic>> content) => {
      'choices': [
        {
          'message': {
            'content': 'OK.',
            'annotations': [
              {
                'type': 'file',
                'file': {'hash': 'h', 'name': 'd.pdf', 'content': content},
              },
            ],
          },
        },
      ],
    };

    test('keeps one page per text part and drops the envelope', () {
      final result = PdfOcrService.parseAnnotations(
        response([
          {'type': 'text', 'text': '<file name="d.pdf">'},
          {'type': 'text', 'text': 'page one'},
          {'type': 'text', 'text': 'page two'},
          {'type': 'text', 'text': '</file>'},
        ]),
      );

      expect(result.pages, ['page one', 'page two']);
      expect(result.hash, 'h');
      expect(result.figures, isEmpty);
    });

    test('places an image on the page that references it', () {
      final result = PdfOcrService.parseAnnotations(
        response([
          {'type': 'text', 'text': '<file name="d.pdf">'},
          {'type': 'text', 'text': 'page one'},
          {'type': 'text', 'text': 'see ![img-0.jpeg](img-0.jpeg) here'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,AQID'},
          },
          {'type': 'text', 'text': '</file>'},
        ]),
      );

      expect(result.figures, hasLength(1));
      expect(result.figures.single.page, 2);
      expect(result.figures.single.mediaType, 'image/jpeg');
      expect(result.figures.single.bytes, [1, 2, 3]);
    });

    test('an image no page references is left unplaced', () {
      final result = PdfOcrService.parseAnnotations(
        response([
          {'type': 'text', 'text': 'page one'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,AQID'},
          },
        ]),
      );

      expect(result.figures.single.isPlaced, isFalse);
    });

    test('a response with no file annotation is an error', () {
      expect(
        () => PdfOcrService.parseAnnotations({
          'choices': [
            {
              'message': {'content': 'OK.'},
            },
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
