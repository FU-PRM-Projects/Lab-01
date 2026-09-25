import 'package:path/path.dart' as p;
import 'package:lab_05/data/models/document_figure.dart';
import 'package:lab_05/data/models/index_state.dart';

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:lab_05/data/models/app_settings.dart';
import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/models/section_revision.dart';
import 'package:lab_05/data/services/collection_index.dart';
import 'package:lab_05/data/services/embedding_client.dart';
import 'package:lab_05/data/services/indexing_pipeline.dart';
import 'package:lab_05/data/services/local_storage.dart';

typedef ImportProgressCallback = void Function(String stage, double progress);

/// Builds the pipeline used for one import. Overridden in tests.
typedef IndexingPipelineFactory = IndexingPipeline Function(
  AppSettings settings,
);

/// Thrown when a paper is imported into a folder that already holds one.
class FolderOccupiedException implements Exception {
  FolderOccupiedException(this.paperTitle);

  /// Title of the paper already in the folder.
  final String paperTitle;

  @override
  String toString() =>
      'This folder already holds "$paperTitle". '
      'Create a new folder to import another paper.';
}

class PaperRepository {
  PaperRepository({
    required this.storage,
    required this.collectionId,
    IndexingPipelineFactory? pipelineFactory,
  }) : _pipelineFactory =
           pipelineFactory ??
           ((settings) => IndexingPipeline(settings: settings));

