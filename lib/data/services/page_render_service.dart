import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// Supplies one PDF's pages as images, one at a time.
///
/// The indexing pipeline only needs "how many pages" and "give me page N as a
/// PNG", so it depends on this rather than on pdfrx directly — which also lets
/// tests drive the pipeline without a real PDF.
abstract class PdfPageImages {
  /// Opens [filePath] and returns its page count.
  Future<int> open(String filePath);

  /// Renders [pageNumber] (1-based) as PNG bytes.
  Future<Uint8List> renderPage(int pageNumber);

  /// Releases the document. Safe to call more than once.
  Future<void> close();
}

/// Renders PDF pages to PNG with the low-level pdfrx API (no PdfViewer
/// widget), so pages can be fed to a multimodal model for transcription.
class PageRenderService implements PdfPageImages {
  PageRenderService({this.dpi = 150});

  final double dpi;
  PdfDocument? _document;

  @override
  Future<int> open(String filePath) async {
    await close();
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile(filePath);
    _document = document;
    return document.pages.length;
  }

  @override
  Future<Uint8List> renderPage(int pageNumber) async {
    final document = _document;
    if (document == null) {
      throw StateError('No PDF is open; call open() first.');
    }

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

  @override
  Future<void> close() async {
    final document = _document;
    _document = null;
    await document?.dispose();
  }
}
