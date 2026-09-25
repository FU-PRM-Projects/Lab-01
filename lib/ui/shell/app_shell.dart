import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/ui/artifacts/artifact_controller.dart';
import 'package:lab_05/ui/artifacts/artifact_panel.dart';
import 'package:lab_05/ui/chat/chat_controller.dart';
import 'package:lab_05/ui/chat/chat_page.dart';
import 'package:lab_05/ui/chat/composer.dart';
import 'package:lab_05/ui/collections/import_controller.dart';
import 'package:lab_05/ui/collections/sidebar.dart';
import 'package:lab_05/ui/core/snackbar.dart';
import 'package:lab_05/ui/core/theme.dart';
import 'package:lab_05/ui/settings/settings_dialog.dart';
import 'package:lab_05/ui/sources/source_panel.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  Future<void> _pickAndImportPaper() async {
    final collection = ref.read(currentCollectionProvider);
    if (collection == null) {
      showAppSnackBar(context, 'Please select or create a collection first');
      return;
    }

    // A folder holds exactly one paper; another paper needs its own folder.
    if (!ref.read(canImportPaperProvider)) {
      showAppSnackBar(
        context,
        'This folder already has its paper. '
        'Create a new folder to import another one.',
      );
      return;
    }

    final apiKey = ref.read(apiKeyProvider);
    if (apiKey.trim().isEmpty) {
      showDialog<void>(
        context: context,
        builder: (_) => const SettingsDialog(),
      );
      showAppSnackBar(
        context,
        'OpenRouter API Key required for embeddings and indexing',
      );
      return;
    }

    if (ref.read(importControllerProvider) != null) return;
    await ref.read(chatControllerProvider.notifier).stop();
    if (!mounted) return;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        dialogTitle: 'Select Research Paper PDF',
      );

      if (files.isEmpty || files.first.path == null) {
        return;
      }

      if (!mounted) return;
      final sourceFile = File(files.first.path!);
      await ref
          .read(importControllerProvider.notifier)
          .import(collection, sourceFile);

      if (mounted) {
        // The imported PDF lands in this chat's artifact sidebar.
        ref
            .read(artifactPanelProvider.notifier)
            .open(ref.read(artifactScopeProvider));
        showAppSnackBar(
          context,
          'Successfully imported "${sourceFile.uri.pathSegments.last}"',
          isSuccess: true,
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Import error: $e',
          isError: true,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Theme.of(context).colorScheme.onError,
            onPressed: _pickAndImportPaper,
          ),
        );
      }
    }
  }

  Future<void> _handleNewChat() async {
    await ref.read(chatControllerProvider.notifier).stop();
    if (!mounted) return;
    ref.read(activeCitationProvider.notifier).state = null;
    ref.read(currentChatProvider.notifier).state = null;
  }

  void _toggleTheme() => ref
      .read(settingsProvider.notifier)
      .toggleTheme(Theme.of(context).brightness);

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;
    final isDark = context.isDarkMode;

    final collection = ref.watch(currentCollectionProvider);
    // The folder's one paper, once it has indexed.
    final paper = ref
        .watch(papersProvider)
        .where((p) => p.occupiesFolder)
        .firstOrNull;
    final activeCitation = ref.watch(activeCitationProvider);
    final importProgress = ref.watch(importControllerProvider);
    final artifactScope = ref.watch(artifactScopeProvider);
    final artifactView = ref.watch(artifactViewProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Row(
        children: [
          // M3 Sidebar Navigation Drawer
          AppSidebar(
            onNewChat: _handleNewChat,
            onImportPaper: _pickAndImportPaper,
          ),

          // Main Conversation Area
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Material 3 Top Header Bar
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 30,
                        child: Center(
                          child: Icon(
                            Icons.folder_outlined,
                            size: 18,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        collection?.name ?? 'Select a project',
                        style: textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.15,
                        ),
                      ),
                      if (collection != null) ...[
                        const SizedBox(width: 10),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: Text(
                              paper?.title ?? 'No paper yet',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),

                      // Per-chat artifact sidebar toggle
                      if (collection != null)
                        IconButton(
                          icon: Icon(
                            artifactView.isOpen
                                ? Icons.inventory_2
                                : Icons.inventory_2_outlined,
                            size: 19,
                            color: artifactView.isOpen
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          tooltip: artifactView.isOpen
                              ? 'Hide artifacts'
                              : 'Show artifacts',
                          onPressed: () {
                            ref.read(activeCitationProvider.notifier).state =
                                null;
                            ref
                                .read(artifactPanelProvider.notifier)
                                .toggle(artifactScope);
                          },
                        ),

                      // Quick Theme Switcher Button
                      IconButton(
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 140),
                          transitionBuilder: (child, animation) =>
                              RotationTransition(
                                turns: Tween<double>(
                                  begin: 0.85,
                                  end: 1,
                                ).animate(animation),
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              ),
                          child: Icon(
                            isDark
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                            key: ValueKey(isDark),
                            size: 19,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        tooltip: isDark
                            ? 'Switch to Light Mode'
                            : 'Switch to Dark Mode',
                        onPressed: _toggleTheme,
                      ),
                    ],
                  ),
                ),

                // Material 3 Import Progress Bar (if active)
                if (importProgress != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    color: colorScheme.surfaceContainerHigh,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                strokeCap: StrokeCap.round,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              importProgress.$1,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${(importProgress.$2 * 100).toInt()}%',
                              style: textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: importProgress.$2,
                            minHeight: 4,
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Chat View Area
                Expanded(child: ChatPage(onImportPaper: _pickAndImportPaper)),

                // Material 3 Floating Composer
                const CodexComposer(),
              ],
            ),
          ),

          // Right dock: this chat's artifacts, or the source inspector while a
          // citation is open. Closing the citation returns to the artifacts.
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerRight,
            child: activeCitation != null
                ? SourcePanel(
                    key: ValueKey(activeCitation.chunkId),
                    citation: activeCitation,
                    onClose: () {
                      ref.read(activeCitationProvider.notifier).state = null;
                    },
                  )
                : artifactView.isOpen && collection != null
                ? ArtifactPanel(
                    key: ValueKey(artifactScope),
                    onImportPaper: _pickAndImportPaper,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
