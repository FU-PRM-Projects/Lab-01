import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/ui/chat/chat_controller.dart';
import 'package:lab_05/ui/collections/import_controller.dart';
import 'package:lab_05/ui/core/theme.dart';
import 'package:lab_05/ui/settings/settings_dialog.dart';

class AppSidebar extends ConsumerStatefulWidget {
  final VoidCallback onNewChat;
  final VoidCallback onImportPaper;

  const AppSidebar({
    super.key,
    required this.onNewChat,
    required this.onImportPaper,
  });

  @override
  ConsumerState<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends ConsumerState<AppSidebar> {
  final Set<String> _expandedCollections = {};

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

    final collections = ref.watch(collectionsProvider);
    final currentCol = ref.watch(currentCollectionProvider);
    final chats = ref.watch(chatsProvider);
    final currentChat = ref.watch(currentChatProvider);
    final apiKey = ref.watch(apiKeyProvider);

    return AbsorbPointer(
      absorbing: ref.watch(importControllerProvider) != null,
      child: Container(
        width: 270,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          border: Border(
            right: BorderSide(
              color: colorScheme.outlineVariant,
              width: 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: Branding & Action Icons
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.psychology,
                      size: 20,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'PaperChat',
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.settings_outlined,
                      size: 18,
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

            // Material 3 "New Chat" Pill Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: FilledButton.tonalIcon(
                onPressed: widget.onNewChat,
                icon: const Icon(Icons.edit_note, size: 20),
                label: const Text('New chat'),
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Scrollable Collections & Recents
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  // Projects / Collections Section Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
                    child: Row(
                      children: [
                        Text(
                          'Projects',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            Icons.add,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'New Collection',
                          onPressed: () => _promptCreateCollection(context),
                        ),
                      ],
                    ),
                  ),

                  // Collection items
                  if (collections.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        'No collections yet',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    )
                  else
                    ...collections.map((col) {
                      final isSelected = currentCol?.id == col.id;
                      final isExpanded =
                          _expandedCollections.contains(col.id) || isSelected;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colorScheme.secondaryContainer
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () async {
                                await ref
                                    .read(chatControllerProvider.notifier)
                                    .stop();
                                if (!mounted) return;
                                ref
                                        .read(activeCitationProvider.notifier)
                                        .state =
                                    null;
                                ref
                                        .read(
                                          currentCollectionProvider.notifier,
                                        )
                                        .state =
                                    col;
                                ref.read(currentChatProvider.notifier).state =
                                    null;
                                setState(() {
                                  if (_expandedCollections.contains(col.id)) {
                                    _expandedCollections.remove(col.id);
                                  } else {
                                    _expandedCollections.add(col.id);
                                  }
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isExpanded
                                          ? Icons.folder_open
                                          : Icons.folder_outlined,
                                      size: 18,
                                      color: isSelected
                                          ? colorScheme.onSecondaryContainer
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        col.name,
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: isSelected
                                              ? colorScheme.onSecondaryContainer
                                              : colorScheme.onSurface,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      icon: Icon(
                                        Icons.more_vert,
                                        size: 16,
                                        color: isSelected
                                            ? colorScheme.onSecondaryContainer
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                      tooltip: 'Collection options',
                                      color: colorScheme.surfaceContainerHigh,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(
                                          color: colorScheme.outlineVariant,
                                        ),
                                      ),
                                      onSelected: (action) async {
                                        if (action == 'import') {
                                          await ref
                                              .read(chatControllerProvider.notifier)
                                              .stop();
                                          if (!mounted) return;
                                          ref.read(currentChatProvider.notifier).state = null;
                                          ref.read(activeCitationProvider.notifier).state = null;
                                          ref
                                                  .read(
                                                    currentCollectionProvider
                                                        .notifier,
                                                  )
                                                  .state =
                                              col;
                                          widget.onImportPaper();
                                        } else if (action == 'rename') {
                                          _promptRenameCollection(context, col);
                                        } else if (action == 'delete') {
                                          _confirmDeleteCollection(
                                            context,
                                            col,
                                          );
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'import',
                                          child: Row(
                                            children: [
                                              Icon(Icons.upload_file, size: 16),
                                              SizedBox(width: 8),
                                              Text('Import PDF Paper'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'rename',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit_outlined, size: 16),
                                              SizedBox(width: 8),
                                              Text('Rename'),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.delete_outline,
                                                size: 16,
                                                color: colorScheme.error,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Delete Collection',
                                                style: TextStyle(
                                                  color: colorScheme.error,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (isExpanded && isSelected) ...[
                            Consumer(
                              builder: (context, ref, child) {
                                final papers = ref.watch(papersProvider);
                                if (papers.isEmpty) {
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      left: 36,
                                      top: 4,
                                      bottom: 6,
                                    ),
                                    child: Text(
                                      'No papers yet',
                                      style: textTheme.labelSmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                  );
                                }
                                return Column(
                                  children: papers.map((paper) {
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        left: 32,
                                        top: 3,
                                        bottom: 3,
                                        right: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            paper.status.name == 'ready'
                                                ? Icons.description_outlined
                                                : paper.status.name == 'processing'
                                                ? Icons.sync
                                                : Icons.error_outline,
                                            size: 14,
                                            color: paper.status.name == 'ready'
                                                ? colorScheme.onSurfaceVariant
                                                : paper.status.name == 'processing'
                                                ? colorScheme.primary
                                                : colorScheme.error,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              paper.title,
                                              style: textTheme.bodySmall?.copyWith(
                                                color: colorScheme.onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        ],
                      );
                    }),

                  const SizedBox(height: 16),

                  // Recents Section Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
                    child: Text(
                      'RECENTS',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),

                  if (chats.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        'No recent chats',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    )
                  else
                    ...chats.map((chat) {
                      final isSelected = currentChat?.id == chat.id;

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.secondaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () async {
                            await ref
                                .read(chatControllerProvider.notifier)
                                .stop();
                            if (!mounted) return;
                            ref.read(activeCitationProvider.notifier).state =
                                null;
                            ref.read(currentChatProvider.notifier).state = chat;
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline,
                                  size: 15,
                                  color: isSelected
                                      ? colorScheme.onSecondaryContainer
                                      : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    chat.title,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: isSelected
                                          ? colorScheme.onSecondaryContainer
                                          : colorScheme.onSurface,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isSelected)
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      size: 16,
                                      color: colorScheme.onSecondaryContainer,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Delete chat',
                                    onPressed: () async {
                                      await ref
                                          .read(chatControllerProvider.notifier)
                                          .stop();
                                      if (!mounted) return;
                                      await ref
                                          .read(chatsProvider.notifier)
                                          .deleteChat(chat.id);
                                      if (!mounted) return;
                                      if (currentChat?.id == chat.id) {
                                        ref
                                                .read(
                                                  currentChatProvider.notifier,
                                                )
                                                .state =
                                            null;
                                      }
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),

            // Material 3 Tonal Footer
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      'P',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => const SettingsDialog(),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Local Workspace',
                            style: textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: apiKey.isNotEmpty
                                      ? AppColors.success
                                      : AppColors.warning,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  apiKey.isNotEmpty
                                      ? 'OpenRouter Ready'
                                      : 'Key Required',
                                  style: textTheme.labelSmall?.copyWith(
                                    fontSize: 10.5,
                                    color: apiKey.isNotEmpty
                                        ? AppColors.success
                                        : AppColors.warning,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      size: 17,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: isDark ? 'Light mode' : 'Dark mode',
                    onPressed: _toggleTheme,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _promptCreateCollection(BuildContext context) {
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create New Collection'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. GraphRAG, Transformer-Papers',
            labelText: 'Collection Name',
          ),
          onSubmitted: (_) {
            _handleCreate(ctx, controller.text);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _handleCreate(ctx, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _handleCreate(BuildContext ctx, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    Navigator.of(ctx).pop();
    await ref.read(chatControllerProvider.notifier).stop();
    if (!mounted) return;
    final newCol = await ref
        .read(collectionsProvider.notifier)
        .createCollection(trimmed);
    if (!mounted) return;
    ref.read(currentChatProvider.notifier).state = null;
    ref.read(activeCitationProvider.notifier).state = null;
    ref.read(currentCollectionProvider.notifier).state = newCol;
  }

  void _promptRenameCollection(BuildContext context, Collection col) {
    final controller = TextEditingController(text: col.name);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Collection'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'New collection name',
            labelText: 'Name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                ref
                    .read(collectionsProvider.notifier)
                    .renameCollection(col.id, newName);
                if (ref.read(currentCollectionProvider)?.id == col.id) {
                  ref.read(currentCollectionProvider.notifier).state = col
                      .copyWith(name: newName);
                }
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCollection(BuildContext context, Collection col) {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${col.name}"?'),
        content: const Text(
          'This will delete the collection, all imported PDFs, vector embeddings, and associated chat history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(chatControllerProvider.notifier).stop();
              if (!mounted) return;
              await ref
                  .read(collectionsProvider.notifier)
                  .deleteCollection(col.id);
              if (!mounted) return;
              ref.invalidate(paperRepositoryProvider(col.id));
              if (ref.read(currentCollectionProvider)?.id == col.id) {
                ref.read(currentCollectionProvider.notifier).state = null;
                ref.read(currentChatProvider.notifier).state = null;
                ref.read(activeCitationProvider.notifier).state = null;
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
