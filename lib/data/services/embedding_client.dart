import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

import 'package:lab_05/data/models/app_settings.dart';

class EmbeddingClient {
  EmbeddingClient({
    required this.apiKey,
    this.model = 'google/gemini-embedding-2',
    this.dimensions = 768,
    this.baseUrl,
    http.Client? client,
  }) : _client = RetryClient(
         client ?? http.Client(),
         retries: 2,
         when: (response) =>
             response.statusCode == 429 || response.statusCode >= 500,
       );

  final String apiKey;
  final String model;
  final int dimensions;
  final String? baseUrl;
  final http.Client _client;
  final _abort = Completer<void>();

  String get endpoint => AppSettings(
    openRouterBaseUrl: baseUrl ?? AppSettings.defaultOpenRouterBaseUrl,
  ).embeddingsUrl;

  Future<List<double>> embedText(String text) async =>
      (await embedTexts([text])).single;

  Future<List<List<double>>> embedTexts(
    List<String> texts, {
    int batchSize = 16,
  }) async {
    RangeError.checkValueInInterval(batchSize, 1, 2048, 'batchSize');
    final embeddings = <List<double>>[];
    for (var start = 0; start < texts.length; start += batchSize) {
      if (_abort.isCompleted) throw StateError('Embedding request cancelled');
      final batch = texts.sublist(start, min(start + batchSize, texts.length));
      final request =
          http.AbortableRequest(
              'POST',
              Uri.parse(endpoint),
              abortTrigger: _abort.future,
            )
            ..headers.addAll({
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            })
            ..body = jsonEncode({
              'model': model,
              'input': batch,
              'dimensions': dimensions,
            });
      final response = await http.Response.fromStream(
        await _client.send(request),
      );
      if (response.statusCode != 200) {
        throw HttpException(
          'OpenRouter embeddings error (${response.statusCode}): ${response.body}',
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (json['data'] as List<dynamic>).cast<Map<String, dynamic>>()
        ..sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));
      if (items.length != batch.length) {
        throw const FormatException('Embedding count mismatch');
      }
      for (var i = 0; i < items.length; i++) {
        if (items[i]['index'] != i) {
          throw const FormatException('Invalid embedding response index');
        }
        final vector = (items[i]['embedding'] as List<dynamic>)
            .map((value) => (value as num).toDouble())
            .toList();
        if (vector.length != dimensions ||
            vector.any((value) => !value.isFinite)) {
          throw FormatException('Expected $dimensions finite embedding values');
        }
        final norm = sqrt(
          vector.fold<double>(0, (sum, value) => sum + value * value),
        );
        if (!norm.isFinite || norm == 0) {
          throw const FormatException('Embedding has invalid magnitude');
        }
        embeddings.add(
          vector.map((value) => value / norm).toList(growable: false),
        );
      }
    }
    return embeddings;
  }

  void close() {
    if (_abort.isCompleted) return;
    _abort.complete();
    _client.close();
  }
}
