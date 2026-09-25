import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:lab_05_rust/paper_native.dart' as native;

import 'package:lab_05/data/models/app_settings.dart';
import 'package:lab_05/data/models/document_figure.dart';
import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/models/reference.dart';
import 'package:lab_05/data/services/instruct_document_service.dart';
import 'package:lab_05/data/services/page_render_service.dart';
import 'package:lab_05/data/services/page_transcription_service.dart';
import 'package:lab_05/data/services/pdf_ocr_service.dart';
import 'package:lab_05/domain/indexing/document_transcript.dart';
import 'package:lab_05/domain/indexing/section_chunker.dart';
import 'package:lab_05/domain/indexing/section_resolver.dart';

typedef IndexingProgressCallback = void Function(String stage, double progress);

/// Everything the indexing pipeline recovered from one PDF.
class IndexedDocument {
  final String title;
  final List<String> authors;
  final int pageCount;

  /// The page-by-page transcription the sections and chunks were cut from.
  final DocumentTranscript transcript;

  /// The paper's structure, for the details view.
  final List<DocumentSection> sections;

  /// The passages to embed and index.
  final List<PaperChunk> chunks;

  /// The bibliography, kept structured for the reference view and for the
  /// validating agent to check later.
  final List<PaperReference> references;

  /// Pages the model reported as carrying no readable text.
  final List<int> blankPages;

  /// Figures lifted out of the PDF, in page order.
  final List<IndexedFigure> figures;

  const IndexedDocument({
    required this.title,
    required this.authors,
    required this.pageCount,
    required this.transcript,
    required this.sections,
    required this.chunks,
    required this.references,
    this.blankPages = const [],
    this.figures = const [],
  });

  DocumentSection? get referencesSection =>
      sections.where((section) => section.isReferences).firstOrNull;
}

/// Turns a PDF into sections, chunks, figures and references.
///
/// Figures are extracted natively and blanked out, the text-only PDF is parsed
/// to per-page Markdown in one `file-parser` request, then an instruct model
/// reports the outline and bibliography. Falls back to per-page transcription
/// if OCR fails; any other failure aborts the import.
class IndexingPipeline {
  IndexingPipeline({
    required this.settings,
    PdfPageImages Function()? openPageImages,
    PageTranscriptionService Function(AppSettings)? transcriberFactory,
    InstructDocumentService Function(AppSettings)? instructFactory,
    PdfOcrService Function(AppSettings)? ocrFactory,
    PdfStripper? stripPdfImages,
    this.maxConcurrentPages = 8,
    this.minFigureWidth = 96,
    this.minFigureHeight = 96,
  }) : openPageImages = openPageImages ?? PageRenderService.new,
       ocrFactory =
           ocrFactory ?? ((settings) => PdfOcrService(settings: settings)),
       stripPdfImages = stripPdfImages ?? _nativeStrip,
       transcriberFactory =
           transcriberFactory ??
           ((settings) => PageTranscriptionService(settings: settings)),
       instructFactory =
           instructFactory ??
           ((settings) => InstructDocumentService(settings: settings));

  final AppSettings settings;

  /// How many pages are transcribed concurrently (lower if rate-limited).
  final int maxConcurrentPages;

  /// Smallest figure worth extracting, in pixels.
  final int minFigureWidth;
  final int minFigureHeight;

  /// Opens the PDF this run reads its page images from, for the fallback path.
  final PdfPageImages Function() openPageImages;

  /// Lifts the figures out of a PDF and returns the image-free copy.
  final PdfStripper stripPdfImages;

  /// Builds the OCR client. The pipeline owns and closes it.
  final PdfOcrService Function(AppSettings) ocrFactory;

  /// Builds the two OpenRouter clients. The pipeline owns and closes both.
  final PageTranscriptionService Function(AppSettings) transcriberFactory;
  final InstructDocumentService Function(AppSettings) instructFactory;

  /// Multimodal model that reads the page images.
  String get transcriptionModel => settings.transcriptionModel;

  /// Text instruct model that reads the assembled transcript. It never sees an
  /// image, so it does not have to be multimodal.
  String get indexingModel => settings.indexingModel;

  /// Model the parsing request is addressed to. Its reply is discarded, so
  /// this is kept separate from the chat model rather than inheriting it.
  String get ocrCarrierModel => settings.ocrCarrierModel;

