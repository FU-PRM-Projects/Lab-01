import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
                    'function': {
                      'name': 'read_page',
                      'arguments': '{"documentId":"doc_',
                    },
                  },
                ],
              },
              {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': 'test","page":1}'},
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
                    'function': {'name': 'list_papers', 'arguments': '{}'},
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

/// The chunk the store returns for every query in these tests. Chunk text now
/// lives in the vector store rather than the paper's metadata JSON, so the fake
/// supplies it directly.
const _evidenceChunk = PaperChunk(
  id: 'doc_test:p1:c0',
  documentId: 'doc_test',
  page: 1,
  ordinal: 0,
  section: 'Results',
  startChar: 0,
  endChar: 13,
  text: 'Exact evidence',
);

class _Index extends CollectionIndex {
  // retrieve() skips the embedding call on an empty store, so the fake has to
  // look non-empty.
  @override
  int get length => 1;

  @override
  Future<List<ChunkHit>> search(List<double> query, {int topK = 15}) async => [
    const ChunkHit(chunk: _evidenceChunk, score: 1),
  ];

  @override
  Future<List<PaperChunk>> chunksForPage(
    String documentId,
    int page, {
    int limit = 4,
  }) async =>
      documentId == 'doc_test' && page == 1 ? [_evidenceChunk] : [];
}
