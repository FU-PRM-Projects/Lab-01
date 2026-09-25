import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/citation.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/services/crossref_client.dart';
import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/models/reference.dart';
import 'package:lab_05/ui/artifacts/artifact_controller.dart';
import 'package:lab_05/ui/chat/chat_controller.dart';
import 'package:lab_05/ui/collections/import_controller.dart';
import 'package:lab_05/ui/core/markdown_math.dart';
import 'package:lab_05/ui/core/snackbar.dart';
import 'package:lab_05/ui/core/theme.dart';

/// Per-chat sidebar for the folder's one paper: the chunks it was indexed
/// into, its outline and the works it cites. An empty folder shows the import
/// instead.
class ArtifactPanel extends ConsumerWidget {
  final VoidCallback onImportPaper;

  const ArtifactPanel({super.key, required this.onImportPaper});

  static const double panelWidth = 400;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final scope = ref.watch(artifactScopeProvider);
    // A folder holds one paper, so there is nothing to pick between: the
    // panel opens straight onto it.
    final paper = ref.watch(papersProvider).firstOrNull;
    final readable = paper != null && paper.occupiesFolder ? paper : null;

    return Container(
      width: panelWidth,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          left: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            title: readable?.title ?? 'Artifacts',
            subtitle: readable?.fileName ?? 'No paper yet',
            onClose: () =>
                ref.read(artifactPanelProvider.notifier).close(scope),
          ),
          Expanded(
            child: readable != null
                ? _PaperDetail(key: ValueKey(readable.id), paper: readable)
                : _NoPaper(failed: paper, onImportPaper: onImportPaper),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  const _PanelHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 8, 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
            tooltip: 'Close artifacts',
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmDeletePaper(
  BuildContext context,
  WidgetRef ref,
  PaperDocument paper,
) async {
  final colorScheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "${paper.title}"?'),
      content: const Text(
        'This will remove the PDF document, its indexed vector embeddings, and cached citations from this project.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  final currentCol = ref.read(currentCollectionProvider);
  if (currentCol == null) return;

  final repository = ref.read(paperRepositoryProvider(currentCol.id));

  if (ref.read(activeCitationProvider)?.documentId == paper.id) {
    ref.read(activeCitationProvider.notifier).state = null;
  }

  try {
    await ref
        .read(projectPapersProvider(currentCol.id).notifier)
        .deletePaper(paper.id, repository);
    if (context.mounted) {
      showAppSnackBar(context, 'Deleted "${paper.title}"');
    }
  } catch (e) {
    if (context.mounted) {
      showAppSnackBar(context, 'Error deleting paper: $e', isError: true);
    }
  }
}

/// What the panel shows until the folder has a readable paper: the import
/// button, and the reason when the last import failed.
class _NoPaper extends ConsumerWidget {
  /// The folder's paper when its import failed or is still running.
  final PaperDocument? failed;
  final VoidCallback onImportPaper;

  const _NoPaper({required this.failed, required this.onImportPaper});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importing = ref.watch(importControllerProvider) != null;
    final error = failed?.status == DocumentStatus.failed
        ? failed?.error
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: FilledButton.tonalIcon(
            onPressed: importing ? null : onImportPaper,
            icon: const Icon(Icons.upload_file_outlined, size: 17),
            label: Text(importing ? 'Importing…' : 'Upload PDF'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Expanded(
          child: error != null
              ? _EmptyHint(
                  icon: Icons.error_outline,
                  title: 'The last import failed',
                  message: '$error\n\nUpload the PDF again to retry.',
                )
              : const _EmptyHint(
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'No paper yet',
                  message:
                      'Each folder holds one research paper. Upload it and it '
                      'will show up here with its indexed chunks and the '
                      'works it cites.',
                ),
        ),
      ],
    );
  }
}

/// The opened paper, laid out like a reader: a thin action bar, then the
/// document's own outline, the chunks it was cut into, and its bibliography.
class _PaperDetail extends ConsumerWidget {
  final PaperDocument paper;

  const _PaperDetail({super.key, required this.paper});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    final activeRevision = ref.watch(activeRevisionProvider(paper.id)).value;
    final originalSections = ref.watch(paperSectionsProvider(paper.id));
    final originalChunks = ref.watch(paperChunksProvider(paper.id));
    final sections = activeRevision == null
        ? originalSections
        : activeRevision.sections;
    final chunks = activeRevision != null && activeRevision.chunks.isNotEmpty
        ? [
            ...activeRevision.chunks,
            ...paper.chunks.where((chunk) => chunk.isFigure),
          ]
        : originalChunks;
    final references = ref.watch(paperReferencesProvider(paper.id));

    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (paper.authors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                paper.authors.join(', '),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 11.5,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // Thin action bar, the way a reader puts its controls above the page.
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
                _BarAction(
                  icon: Icons.open_in_new,
                  label: 'Open PDF',
                  onTap: chunks.isEmpty
                      ? null
                      : () => _openCitation(ref, chunks.first),
                ),
                const SizedBox(width: 2),
                _SectionExportAction(
                  enabled: sections.isNotEmpty,
                  onSelected: (choice) => _exportSections(context, ref, choice),
                ),
                const Spacer(),
                _BarAction(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  isDanger: true,
                  onTap: () => _confirmDeletePaper(context, ref, paper),
                ),
              ],
            ),
          ),

          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant, width: 1),
              ),
            ),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.label,
              indicatorWeight: 2,
              labelColor: colorScheme.onSurface,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              labelStyle: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
              unselectedLabelStyle: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 12.5,
              ),
              tabs: [
                Tab(height: 38, text: 'Sections  ${sections.length}'),
                Tab(height: 38, text: 'Chunks  ${chunks.length}'),
                Tab(height: 38, text: 'References  ${references.length}'),
              ],
            ),
          ),

          // The reading surface itself: one flat page rather than a stack of
          // cards.
          Expanded(
            child: Container(
              color: colorScheme.surface,
              child: TabBarView(
                children: [
                  _SectionList(
                    paper: paper,
                    sections: sections,
                    chunks: chunks,
                  ),
                  _ChunkList(paper: paper, chunks: chunks),
                  _ReferenceList(paper: paper, references: references),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openCitation(WidgetRef ref, PaperChunk chunk) {
    ref.read(activeCitationProvider.notifier).state = citationForChunk(
      paper,
      chunk,
    );
  }

  Future<void> _exportSections(
    BuildContext context,
    WidgetRef ref,
    _SectionExportChoice choice,
  ) async {
    if (ref.read(currentCollectionProvider) == null) return;

    try {
      await ref
          .read(chatControllerProvider.notifier)
          .exportSectionsFromPanel(paper, format: choice.name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Export review created in chat'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not export sections: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

enum _SectionExportChoice { markdown, json, both }

class _SectionExportAction extends StatelessWidget {
  final bool enabled;
  final ValueChanged<_SectionExportChoice> onSelected;

  const _SectionExportAction({required this.enabled, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final color = context.colorScheme.onSurfaceVariant;
    return PopupMenuButton<_SectionExportChoice>(
      enabled: enabled,
      tooltip: enabled ? 'Export sections' : 'No sections to export',
      onSelected: onSelected,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _SectionExportChoice.markdown,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.description_outlined, size: 17),
            title: Text('Review Markdown'),
          ),
        ),
        PopupMenuItem(
          value: _SectionExportChoice.json,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.data_object, size: 17),
            title: Text('Review JSON'),
          ),
        ),
        PopupMenuItem(
          value: _SectionExportChoice.both,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.folder_copy_outlined, size: 17),
            title: Text('Review both'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_outlined, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              'Export',
              style: TextStyle(
                color: enabled ? color : color.withValues(alpha: 0.38),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A low-chrome text button for the detail action bar.
class _BarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDanger;
  final VoidCallback? onTap;

  const _BarAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final color = isDanger ? colorScheme.error : colorScheme.onSurfaceVariant;

    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

/// Builds the same shape of [Citation] the research agent emits, so a chunk
/// picked here opens in the existing source panel and PDF viewer.
Citation citationForChunk(PaperDocument paper, PaperChunk chunk) {
  return Citation(
    sourceId: 'p${chunk.page}',
    documentId: paper.id,
    documentHash: paper.sha256,
    fileName: paper.fileName,
    title: paper.title,
    page: chunk.page,
    section: chunk.section,
    chunkId: chunk.id,
    extractionVersion: paper.extractionVersion,
    startChar: chunk.startChar,
    endChar: chunk.endChar,
    excerpt: chunk.text,
  );
}

/// The paper's own structure, as the instruct model read it: a table of
/// contents that expands in place, with the page number in the right margin.
class _SectionList extends ConsumerWidget {
  final PaperDocument paper;
  final List<DocumentSection> sections;
  final List<PaperChunk> chunks;

  const _SectionList({
    required this.paper,
    required this.sections,
    required this.chunks,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sections.isEmpty) {
      return _EmptyHint(
        icon: Icons.segment,
        title: 'No sections detected',
        message: switch (paper.status) {
          DocumentStatus.failed =>
            paper.error ?? 'This import failed, so nothing was indexed.',
          DocumentStatus.ready when paper.isStale =>
            'This paper was imported with an earlier pipeline. Delete and '
                're-import the PDF to get its sections.',
          _ => 'This paper has not finished processing yet.',
        },
      );
    }

    final chunkCounts = <String, int>{};
    for (final chunk in chunks) {
      chunkCounts.update(chunk.sectionId, (n) => n + 1, ifAbsent: () => 1);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final section = sections[index];
        return _SectionRow(
          key: ValueKey(section.id),
          section: section,
          chunkCount: chunkCounts[section.id] ?? 0,
          onOpen: () => ref.read(activeCitationProvider.notifier).state =
              citationForSection(paper, section),
        );
      },
    );
  }
}

/// One outline entry. Collapsed it reads as a line in a table of contents;
/// expanded it drops the transcribed text below, held by a margin rule.
class _SectionRow extends StatefulWidget {
  final DocumentSection section;
  final int chunkCount;
  final VoidCallback onOpen;

  const _SectionRow({
    super.key,
    required this.section,
    required this.chunkCount,
    required this.onOpen,
  });

  @override
  State<_SectionRow> createState() => _SectionRowState();
}

class _SectionRowState extends State<_SectionRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    final section = widget.section;
    final depth = (section.level - 1).clamp(0, 3);
    final indent = 12.0 + 15.0 * depth;
    final isTopLevel = section.level == 1;
    final pages = section.startPage == section.endPage
        ? '${section.startPage}'
        : '${section.startPage}-${section.endPage}';
    final meta = section.isReferences
        ? 'bibliography, not indexed'
        : '${widget.chunkCount} ${widget.chunkCount == 1 ? 'chunk' : 'chunks'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: EdgeInsets.fromLTRB(indent, 9, 6, 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 140),
                    child: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.displayName,
                        style: textTheme.bodyMedium?.copyWith(
                          color: isTopLevel
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                          fontWeight: isTopLevel
                              ? FontWeight.w600
                              : FontWeight.w400,
                          fontSize: isTopLevel ? 13.5 : 12.5,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.75,
                          ),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Page number in the right margin, the way a printed contents
                // page carries it.
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    pages,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 14),
                  color: colorScheme.onSurfaceVariant,
                  tooltip: 'Open at page ${section.startPage}',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: widget.onOpen,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Container(
            width: double.infinity,
            margin: EdgeInsets.fromLTRB(indent + 22, 0, 16, 14),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: colorScheme.outlineVariant, width: 1),
              ),
            ),
            child: MathMarkdown(
              data: section.text.trim(),
              selectable: true,
              styleSheet: _sectionMarkdownStyle(context),
            ),
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 160),
          sizeCurve: Curves.easeOutCubic,
        ),
        Divider(
          height: 1,
          thickness: 1,
          indent: indent,
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ],
    );
  }
}

