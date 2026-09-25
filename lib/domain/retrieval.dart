import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/services/local_storage.dart';
import 'package:lab_05/data/services/collection_index.dart';
import 'package:lab_05/data/services/embedding_client.dart';

Future<List<PaperChunk>> retrieve(
  String collectionId,
  String query, {
  required LocalStorage storage,
  required EmbeddingClient embeddings,
  required CollectionIndex index,
  int topK = 15,
  int finalLimit = 8,
}) async {
  // 1. Fetch ready documents in collection to build vectorId -> chunk lookup
  final papers = await storage.listPapers(collectionId);
  final readyPapers = papers
      .where((p) => p.status == DocumentStatus.ready)
      .toList();
  if (readyPapers.isEmpty) return [];

  final Map<int, PaperChunk> chunkMap = {};
  for (final paper in readyPapers) {
    final active = await storage.loadActiveRevision(collectionId, paper);
    final activeTextChunks = active?.chunks.isNotEmpty == true
        ? active!.chunks
        : paper.chunks.where((chunk) => !chunk.isFigure);
    final searchable = [
      ...activeTextChunks,
      ...paper.chunks.where((chunk) => chunk.isFigure),
    ];
    for (final chunk in searchable) {
      chunkMap[chunk.vectorId] = chunk;
    }
  }

  if (chunkMap.isEmpty) return [];

  // 2. Embed the query
  final queryVec = await embeddings.embedText(query);

  // 3. Search TurboVEC index
  final searchResults = await index.search(
    queryVec,
    topK: topK,
    allowlist: chunkMap.keys.toList(),
  );

  // 4. Map search results to chunks and deduplicate
  final List<PaperChunk> matchedChunks = [];
  final Set<String> seenKeys = {};

  for (final res in searchResults) {
    final chunk = chunkMap[res.vectorId];
    if (chunk == null) continue;

    // Deduplication key: same doc and same page and overlapping text
    final dedupKey = '${chunk.parentDocId}_${chunk.page}_${chunk.startChar}';
    if (seenKeys.contains(dedupKey)) continue;
    seenKeys.add(dedupKey);

    matchedChunks.add(chunk);
    if (matchedChunks.length >= finalLimit) break;
  }

  return matchedChunks;
}
