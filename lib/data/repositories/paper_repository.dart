import 'package:path/path.dart' as p;
import 'package:lab_05/data/models/index_state.dart';

import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:lab_05_rust/paper_native.dart' as rust_pdf;

import 'package:lab_05/data/services/collection_index.dart';
import 'package:lab_05/data/services/embedding_client.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/services/pdf_processor.dart';
import 'package:lab_05/data/services/local_storage.dart';
import 'package:lab_05/data/services/page_render_service.dart';
import 'package:lab_05/data/services/vision_ocr_service.dart';

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

      final totalPages = extractResult.pageCount;
      final ocrPages = extractResult.needsOcrPages;
      final hasText = extractResult.chunks.isNotEmpty;
      var chunksToIndex = extractResult.chunks;

      if (ocrPages.isNotEmpty) {
        // Scanned or hybrid PDF: OCR the flagged pages before indexing.
        debugPrint(
          '[import] $documentId ($originalFileName): '
          'pdfType=${extractResult.pdfType}, '
          'totalPages=$totalPages, '
          'needsOcr=${ocrPages.length} (pages: ${ocrPages.join(', ')}), '
          'emptyPages=${extractResult.emptyPages.length}, '
          'textChunks=${extractResult.chunks.length}',
        );
        final ocrChunks = await _ocrPages(
          pdfPath: targetPdfPath,
          documentId: documentId,
          pages: ocrPages,
          textChunks: extractResult.chunks,
          onProgress: onProgress,
        );

        // A page that was OCR'd keeps only its OCR chunks, so text and OCR
        // chunks never mix on the same page (their ordinals are unrelated).
        final ocrPageSet = ocrChunks.map((c) => c.page).toSet();
        final merged = [
          ...extractResult.chunks.where((c) => !ocrPageSet.contains(c.page)),
          ...ocrChunks,
        ]..sort((a, b) {
            final byPage = a.page.compareTo(b.page);
            return byPage != 0 ? byPage : a.ordinal.compareTo(b.ordinal);
          });
        chunksToIndex = [
          for (var i = 0; i < merged.length; i++)
            PaperChunk(
              id: merged[i].id,
              vectorId: merged[i].vectorId,
              page: merged[i].page,
              ordinal: i,
              section: merged[i].section,
              startChar: merged[i].startChar,
              endChar: merged[i].endChar,
              text: merged[i].text,
            ),
        ];
        debugPrint(
          '[import] $documentId: OCR gave ${ocrChunks.length} chunks from '
          '${ocrPageSet.length}/${ocrPages.length} pages; '
          'total chunks=${chunksToIndex.length}',
        );

        if (chunksToIndex.isEmpty) {
          throw StateError(
            'OCR ran on ${ocrPages.length}/$totalPages pages but found no text '
            '(pdfType: ${extractResult.pdfType}). The pages may be blank.',
          );
        }
      } else if (!hasText) {
        // No text and nothing flagged for OCR: unreadable or broken PDF.
        throw StateError(
          'Could not read any content from PDF '
          '(pdfType: ${extractResult.pdfType}, pages: $totalPages, '
          'empty pages: ${extractResult.emptyPages.length}). '
          'The file may be corrupted or unsupported.',
        );
      }

      // 5. Reserve monotonic vector IDs from collection
      final collection = await storage.loadCollection(collectionId);
      if (collection == null) {
        throw StateError('Collection $collectionId not found');
      }

      int currentVectorId = collection.nextVectorId;
      final List<PaperChunk> assignedChunks = [];
      for (final chunk in chunksToIndex) {
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

  static const _maxConcurrentOcr = 3;

  /// Same pattern as `section_regex` in rust/src/api/pdf_parser.rs, so OCR
  /// chunks get the same section names as text chunks.
  static final _sectionRegex = RegExp(
    r'^(?:\d+(?:\.\d+)*\s+)?(Abstract|Introduction|Background|Related\s+Work|Methodology|Method|Architecture|Implementation|Evaluation|Experiments?|Results?|Discussion|Conclusion|References)\b',
    caseSensitive: false,
  );

  /// Renders and OCRs [pages], at most [_maxConcurrentOcr] at a time, then
  /// chunks the text with the same Rust chunker used for text pages.
  /// Returns only after every page is done; any page failure fails the import.
  Future<List<PaperChunk>> _ocrPages({
    required String pdfPath,
    required String documentId,
    required List<int> pages,
    required List<PaperChunk> textChunks,
    ImportProgressCallback? onProgress,
  }) async {
    final settings = await storage.loadSettings();
    if (settings.openRouterApiKey.trim().isEmpty) {
      throw StateError('OpenRouter API key is required for OCR.');
    }
    final modelId = settings.chatModel;
    const renderer = PageRenderService();
    // One document shared by all workers; closed after every worker is done.
    final document = await renderer.openDocument(pdfPath);
    final ocr = VisionOcrService(settings: settings);

    final queue = pages.toSet().toList()..sort();
    final texts = <int, String>{};
    var next = 0;
    var done = 0;
    Object? failure;
    StackTrace? failureStack;

    Future<void> worker() async {
      while (failure == null && next < queue.length) {
        final page = queue[next++];
        try {
          final png = await renderer.renderDocumentPage(document, page);
          texts[page] = await ocr.ocrPage(png, modelId: modelId);
          done++;
          onProgress?.call(
            'OCR $done/${queue.length} pages ($modelId)...',
            0.3 + 0.2 * done / queue.length,
          );
        } catch (e, stack) {
          failure ??= StateError('OCR failed on page $page: $e');
          failureStack ??= stack;
        }
      }
    }

    try {
      await Future.wait([
        for (var i = 0; i < min(_maxConcurrentOcr, queue.length); i++)
          worker(),
      ]);
    } finally {
      ocr.close();
      await document.dispose();
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack ?? StackTrace.current);
    }

    // Section tracking mirrors the Rust parser: start at "Introduction",
    // carry the current section forward page by page, and let the first
    // matching heading on a page set the section for that whole page.
    final ocrPageSet = queue.toSet();
    final sortedText = textChunks
        .where((c) => !ocrPageSet.contains(c.page))
        .toList()
      ..sort((a, b) {
        final byPage = a.page.compareTo(b.page);
        return byPage != 0 ? byPage : a.ordinal.compareTo(b.ordinal);
      });
    var currentSection = 'Introduction';
    var textIndex = 0;

    final chunks = <PaperChunk>[];
    for (final page in queue) {
      // Pick up the section reached by text pages that come before this page.
      while (textIndex < sortedText.length &&
          sortedText[textIndex].page < page) {
        currentSection = sortedText[textIndex].section;
        textIndex++;
      }

      final text = texts[page]?.trim() ?? '';
      if (text.isEmpty) {
        debugPrint('[import] $documentId: OCR page $page is blank');
        continue;
      }

      for (final line in text.split('\n')) {
        final trimmed = line.trim().replaceFirst(RegExp(r'^#+'), '').trim();
        final match = _sectionRegex.firstMatch(trimmed);
        if (match != null) {
          currentSection = match.group(0)!;
          break;
        }
      }

      final pageChunks = await rust_pdf.chunkText(
        pageText: text,
        pageNum: page,
        documentId: documentId,
        section: currentSection,
        startOrdinal: 0,
      );
      for (final rc in pageChunks) {
        chunks.add(
          PaperChunk(
            // ':ocr' in the id (not the section) marks OCR chunks and keeps
            // ids from clashing with text chunks on the same page.
            id: '$documentId:p${rc.page}:ocr${rc.ordinal}',
            vectorId: 0,
            page: rc.page,
            ordinal: rc.ordinal,
            section: rc.section,
            startChar: rc.startChar,
            endChar: rc.endChar,
            text: rc.text,
          ),
        );
      }
    }
    return chunks;
  }
}