/// Styling for a section's expanded body text: matches the plain-text
/// look the SelectableText it replaced had, but lets Markdown headings,
/// emphasis, and (via mathInlineSyntaxes/mathBuilders) LaTeX formulas
/// render instead of showing up as raw source.
MarkdownStyleSheet _sectionMarkdownStyle(BuildContext context) {
  final colorScheme = context.colorScheme;
  final base = context.textTheme.bodySmall?.copyWith(
    color: colorScheme.onSurface,
    fontSize: 12.5,
    height: 1.6,
  );
  return MarkdownStyleSheet(
    p: base,
    listBullet: base,
    strong: base?.copyWith(fontWeight: FontWeight.w700),
    em: base?.copyWith(fontStyle: FontStyle.italic),
    h1: base?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
    h2: base?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
    h3: base?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
    code: base?.copyWith(
      fontFamily: 'Consolas',
      backgroundColor: colorScheme.surfaceContainerHighest,
    ),
    blockquote: base?.copyWith(color: colorScheme.onSurfaceVariant),
  );
}

/// A [Citation] pointing at a whole section, so opening one lands on the page
/// the section starts on with its text in the source panel.
Citation citationForSection(PaperDocument paper, DocumentSection section) {
  return Citation(
    sourceId: 'p${section.startPage}',
    documentId: paper.id,
    documentHash: paper.sha256,
    fileName: paper.fileName,
    title: paper.title,
    page: section.startPage,
    section: section.name,
    chunkId: section.id,
    extractionVersion: paper.extractionVersion,
    startChar: section.startChar,
    endChar: section.endChar,
    excerpt: section.text.trim(),
  );
}

