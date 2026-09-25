import 'dart:typed_data';

/// A figure extracted from a PDF, before its bytes are saved to disk.
class IndexedFigure {
  /// 1-based page the figure is printed on.
  final int page;

  /// Position within the page, in the order the images appear in the page's
  /// resources.
  final int indexOnPage;

  /// The caption found for this figure, e.g. `Figure 3: Accuracy over time.`,
  /// or an empty string when the page had no caption left to pair with it.
  final String caption;

  /// Name of the section the figure's page falls in, used the same way it is
  /// for text chunks so a figure embeds near the argument it belongs to.
  final String section;

  final String mediaType;
  final Uint8List bytes;

  /// True when the figure came back from the OCR pass rather than the native
  /// strip — i.e. the native decoder could not read it.
  final bool fromOcr;

  const IndexedFigure({
    required this.page,
    required this.indexOnPage,
    required this.caption,
    required this.section,
    required this.mediaType,
    required this.bytes,
    this.fromOcr = false,
  });

  /// File extension matching [mediaType].
  String get extension => switch (mediaType) {
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    _ => 'jpg',
  };

  /// Text embedded for the figure: caption plus page and section.
  String get embeddingText {
    final parts = [
      if (section.trim().isNotEmpty) section.trim(),
      if (caption.trim().isNotEmpty) caption.trim() else 'Figure on page $page',
    ];
    return parts.join('\n\n');
  }
}
