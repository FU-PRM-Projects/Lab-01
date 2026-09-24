import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/citation.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/ui/artifacts/artifact_controller.dart';
import 'package:lab_05/ui/core/markdown_math.dart';
import 'package:lab_05/ui/core/snackbar.dart';
import 'package:lab_05/ui/core/theme.dart';

/// Which body the panel shows. A figure citation defaults to [figure]; a text
/// citation only ever has [excerpt] and [pdf].
enum _PanelView { figure, excerpt, pdf }

class SourcePanel extends ConsumerStatefulWidget {
  final Citation citation;
  final VoidCallback onClose;

  const SourcePanel({super.key, required this.citation, required this.onClose});

  @override
  ConsumerState<SourcePanel> createState() => _SourcePanelState();
}

class _SourcePanelState extends ConsumerState<SourcePanel> {
  _PanelView _view = _PanelView.excerpt;
  bool _renderMarkdown = true;
  PdfViewerController? _pdfController;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    _view = _defaultViewFor(widget.citation);
  }

  /// A figure citation opens straight on its image; a text citation opens on
  /// the excerpt, same as before this feature existed.
  _PanelView _defaultViewFor(Citation citation) {
    final chunk = _chunkFor(citation);
    return (chunk?.isFigure ?? false) ? _PanelView.figure : _PanelView.excerpt;
  }

  PaperChunk? _chunkFor(Citation citation) {
    final chunks = ref.read(paperChunksProvider(citation.documentId));
    for (final chunk in chunks) {
      if (chunk.id == citation.chunkId) return chunk;
    }
    return null;
  }

  @override
  void didUpdateWidget(covariant SourcePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.citation.page != widget.citation.page ||
        oldWidget.citation.documentId != widget.citation.documentId) {
      if (_view == _PanelView.pdf) {
        _pdfController?.goToPage(pageNumber: widget.citation.page);
      }
    }
    // A different citation resets to its own default view, so switching from
    // a figure to a text passage does not leave the panel stuck showing an
    // "Excerpt" tab with nothing under it, or vice versa.
    if (oldWidget.citation.chunkId != widget.citation.chunkId) {
      _view = _defaultViewFor(widget.citation);
    }
  }

  @override
  void dispose() {
    _pdfController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    final collection = ref.watch(currentCollectionProvider);
    final storage = ref.watch(localStorageProvider);
    final chunk = _chunkFor(widget.citation);
    final isFigure = chunk?.isFigure ?? false;

    String? pdfPath;
    bool pdfExists = false;
    String? figurePath;
    bool figureExists = false;
    if (collection != null) {
      pdfPath = storage.paperPdfPath(collection.id, widget.citation.documentId);
      pdfExists = File(pdfPath).existsSync();
      if (isFigure) {
        figurePath = storage.figurePath(
          collection.id,
          widget.citation.documentId,
          chunk!.imagePath!,
        );
        figureExists = File(figurePath).existsSync();
      }
    }

    // A figure whose file went missing has nothing to show as a figure, so
    // the panel falls back to the excerpt body rather than a blank pane.
    final effectiveView = (_view == _PanelView.figure && !figureExists)
        ? _PanelView.excerpt
        : _view;

    return Container(
      width: 500,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          left: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Material 3 Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.citation.sourceId,
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.citation.title,
                    style: textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (figureExists)
                  IconButton(
                    icon: Icon(
                      Icons.download_outlined,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    tooltip: 'Export image',
                    onPressed: () => _exportFigure(context, figurePath!),
                  ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'Close source panel',
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          // View Selector & Metadata Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: colorScheme.surfaceContainerLow,
            child: Row(
              children: [
                _buildInfoChip(
                  context,
                  Icons.description_outlined,
                  'Page ${widget.citation.page}',
                ),
                if (widget.citation.section.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _buildInfoChip(
                    context,
                    Icons.bookmark_outline,
                    widget.citation.section,
                  ),
                ],
                const Spacer(),
                if (figureExists || pdfExists)
                  SegmentedButton<_PanelView>(
                    segments: [
                      if (figureExists)
                        const ButtonSegment<_PanelView>(
                          value: _PanelView.figure,
                          label: Text('Figure'),
                          icon: Icon(Icons.image_outlined, size: 14),
                        ),
                      const ButtonSegment<_PanelView>(
                        value: _PanelView.excerpt,
                        label: Text('Excerpt'),
                        icon: Icon(Icons.notes, size: 14),
                      ),
                      if (pdfExists)
                        const ButtonSegment<_PanelView>(
                          value: _PanelView.pdf,
                          label: Text('PDF'),
                          icon: Icon(Icons.picture_as_pdf_outlined, size: 14),
                        ),
                    ],
                    selected: {effectiveView},
                    onSelectionChanged: (Set<_PanelView> selected) {
                      setState(() {
                        _view = selected.first;
                      });
                    },
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),

          // Body: Figure, Excerpt or PDF Viewer
          Expanded(
            child: switch (effectiveView) {
              _PanelView.figure when figureExists =>
                _buildFigureView(context, figurePath!),
              _PanelView.pdf when pdfExists && pdfPath != null =>
                _buildPdfViewer(pdfPath),
              _ => _buildExcerptView(context, pdfExists),
            },
          ),
        ],
      ),
    );
  }

  /// Writes [figurePath]'s bytes wherever the person chooses via the native
  /// save-as dialog. Mirrors the PDF-import flow's use of [FilePicker] in
  /// `app_shell.dart`, just for saving instead of picking.
  Future<void> _exportFigure(BuildContext context, String figurePath) async {
    final Uint8List bytes;
    try {
      bytes = await File(figurePath).readAsBytes();
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, 'Could not read the figure file: $e');
      }
      return;
    }

    final extension = figurePath.contains('.')
        ? figurePath.substring(figurePath.lastIndexOf('.') + 1)
        : 'png';
    final suggestedName =
        '${widget.citation.sourceId}_p${widget.citation.page}.$extension';

    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Export figure image',
        fileName: suggestedName,
        bytes: bytes,
      );
      if (saved != null && context.mounted) {
        showAppSnackBar(context, 'Saved $suggestedName', isSuccess: true);
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, 'Could not save the image: $e');
      }
    }
  }

  Widget _buildFigureView(BuildContext context, String figurePath) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Center(
                  child: Image.file(File(figurePath), fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          if (widget.citation.excerpt.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Text(
                widget.citation.excerpt,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip(BuildContext context, IconData icon, String label) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExcerptView(BuildContext context, bool pdfExists) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.format_quote_outlined,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'SUPPORTING EVIDENCE EXCERPT',
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _renderMarkdown ? Icons.code : Icons.auto_awesome_outlined,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                tooltip: _renderMarkdown
                    ? 'View raw text'
                    : 'View formatted markdown',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _renderMarkdown = !_renderMarkdown;
                  });
                },
              ),
              IconButton(
                icon: Icon(
                  Icons.copy_outlined,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                tooltip: 'Copy excerpt',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: widget.citation.excerpt),
                  );
                  showCopiedSnackBar(context, 'Excerpt');
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: SelectionArea(
                child: SingleChildScrollView(
                  child: _renderMarkdown
                      ? MathMarkdown(
                          data: _cleanMarkdown(widget.citation.excerpt),
                          styleSheet: _buildMarkdownStyle(context),
                          extraInlineSyntaxes: [_UnderlineSyntax()],
                          extraBuilders: {'u': _UnderlineBuilder()},
                          onTapLink: (text, href, title) {
                            if (href != null) {
                              final uri = Uri.tryParse(href);
                              if (uri != null &&
                                  (uri.scheme == 'http' ||
                                      uri.scheme == 'https')) {
                                launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            }
                          },
                        )
                      : Text(
                          widget.citation.excerpt,
                          style: textTheme.bodyMedium?.copyWith(
                            fontFamily: 'Consolas',
                            color: colorScheme.onSurface,
                            height: 1.6,
                            fontSize: 13,
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (!pdfExists)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The source PDF file was removed from disk. Historical excerpt remains preserved.',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            FilledButton.tonalIcon(
              onPressed: () {
                setState(() {
                  _view = _PanelView.pdf;
                });
              },
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text('Inspect Page ${widget.citation.page} in PDF Viewer'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _buildMarkdownStyle(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    return MarkdownStyleSheet(
      p: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurface,
        height: 1.6,
        fontSize: 13.5,
      ),
      h1: textTheme.titleMedium?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.bold,
        fontSize: 16,
        height: 1.5,
      ),
      h2: textTheme.titleSmall?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.bold,
        fontSize: 14.5,
        height: 1.5,
      ),
      h3: textTheme.bodyLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 13.5,
        height: 1.5,
      ),
      h4: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      code: TextStyle(
        backgroundColor: colorScheme.surfaceContainerHighest,
        color: colorScheme.primary,
        fontFamily: 'Consolas',
        fontSize: 12.5,
      ),
      codeblockDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      blockquote: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
        fontSize: 13,
      ),
      blockquoteDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: colorScheme.primary, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      tableBorder: TableBorder.all(
        color: colorScheme.outlineVariant,
        width: 1,
        borderRadius: BorderRadius.circular(6),
      ),
      tableColumnWidth: const FlexColumnWidth(),
      tableHead: textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
        fontSize: 13,
      ),
      tableBody: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurface,
        fontSize: 12.5,
      ),
      tableCellsPadding: const EdgeInsets.all(8),
      listBullet: textTheme.bodyMedium?.copyWith(
        color: colorScheme.primary,
        fontSize: 13.5,
      ),
    );
  }

  String _cleanMarkdown(String raw) {
    var text = raw;
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAllMapped(
      RegExp(
        r'<(?:b|strong)>(.*?)</(?:b|strong)>',
        caseSensitive: false,
        dotAll: true,
      ),
      (m) => '**${m[1]}**',
    );
    text = text.replaceAllMapped(
      RegExp(r'<(?:i|em)>(.*?)</(?:i|em)>', caseSensitive: false, dotAll: true),
      (m) => '*${m[1]}*',
    );
    text = text.replaceAllMapped(
      RegExp(
        r'<(?:del|s)>(.*?)</(?:del|s)>',
        caseSensitive: false,
        dotAll: true,
      ),
      (m) => '~~${m[1]}~~',
    );
    text = text.replaceAllMapped(
      RegExp(r'<code>(.*?)</code>', caseSensitive: false, dotAll: true),
      (m) => '`${m[1]}`',
    );
    return text;
  }

  Widget _buildPdfViewer(String filePath) {
    return PdfViewer.file(
      filePath,
      initialPageNumber: widget.citation.page,
      controller: _pdfController,
    );
  }
}

class _UnderlineSyntax extends md.InlineSyntax {
  _UnderlineSyntax() : super(r'<u\b[^>]*>(.*?)<\/u>');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match[1] ?? '';
    parser.addNode(md.Element.text('u', text));
    return true;
  }
}

class _UnderlineBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Text.rich(
      TextSpan(
        text: element.textContent,
        style: preferredStyle?.copyWith(decoration: TextDecoration.underline),
      ),
    );
  }
}
