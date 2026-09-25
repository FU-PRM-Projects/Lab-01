import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/chat.dart';
import 'package:lab_05/data/models/chat_artifact.dart';
import 'package:lab_05/data/models/citation.dart';
import 'package:lab_05/data/services/section_artifact_service.dart';
import 'package:lab_05/ui/chat/chat_controller.dart';
import 'package:lab_05/ui/chat/tool_call_log.dart';
import 'package:lab_05/ui/collections/import_controller.dart';
import 'package:lab_05/ui/core/markdown_math.dart';
import 'package:lab_05/ui/core/snackbar.dart';
import 'package:lab_05/ui/core/theme.dart';

class ChatPage extends ConsumerStatefulWidget {
  final VoidCallback onImportPaper;

  const ChatPage({super.key, required this.onImportPaper});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final ScrollController _scrollController = ScrollController();
  bool _userScrolledUp = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll > 80) {
      _userScrolledUp = true;
    } else {
      _userScrolledUp = false;
    }
  }

  void _scrollToBottom({bool animate = false}) {
    if (!_userScrolledUp && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && !_userScrolledUp) {
          final max = _scrollController.position.maxScrollExtent;
          if (animate) {
            _scrollController.animateTo(
              max,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          } else {
            _scrollController.jumpTo(max);
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = ref.watch(currentCollectionProvider);
    final chat = ref.watch(currentChatProvider);
    final isStreaming = ref.watch(
      chatControllerProvider.select((s) => s.isStreaming),
    );

    ref.listen(chatControllerProvider.select((s) => s.errorMessage), (
      prev,
      next,
    ) {
      if (next != null && next.isNotEmpty) {
        showAppSnackBar(context, next, isError: true);
      }
    });

    final messages = chat?.messages ?? [];
    final hasMessages = messages.isNotEmpty || isStreaming;

    final Widget content;
    if (!hasMessages) {
      content = KeyedSubtree(
        key: const ValueKey('empty-chat'),
        child: _buildEmptyState(context, collection?.name ?? 'your collection'),
      );
    } else {
      content = SelectionArea(
        key: const ValueKey('active-chat'),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(top: 24, bottom: 32),
          itemCount: messages.length + (isStreaming ? 1 : 0),
          itemBuilder: (context, index) {
            final Widget item;
            if (index < messages.length) {
              final msg = messages[index];
              item = _buildMessageItem(context, msg);
            } else {
              item = _StreamingMessageBubble(
                onScrollNeeded: _scrollToBottom,
                onCitationTap: _openCitation,
              );
            }

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: item,
                ),
              ),
            );
          },
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.012),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: content,
    );
  }

  Widget _buildEmptyState(BuildContext context, String collectionName) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;
    // An empty folder has nothing to chat about yet; its one paper is the
    // only thing to offer, and this is the only place that offers it.
    final canImport = ref.watch(canImportPaperProvider);
    final importing = ref.watch(importControllerProvider) != null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main prompt headline
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                    letterSpacing: -0.3,
                  ),
                  children: [
                    const TextSpan(text: 'What should we explore in '),
                    TextSpan(
                      text: collectionName,
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(text: '?'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                canImport
                    ? 'Each folder holds one research paper. Import it to start '
                          'asking questions with every answer traced back to it.'
                    : 'Ask questions, compare findings, and trace every answer back to your paper.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              if (canImport)
                FilledButton.icon(
                  key: const ValueKey('import-paper-button'),
                  onPressed: importing ? null : widget.onImportPaper,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text(importing ? 'Importing…' : 'Import paper (PDF)'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                )
              else
                // Prompt suggestion chips
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildPromptChip(
                      context,
                      'Summarize main methodology and novelty',
                      Icons.auto_stories_outlined,
                    ),
                    _buildPromptChip(
                      context,
                      'Compare evaluation benchmarks & metrics',
                      Icons.insights_outlined,
                    ),
                    _buildPromptChip(
                      context,
                      'Extract key algorithmic equations & steps',
                      Icons.calculate_outlined,
                    ),
                    _buildPromptChip(
                      context,
                      'What limitations do the authors highlight?',
                      Icons.psychology_alt_outlined,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromptChip(BuildContext context, String prompt, IconData icon) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    return ActionChip(
      avatar: Icon(icon, size: 16, color: colorScheme.primary),
      label: Text(prompt),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return colorScheme.surfaceContainerHighest;
        }
        if (states.contains(WidgetState.hovered)) {
          return colorScheme.surfaceContainerHigh;
        }
        return colorScheme.surfaceContainer;
      }),
      elevation: 0,
      pressElevation: 0,
      side: BorderSide(color: colorScheme.outlineVariant),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      labelStyle: textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w500,
      ),
      onPressed: () {
        ref.read(chatControllerProvider.notifier).sendMessage(prompt);
      },
    );
  }

  Widget _buildMessageItem(BuildContext context, ChatMessage msg) {
    final isUser = msg.role == 'user';
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(top: 2, right: 14),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.psychology,
                size: 18,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: isUser ? 620 : 760),
              padding: isUser
                  ? const EdgeInsets.symmetric(horizontal: 18, vertical: 12)
                  : EdgeInsets.zero,
              decoration: isUser
                  ? BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(6),
                      ),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isUser)
                    Text(
                      msg.content,
                      style: textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        height: 1.5,
                      ),
                    )
                  else ...[
                    // What the agent did before answering
                    if (msg.toolCalls.isNotEmpty)
                      ToolCallLog(calls: msg.toolCalls),

                    // Assistant Markdown Content with Clickable Citations
                    _buildAssistantMarkdown(
                      context,
                      msg.content,
                      msg.citations,
                    ),

                    if (msg.artifacts.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final artifact in msg.artifacts) ...[
                        _SectionArtifactCard(artifact: artifact),
                        const SizedBox(height: 8),
                      ],
                    ],

                    // Sources Bar if citations present
                    if (msg.citations.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildSourcesRack(context, msg.citations),
                    ],

                    // Action bar (copy, timestamp/model)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.copy_outlined,
                              size: 15,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            tooltip: 'Copy response',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: msg.content),
                              );
                              showCopiedSnackBar(context, 'Response');
                            },
                          ),
                          const SizedBox(width: 8),
                          if (msg.model != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                              child: Text(
                                msg.model!.split('/').last,
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static MarkdownStyleSheet createMarkdownStyle(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    return MarkdownStyleSheet(
      p: textTheme.bodyLarge?.copyWith(
        color: colorScheme.onSurface,
        fontSize: 14.5,
        height: 1.6,
      ),
      h1: textTheme.titleLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.bold,
      ),
      h2: textTheme.titleMedium?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.bold,
      ),
      h3: textTheme.titleSmall?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.bold,
      ),
      code: TextStyle(
        backgroundColor: colorScheme.surfaceContainerHighest,
        color: colorScheme.primary,
        fontFamily: 'Consolas',
        fontSize: 13,
      ),
      codeblockDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      blockquote: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: colorScheme.primary, width: 3)),
      ),
    );
  }

  Widget _buildAssistantMarkdown(
    BuildContext context,
    String content,
    List<Citation> citations,
  ) {
    final citationMap = {for (final c in citations) c.sourceId: c};

    return MathMarkdown(
      data: content,
      styleSheet: createMarkdownStyle(context),
      onTapLink: (text, href, title) {
        if (href != null && citationMap.containsKey(href)) {
          _openCitation(citationMap[href]!);
        }
      },
    );
  }

  Widget _buildSourcesRack(BuildContext context, List<Citation> citations) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.library_books_outlined,
                size: 14,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'CITED SOURCES',
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: citations.map((citation) {
              return ActionChip(
                backgroundColor: colorScheme.surfaceContainerHigh,
                side: BorderSide(color: colorScheme.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                avatar: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    citation.sourceId,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                label: Text(
                  '${citation.title} (p. ${citation.page})',
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
                onPressed: () => _openCitation(citation),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _openCitation(Citation citation) {
    ref.read(activeCitationProvider.notifier).state = citation;
  }
}

class _StreamingMessageBubble extends ConsumerWidget {
  final VoidCallback onScrollNeeded;
  final void Function(Citation) onCitationTap;

  const _StreamingMessageBubble({
    required this.onScrollNeeded,
    required this.onCitationTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    final statusMessage = ref.watch(
      chatControllerProvider.select((s) => s.statusMessage),
    );
    final text = ref.watch(
      chatControllerProvider.select((s) => s.streamingText ?? ''),
    );
    final sources = ref.watch(
      chatControllerProvider.select((s) => s.streamingSources.values.toList()),
    );
    final toolCalls = ref.watch(
      chatControllerProvider.select((s) => s.toolCalls),
    );
    final artifacts = ref.watch(
      chatControllerProvider.select((s) => s.artifacts),
    );

    ref.listen(chatControllerProvider.select((s) => s.streamingText), (
      prev,
      next,
    ) {
      if (next != null && next.isNotEmpty) {
        onScrollNeeded();
      }
    });

    final citationMap = {for (final c in sources) c.sourceId: c};

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(top: 2, right: 14),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.psychology,
              size: 18,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (toolCalls.isNotEmpty) ToolCallLog(calls: toolCalls),
                  if (toolCalls.any(
                        (call) =>
                            call.name == 'export_sections' && call.isRunning,
                      ) &&
                      artifacts.isEmpty)
                    _SavingArtifactCard(
                      title:
                          toolCalls
                              .where((call) => call.name == 'export_sections')
                              .last
                              .arguments['paperTitle']
                              ?.toString() ??
                          'Paper sections',
                    ),
                  if (statusMessage != null && text.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              strokeCap: StrokeCap.round,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            statusMessage,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (text.isNotEmpty)
                    MathMarkdown(
                      data: text,
                      styleSheet: _ChatPageState.createMarkdownStyle(context),
                      onTapLink: (t, href, title) {
                        if (href != null && citationMap.containsKey(href)) {
                          onCitationTap(citationMap[href]!);
                        }
                      },
                    ),
                  if (artifacts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final artifact in artifacts) ...[
                      _SectionArtifactCard(artifact: artifact),
                      const SizedBox(height: 8),
                    ],
                  ],
                  if (text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 8,
                        height: 14,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavingArtifactCard extends StatelessWidget {
  final String title;

  const _SavingArtifactCard({required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preparing export review…',
                  style: context.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _ArtifactSaveChoice { markdown, json, both }

class _SectionDiff {
  final String title;
  final String before;
  final String after;

  const _SectionDiff({
    required this.title,
    required this.before,
    required this.after,
  });
}

enum _DiffKind { unchanged, removed, added }

class _DiffLine {
  final _DiffKind kind;
  final String text;
  final int? oldNumber;
  final int? newNumber;

  const _DiffLine(this.kind, this.text, this.oldNumber, this.newNumber);
}

class _SectionDiffView extends StatelessWidget {
  final List<_SectionDiff> changes;

  const _SectionDiffView({required this.changes});

  @override
  Widget build(BuildContext context) {
    if (changes.isEmpty) {
      return const Center(child: Text('No changed lines.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 14),
      itemCount: changes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final change = changes[index];
        final lines = _buildLineDiff(change.before, change.after);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.difference_outlined, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      change.title,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final line in lines) _DiffLineRow(line: line),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  final _DiffLine line;

  const _DiffLineRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, stripe, marker) = switch (line.kind) {
      _DiffKind.removed => (
        colors.errorContainer.withValues(alpha: 0.58),
        colors.error,
        '−',
      ),
      _DiffKind.added => (
        const Color(0xFF2DA44E).withValues(alpha: 0.14),
        const Color(0xFF2DA44E),
        '+',
      ),
      _ => (Colors.transparent, colors.outlineVariant, ' '),
    };
    final numberStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      color: colors.onSurfaceVariant,
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 25),
      decoration: BoxDecoration(
        color: background,
        border: Border(left: BorderSide(color: stripe, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 45,
            child: Text(
              line.oldNumber?.toString() ?? '',
              textAlign: TextAlign.right,
              style: numberStyle,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 45,
            child: Text(
              line.newNumber?.toString() ?? '',
              textAlign: TextAlign.right,
              style: numberStyle,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 18,
            child: Text(marker, style: numberStyle.copyWith(color: stripe)),
          ),
          Expanded(
            child: SelectableText(
              line.text.isEmpty ? ' ' : line.text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.45,
                color: colors.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

List<_DiffLine> _buildLineDiff(String before, String after) {
  final oldLines = before.split('\n');
  final newLines = after.split('\n');
  final width = newLines.length + 1;
  // A section can occasionally contain a very large generated block. Keep the
  // preview responsive instead of allocating an unbounded LCS table.
  if (oldLines.length * newLines.length > 750000) {
    return [
      for (var i = 0; i < oldLines.length; i++)
        _DiffLine(_DiffKind.removed, oldLines[i], i + 1, null),
      for (var i = 0; i < newLines.length; i++)
        _DiffLine(_DiffKind.added, newLines[i], null, i + 1),
    ];
  }
  final table = Uint32List((oldLines.length + 1) * width);
  for (var oldIndex = oldLines.length - 1; oldIndex >= 0; oldIndex--) {
    for (var newIndex = newLines.length - 1; newIndex >= 0; newIndex--) {
      final at = oldIndex * width + newIndex;
      table[at] = oldLines[oldIndex] == newLines[newIndex]
          ? table[(oldIndex + 1) * width + newIndex + 1] + 1
          : table[(oldIndex + 1) * width + newIndex] >=
                table[oldIndex * width + newIndex + 1]
          ? table[(oldIndex + 1) * width + newIndex]
          : table[oldIndex * width + newIndex + 1];
    }
  }
  final result = <_DiffLine>[];
  var oldIndex = 0;
  var newIndex = 0;
  while (oldIndex < oldLines.length && newIndex < newLines.length) {
    if (oldLines[oldIndex] == newLines[newIndex]) {
      result.add(
        _DiffLine(
          _DiffKind.unchanged,
          oldLines[oldIndex],
          oldIndex + 1,
          newIndex + 1,
        ),
      );
      oldIndex++;
      newIndex++;
    } else if (table[(oldIndex + 1) * width + newIndex] >=
        table[oldIndex * width + newIndex + 1]) {
      result.add(
        _DiffLine(_DiffKind.removed, oldLines[oldIndex], oldIndex + 1, null),
      );
      oldIndex++;
    } else {
      result.add(
        _DiffLine(_DiffKind.added, newLines[newIndex], null, newIndex + 1),
      );
      newIndex++;
    }
  }
  while (oldIndex < oldLines.length) {
    result.add(
      _DiffLine(_DiffKind.removed, oldLines[oldIndex], oldIndex + 1, null),
    );
    oldIndex++;
  }
  while (newIndex < newLines.length) {
    result.add(
      _DiffLine(_DiffKind.added, newLines[newIndex], null, newIndex + 1),
    );
    newIndex++;
  }
  return result;
}

class _SectionArtifactCard extends ConsumerWidget {
  final ChatArtifact artifact;

  const _SectionArtifactCard({required this.artifact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colorScheme;
    final isExportDraft = artifact.type == 'sectionDraft';
    final isChangeDraft = artifact.type == 'sectionChangeDraft';
    final isDraft = isExportDraft || isChangeDraft;
    final isRevision = artifact.type == 'sectionRevision';
    final isDiscarded = artifact.status == 'discarded';
    final isSuperseded = artifact.status == 'superseded';
    final formatLabel = switch (artifact.requestedFormat) {
      'markdown' => 'Markdown',
      'json' => 'JSON',
      _ => 'Markdown + JSON',
    };
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isChangeDraft
                  ? Icons.difference_outlined
                  : Icons.description_outlined,
              size: 20,
              color: colors.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artifact.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isDraft
                      ? (isDiscarded
                            ? 'Draft discarded'
                            : isSuperseded
                            ? 'Superseded by a newer chat edit'
                            : artifact.status == 'index_failed'
                            ? 'Revision saved · indexing failed · retry available'
                            : isChangeDraft
                            ? 'Change draft · review highlighted edits before applying'
                            : 'Export review · edit in chat or save when ready')
                      : artifact.status == 'reverted'
                      ? 'Revision reverted · exported snapshot retained'
                      : '${artifact.sectionCount} sections · $formatLabel · saved locally',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: isDiscarded ? null : () => _open(context, ref),
            child: const Text('Open'),
          ),
          if (isDraft && !isDiscarded && !isSuperseded) ...[
            FilledButton.tonal(
              onPressed: () => _saveDraft(context, ref),
              child: Text(
                artifact.status == 'index_failed'
                    ? 'Retry indexing'
                    : isChangeDraft
                    ? 'Apply changes'
                    : switch (artifact.requestedFormat) {
                        'markdown' => 'Save Markdown',
                        'json' => 'Save JSON',
                        _ => 'Save both',
                      },
              ),
            ),
            IconButton(
              tooltip: 'Discard draft',
              onPressed: () => _discardDraft(context, ref),
              icon: const Icon(Icons.delete_outline, size: 19),
            ),
          ] else ...[
            if (isRevision &&
                artifact.parentRevisionId != null &&
                artifact.status != 'reverted')
              TextButton(
                onPressed: () => _revert(context, ref),
                child: const Text('Revert'),
              ),
            PopupMenuButton<_ArtifactSaveChoice>(
              tooltip: 'Download artifact',
              onSelected: (choice) => _save(context, ref, choice),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _ArtifactSaveChoice.markdown,
                  child: Text('Save Markdown'),
                ),
                PopupMenuItem(
                  value: _ArtifactSaveChoice.json,
                  child: Text('Save JSON'),
                ),
                PopupMenuItem(
                  value: _ArtifactSaveChoice.both,
                  child: Text('Save both'),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Download'),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 17,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<({String markdownPath, String jsonPath})> _ensureFiles(
    WidgetRef ref,
  ) async {
    final storage = ref.read(localStorageProvider);
    final artifactId = artifact.artifactId;
    final markdownPath = storage.sectionsMarkdownPath(
      artifact.collectionId,
      artifact.documentId,
      artifactId,
    );
    final jsonPath = storage.sectionsJsonPath(
      artifact.collectionId,
      artifact.documentId,
      artifactId,
    );
    if (await File(markdownPath).exists() && await File(jsonPath).exists()) {
      return (markdownPath: markdownPath, jsonPath: jsonPath);
    }
    final paper = await storage.loadPaper(
      artifact.collectionId,
      artifact.documentId,
    );
    if (paper == null) {
      throw StateError('The source paper is no longer available.');
    }
    final revision = artifact.revisionId == null
        ? null
        : await storage.loadRevision(
            artifact.collectionId,
            artifact.documentId,
            artifact.revisionId!,
          );
    final created = await storage.saveSectionArtifacts(
      artifact.collectionId,
      paper,
      revision: revision,
      artifactId: artifactId,
    );
    return (markdownPath: created.markdownPath, jsonPath: created.jsonPath);
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    try {
      final String markdown;
      final String json;
      final isChangeDraft = artifact.type == 'sectionChangeDraft';
      List<_SectionDiff> changes = const [];
      if (artifact.type == 'sectionDraft' || isChangeDraft) {
        final revisionId = artifact.revisionId;
        if (revisionId == null) throw StateError('Draft revision is missing.');
        final storage = ref.read(localStorageProvider);
        final revision = await storage.loadRevision(
          artifact.collectionId,
          artifact.documentId,
          revisionId,
        );
        if (revision == null) throw StateError('Draft revision was deleted.');
        final paper = await storage.loadPaper(
          artifact.collectionId,
          artifact.documentId,
        );
        if (paper == null) {
          throw StateError('The source paper is no longer available.');
        }
        final preview = SectionArtifactService.build(
          paper.copyWith(sections: revision.sections),
          revisionId: revision.id,
        );
        markdown = preview.markdown;
        json = preview.jsonText;
        if (isChangeDraft) {
          final parentId = revision.parentRevisionId;
          final parent = parentId == null
              ? null
              : await storage.loadRevision(
                  artifact.collectionId,
                  artifact.documentId,
                  parentId,
                );
          final beforeById = {
            for (final section in parent?.sections ?? paper.sections)
              section.id: section,
          };
          changes = [
            for (final section in revision.sections)
              if (beforeById[section.id]?.text != section.text)
                _SectionDiff(
                  title: section.displayName,
                  before: beforeById[section.id]?.text ?? '',
                  after: section.text,
                ),
          ];
        }
      } else {
        final paths = await _ensureFiles(ref);
        markdown = await File(paths.markdownPath).readAsString();
        json = await File(paths.jsonPath).readAsString();
      }
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => DefaultTabController(
          length: isChangeDraft ? 3 : 2,
          child: Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 8, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${artifact.title} · '
                            '${isChangeDraft ? 'Review changes' : 'Export review'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(dialogContext)
                                .textTheme
                                .titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  TabBar(
                    tabs: [
                      if (isChangeDraft) const Tab(text: 'Changes'),
                      const Tab(text: 'Markdown'),
                      const Tab(text: 'JSON'),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      children: [
                        if (isChangeDraft) _SectionDiffView(changes: changes),
                        Markdown(
                          data: SectionArtifactService.readableMarkdown(
                            markdown,
                          ),
                          selectable: true,
                          padding: const EdgeInsets.all(20),
                          styleSheet: _ChatPageState.createMarkdownStyle(
                            dialogContext,
                          ),
                        ),
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: SelectableText(
                            json,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _saveDraft(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(chatControllerProvider.notifier)
          .saveDraftRevision(artifact);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _discardDraft(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(chatControllerProvider.notifier)
          .discardDraftRevision(artifact);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _revert(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(chatControllerProvider.notifier).revertRevision(artifact);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    _ArtifactSaveChoice choice,
  ) async {
    try {
      final paths = await _ensureFiles(ref);
      final baseName = _safeFileName(artifact.title);
      if (choice == _ArtifactSaveChoice.both) {
        final directory = await FilePicker.getDirectoryPath(
          dialogTitle: 'Save section artifacts',
        );
        if (directory == null || directory.isEmpty) return;
        await File(paths.markdownPath)
            .copy(p.join(directory, '${baseName}_sections.md'));
        await File(paths.jsonPath)
            .copy(p.join(directory, '${baseName}_sections.json'));
      } else {
        final markdown = choice == _ArtifactSaveChoice.markdown;
        final sourcePath = markdown ? paths.markdownPath : paths.jsonPath;
        final extension = markdown ? 'md' : 'json';
        final destination = await FilePicker.saveFile(
          dialogTitle: markdown
              ? 'Save sections as Markdown'
              : 'Save sections as JSON',
          fileName: '${baseName}_sections.$extension',
          bytes: await File(sourcePath).readAsBytes(),
          mimeType: markdown ? 'text/markdown' : 'application/json',
          type: FileType.custom,
          allowedExtensions: [extension],
        );
        if (destination == null) return;
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Section artifact saved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  static String _safeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^[_. ]+|[_. ]+$'), '');
    return cleaned.isEmpty ? 'paper' : cleaned;
  }

  static void _showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open section artifact: $error'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
