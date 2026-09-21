import 'dart:io';

import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05_rust/paper_native.dart' as rust_pdf;

class PdfProcessedResult {
  final String title;
  final int pageCount;
  final List<PaperChunk> chunks;
  final List<int> emptyPages;
  final String pdfType;
  final List<int> needsOcrPages;

  PdfProcessedResult({
    required this.title,
    required this.pageCount,
    required this.chunks,
    required this.emptyPages,
    this.pdfType = 'TextBased',
    this.needsOcrPages = const [],
  });
}

class PdfProcessor {
  /// Process PDF file using Rust and Firecrawl's pdf-inspector library
  static Future<PdfProcessedResult> processPdf(
    String filePath, {
    required String documentId,
    String? fallbackTitle,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw ArgumentError('PDF file not found at: $filePath');
    }

    final rustResult = await rust_pdf.parsePdf(
      filePath: filePath,
      documentId: documentId,
      fallbackTitle: fallbackTitle,
    );

    final chunks = rustResult.chunks.map((rc) {
      return PaperChunk(
        id: rc.id,
        page: rc.page,
        ordinal: rc.ordinal,
        section: rc.section,
        startChar: rc.startChar,
        endChar: rc.endChar,
        text: rc.text,
      );
    }).toList();

    final emptyPages = rustResult.emptyPages.toList();
    final needsOcrPages = rustResult.needsOcrPages.toList();

    return PdfProcessedResult(
      title: rustResult.title,
      pageCount: rustResult.pageCount,
      chunks: chunks,
      emptyPages: emptyPages,
      pdfType: rustResult.pdfType,
      needsOcrPages: needsOcrPages,
    );
  }
}
