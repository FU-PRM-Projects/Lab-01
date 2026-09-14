import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/citation.dart';
import 'package:lab_05/ui/core/theme.dart';

class SourcePanel extends ConsumerStatefulWidget {
  final Citation citation;
  final VoidCallback onClose;

  const SourcePanel({super.key, required this.citation, required this.onClose});

  @override
  ConsumerState<SourcePanel> createState() => _SourcePanelState();
}

class _SourcePanelState extends ConsumerState<SourcePanel> {
  bool _showPdfView = false;
  PdfViewerController? _pdfController;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
  }

  @override
  void didUpdateWidget(covariant SourcePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.citation.page != widget.citation.page ||
        oldWidget.citation.documentId != widget.citation.documentId) {
      if (_showPdfView) {
        _pdfController?.goToPage(pageNumber: widget.citation.page);
      }
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

    String? pdfPath;
    bool pdfExists = false;
    if (collection != null) {
      pdfPath = storage.paperPdfPath(collection.id, widget.citation.documentId);
      pdfExists = File(pdfPath).existsSync();
    }

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
                if (pdfExists)
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('Excerpt'),
                        icon: Icon(Icons.notes, size: 14),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('PDF'),
                        icon: Icon(Icons.picture_as_pdf_outlined, size: 14),
                      ),
                    ],
                    selected: {_showPdfView},
                    onSelectionChanged: (Set<bool> selected) {
                      setState(() {
                        _showPdfView = selected.first;
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

          // Body: Excerpt or PDF Viewer
          Expanded(
            child: _showPdfView && pdfExists && pdfPath != null
                ? _buildPdfViewer(pdfPath)
                : _buildExcerptView(context, pdfExists),
          ),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Excerpt copied to clipboard'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
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
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.citation.excerpt,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    height: 1.6,
                    fontSize: 13.5,
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
                border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
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
                  _showPdfView = true;
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

  Widget _buildPdfViewer(String filePath) {
    return PdfViewer.file(
      filePath,
      initialPageNumber: widget.citation.page,
      controller: _pdfController,
    );
  }
}
