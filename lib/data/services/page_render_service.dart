import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// Renders single PDF pages to PNG using the low-level pdfrx API
/// (no PdfViewer widget). Used to feed scanned pages to vision OCR.
class PageRenderService {
  const PageRenderService({this.dpi = 150});

  final double dpi;

  /// Renders [pageNumber] (1-based) of [filePath] as PNG bytes at [dpi].
  /// The document is always closed, including when rendering fails.
  Future<Uint8List> renderPage(String filePath, int pageNumber) async {
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile(filePath);
    try {
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
        throw StateError('Failed to render page $pageNumber of $filePath');
      }

      // The raw BGRA buffer is freed as soon as the ui.Image exists.
      final image = await pdfImage.createImage().whenComplete(
        pdfImage.dispose,
      );
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) {
          throw StateError('Failed to encode page $pageNumber as PNG');
        }
        return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      await document.dispose();
    }
  }
}
