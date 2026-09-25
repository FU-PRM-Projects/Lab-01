import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/ui/chat/chat_controller.dart';
import 'package:lab_05/ui/core/theme.dart';

class CodexComposer extends ConsumerStatefulWidget {
  const CodexComposer({super.key});

  @override
  ConsumerState<CodexComposer> createState() => _CodexComposerState();
}

class _CodexComposerState extends ConsumerState<CodexComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  String _formatModelName(String modelId) {
    if (modelId.contains('deepseek-v4.1-flash') ||
        modelId.contains('deepseek')) {
      return 'DeepSeek 4.1 Flash';
    }
    if (modelId.contains('minimax-m3') || modelId.contains('mimo')) {
      return 'MiMo M3';
    }
    return modelId.split('/').last;
  }

  void _handleSubmit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final chatState = ref.read(chatControllerProvider);
    if (chatState.isStreaming) return;

    _controller.clear();
    ref.read(chatControllerProvider.notifier).sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;
    final isDark = context.isDarkMode;

    final isStreaming = ref.watch(
      chatControllerProvider.select((s) => s.isStreaming),
    );
    final collection = ref.watch(currentCollectionProvider);
    final settings = ref.watch(settingsProvider);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.fromLTRB(18, 6, 18, 14),
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainerHigh
                : colorScheme.surfaceBright,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focusNode.hasFocus
                  ? colorScheme.outline
                  : colorScheme.outlineVariant,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: _focusNode.hasFocus
                      ? (isDark ? 0.30 : 0.10)
                      : (isDark ? 0.20 : 0.05),
                ),
                blurRadius: _focusNode.hasFocus ? 18 : 12,
                offset: Offset(0, _focusNode.hasFocus ? 5 : 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Multi-line Text Input
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                child: KeyboardListener(
                  focusNode: _keyboardFocusNode,
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _handleSubmit();
                    }
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 4,
                    style: textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurface,
                      height: 1.45,
                    ),
                    cursorColor: colorScheme.primary,
                    decoration: InputDecoration(
                      hintText: collection == null
                          ? 'Select or create a collection to begin research...'
                          : 'Message PaperChat about ${collection.name}...',
                      hintStyle: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.65,
                        ),
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
              ),

              // Bottom Action Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 10, 8),
                child: Row(
                  children: [
                    // A folder holds one paper, imported when the folder is
                    // created, so the composer carries no "add source" button.
                    const Spacer(),

                    Text(
                      'Enter to send',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.72,
                        ),
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Model Selector Chip
                    PopupMenuButton<String>(
                      tooltip: 'Select Multimodal AI Model',
                      color: colorScheme.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: colorScheme.outlineVariant),
                      ),
                      onSelected: (modelId) {
                        ref
                            .read(settingsProvider.notifier)
                            .update(settings.copyWith(chatModel: modelId));
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          value: 'deepseek/deepseek-v4.1-flash',
                          child: Row(
                            children: [
                              Icon(
                                settings.chatModel ==
                                        'deepseek/deepseek-v4.1-flash'
                                    ? Icons.check
                                    : Icons.circle_outlined,
                                size: 16,
                                color:
                                    settings.chatModel ==
                                        'deepseek/deepseek-v4.1-flash'
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              const Text('DeepSeek 4.1 Flash'),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Multimodal',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'minimax/minimax-m3',
                          child: Row(
                            children: [
                              Icon(
                                settings.chatModel == 'minimax/minimax-m3'
                                    ? Icons.check
                                    : Icons.circle_outlined,
                                size: 16,
                                color:
                                    settings.chatModel == 'minimax/minimax-m3'
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              const Text('MiMo M3'),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Multimodal',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.model_training,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _formatModelName(settings.chatModel),
                              style: textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Send or stop generation
                    IconButton.filled(
                      onPressed: () {
                        if (isStreaming) {
                          ref.read(chatControllerProvider.notifier).stop();
                        } else {
                          _handleSubmit();
                        }
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: isStreaming
                            ? colorScheme.error
                            : colorScheme.primary,
                        foregroundColor: isStreaming
                            ? colorScheme.onError
                            : colorScheme.onPrimary,
                        minimumSize: const Size(36, 36),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      icon: Icon(
                        isStreaming ? Icons.stop : Icons.arrow_upward,
                        size: 18,
                      ),
                      tooltip: isStreaming ? 'Stop generation' : 'Send message',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