  /// Model that reads the bibliography. Reference windows are short and
  /// formulaic, so this is a smaller, much faster model than [indexingModel].
  String get referenceModel => settings.referenceModel;

  Future<IndexedDocument> run({
    required String pdfPath,
    required String documentId,
    String? fallbackTitle,
    IndexingProgressCallback? onProgress,
  }) async {
    if (settings.openRouterApiKey.trim().isEmpty) {
      throw StateError(
        'An OpenRouter API key is required to index PDFs. Add one in Settings.',
      );
    }

    final transcriber = transcriberFactory(settings);
    final instruct = instructFactory(settings);
    final ocr = ocrFactory(settings);

    try {
      onProgress?.call('Opening PDF...', 0.05);
      final read = await _readDocument(
        pdfPath: pdfPath,
        ocr: ocr,
        transcriber: transcriber,
        onProgress: onProgress,
      );
      final transcript = read.transcript;

      final blankPages = [
        for (final page in transcript.pages)
          if (page.isEmpty) page.page,
      ];

      if (transcript.text.trim().isEmpty) {
        throw StateError(
          'No readable text was recovered from any of '
          '${transcript.pageCount} pages. The PDF may be blank or corrupted.',
        );
      }

      onProgress?.call('Reading document structure ($indexingModel)...', 0.58);
      final outline = await instruct.analyzeOutline(
        transcript.markedMarkdown,
        modelId: indexingModel,
      );

      onProgress?.call('Building sections...', 0.66);
      final sections = SectionResolver.resolve(
        documentId: documentId,
        transcript: transcript,
        outlines: outline.sections,
      );

      final chunks = SectionChunker.chunk(
        documentId: documentId,
        transcript: transcript,
        sections: sections,
      );

      if (chunks.isEmpty) {
        throw StateError(
          'The transcript produced no indexable passages '
          '(${sections.length} sections, ${transcript.length} characters).',
        );
      }

      // Read the bibliography separately, a window at a time, to stay within output limits.
      final bibliography = _bibliographyText(transcript, sections);
      final references = bibliography == null
          ? const <PaperReference>[]
          : await instruct.extractReferences(
              bibliography,
              modelId: referenceModel,
              onProgress: (done, count) => onProgress?.call(
                'Reading bibliography $done/$count ($referenceModel)...',
                0.7 + 0.25 * done / count,
              ),
            );

      final title = _pickTitle(outline.title, fallbackTitle);

      // Captions and section names are only knowable once the outline has been
      // resolved, so figures are finished here rather than at extraction time.
      final figures = _describeFigures(
        raw: read.figures,
        transcript: transcript,
        sections: sections,
      );

      debugPrint(
        '[index] $documentId: ${transcript.pageCount} pages '
        '(${blankPages.length} blank), ${transcript.length} chars, '
        '${sections.length} sections, ${chunks.length} chunks, '
        '${figures.length} figures, ${references.length} references',
      );

      return IndexedDocument(
        title: title,
        authors: outline.authors,
        pageCount: transcript.pageCount,
        transcript: transcript,
        sections: sections,
        chunks: chunks,
        references: references,
        blankPages: blankPages,
        figures: figures,
      );
    } finally {
      transcriber.close();
      instruct.close();
      ocr.close();
    }
  }

