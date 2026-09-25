import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/chat.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/ui/artifacts/artifact_controller.dart';
import 'package:lab_05/ui/chat/chat_controller.dart';
import 'package:lab_05/ui/collections/import_controller.dart';
import 'package:lab_05/ui/core/snackbar.dart';
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
  String? _hoveredCollectionId;
  String? _hoveredChatId;
  bool _isFooterHovered = false;

  void _toggleTheme() => ref
      .read(settingsProvider.notifier)
      .toggleTheme(Theme.of(context).brightness);

  Future<void> _selectCollection(Collection collection) async {
    await ref.read(chatControllerProvider.notifier).stop();
    if (!mounted) return;
    ref.read(activeCitationProvider.notifier).state = null;
    ref.read(currentCollectionProvider.notifier).state = collection;
    ref.read(currentChatProvider.notifier).state = null;
  }

  Future<void> _startNewChatIn(Collection col) async {
    await ref.read(chatControllerProvider.notifier).stop();
    if (!mounted) return;
    ref.read(activeCitationProvider.notifier).state = null;
    if (ref.read(currentCollectionProvider)?.id != col.id) {
      ref.read(currentCollectionProvider.notifier).state = col;
    }
    ref.read(currentChatProvider.notifier).state = null;
  }

  Future<void> _togglePinnedCollection(String collectionId) async {
    final settings = ref.read(settingsProvider);
    final pinnedIds = settings.pinnedCollectionIds.toSet();
    if (!pinnedIds.add(collectionId)) pinnedIds.remove(collectionId);

    try {
      await ref
          .read(settingsProvider.notifier)
          .update(settings.copyWith(pinnedCollectionIds: pinnedIds.toList()));
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Could not update pinned projects: $error',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;
    final isDark = context.isDarkMode;

    final collections = ref.watch(collectionsProvider);
    final currentCol = ref.watch(currentCollectionProvider);
    final currentChat = ref.watch(currentChatProvider);
    final apiKey = ref.watch(apiKeyProvider);
    final settings = ref.watch(settingsProvider);
    final pinnedIds = settings.pinnedCollectionIds.toSet();
    final pinnedCollections = collections
        .where((collection) => pinnedIds.contains(collection.id))
        .toList(growable: false);
    final projectCollections = collections
        .where((collection) => !pinnedIds.contains(collection.id))
        .toList(growable: false);

    return AbsorbPointer(
      absorbing: ref.watch(importControllerProvider) != null,
      child: Container(
        width: 278,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          border: Border(
            right: BorderSide(color: colorScheme.outlineVariant, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Codex-style workspace header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          'PaperChat',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.25,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 19,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Primary workspace action
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: TextButton.icon(
                onPressed: widget.onNewChat,
                icon: const Icon(Icons.edit_square, size: 19),
                label: const Text('New chat'),
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 11,
                  ),
                  foregroundColor: colorScheme.onSurface,
                  alignment: Alignment.centerLeft,
                  textStyle: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w400,
                  ),
                  overlayColor: colorScheme.onSurface.withValues(alpha: 0.06),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Scrollable Collections & Recents
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
                    child: Row(
                      children: [
                        Text(
                          'Pinned',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.25,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 17,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                  if (pinnedCollections.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 5, 8, 8),
                      child: Text(
                        'Pin projects from the ••• menu',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.62,
                          ),
                          fontSize: 12.5,
                        ),
                      ),
                    )
                  else
                    ...pinnedCollections.map(
                      (collection) => _buildCollectionItem(
                        context: context,
                        col: collection,
                        isPinned: true,
                        currentCol: currentCol,
                        currentChat: currentChat,
                        pinnedIds: pinnedIds,
                        colorScheme: colorScheme,
                        textTheme: textTheme,
                        isDark: isDark,
                      ),
                    ),
                  const SizedBox(height: 8),

                  // Projects / Collections Section Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 4, 6),
                    child: Row(
                      children: [
                        Text(
                          'Projects',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.25,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            Icons.add,
                            size: 19,
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
                  if (projectCollections.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        collections.isEmpty
                            ? 'No projects yet'
                            : 'All projects are pinned',
                        style: textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    )
                  else
                    ...projectCollections.map(
                      (col) => _buildCollectionItem(
                        context: context,
                        col: col,
                        isPinned: false,
                        currentCol: currentCol,
                        currentChat: currentChat,
                        pinnedIds: pinnedIds,
                        colorScheme: colorScheme,
                        textTheme: textTheme,
                        isDark: isDark,
                      ),
                    ),
                ],
              ),
            ),

            // Local account and settings footer
            MouseRegion(
              onEnter: (_) => setState(() => _isFooterHovered = true),
              onExit: (_) => setState(() => _isFooterHovered = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _isFooterHovered
                      ? colorScheme.surfaceContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
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
                      child: Tooltip(
                        message: 'Settings',
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
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w500,
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
                                        fontSize: 11.5,
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
                    ),
                    IconButton(
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 140),
                        child: Icon(
                          isDark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          key: ValueKey(isDark),
                          size: 19,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                      tooltip: isDark ? 'Light mode' : 'Dark mode',
                      onPressed: _toggleTheme,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionItem({
    required BuildContext context,
    required Collection col,
    required bool isPinned,
    required Collection? currentCol,
    required Chat? currentChat,
    required Set<String> pinnedIds,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required bool isDark,
  }) {
    final isSelected = currentCol?.id == col.id;
    final isExpanded = _expandedCollections.contains(col.id) || isSelected;
    // A folder holds one paper, so "Import PDF Paper" is offered only while
    // this folder has none (or its only import failed).
    final canImportHere = !ref
        .watch(projectPapersProvider(col.id))
        .any((paper) => paper.occupiesFolder);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.secondaryContainer
                : _hoveredCollectionId == col.id
                ? colorScheme.onSurface.withValues(
                    alpha: isDark ? 0.065 : 0.035,
                  )
                : Colors.transparent,
            borderRadius: BorderRadius.circular(isSelected ? 9 : 7),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            onHover: (hovering) {
              setState(() {
                _hoveredCollectionId = hovering ? col.id : null;
              });
            },
            onTap: () async {
              await _selectCollection(col);
              if (!mounted) return;
              setState(() {
                if (_expandedCollections.contains(col.id)) {
                  _expandedCollections.remove(col.id);
                } else {
                  _expandedCollections.add(col.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                    color: isSelected
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded ? Icons.folder_open : Icons.folder_outlined,
                    size: 18,
                    color: isSelected
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      col.name,
                      style: textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        color: isSelected
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onSurface,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: IconButton(
                      icon: const Icon(Icons.add, size: 16),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 26,
                        height: 26,
                      ),
                      tooltip: 'New chat in ${col.name}',
                      color: isSelected
                          ? colorScheme.onSecondaryContainer
                          : colorScheme.onSurfaceVariant,
                      onPressed: () {
                        setState(() {
                          _expandedCollections.add(col.id);
                        });
                        _startNewChatIn(col);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      splashRadius: 16,
                      position: PopupMenuPosition.under,
                      offset: const Offset(0, 2),
                      icon: Icon(
                        Icons.more_vert,
                        size: 16,
                        color: isSelected
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                      tooltip: 'Options',
                      color: colorScheme.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: colorScheme.outlineVariant),
                      ),
                      onSelected: (action) async {
                        if (action == 'new_chat') {
                          setState(() {
                            _expandedCollections.add(col.id);
                          });
                          _startNewChatIn(col);
                        } else if (action == 'artifacts') {
                          if (currentCol?.id != col.id) {
                            await _selectCollection(col);
                            if (!mounted) return;
                          }
                          ref.read(activeCitationProvider.notifier).state =
                              null;
                          final scope = ref.read(artifactScopeProvider);
                          ref.read(artifactPanelProvider.notifier).open(scope);
                        } else if (action == 'pin') {
                          await _togglePinnedCollection(col.id);
                        } else if (action == 'import') {
                          await ref
                              .read(chatControllerProvider.notifier)
                              .stop();
                          if (!mounted) return;
                          ref.read(currentChatProvider.notifier).state = null;
                          ref.read(activeCitationProvider.notifier).state =
                              null;
                          ref.read(currentCollectionProvider.notifier).state =
                              col;
                          widget.onImportPaper();
                        } else if (action == 'rename') {
                          _promptRenameCollection(context, col);
                        } else if (action == 'delete') {
                          _confirmDeleteCollection(context, col);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'new_chat',
                          height: 38,
                          child: Row(
                            children: [
                              Icon(Icons.add_comment_outlined, size: 16),
                              SizedBox(width: 8),
                              Text('New Chat'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'artifacts',
                          height: 38,
                          child: Row(
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 16),
                              SizedBox(width: 8),
                              Text('View Artifacts'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'pin',
                          height: 38,
                          child: Row(
                            children: [
                              Icon(
                                isPinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(isPinned ? 'Unpin Project' : 'Pin Project'),
                            ],
                          ),
                        ),
                        if (canImportHere)
                          const PopupMenuItem(
                            value: 'import',
                            height: 38,
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
                          height: 38,
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
                          height: 38,
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
                                style: TextStyle(color: colorScheme.error),
                              ),
                            ],
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

        // Expanded content: Chats
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(
              left: 20,
              right: 4,
              top: 2,
              bottom: 4,
            ),
            child: Consumer(
              builder: (context, ref, _) {
                final chats = ref.watch(projectChatsProvider(col.id));

                if (chats.isEmpty) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _startNewChatIn(col),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.add_comment_outlined,
                            size: 13,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Start a chat',
                            style: textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: chats.map((chat) {
                    final isChatSelected =
                        isSelected && currentChat?.id == chat.id;

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      margin: const EdgeInsets.symmetric(vertical: 1),
                      decoration: BoxDecoration(
                        color: isChatSelected
                            ? colorScheme.secondaryContainer.withValues(
                                alpha: 0.8,
                              )
                            : _hoveredChatId == chat.id
                            ? colorScheme.onSurface.withValues(
                                alpha: isDark ? 0.06 : 0.03,
                              )
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        hoverColor: Colors.transparent,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        onHover: (hovering) {
                          setState(() {
                            _hoveredChatId = hovering ? chat.id : null;
                          });
                        },
                        onTap: () async {
                          await ref
                              .read(chatControllerProvider.notifier)
                              .stop();
                          if (!mounted) return;
                          ref.read(activeCitationProvider.notifier).state =
                              null;
                          if (currentCol?.id != col.id) {
                            ref.read(currentCollectionProvider.notifier).state =
                                col;
                          }
                          ref.read(currentChatProvider.notifier).state = chat;
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 14,
                                color: isChatSelected
                                    ? colorScheme.onSecondaryContainer
                                    : colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  chat.title,
                                  style: textTheme.bodySmall?.copyWith(
                                    fontSize: 12.5,
                                    color: isChatSelected
                                        ? colorScheme.onSecondaryContainer
                                        : colorScheme.onSurface,
                                    fontWeight: isChatSelected
                                        ? FontWeight.w500
                                        : FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isChatSelected || _hoveredChatId == chat.id)
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 15,
                                    color: isChatSelected
                                        ? colorScheme.onSecondaryContainer
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 22,
                                    height: 22,
                                  ),
                                  tooltip: 'Delete chat',
                                  onPressed: () async {
                                    await ref
                                        .read(chatControllerProvider.notifier)
                                        .stop();
                                    if (!mounted) return;
                                    await ref
                                        .read(
                                          projectChatsProvider(col.id).notifier,
                                        )
                                        .deleteChat(chat.id);
                                    if (!mounted) return;
                                    ref
                                        .read(artifactPanelProvider.notifier)
                                        .forget('chat:${chat.id}');
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
                  }).toList(),
                );
              },
            ),
          ),
      ],
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
    // No picker opens here: a new folder can stay empty until the user
    // chooses to import its paper from the empty state or the folder menu.
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
