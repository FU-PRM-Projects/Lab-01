import 'package:path/path.dart' as p;
import 'package:lab_05/data/models/index_state.dart';

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:lab_05/data/services/collection_index.dart';
import 'package:lab_05/data/services/embedding_client.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/services/pdf_processor.dart';
import 'package:lab_05/data/services/local_storage.dart';

typedef ImportProgressCallback = void Function(String stage, double progress);

class PaperRepository {
  PaperRepository({required this.storage, required this.collectionId});

  final LocalStorage storage;
  final String collectionId;
  CollectionIndex? _index;
  Future<CollectionIndex>? _opening;

  Future<CollectionIndex> openIndex() => _opening ??= _openIndex();

  Future<CollectionIndex> _openIndex() async {
    try {
      final collection = await storage.loadCollection(collectionId);
      if (collection == null) {
        throw StateError('Collection not found: $collectionId');
      }
      final index = CollectionIndex(
        dimensions: collection.embeddingProfile.dimensions,
      );
      _index = index;
      await index.openOrCreate(storage.indexVectorsPath(collectionId));
      return index;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  void close() => _index?.close();

  Future<PaperDocument> importPaper({
    required File sourcePdfFile,
    required EmbeddingClient embeddings,
    ImportProgressCallback? onProgress,
  }) async {
    final index = await openIndex();
    onProgress?.call('Reading PDF file...', 0.1);

    // 1. Compute SHA-256 hash of PDF
    final hashDigest = await sha256.bind(sourcePdfFile.openRead()).first;
    final sha256Hex = hashDigest.toString();

    // Check duplicate hash within collection
    final existingPapers = await storage.listPapers(collectionId);
    final duplicate = existingPapers
        .where((p) => p.sha256 == sha256Hex && p.status == DocumentStatus.ready)
        .firstOrNull;
    if (duplicate != null) {
      onProgress?.call('Paper already imported', 1.0);
      return duplicate;
    }

    // 2. Generate new document ID and copy PDF to collection documents folder
    final documentId = 'doc_${const Uuid().v4()}';
    final targetPdfPath = storage.paperPdfPath(collectionId, documentId);
    final targetPdfFile = File(targetPdfPath);
    final parentDir = targetPdfFile.parent;
    if (!parentDir.existsSync()) {
      parentDir.createSync(recursive: true);
    }
    await sourcePdfFile.copy(targetPdfPath);

    final originalFileName = p.basename(sourcePdfFile.path);

    // 3. Create metadata with status: processing
    var paperDoc = PaperDocument(
      schemaVersion: 1,
      id: documentId,
      fileName: originalFileName,
      title: p.basenameWithoutExtension(originalFileName).replaceAll('_', ' '),
      sha256: sha256Hex,
      pageCount: 0,
      status: DocumentStatus.processing,
      createdAt: DateTime.now().toUtc(),
      embeddingProfileId: embeddings.model,
      chunks: const [],
    );
    await storage.savePaper(collectionId, paperDoc);

    try {
      // 4. Extract pages and chunks
      onProgress?.call('Extracting text and sections...', 0.3);
      final extractResult = await PdfProcessor.processPdf(
        targetPdfPath,
        documentId: documentId,
        fallbackTitle: paperDoc.title,
      );

      if (extractResult.chunks.isEmpty) {
        throw StateError(
          'No extractable text found in PDF. The document may be image-only/scanned, which requires OCR.',
        );
      }

      // 5. Reserve monotonic vector IDs from collection
      final collection = await storage.loadCollection(collectionId);
      if (collection == null) {
        throw StateError('Collection $collectionId not found');
      }

      int currentVectorId = collection.nextVectorId;
      final List<PaperChunk> assignedChunks = [];
      for (final chunk in extractResult.chunks) {
        assignedChunks.add(
          PaperChunk(
            id: chunk.id,
            vectorId: currentVectorId++,
            page: chunk.page,
            ordinal: chunk.ordinal,
            section: chunk.section,
            startChar: chunk.startChar,
            endChar: chunk.endChar,
            text: chunk.text,
            documentId: documentId,
            documentTitle: extractResult.title,
            documentFileName: originalFileName,
          ),
        );
      }

      // Update collection nextVectorId
      await storage.saveCollection(
        collection.copyWith(nextVectorId: currentVectorId),
      );

      // Save assigned chunks in metadata before vector insert
      paperDoc = paperDoc.copyWith(
        title: extractResult.title,
        pageCount: extractResult.pageCount,
        chunks: assignedChunks,
      );
      await storage.savePaper(collectionId, paperDoc);

      // 6. Generate embeddings
      onProgress?.call(
        'Generating embeddings (${assignedChunks.length} chunks)...',
        0.5,
      );
      final chunkTexts = assignedChunks.map((c) => c.text).toList();
      final vectors = await embeddings.embedTexts(chunkTexts);

      if (vectors.length != assignedChunks.length) {
        throw StateError(
          'Embedding count mismatch: expected ${assignedChunks.length}, got ${vectors.length}',
        );
      }

      // 7. Save index state as dirty before native mutation
      onProgress?.call('Indexing vectors...', 0.8);
      final indexFilePath = storage.indexVectorsPath(collectionId);
      if (!index.isOpen) {
        await index.openOrCreate(indexFilePath);
      }

      await storage.saveIndexState(
        collectionId,
        IndexState(
          status: 'dirty',
          embeddingProfileId: collection.embeddingProfile.id,
          dimensions: collection.embeddingProfile.dimensions,
          pending: {'operation': 'import', 'documentId': documentId},
        ),
      );

      // 8. Insert vectors into TurboVEC index and save
      await index.add(assignedChunks, vectors);
      await index.save(indexFilePath);

      // 9. Mark paper as ready, index state as clean
      paperDoc = paperDoc.copyWith(status: DocumentStatus.ready);
      await storage.savePaper(collectionId, paperDoc);

      await storage.saveIndexState(
        collectionId,
        IndexState(
          status: 'clean',
          embeddingProfileId: collection.embeddingProfile.id,
          dimensions: collection.embeddingProfile.dimensions,
          vectorCount: index.length,
          pending: null,
        ),
      );

      onProgress?.call('Paper ready!', 1.0);
      return paperDoc;
    } catch (e, stack) {
      debugPrint('Import paper failed for $documentId: $e\n$stack');
      paperDoc = paperDoc.copyWith(
        status: DocumentStatus.failed,
        error: e.toString(),
      );
      await storage.savePaper(collectionId, paperDoc);
      rethrow;
    }
  }
}