  /// Reads the document: figures out natively, text in one OCR request.
  Future<_ReadDocument> _readDocument({
    required String pdfPath,
    required PdfOcrService ocr,
    required PageTranscriptionService transcriber,
    IndexingProgressCallback? onProgress,
  }) async {
    native.StrippedPdf? stripped;
    try {
      onProgress?.call('Extracting figures...', 0.08);
      stripped = await stripPdfImages(
        pdfPath: pdfPath,
        minWidth: minFigureWidth,
        minHeight: minFigureHeight,
      );
      debugPrint(
        '[strip] ${stripped.images.length} figures, ${stripped.skipped} '
        'undecodable, ${stripped.originalBytes}B -> ${stripped.pdf.length}B',
      );
    } catch (e) {
      // Stripping is an optimisation, not a requirement: a PDF the native
      // parser cannot read is still worth uploading whole.
      debugPrint('[strip] failed, uploading the original PDF: $e');
    }

    try {
      onProgress?.call('Reading PDF (${ocr.engine})...', 0.12);
      // Reading the original is part of the fast path, not a precondition for
      // it: if the file cannot be read here the fallback still gets a chance.
      final upload = stripped?.pdf ?? await File(pdfPath).readAsBytes();
      final result = await ocr.parse(upload, modelId: ocrCarrierModel);
      if (result.isEmpty) {
        throw StateError('The parser returned no text.');
      }
      onProgress?.call('Read ${result.pageCount} pages', 0.55);

      return _ReadDocument(
        transcript: DocumentTranscript.fromPages([
          for (var i = 0; i < result.pages.length; i++)
            PageTranscript(page: i + 1, text: result.pages[i]),
        ]),
        figures: [
          ..._nativeFigures(stripped),
          // Figures the native pass could not decode were left in the PDF, so
          // the parser returns them instead - up to its 8-image ceiling.
          for (final figure in result.figures)
            if (figure.isPlaced)
              _RawFigure(
                page: figure.page,
                indexOnPage: 0,
                mediaType: figure.mediaType,
                bytes: figure.bytes,
                fromOcr: true,
              ),
        ],
      );
    } catch (e) {
      debugPrint('[ocr] failed, falling back to per-page transcription: $e');
      onProgress?.call('Parser failed; transcribing pages...', 0.12);
      return _ReadDocument(
        transcript: await _transcribe(
          pdfPath: pdfPath,
          transcriber: transcriber,
          onProgress: onProgress,
        ),
        figures: _nativeFigures(stripped),
      );
    }
  }

  static List<_RawFigure> _nativeFigures(native.StrippedPdf? stripped) => [
    for (final image in stripped?.images ?? const <native.ExtractedImage>[])
      _RawFigure(
        page: image.page,
        indexOnPage: image.indexOnPage,
        mediaType: image.mediaType,
        bytes: image.bytes,
        fromOcr: false,
      ),
  ];

  /// Pairs each extracted image with its page's captions (in order) and section.
  static List<IndexedFigure> _describeFigures({
    required List<_RawFigure> raw,
    required DocumentTranscript transcript,
    required List<DocumentSection> sections,
  }) {
    final byPage = <int, List<_RawFigure>>{};
    for (final figure in raw) {
      if (figure.page < 1 || figure.page > transcript.pageCount) continue;
      byPage.putIfAbsent(figure.page, () => []).add(figure);
    }

    final figures = <IndexedFigure>[];
    for (final entry in byPage.entries) {
      final page = entry.key;
      final onPage = entry.value
        ..sort((a, b) => a.indexOnPage.compareTo(b.indexOnPage));
      final captions = _captionsOnPage(transcript, page);
      final section = _sectionNameForPage(sections, page);

      for (var i = 0; i < onPage.length; i++) {
        figures.add(
          IndexedFigure(
            page: page,
            indexOnPage: i,
            caption: i < captions.length ? captions[i] : '',
            section: section,
            mediaType: onPage[i].mediaType,
            bytes: onPage[i].bytes,
            fromOcr: onPage[i].fromOcr,
          ),
        );
      }
    }

    figures.sort((a, b) {
      final byPageNumber = a.page.compareTo(b.page);
      return byPageNumber != 0
          ? byPageNumber
          : a.indexOnPage.compareTo(b.indexOnPage);
    });
    return figures;
  }

  /// Matches a caption line, optionally preceded by an image placeholder the
  /// parser left behind for a figure it extracted itself.
  static final _captionPattern = RegExp(
    r'^[ \t]*(?:!\[[^\]]*\]\([^)]*\)[ \t]*)?'
    r'((?:Figure|Fig\.?|Table|Chart|Scheme)[ \t]*\d+[.:)]?[ \t]+\S.*)$',
    multiLine: true,
    caseSensitive: false,
  );

  /// Caption lines printed on [page], in order.
  static List<String> _captionsOnPage(DocumentTranscript transcript, int page) {
    final text = transcript.pages
        .where((p) => p.page == page)
        .map((p) => p.text)
        .firstOrNull;
    if (text == null) return const [];
    return [
      for (final match in _captionPattern.allMatches(text))
        _trimCaption(match.group(1)!),
    ];
  }

