import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/chat.dart';
import 'package:lab_05/data/models/citation.dart';
import 'package:lab_05/ui/chat/chat_controller.dart';
import 'package:lab_05/ui/chat/tool_call_log.dart';
import 'package:lab_05/ui/core/markdown_math.dart';
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
    final colorScheme = context.colorScheme;

    ref.listen(chatControllerProvider.select((s) => s.errorMessage), (
      prev,
      next,
    ) {
      if (next != null && next.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
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
                'Ask questions, compare findings, and trace every answer back to your papers.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

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
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Response copied to clipboard',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 1),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              );
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

    return MarkdownBody(
      data: content,
      selectable: false,
      styleSheet: createMarkdownStyle(context),
      blockSyntaxes: mathBlockSyntaxes,
      inlineSyntaxes: mathInlineSyntaxes,
      builders: mathBuilders,
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
                    MarkdownBody(
                      data: text,
                      selectable: false,
                      styleSheet: _ChatPageState.createMarkdownStyle(context),
                      blockSyntaxes: mathBlockSyntaxes,
                      inlineSyntaxes: mathInlineSyntaxes,
                      builders: mathBuilders,
                      onTapLink: (t, href, title) {
                        if (href != null && citationMap.containsKey(href)) {
                          onCitationTap(citationMap[href]!);
                        }
                      },
                    ),
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
