import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// Renders PDF pages to PNG using the low-level pdfrx API
/// (no PdfViewer widget). Used to feed scanned pages to vision OCR.
class PageRenderService {
  const PageRenderService({this.dpi = 150});

  final double dpi;

  /// Opens [filePath] for rendering several pages. The caller owns the
  /// returned document and must call `dispose()` when done.
  Future<PdfDocument> openDocument(String filePath) async {
    await pdfrxFlutterInitialize();
    return PdfDocument.openFile(filePath);
  }

  /// Renders [pageNumber] (1-based) of [filePath] as PNG bytes at [dpi].
  /// Opens and closes the document itself; use [openDocument] and
  /// [renderDocumentPage] when rendering several pages of the same file.
  Future<Uint8List> renderPage(String filePath, int pageNumber) async {
    final document = await openDocument(filePath);
    try {
      return await renderDocumentPage(document, pageNumber);
    } finally {
      await document.dispose();
    }
  }

  /// Renders [pageNumber] (1-based) of an already open [document] as PNG
  /// bytes at [dpi]. Does not close the document.
  Future<Uint8List> renderDocumentPage(
    PdfDocument document,
    int pageNumber,
  ) async {
    final pageCount = document.pages.length;
    if (pageNumber < 1 || pageNumber > pageCount) {
      throw RangeError.range(pageNumber, 1, pageCount, 'pageNumber');
    }
    final page = document.pages[pageNumber - 1];

    // PdfPage.width/height are in points (72 per inch), already rotated.
    final scale = dpi / 72.0;
    final width = (page.width * scale).round();
    final height = (page.height * scale).round();

    final pdfImage = await page.render(
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
      backgroundColor: 0xffffffff,
    );
    if (pdfImage == null) {
      throw StateError(
        'Failed to render page $pageNumber of ${document.sourceName}',
      );
    }

    // The raw BGRA buffer is freed as soon as the ui.Image exists.
    final image = await pdfImage.createImage().whenComplete(pdfImage.dispose);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw StateError('Failed to encode page $pageNumber as PNG');
      }
      return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    } finally {
      image.dispose();
    }
  }
}
