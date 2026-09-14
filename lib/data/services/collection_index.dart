import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05_rust/paper_native.dart';

class SearchResult {
  final int vectorId;
  final double score;

  const SearchResult({required this.vectorId, required this.score});
}

class CollectionIndex {
  NativeVectorIndex? _index;
  final int dimensions;
  final int bitWidth;
  String? _currentLoadedPath;
  int _length = 0;
  int _dim = 0;

  CollectionIndex({this.dimensions = 768, this.bitWidth = 4})
    : _dim = dimensions;

  bool get isOpen => _index != null;
  int get length => _length;
  int get dim => _dim;

  /// Open existing index from file or create a fresh one
  Future<void> openOrCreate(String indexPath) async {
    close();

    _currentLoadedPath = indexPath;
    final file = File(indexPath);
    if (file.existsSync() && file.lengthSync() > 0) {
      _index = await NativeVectorIndex.load(path: indexPath);
      _length = await _index!.len();
      _dim = await _index!.dim();
      if (_dim != dimensions) {
        close();
        throw StateError(
          'Index dimensions do not match the collection profile. Reindex required.',
        );
      }
      return;
    }

    _index = await NativeVectorIndex.newInstance(
      dim: dimensions,
      bitWidth: bitWidth,
    );
    _length = 0;
    _dim = dimensions;
    debugPrint(
      'Created fresh native vector index with dimensions=$dimensions, bitWidth=$bitWidth',
    );
  }

  /// Insert chunks and their embeddings
  Future<void> add(List<PaperChunk> chunks, List<List<double>> vectors) async {
    if (_index == null) {
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
    await _index!.addBatch(
      ids: chunks.map((chunk) => chunk.vectorId).toList(),
      vectors: vectors.expand((vector) => vector).toList(),
      dim: _dim,
    );
    _length = await _index!.len();
  }

  /// Search top-k vectors nearest to the query embedding
  Future<List<SearchResult>> search(
    List<double> query, {
    int topK = 15,
    List<int>? allowlist,
  }) async {
    if (_index == null || _length == 0) {
      return [];
    }

    final rawResults = await _index!.search(
      query: query,
      k: topK,
      allowlist: allowlist,
    );

    return rawResults
        .map((r) => SearchResult(vectorId: r.vectorId, score: r.score))
        .toList();
  }

  /// Remove document's vectors
  Future<void> removeVectors(List<int> vectorIds) async {
    if (_index == null) return;
    for (final id in vectorIds) {
      await _index!.remove(id: id);
    }
    _length = await _index!.len();
  }

  /// Save index snapshot to disk
  Future<void> save([String? targetPath]) async {
    final path = targetPath ?? _currentLoadedPath;
    if (_index == null || path == null) return;

    final parent = Directory(File(path).parent.path);
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }

    final tempPath = '$path.tmp';
    await _index!.write(path: tempPath);
    final tempFile = File(tempPath);
    if (tempFile.existsSync()) {
      tempFile.renameSync(path);
      debugPrint('Saved native vector index to $path ($_length vectors)');
    } else {
      throw StateError('Failed to save vector index to $tempPath');
    }
  }

  void close() {
    _index?.dispose();
    _index = null;
    _length = 0;
  }
}
