import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

import 'package:lab_05/data/models/app_settings.dart';

/// One thing to embed: a passage, or a figure with the text that describes it.
///
/// A figure embeds as a single joint vector over its image *and* its caption,
/// so it lands in the same space as the text chunks and needs no second index
/// or separate query path.
class EmbeddingInput {
  final String text;

  /// Image bytes for a figure, or null for a plain passage.
  final Uint8List? imageBytes;

  /// Media type of [imageBytes], e.g. `image/png`.
  final String? imageMediaType;

  const EmbeddingInput.text(this.text)
    : imageBytes = null,
      imageMediaType = null;

  const EmbeddingInput.image({
    required this.text,
    required Uint8List bytes,
    required String mediaType,
  }) : imageBytes = bytes,
       imageMediaType = mediaType;

  bool get hasImage => imageBytes != null;

  /// The OpenRouter content array for this input.
  Map<String, dynamic> toContent() => {
    'content': [
      if (text.trim().isNotEmpty) {'type': 'text', 'text': text},
      if (imageBytes != null)
        {
          'type': 'image_url',
          'image_url': {
            'url':
                'data:${imageMediaType ?? 'image/png'};base64,'
                '${base64Encode(imageBytes!)}',
          },
        },
    ],
  };
}

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
  }) => embedInputs([
    for (final text in texts) EmbeddingInput.text(text),
  ], batchSize: batchSize);

  /// Embeds a mix of passages and figures, returning one vector per input in
  /// the order they were given.
  ///
  /// Batches carrying an image are sent in smaller groups: a figure is worth
  /// a few hundred tokens against a passage's few dozen, and a full batch of
  /// them makes for a large request and a slow one.
  Future<List<List<double>>> embedInputs(
    List<EmbeddingInput> inputs, {
    int batchSize = 16,
    int imageBatchSize = 4,
  }) async {
    RangeError.checkValueInInterval(batchSize, 1, 2048, 'batchSize');
    RangeError.checkValueInInterval(imageBatchSize, 1, 2048, 'imageBatchSize');

    final embeddings = <List<double>>[];
    var start = 0;
    while (start < inputs.length) {
      if (_abort.isCompleted) throw StateError('Embedding request cancelled');

      // Group by kind so a single figure does not shrink a whole text batch.
      final isImageBatch = inputs[start].hasImage;
      final limit = isImageBatch ? imageBatchSize : batchSize;
      var end = start;
      while (end < inputs.length &&
          end - start < limit &&
          inputs[end].hasImage == isImageBatch) {
        end++;
      }
      final batch = inputs.sublist(start, end);
      start = end;
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
              // Plain strings for text-only batches, keeping the wire format
              // identical to what text documents have always sent; the content
              // array form is only needed once an image is involved.
              'input': isImageBatch
                  ? [for (final input in batch) input.toContent()]
                  : [for (final input in batch) input.text],
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
