import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/ui/chat/chat_controller.dart';
import 'package:lab_05/ui/chat/chat_page.dart';
import 'package:lab_05/ui/chat/composer.dart';
import 'package:lab_05/ui/collections/import_controller.dart';
import 'package:lab_05/ui/collections/sidebar.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select or create a collection first'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final apiKey = ref.read(apiKeyProvider);
    if (apiKey.trim().isEmpty) {
      showDialog<void>(
        context: context,
        builder: (_) => const SettingsDialog(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'OpenRouter API Key required for embeddings and indexing',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Successfully imported "${sourceFile.uri.pathSegments.last}"',
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import error: $e'),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            action: SnackBarAction(
              label: 'Retry',
              textColor: colorScheme.onError,
              onPressed: _pickAndImportPaper,
            ),
            duration: const Duration(seconds: 5),
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

  void _toggleTheme() {
    final settings = ref.read(settingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nextTheme = isDark ? 'light' : 'dark';
    ref.read(settingsProvider.notifier).update(
      settings.copyWith(theme: nextTheme),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;
    final isDark = context.isDarkMode;

    final collection = ref.watch(currentCollectionProvider);
    final papers = ref.watch(papersProvider);
    final activeCitation = ref.watch(activeCitationProvider);
    final importProgress = ref.watch(importControllerProvider);

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
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    border: Border(
                      bottom: BorderSide(
                        color: colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: collection != null
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.folder_outlined,
                          size: 16,
                          color: collection != null
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        collection?.name ?? 'No Collection Selected',
                        style: textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (collection != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            '${papers.length} ${papers.length == 1 ? 'paper' : 'papers'}',
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (collection != null)
                        FilledButton.tonalIcon(
                          onPressed: _pickAndImportPaper,
                          icon: const Icon(Icons.upload_file_outlined, size: 16),
                          label: const Text('Import PDF'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      const SizedBox(width: 8),

                      // Quick Theme Switcher Button
                      IconButton(
                        icon: Icon(
                          isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                          size: 19,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                        onPressed: _toggleTheme,
                      ),

                      // Settings Button
                      IconButton(
                        icon: Icon(
                          Icons.settings_outlined,
                          size: 19,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        tooltip: 'Settings',
                        onPressed: () {
                          showDialog<void>(
                            context: context,
                            builder: (_) => const SettingsDialog(),
                          );
                        },
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
                            backgroundColor: colorScheme.surfaceContainerHighest,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Chat View Area
                Expanded(child: ChatPage(onImportPaper: _pickAndImportPaper)),

                // Material 3 Floating Composer
                CodexComposer(onImportPaper: _pickAndImportPaper),
              ],
            ),
          ),

          // Side-by-side Source Inspection & PDF Panel
          if (activeCitation != null)
            SourcePanel(
              citation: activeCitation,
              onClose: () {
                ref.read(activeCitationProvider.notifier).state = null;
              },
            ),
        ],
      ),
    );
  }
}