  final LocalStorage storage;
  final String collectionId;
  final IndexingPipelineFactory _pipelineFactory;
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
    } catch (e) {
      _opening = null;
      // If index is corrupt and collection has 0 papers, recover with a clean index
      final papers = await storage.listPapers(collectionId);
      if (papers.isEmpty) {
        final collection = await storage.loadCollection(collectionId);
        if (collection != null) {
          try {
            final vectorFile = File(storage.indexVectorsPath(collectionId));
            if (await vectorFile.exists()) {
              await vectorFile.delete();
            }
            final index = CollectionIndex(
              dimensions: collection.embeddingProfile.dimensions,
            );
            _index = index;
            await index.openOrCreate(storage.indexVectorsPath(collectionId));
            await storage.saveIndexState(
              collectionId,
              IndexState(
                status: 'clean',
                embeddingProfileId: collection.embeddingProfile.id,
                dimensions: collection.embeddingProfile.dimensions,
                vectorCount: 0,
                pending: null,
              ),
            );
            return index;
          } catch (_) {}
        }
      }
      rethrow;
    }
  }

  void close() => _index?.close();

  Future<void> deletePaper(String documentId) async {
    final papers = await storage.listPapers(collectionId);
    final paper = papers.where((p) => p.id == documentId).firstOrNull;
    if (paper != null && paper.chunks.isNotEmpty) {
      try {
        final collection = await storage.loadCollection(collectionId);
        final index = await openIndex();
        final revisions = await storage.listRevisions(collectionId, documentId);
        final vectorIds = {
          ...paper.chunks.map((c) => c.vectorId),
          ...revisions
              .expand((revision) => revision.chunks)
              .map((chunk) => chunk.vectorId),
        }.where((id) => id > 0).toList();
        await index.removeVectors(vectorIds);
        await index.save(storage.indexVectorsPath(collectionId));

        if (collection != null) {
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
        }
      } catch (e) {
        debugPrint('Warning: Could not remove vectors for $documentId: $e');
      }
    }
    await storage.deletePaper(collectionId, documentId);
  }

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

    // A folder holds exactly one paper. The UI hides every import entry once
    // the slot is taken; this check keeps the rule for any other caller.
    final occupant = existingPapers.where((p) => p.occupiesFolder).firstOrNull;
    if (occupant != null) {
      throw FolderOccupiedException(occupant.title);
    }
    // A failed or abandoned import is replaced rather than kept beside the
    // new paper, so the folder never lists more than one document.
    for (final leftover in existingPapers) {
      await deletePaper(leftover.id);
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
      id: documentId,
      fileName: originalFileName,
      title: p.basenameWithoutExtension(originalFileName).replaceAll('_', ' '),
      sha256: sha256Hex,
      pageCount: 0,
      status: DocumentStatus.processing,
      createdAt: DateTime.now().toUtc(),
      embeddingProfileId: embeddings.model,
    );
    await storage.savePaper(collectionId, paperDoc);

    try {
      // 4. Transcribe every page, read the structure, cut the chunks.
      final settings = await storage.loadSettings();
      final indexed = await _pipelineFactory(settings).run(
        pdfPath: targetPdfPath,
        documentId: documentId,
        fallbackTitle: paperDoc.title,
        onProgress: (stage, progress) =>
            // The pipeline owns the first 70% of the import; embedding and
            // the native index own the rest.
            onProgress?.call(stage, 0.1 + 0.6 * progress),
      );

      // 5. Save the figures and turn each into a chunk.
      //
      // A figure rides the same rails as a text passage from here on: it gets
      // a vector id, goes into the same index and comes back from the same
      // search. The only difference is that its vector is a joint embedding of
      // the image and its caption, and that retrieval sends the image itself
      // to the model.
      final figureChunks = await _saveFigures(
        collectionId: collectionId,
        documentId: documentId,
        figures: indexed.figures,
      );

      // 6. Reserve monotonic vector IDs from collection
      final collection = await storage.loadCollection(collectionId);
      if (collection == null) {
        throw StateError('Collection $collectionId not found');
      }

      var currentVectorId = collection.nextVectorId;
      final assignedChunks = [
        for (final chunk in [...indexed.chunks, ...figureChunks])
          chunk.copyWith(
            vectorId: currentVectorId++,
            documentId: documentId,
            documentTitle: indexed.title,
            documentFileName: originalFileName,
          ),
      ];

      await storage.saveCollection(
        collection.copyWith(nextVectorId: currentVectorId),
      );

      // Save the structure before the vector insert, so a failure past this
      // point still leaves the sections and references on disk.
      paperDoc = paperDoc.copyWith(
        title: indexed.title,
        authors: indexed.authors,
        pageCount: indexed.pageCount,
        sections: indexed.sections,
        chunks: assignedChunks,
        references: indexed.references,
      );
      await storage.savePaper(collectionId, paperDoc);

      // 7. Generate embeddings. Figure chunks embed jointly over their image
      // and caption; text chunks are unchanged.
      onProgress?.call(
        'Generating embeddings (${assignedChunks.length} chunks, '
        '${figureChunks.length} figures)...',
        0.75,
      );
      final inputs = <EmbeddingInput>[];
      for (final chunk in assignedChunks) {
        final path = chunk.imagePath;
        if (path == null) {
          inputs.add(EmbeddingInput.text(chunk.embeddingText));
          continue;
        }
        final file = File(storage.figurePath(collectionId, documentId, path));
        if (!file.existsSync()) {
          // The image went missing between saving and embedding; the caption
          // alone still makes the figure findable.
          inputs.add(EmbeddingInput.text(chunk.embeddingText));
          continue;
        }
        inputs.add(
          EmbeddingInput.image(
            text: chunk.embeddingText,
            bytes: await file.readAsBytes(),
            mediaType: chunk.imageMediaType ?? 'image/png',
          ),
        );
      }
      final vectors = await embeddings.embedInputs(inputs);

      if (vectors.length != assignedChunks.length) {
        throw StateError(
          'Embedding count mismatch: expected ${assignedChunks.length}, '
          'got ${vectors.length}',
        );
      }

      // 8. Save index state as dirty before native mutation
      onProgress?.call('Indexing vectors...', 0.9);
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

      // 9. Insert vectors into TurboVEC index and save
      await index.add(assignedChunks, vectors);
      await index.save(indexFilePath);

      // 10. Mark paper as ready, index state as clean
      paperDoc = paperDoc.copyWith(status: DocumentStatus.ready);
      await storage.savePaper(collectionId, paperDoc);
      await storage.ensureOriginalRevision(collectionId, paperDoc);

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

  Future<
    ({
      SectionRevision revision,
      String artifactId,
      String markdownPath,
      String jsonPath,
    })
  >
  saveDraftRevision({
    required String documentId,
    required String revisionId,
    required EmbeddingClient embeddings,
  }) async {
    final paper = await storage.loadPaper(collectionId, documentId);
    if (paper == null) throw StateError('Paper not found: $documentId');
    final loadedRevision = await storage.loadRevision(
      collectionId,
      documentId,
      revisionId,
    );
    if (loadedRevision == null) {
      throw StateError('Revision not found: $revisionId');
    }
    var revision = loadedRevision;

    try {
      if (!revision.isIndexed) {
        revision = revision.copyWith(
          status: 'saved',
          indexStatus: 'indexing',
          updatedAt: DateTime.now().toUtc(),
        );
        await storage.saveRevision(collectionId, revision);

        final collection = await storage.loadCollection(collectionId);
        if (collection == null) {
          throw StateError('Collection not found: $collectionId');
        }
        var nextVectorId = collection.nextVectorId;
        final chunks = _revisionChunks(
          paper,
          revision.sections,
          revision.id,
        ).map((chunk) => chunk.copyWith(vectorId: nextVectorId++)).toList();
        final vectors = await embeddings.embedTexts(
          chunks.map((chunk) => chunk.embeddingText).toList(),
        );
        await storage.saveCollection(
          collection.copyWith(nextVectorId: nextVectorId),
        );

        final index = await openIndex();
        await storage.saveIndexState(
          collectionId,
          IndexState(
            status: 'dirty',
            embeddingProfileId: collection.embeddingProfile.id,
            dimensions: collection.embeddingProfile.dimensions,
            vectorCount: index.length,
            pending: {
              'operation': 'saveRevision',
              'documentId': documentId,
              'revisionId': revisionId,
            },
          ),
        );
        await index.add(chunks, vectors);
        await index.save(storage.indexVectorsPath(collectionId));
        revision = revision.copyWith(
          status: 'saved',
          indexStatus: 'indexed',
          chunks: chunks,
          updatedAt: DateTime.now().toUtc(),
        );
        await storage.saveRevision(collectionId, revision);
        await storage.saveIndexState(
          collectionId,
          IndexState(
            status: 'clean',
            embeddingProfileId: collection.embeddingProfile.id,
            dimensions: collection.embeddingProfile.dimensions,
            vectorCount: index.length,
          ),
        );
      }

      await storage.activateRevision(collectionId, documentId, revisionId);
      final artifact = await storage.saveSectionArtifacts(
        collectionId,
        paper,
        revision: revision,
      );
      return (
        revision: revision,
        artifactId: artifact.artifactId,
        markdownPath: artifact.markdownPath,
        jsonPath: artifact.jsonPath,
      );
    } catch (_) {
      if (!revision.isIndexed) {
        final failed = revision.copyWith(
          status: 'saved',
          indexStatus: 'failed',
          updatedAt: DateTime.now().toUtc(),
        );
        await storage.saveRevision(collectionId, failed);
      }
      rethrow;
    }
  }

  Future<SectionRevision> revertToRevision({
    required String documentId,
    required String revisionId,
  }) async {
    var candidate = await storage.loadRevision(
      collectionId,
      documentId,
      revisionId,
    );
    if (candidate == null) throw StateError('Revision not found: $revisionId');
    while (candidate != null &&
        !candidate.isIndexed &&
        candidate.parentRevisionId != null) {
      candidate = await storage.loadRevision(
        collectionId,
        documentId,
        candidate.parentRevisionId!,
      );
    }
    if (candidate == null || !candidate.isIndexed) {
      throw StateError('No indexed ancestor is available to restore.');
    }
    await storage.activateRevision(collectionId, documentId, candidate.id);
    return candidate;
  }

  static List<PaperChunk> _revisionChunks(
    PaperDocument paper,
    List<DocumentSection> sections,
    String revisionId,
  ) {
    const maxChars = 2400;
    final chunks = <PaperChunk>[];
    var ordinal = 0;
    for (final section in sections) {
      if (section.isReferences || section.text.trim().isEmpty) continue;
      final text = section.text.trim();
      for (var start = 0, part = 0; start < text.length; part++) {
        var end = (start + maxChars).clamp(0, text.length);
        if (end < text.length) {
          final boundary = text.lastIndexOf(RegExp(r'\s'), end);
          if (boundary > start + 400) end = boundary;
        }
        final body = text.substring(start, end).trim();
        if (body.isNotEmpty) {
          chunks.add(
            PaperChunk(
              id: '${paper.id}:$revisionId:${section.id}:c$part',
              vectorId: 0,
              page: section.startPage,
              ordinal: ordinal++,
              section: section.name,
              sectionId: section.id,
              startChar: section.startChar + start,
              endChar: section.startChar + end,
              text: body,
              documentId: paper.id,
              documentTitle: paper.title,
              documentFileName: paper.fileName,
            ),
          );
        }
        if (end <= start) break;
        start = end;
      }
    }
    if (chunks.isEmpty) {
      throw StateError('The revision has no content that can be indexed.');
    }
    return chunks;
  }

  /// Writes each figure next to its document and returns the chunks that
  /// point at them.
  ///
  /// The chunk stores only the file name; the collection and document are
  /// already known wherever it is read, and keeping the path relative means a
  /// moved data directory does not strand every figure.
  Future<List<PaperChunk>> _saveFigures({
    required String collectionId,
    required String documentId,
    required List<IndexedFigure> figures,
  }) async {
    if (figures.isEmpty) return const [];

    final dir = Directory(storage.figuresDir(collectionId, documentId));
    await dir.create(recursive: true);

    final chunks = <PaperChunk>[];
    for (var i = 0; i < figures.length; i++) {
      final figure = figures[i];
      final name = 'fig_${i.toString().padLeft(3, '0')}.${figure.extension}';
      await File(p.join(dir.path, name)).writeAsBytes(figure.bytes);

      chunks.add(
        PaperChunk(
          id: '$documentId:figure:$i',
          vectorId: 0,
          page: figure.page,
          ordinal: i,
          section: figure.section,
          // A figure occupies no span of the transcript; an empty span keeps
          // it out of any offset-based lookup rather than pointing at text it
          // did not come from.
          startChar: 0,
          endChar: 0,
          text: figure.embeddingText,
          imagePath: name,
          imageMediaType: figure.mediaType,
        ),
      );
    }

    debugPrint(
      '[figures] $documentId: saved ${chunks.length} figures to ${dir.path}',
    );
    return chunks;
  }
}
