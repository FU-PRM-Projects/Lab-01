import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/services/collection_index.dart';
import 'package:lab_05/data/services/embedding_client.dart';
import 'package:lab_05/data/services/local_storage.dart';
import 'package:lab_05/domain/research_agent.dart';

void main() {
  late Directory directory;
  late LocalStorage storage;
  late _Embeddings embeddings;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('agent_test');
    storage = LocalStorage(rootDir: directory);
    embeddings = _Embeddings();
    await storage.savePaper(
      'collection',
      PaperDocument(
        id: 'doc_test',
        fileName: 'test.pdf',
        title: 'Test paper',
        sha256: 'hash',
        pageCount: 1,
        status: DocumentStatus.ready,
        createdAt: DateTime.utc(2026),
        embeddingProfileId: 'test',
        sections: const [
          DocumentSection(
            id: 'doc_test:s0',
            ordinal: 0,
            name: 'Results',
            rawHeading: '4 Results',
            level: 1,
            kind: SectionKind.body,
            startPage: 1,
            endPage: 1,
            startChar: 0,
            endChar: 13,
            text: '## 4 Results\n\nExact evidence',
          ),
        ],
        chunks: const [
          PaperChunk(
            id: 'doc_test:p1:c0',
            vectorId: 1,
            page: 1,
            ordinal: 0,
            section: 'Results',
            startChar: 0,
            endChar: 13,
            text: 'Exact evidence',
          ),
        ],
      ),
    );
  });
  tearDown(() => directory.delete(recursive: true));

  ResearchAgent agent(http.Client client) => ResearchAgent(
    apiKey: 'test-key',
    chatModel: 'test-model',
    baseUrl: 'https://example.test/v1',
    storage: storage,
    embeddings: embeddings,
    index: _Index(),
    client: client,
  );

  test(
    'Streams fragmented tool calls and reuses source IDs for the same passage',
    () async {
      final requests = <Map<String, dynamic>>[];
      final model = agent(
        MockClient((request) async {
          expect(request.url.path, '/v1/chat/completions');
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (requests.length == 1) {
            return _stream([
              {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call-1',
                    'type': 'function',
                    'function': {'name': 'read_page', 'arguments': '{"pa'},
                  },
                ],
              },
              {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': 'ge":1}'},
                  },
                ],
              },
            ], finishReason: 'tool_calls');
          }
          final messages = requests.last['messages'] as List<dynamic>;
          final tool = messages.last as Map<String, dynamic>;
          expect(tool['tool_call_id'], 'call-1');
          expect(tool['content'], contains('[S1]'));
          expect(tool['content'], contains('Exact evidence'));
          return _stream([
            {'content': 'Supported '},
            {'content': 'claim [S1].'},
          ]);
        }),
      );
      final events = await model
          .streamAnswer(collectionId: 'collection', userQuestion: 'Explain')
          .toList();
      expect(events.whereType<ChatError>(), isEmpty);
      expect(
        events.whereType<TextChunk>().map((event) => event.text).join(),
        'Supported claim [S1].',
      );
      final done = events.whereType<ChatDone>().single;
      expect(done.sources.keys, ['S1']);
      expect(done.sources['S1']!.documentId, 'doc_test');
      expect(requests.length, 2);
      expect(embeddings.closed, isTrue);
    },
  );

  test('Every tool call is logged with its arguments and outcome', () async {
    var count = 0;
    final model = agent(
      MockClient((request) async {
        count++;
        if (count == 1) {
          return _stream([
            {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call-1',
                  'type': 'function',
                  'function': {'name': 'read_page', 'arguments': '{"page":1}'},
                },
                {
                  'index': 1,
                  'id': 'call-2',
                  'type': 'function',
                  'function': {'name': 'read_page', 'arguments': '{"page":99}'},
                },
              ],
            },
          ], finishReason: 'tool_calls');
        }
        return _stream([
          {'content': 'Answer [S1].'},
        ]);
      }),
    );
    final events = await model
        .streamAnswer(collectionId: 'collection', userQuestion: 'Explain')
        .toList();

    final started = events.whereType<ToolCallStarted>().toList();
    final finished = events.whereType<ToolCallFinished>().toList();
    // The opening retrieval plus both model-requested calls.
    expect(started.map((event) => event.call.id), [
      'retrieval',
      'call-1',
      'call-2',
    ]);
    expect(started.every((event) => event.call.isRunning), isTrue);
    expect(
      finished.map((event) => event.call.id),
      started.map((event) => event.call.id),
    );

    final retrieval = finished.first.call;
    expect(retrieval.name, 'search_papers');
    expect(retrieval.arguments['query'], 'Explain');
    expect(retrieval.summary, '1 passage');
    expect(retrieval.isFailed, isFalse);
    expect(retrieval.durationMs, isNotNull);

    final page = finished[1].call;
    expect(page.arguments, {'page': 1});
    expect(page.summary, '1 passage');
    expect(page.resultPreview, contains('Exact evidence'));

    // A call the agent rejects is logged as failed, with the reason shown.
    final outOfRange = finished[2].call;
    expect(outOfRange.arguments['page'], 99);
    expect(outOfRange.isFailed, isTrue);
    expect(outOfRange.summary, 'Page is outside this document.');

    expect(events.whereType<ChatDone>(), hasLength(1));
  });

  test(
    'export_sections falls back to the only paper for a stale document id',
    () async {
      var count = 0;
      final model = agent(
        MockClient((request) async {
          count++;
          if (count == 1) {
            return _stream([
              {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'export-1',
                    'type': 'function',
                    'function': {
                      'name': 'export_sections',
                      'arguments': '{"documentId":"stale-id","format":"both"}',
                    },
                  },
                ],
              },
            ], finishReason: 'tool_calls');
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final messages = (body['messages'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          expect(
            messages.last['content'],
            contains('No Markdown or JSON file'),
          );
          return _stream([
            {'content': 'Section artifacts are ready.'},
          ]);
        }),
      );

      final events = await model
          .streamAnswer(
            collectionId: 'collection',
            userQuestion: 'Prepare reusable section artifacts',
          )
          .toList();

      expect(events.whereType<ChatError>(), isEmpty);
      final export = events
          .whereType<ToolCallFinished>()
          .map((event) => event.call)
          .singleWhere((call) => call.name == 'export_sections');
      expect(export.isFailed, isFalse);
      expect(export.summary, contains('1 sections'));
      final artifact = events.whereType<ArtifactCreated>().single.artifact;
      expect(artifact.documentId, 'doc_test');
      expect(artifact.requestedFormat, 'both');
      expect(artifact.type, 'sectionDraft');
      expect(artifact.status, 'pending');
      expect(artifact.artifactId, isNull);
      expect(artifact.revisionId, isNotNull);
      expect(
        await File(
          storage.sectionsMarkdownPath(
            'collection',
            'doc_test',
            artifact.artifactId,
          ),
        ).exists(),
        isFalse,
      );
      expect(
        await File(
          storage.sectionsJsonPath(
            'collection',
            'doc_test',
            artifact.artifactId,
          ),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'explicit Markdown export command works without a model request',
    () async {
      final model = agent(
        MockClient((_) async {
          fail('A direct section export must not call OpenRouter.');
        }),
      );

      final events = await model
          .streamAnswer(
            collectionId: 'collection',
            userQuestion: 'extract ra md',
          )
          .toList();

      expect(events.whereType<ChatError>(), isEmpty);
      expect(
        events.whereType<ToolCallStarted>().single.call.name,
        'export_sections',
      );
      expect(
        events.whereType<TextChunk>().single.text,
        contains('Chưa có file nào được lưu'),
      );
      final artifact = events.whereType<ArtifactCreated>().single.artifact;
      expect(artifact.requestedFormat, 'markdown');
      expect(artifact.type, 'sectionDraft');
      expect(artifact.status, 'pending');
      expect(
        await File(
          storage.sectionsMarkdownPath(
            'collection',
            'doc_test',
            artifact.artifactId,
          ),
        ).exists(),
        isFalse,
      );
      expect(embeddings.closed, isTrue);
    },
  );

  test('DSML text is executed as a tool call and never rendered', () async {
    var count = 0;
    final model = agent(
      MockClient((request) async {
        count++;
        if (count == 1) {
          return _stream([
            {
              'content':
                  '<|DSML|calls>'
                  '<|DSML|invoke name="export_sections">'
                  '<|DSML|parameter name="format" string="true">markdown'
                  '</|DSML|parameter>'
                  '</|DSML|invoke>'
                  '<|DSML|invoke name="export_sections">'
                  '<|DSML|parameter name="format" string="true">json'
                  '</|DSML|parameter>'
                  '</|DSML|invoke>'
                  '</|DSML|calls>',
            },
          ]);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = (body['messages'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final toolMessages = messages
            .where((message) => message['role'] == 'tool')
            .toList();
        expect(toolMessages, hasLength(1));
        expect(
          toolMessages.single['content'],
          contains('Created export review'),
        );
        return _stream([
          {'content': 'Review ready.'},
        ]);
      }),
    );

    final events = await model
        .streamAnswer(
          collectionId: 'collection',
          userQuestion: 'Prepare reusable artifacts',
        )
        .toList();

    expect(events.whereType<ChatError>().map((event) => event.error), isEmpty);
    expect(
      events.whereType<TextChunk>().map((event) => event.text).join(),
      'Review ready.',
    );
    final calls = events
        .whereType<ToolCallStarted>()
        .where((event) => event.call.name == 'export_sections')
        .toList();
    expect(calls, hasLength(1));
    expect(calls.single.call.arguments['format'], 'both');
    final artifact = events.whereType<ArtifactCreated>().single.artifact;
    expect(artifact.requestedFormat, 'both');
    expect(count, 2);
  });

  test('JSON draft payload is converted into a change card', () async {
    var count = 0;
    final model = agent(
      MockClient((request) async {
        count++;
        if (count == 1) {
          return _stream([
            {
              'content':
                  '```json\n'
                  '${jsonEncode({'sectionName': 'Results', 'baseRevisionId': 'rev_original', 'content': '## 4 Results\n\nExpanded explanation.'})}\n'
                  '```',
            },
          ]);
        }
        return _stream([
          {'content': 'Change draft ready for review.'},
        ]);
      }),
    );

    final events = await model
        .streamAnswer(
          collectionId: 'collection',
          userQuestion: 'p1',
          previousMessages: const [
            {'role': 'assistant', 'content': 'Bạn muốn chỉnh section nào?'},
          ],
        )
        .toList();

    expect(events.whereType<ChatError>().map((event) => event.error), isEmpty);
    final card = events.whereType<ArtifactCreated>().single.artifact;
    expect(card.type, 'sectionChangeDraft');
    expect(card.status, 'pending');
    expect(
      events.whereType<TextChunk>().map((event) => event.text).join(),
      isNot(contains('baseRevisionId')),
    );
    final revision = await storage.loadRevision(
      'collection',
      'doc_test',
      card.revisionId!,
    );
    expect(revision!.sections.single.text, contains('Expanded explanation'));
    expect(count, 2);
  });

  test('AI edit tool creates a persistent pending revision', () async {
    var count = 0;
    final model = agent(
      MockClient((request) async {
        count++;
        if (count == 1) {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final tools = (payload['tools'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          expect(tools, hasLength(1));
          expect(
            (tools.single['function'] as Map<String, dynamic>)['name'],
            'save_section_draft',
          );
          return _stream([
            {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'draft-1',
                  'type': 'function',
                  'function': {
                    'name': 'save_section_draft',
                    'arguments': jsonEncode({
                      'sectionId': 'stale-section-id',
                      'sectionName': 'Results',
                      'revisedContent': '## 4 Results\n\nClearer evidence.',
                      'instruction': 'Make the result clearer',
                    }),
                  },
                },
              ],
            },
          ], finishReason: 'tool_calls');
        }
        return _stream([
          {'content': 'Draft ready for review.'},
        ]);
      }),
    );

    final events = await model
        .streamAnswer(
          collectionId: 'collection',
          userQuestion: 'Rewrite the Results section more clearly',
        )
        .toList();

    expect(events.whereType<ChatError>(), isEmpty);
    final card = events.whereType<ArtifactCreated>().single.artifact;
    expect(card.type, 'sectionChangeDraft');
    expect(card.status, 'pending');
    final revision = await storage.loadRevision(
      'collection',
      'doc_test',
      card.revisionId!,
    );
    expect(revision, isNotNull);
    expect(revision!.isPending, isTrue);
    expect(revision.sections.single.text, contains('Clearer evidence'));
    final original = await storage.loadRevision(
      'collection',
      'doc_test',
      'rev_original',
    );
    expect(original!.sections.single.text, contains('Exact evidence'));
  });

  test('an ambiguous edit asks for a section instead of guessing', () async {
    final model = agent(
      MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['tools'] as List<dynamic>? ?? const [], isEmpty);
        return _stream([
          {'content': 'Which section should be edited: Results or another?'},
        ]);
      }),
    );

    final events = await model
        .streamAnswer(
          collectionId: 'collection',
          userQuestion: 'chỉnh chi tiết hơn',
        )
        .toList();

    expect(events.whereType<ArtifactCreated>(), isEmpty);
    expect(events.whereType<ChatError>().map((event) => event.error), isEmpty);
    expect(
      events.whereType<ChatDone>().single.fullAnswer,
      contains('section should be edited'),
    );
  });

  test(
    'a short clarification answer completes the pending edit flow',
    () async {
      var count = 0;
      final model = agent(
        MockClient((request) async {
          count++;
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final tools = (payload['tools'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          expect(tools, hasLength(1));
          expect(
            (tools.single['function'] as Map<String, dynamic>)['name'],
            'save_section_draft',
          );
          if (count == 1) {
            return _stream([
              {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'draft-follow-up',
                    'type': 'function',
                    'function': {
                      'name': 'save_section_draft',
                      'arguments': jsonEncode({
                        'sectionName': 'Results',
                        'revisedContent':
                            '## 4 Results\n\nMarkdown explanation added.',
                        'instruction': 'Add an explanatory Markdown note',
                      }),
                    },
                  },
                ],
              },
            ], finishReason: 'tool_calls');
          }
          return _stream([
            {'content': 'Change draft ready.'},
          ]);
        }),
      );

      final events = await model
          .streamAnswer(
            collectionId: 'collection',
            userQuestion: 'chú thích ở md',
            previousMessages: const [
              {
                'role': 'user',
                'content': 'Chỉnh section Results và thêm comment giải thích',
              },
              {
                'role': 'assistant',
                'content': 'Bạn muốn comment theo kiểu nào?',
              },
            ],
          )
          .toList();

      expect(
        events.whereType<ChatError>().map((event) => event.error),
        isEmpty,
      );
      final card = events.whereType<ArtifactCreated>().single.artifact;
      expect(card.type, 'sectionChangeDraft');
      expect(card.status, 'pending');
    },
  );

  test('Tool budget applies to every call in a multi-tool response', () async {
    var count = 0;
    final model = agent(
      MockClient((request) async {
        count++;
        if (count == 1) {
          return _stream([
            {
              'tool_calls': [
                for (var i = 0; i < 5; i++)
                  {
                    'index': i,
                    'id': 'call-$i',
                    'type': 'function',
                    'function': {
                      'name': 'read_page',
                      'arguments': '{"page":1}',
                    },
                  },
              ],
            },
          ], finishReason: 'tool_calls');
        }
        final json = jsonDecode(request.body) as Map<String, dynamic>;
        expect(json['tool_choice'], 'none');
        final toolMessages = (json['messages'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .where((m) => m['role'] == 'tool')
            .toList();
        expect(toolMessages, hasLength(5));
        expect(
          toolMessages.where(
            (m) => (m['content'] as String).contains('budget exhausted'),
          ),
          hasLength(2),
        );
        return _stream([
          {'content': 'Answer [S1].'},
        ]);
      }),
    );
    final events = await model
        .streamAnswer(collectionId: 'collection', userQuestion: 'Explain')
        .toList();
    expect(
      events.whereType<ToolStatus>().where(
        (event) => event.message.startsWith('Executing'),
      ),
      hasLength(3),
    );
    expect(events.whereType<ChatDone>(), hasLength(1));
    expect(count, 2);
  });

  test(
    'Provider failures are visible and do not become a completed answer',
    () async {
      final model = agent(
        MockClient(
          (_) async => http.Response(
            '{"error":{"message":"Invalid key","type":"authentication_error"}}',
            401,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final events = await model
          .streamAnswer(collectionId: 'collection', userQuestion: 'Explain')
          .toList();
      expect(events.whereType<ChatError>(), hasLength(1));
      expect(events.whereType<ChatDone>(), isEmpty);
      expect(embeddings.closed, isTrue);
    },
  );

  test(
    'Cancel during retrieval closes embeddings and prevents model requests',
    () async {
      embeddings.pending = Completer<List<double>>();
      var requests = 0;
      final model = agent(
        MockClient((_) async {
          requests++;
          return _stream([]);
        }),
      );
      final future = model
          .streamAnswer(collectionId: 'collection', userQuestion: 'Explain')
          .toList();
      await embeddings.started.future;
      model.cancel();
      embeddings.pending!.complete([1, 0, 0]);
      final events = await future;
      expect(embeddings.closed, isTrue);
      expect(requests, 0);
      expect(events.whereType<TextChunk>(), isEmpty);
      expect(events.whereType<ChatDone>(), isEmpty);
    },
  );
}

http.Response _stream(
  List<Map<String, Object?>> deltas, {
  String finishReason = 'stop',
}) {
  String chunk(Map<String, Object?> delta, String? finish) =>
      'data: ${jsonEncode({
        'id': 'completion',
        'object': 'chat.completion.chunk',
        'created': 1,
        'model': 'test-model',
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finish},
        ],
      })}\n\n';
  return http.Response(
    '${deltas.map((delta) => chunk(delta, null)).join()}${chunk({}, finishReason)}data: [DONE]\n\n',
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}

class _Embeddings extends EmbeddingClient {
  _Embeddings() : super(apiKey: 'test');
  bool closed = false;
  final started = Completer<void>();
  Completer<List<double>>? pending;
  @override
  Future<List<double>> embedText(String text) async {
    if (!started.isCompleted) started.complete();
    return pending == null ? [1, 0, 0] : pending!.future;
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

class _Index extends CollectionIndex {
  @override
  Future<List<SearchResult>> search(
    List<double> query, {
    int topK = 15,
    List<int>? allowlist,
  }) async => [const SearchResult(vectorId: 1, score: 1)];
}