/// The indexed chunks, listed as one continuous column with the page number in
/// a left gutter and a rule marking the ones the agent has cited.
class _ChunkList extends ConsumerWidget {
  final PaperDocument paper;
  final List<PaperChunk> chunks;

  const _ChunkList({required this.paper, required this.chunks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;
    final citedChunkIds = ref.watch(citedChunkIdsProvider);

    if (chunks.isEmpty) {
      return _EmptyHint(
        icon: Icons.notes_outlined,
        title: 'No chunks indexed',
        message: paper.status == DocumentStatus.failed
            ? paper.error ?? 'This import failed, so nothing was indexed.'
            : 'This paper has not finished processing yet.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: chunks.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 1,
        indent: 14,
        color: colorScheme.outlineVariant.withValues(alpha: 0.45),
      ),
      itemBuilder: (context, index) {
        final chunk = chunks[index];
        final isCited = citedChunkIds.contains(chunk.id);
        final preview = chunk.text.replaceAll(RegExp(r'\s+'), ' ').trim();

        return InkWell(
          onTap: () {
            ref.read(activeCitationProvider.notifier).state = citationForChunk(
              paper,
              chunk,
            );
          },
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: isCited ? colorScheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 11, 16, 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Page gutter.
                SizedBox(
                  width: 34,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'p.${chunk.page}',
                        style: textTheme.labelSmall?.copyWith(
                          color: isCited
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (isCited)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Icon(
                            Icons.format_quote,
                            size: 13,
                            color: colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (chunk.section.isNotEmpty) ...[
                        Text(
                          chunk.section,
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 10.5,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        preview,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReferenceList extends ConsumerWidget {
  final PaperDocument paper;
  final List<PaperReference> references;

  const _ReferenceList({required this.paper, required this.references});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    final resolved = ref.watch(resolvedReferencesProvider(paper.id));
    final notifier = ref.read(resolvedReferencesProvider(paper.id).notifier);

    if (references.isEmpty) {
      return _EmptyHint(
        icon: Icons.link_off,
        title: 'No bibliography found',
        message:
            'No "References" section was detected in this PDF, so there is '
            'nothing to link out to.',
      );
    }

    final unlinked = references
        .where(
          (reference) =>
              !reference.hasDirectLink && notifier.matchFor(reference) == null,
        )
        .length;

    final hasStatusBar =
        resolved.isResolving || unlinked > 0 || resolved.errorMessage != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasStatusBar)
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (resolved.isResolving) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 0, 0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            strokeCap: StrokeCap.round,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Looking up ${resolved.resolvedCount}/${resolved.totalCount} on Crossref…',
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: resolved.progress,
                      minHeight: 3,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      color: colorScheme.primary,
                    ),
                  ),
                ] else if (unlinked > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _BarAction(
                      icon: Icons.travel_explore,
                      label: 'Find links for $unlinked references',
                      onTap: () => notifier.resolve(references),
                    ),
                  ),
                if (resolved.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 0, 4),
                    child: Text(
                      resolved.errorMessage!,
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.error,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            itemCount: references.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              thickness: 1,
              indent: 14,
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
            itemBuilder: (context, index) {
              final reference = references[index];
              return _ReferenceRow(
                reference: reference,
                match: notifier.matchFor(reference),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One bibliography entry, set like a printed reference list: marker in the
/// gutter, entry text in the column, link underneath.
class _ReferenceRow extends StatelessWidget {
  final PaperReference reference;
  final CrossrefMatch? match;

  const _ReferenceRow({required this.reference, required this.match});

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    // Reference URLs come out of imported documents, so only the web schemes
    // are handed to the OS; a file: or custom-protocol link in a bibliography
    // would otherwise invoke a registered handler on click.
    final isWeb =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final launched =
        isWeb && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      showAppSnackBar(context, 'Could not open $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    final crossrefMatch = match;
    final resolvedUrl = reference.resolvedUrl ?? crossrefMatch?.url;
    final linkLabel = reference.hasDirectLink
        ? reference.linkLabel
        : crossrefMatch != null
        ? 'doi.org/${crossrefMatch.doi}'
        : null;
    final title = reference.hasDirectLink || crossrefMatch == null
        ? reference.title
        : (crossrefMatch.title ?? reference.title);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Text(
              reference.marker ?? '${reference.index}',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title ?? reference.raw,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (reference.year != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '${reference.year}',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  reference.raw,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.45,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: _LinkButton(
                        label: linkLabel ?? 'Search on Google Scholar',
                        isStrong: resolvedUrl != null,
                        onTap: () =>
                            _open(context, resolvedUrl ?? reference.searchUrl),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.copy_outlined,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      tooltip: 'Copy reference',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: reference.raw));
                        showCopiedSnackBar(context, 'Reference');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  final String label;
  final bool isStrong;
  final VoidCallback onTap;

  const _LinkButton({
    required this.label,
    required this.isStrong,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isStrong ? Icons.link : Icons.search,
              size: 14,
              color: isStrong
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isStrong
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyHint({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              title,
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
