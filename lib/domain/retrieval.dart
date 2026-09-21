import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/services/collection_index.dart';
import 'package:lab_05/data/services/embedding_client.dart';

/// Retrieves the passages most relevant to [query].
///
/// The store is already scoped to one collection and only holds rows for ready
/// documents, so there is no allowlist to build and no metadata to read from
/// disk: the hits carry their own text, page and offsets.
Future<List<PaperChunk>> retrieve(
  String query, {
  required EmbeddingClient embeddings,
  required CollectionIndex index,
  int topK = 15,
  int finalLimit = 8,
}) async {
  // Check before embedding: an empty collection must not cost an API call.
  if (index.length == 0) return [];

  final queryVec = await embeddings.embedText(query);
  final hits = await index.search(queryVec, topK: topK);

  final List<PaperChunk> matchedChunks = [];
  final Set<String> seenKeys = {};

  for (final hit in hits) {
    final chunk = hit.chunk;

    // Deduplication key: same doc and same page and overlapping text
    final dedupKey = '${chunk.parentDocId}_${chunk.page}_${chunk.startChar}';
    if (!seenKeys.add(dedupKey)) continue;

    matchedChunks.add(chunk);
    if (matchedChunks.length >= finalLimit) break;
  }

  return matchedChunks;
}