  /// Captions run to the end of their line; a very long one is clipped so it
  /// does not dominate the figure's embedding.
  static String _trimCaption(String caption) {
    final text = caption.trim();
    const maxLength = 400;
    return text.length <= maxLength
        ? text
        : '${text.substring(0, maxLength).trimRight()}...';
  }

  static String _sectionNameForPage(List<DocumentSection> sections, int page) {
    for (final section in sections.reversed) {
      if (section.startPage <= page) return section.name;
    }
    return sections.isEmpty ? '' : sections.first.name;
  }

  /// Calls into the Rust extractor. Injected in tests so the pipeline can run
  /// without the native library loaded.
  static Future<native.StrippedPdf> _nativeStrip({
    required String pdfPath,
    required int minWidth,
    required int minHeight,
  }) => native.extractAndStripImages(
    pdfPath: pdfPath,
    minWidth: minWidth,
    minHeight: minHeight,
  );

  /// Renders and transcribes every page, a few at a time.
  Future<DocumentTranscript> _transcribe({
    required String pdfPath,
    required PageTranscriptionService transcriber,
    IndexingProgressCallback? onProgress,
  }) async {
    final images = openPageImages();
    final pageCount = await images.open(pdfPath);
    if (pageCount == 0) {
      await images.close();
      throw StateError('The PDF reports no pages.');
    }

    final texts = <int, String>{};
    var next = 1;
    var done = 0;
    Object? failure;
    StackTrace? failureStack;

    Future<void> worker() async {
      while (failure == null && next <= pageCount) {
        final page = next++;
        try {
          final png = await images.renderPage(page);
          texts[page] = await transcriber.transcribePage(
            png,
            modelId: transcriptionModel,
          );
          done++;
          onProgress?.call(
            'Transcribing page $done/$pageCount ($transcriptionModel)...',
            0.05 + 0.5 * done / pageCount,
          );
        } catch (e, stack) {
          failure ??= StateError('Transcription failed on page $page: $e');
          failureStack ??= stack;
        }
      }
    }

    try {
      await Future.wait([
        for (var i = 0; i < min(maxConcurrentPages, pageCount); i++) worker(),
      ]);
    } finally {
      await images.close();
    }

    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack ?? StackTrace.current);
    }

    return DocumentTranscript.fromPages([
      for (var page = 1; page <= pageCount; page++)
        PageTranscript(page: page, text: texts[page] ?? ''),
    ]);
  }

  /// The references section, or everything after the last "References" heading.
  static String? _bibliographyText(
    DocumentTranscript transcript,
    List<DocumentSection> sections,
  ) {
    final section = sections.where((s) => s.isReferences).firstOrNull;
    if (section != null) {
      final text = section.text.trim();
      return text.isEmpty ? null : text;
    }

    final offset =
        transcript.findLastHeading('References') ??
        transcript.findLastHeading('Bibliography');
    if (offset == null) return null;

    final text = transcript.text.substring(offset).trim();
    return text.isEmpty ? null : text;
  }

  static String _pickTitle(String? fromModel, String? fallback) {
    final candidate = fromModel?.trim() ?? '';
    // A model occasionally answers with a filename or a stray fragment; the
    // length window rejects both without second-guessing real titles.
    if (candidate.length > 3 && candidate.length < 300) return candidate;
    final fallbackTitle = fallback?.trim() ?? '';
    return fallbackTitle.isEmpty ? 'Untitled' : fallbackTitle;
  }
}

/// Lifts the figures out of a PDF, returning the image-free copy.
typedef PdfStripper = Future<native.StrippedPdf> Function({
  required String pdfPath,
  required int minWidth,
  required int minHeight,
});

/// A figure before its caption and section are known.
class _RawFigure {
  final int page;
  final int indexOnPage;
  final String mediaType;
  final Uint8List bytes;
  final bool fromOcr;

  const _RawFigure({
    required this.page,
    required this.indexOnPage,
    required this.mediaType,
    required this.bytes,
    required this.fromOcr,
  });
}

/// The raw read of a PDF, before the outline gives figures their context.
class _ReadDocument {
  final DocumentTranscript transcript;
  final List<_RawFigure> figures;

  const _ReadDocument({required this.transcript, required this.figures});
}
