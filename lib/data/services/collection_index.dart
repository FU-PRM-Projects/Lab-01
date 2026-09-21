import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05_rust/paper_native.dart';

/// A search hit: the chunk itself plus its cosine similarity.
class ChunkHit {
  final PaperChunk chunk;
  final double score;

  const ChunkHit({required this.chunk, required this.score});
}

/// The LanceDB table backing one collection.
///
/// The table stores each chunk's metadata and text next to its vector, so a
/// search returns everything retrieval needs and no vector-id bookkeeping is
/// kept anywhere. One store belongs to exactly one collection; never share one.
class CollectionIndex {
  NativeChunkStore? _store;
  final int dimensions;
  int _length = 0;
  int _dim = 0;

  CollectionIndex({this.dimensions = 768}) : _dim = dimensions;

  bool get isOpen => _store != null;
  int get length => _length;
  int get dim => _dim;

  /// Opens the collection's table, creating it on first use.
  Future<void> open(String directoryPath) async {
    close();

    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    final NativeChunkStore store;
    try {
      store = await NativeChunkStore.open(
        path: directoryPath,
        dim: dimensions,
      );
    } catch (e) {
      // The table was built for a different embedding profile. Surface the
      // same error the TVEC index did rather than resetting the data.
      if (e.toString().contains('DIM_MISMATCH')) {
        throw StateError(
          'Index dimensions do not match the collection profile. Reindex required.',
        );
      }
      rethrow;
    }

    _store = store;
    _length = await store.count();
    _dim = await store.dim();
  }

  /// Appends chunks and their embeddings in a single transaction.
  Future<void> add(List<PaperChunk> chunks, List<List<double>> vectors) async {
    final store = _store;
    if (store == null) {
      throw StateError('CollectionIndex is not open');
    }
    if (chunks.length != vectors.length) {
      throw ArgumentError(
        'Chunks and vectors count mismatch (${chunks.length} vs ${vectors.length})',
      );
    }
    if (chunks.isEmpty) return;

    for (final vector in vectors) {
      if (vector.length != _dim ||
          vector.any((value) => !value.isFinite) ||
          vector.every((value) => value == 0)) {
        throw ArgumentError('Expected $_dim finite, non-zero embedding values');
      }
    }

    await store.add(
      rows: chunks.map(_toRow).toList(),
      vectors: vectors.expand((vector) => vector).toList(),
    );
    _length = await store.count();
  }

  /// Top-k chunks nearest to the query embedding.
  Future<List<ChunkHit>> search(List<double> query, {int topK = 15}) async {
    final store = _store;
    if (store == null || _length == 0) {
      return [];
    }

    final hits = await store.search(query: query, k: topK);
    return hits
        .map((hit) => ChunkHit(chunk: _toChunk(hit.row), score: hit.score))
        .toList();
  }

  /// Passages on one physical page of one document, in reading order.
  Future<List<PaperChunk>> chunksForPage(
    String documentId,
    int page, {
    int limit = 4,
  }) async {
    final store = _store;
    if (store == null || _length == 0) {
      return [];
    }

    final rows = await store.pageChunks(
      docId: documentId,
      page: page,
      limit: limit,
    );
    return rows.map(_toChunk).toList();
  }

  /// Removes every chunk belonging to one document.
  Future<void> deleteDocument(String documentId) async {
    final store = _store;
    if (store == null) return;
    await store.deleteDoc(docId: documentId);
    _length = await store.count();
  }

  /// Drops chunks whose document is not in [documentIds], returning how many
  /// documents were removed. Writes nothing when there is nothing stale.
  Future<int> retainDocuments(List<String> documentIds) async {
    final store = _store;
    if (store == null) return 0;
    final removed = await store.retainDocs(docIds: documentIds);
    if (removed > 0) {
      _length = await store.count();
      debugPrint('Dropped $removed stale document(s) from the vector store');
    }
    return removed;
  }

  /// Compacts fragments and prunes superseded versions. Best effort.
  Future<void> compact() async {
    await _store?.compact();
  }

  void close() {
    _store?.dispose();
    _store = null;
    _length = 0;
  }

  RustChunkRow _toRow(PaperChunk chunk) => RustChunkRow(
    chunkId: chunk.id,
    docId: chunk.parentDocId,
    page: chunk.page,
    ordinal: chunk.ordinal,
    section: chunk.section,
    startChar: chunk.startChar,
    endChar: chunk.endChar,
    text: chunk.text,
  );

  PaperChunk _toChunk(RustChunkRow row) => PaperChunk(
    id: row.chunkId,
    documentId: row.docId,
    page: row.page,
    ordinal: row.ordinal,
    section: row.section,
    startChar: row.startChar,
    endChar: row.endChar,
    text: row.text,
  );
}
