import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lab_05/data/services/embedding_client.dart';

void main() {
  test('Batches and restores ordering before normalizing embeddings', () async {
    var requests = 0;
    final client = EmbeddingClient(
      apiKey: 'test',
      dimensions: 2,
      client: MockClient((request) async {
        requests++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final inputs = body['input'] as List<dynamic>;
        return http.Response(
          jsonEncode({
            'data': [
              for (var i = inputs.length - 1; i >= 0; i--)
                {
                  'index': i,
                  'embedding': i == 0 ? [3, 4] : [0, 5],
                },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);
    expect(await client.embedTexts(['a', 'b', 'c'], batchSize: 2), [
      [0.6, 0.8],
      [0, 1],
      [0.6, 0.8],
    ]);
    expect(requests, 2);
  });

  test('Authentication failures are not retried', () async {
    var requests = 0;
    final client = EmbeddingClient(
      apiKey: 'test',
      client: MockClient((_) async {
        requests++;
        return http.Response('invalid key', 401);
      }),
    );
    addTearDown(client.close);
    await expectLater(client.embedText('text'), throwsA(isA<HttpException>()));
    expect(requests, 1);
  });

  for (final data in [
    <Map<String, Object>>[],
    [
      {
        'index': 0,
        'embedding': [1],
      },
    ],
    [
      {
        'index': 0,
        'embedding': [0, 0],
      },
    ],
    [
      {
        'index': 1,
        'embedding': [1, 0],
      },
    ],
  ]) {
    test('Rejects malformed embedding response $data', () async {
      final client = EmbeddingClient(
        apiKey: 'test',
        dimensions: 2,
        client: MockClient(
          (_) async => http.Response(jsonEncode({'data': data}), 200),
        ),
      );
      addTearDown(client.close);
      await expectLater(client.embedText('text'), throwsFormatException);
    });
  }

  test('Closed clients do not send more batches', () async {
    var requests = 0;
    final client = EmbeddingClient(
      apiKey: 'test',
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    client.close();
    await expectLater(client.embedText('text'), throwsStateError);
    expect(requests, 0);
  });
}
