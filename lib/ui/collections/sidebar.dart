import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/models/paper.dart';
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
  String? _hoveredCollectionId;
  String? _hoveredChatId;
  String? _hoveredPinnedCollectionId;
  bool _isFooterHovered = false;

  void _toggleTheme() {
    final settings = ref.read(settingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nextTheme = isDark ? 'light' : 'dark';
    ref
        .read(settingsProvider.notifier)
        .update(settings.copyWith(theme: nextTheme));
  }

  Future<void> _selectCollection(Collection collection) async {
    await ref.read(chatControllerProvider.notifier).stop();
    if (!mounted) return;
    ref.read(activeCitationProvider.notifier).state = null;
    ref.read(currentCollectionProvider.notifier).state = collection;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update pinned projects: $error')),
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
    final chats = ref.watch(chatsProvider);
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
                    ...pinnedCollections.map((collection) {
                      final isSelected = currentCol?.id == collection.id;
                      final isHovered =
                          _hoveredPinnedCollectionId == collection.id;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(vertical: 1),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.secondaryContainer
                              : isHovered
                              ? colorScheme.onSurface.withValues(
                                  alpha: isDark ? 0.065 : 0.035,
                                )
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(7),
                          hoverColor: Colors.transparent,
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          onHover: (hovering) {
                            setState(() {
                              _hoveredPinnedCollectionId = hovering
                                  ? collection.id
                                  : null;
                            });
                          },
                          onTap: () => _selectCollection(collection),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  size: 18,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    collection.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontSize: 14,
                                      color: colorScheme.onSurface,
                                      fontWeight: isSelected
                                          ? FontWeight.w500
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      _togglePinnedCollection(collection.id),
                                  icon: const Icon(
                                    Icons.push_pin_outlined,
                                    size: 16,
                                  ),
                                  tooltip: 'Unpin project',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 32,
                                    height: 32,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
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
                    ...projectCollections.map((col) {
                      final isSelected = currentCol?.id == col.id;
                      final isExpanded =
                          _expandedCollections.contains(col.id) || isSelected;

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
                              borderRadius: BorderRadius.circular(
                                isSelected ? 9 : 7,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              hoverColor: Colors.transparent,
                              splashColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                              onHover: (hovering) {
                                setState(() {
                                  _hoveredCollectionId = hovering
                                      ? col.id
                                      : null;
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 2,
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
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        col.name,
                                        style: textTheme.bodyMedium?.copyWith(
                                          fontSize: 14,
                                          color: isSelected
                                              ? colorScheme.onSecondaryContainer
                                              : colorScheme.onSurface,
                                          fontWeight: isSelected
                                              ? FontWeight.w500
                                              : FontWeight.w400,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: PopupMenuButton<String>(
                                        padding: EdgeInsets.zero,
                                        splashRadius: 17,
                                        position: PopupMenuPosition.under,
                                        offset: const Offset(0, 2),
                                        icon: Icon(
                                          Icons.more_vert,
                                          size: 17,
                                          color: isSelected
                                              ? colorScheme.onSecondaryContainer
                                              : colorScheme.onSurfaceVariant,
                                        ),
                                        tooltip: 'Collection options',
                                        color: colorScheme.surfaceContainerHigh,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          side: BorderSide(
                                            color: colorScheme.outlineVariant,
                                          ),
                                        ),
                                        onSelected: (action) async {
                                          if (action == 'pin') {
                                            await _togglePinnedCollection(
                                              col.id,
                                            );
                                          } else if (action == 'import') {
                                            await ref
                                                .read(
                                                  chatControllerProvider
                                                      .notifier,
                                                )
                                                .stop();
                                            if (!mounted) return;
                                            ref
                                                    .read(
                                                      currentChatProvider
                                                          .notifier,
                                                    )
                                                    .state =
                                                null;
                                            ref
                                                    .read(
                                                      activeCitationProvider
                                                          .notifier,
                                                    )
                                                    .state =
                                                null;
                                            ref
                                                    .read(
                                                      currentCollectionProvider
                                                          .notifier,
                                                    )
                                                    .state =
                                                col;
                                            widget.onImportPaper();
                                          } else if (action == 'rename') {
                                            _promptRenameCollection(
                                              context,
                                              col,
                                            );
                                          } else if (action == 'delete') {
                                            _confirmDeleteCollection(
                                              context,
                                              col,
                                            );
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'pin',
                                            height: 40,
                                            child: Row(
                                              children: [
                                                Icon(
                                                  pinnedIds.contains(col.id)
                                                      ? Icons.push_pin
                                                      : Icons.push_pin_outlined,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  pinnedIds.contains(col.id)
                                                      ? 'Unpin Project'
                                                      : 'Pin Project',
                                                ),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'import',
                                            height: 40,
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.upload_file,
                                                  size: 16,
                                                ),
                                                SizedBox(width: 8),
                                                Text('Import PDF Paper'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'rename',
                                            height: 40,
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.edit_outlined,
                                                  size: 16,
                                                ),
                                                SizedBox(width: 8),
                                                Text('Rename'),
                                              ],
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            height: 40,
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
                                      left: 34,
                                      top: 2,
                                      bottom: 4,
                                    ),
                                    child: Text(
                                      'No papers yet',
                                      style: textTheme.labelSmall?.copyWith(
                                        fontSize: 12.5,
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
                                      child: Tooltip(
                                        message: _paperStatusMessage(paper),
                                        child: Row(
                                          children: [
                                            Icon(
                                              _paperStatusIcon(paper.status),
                                              size: 16,
                                              color: _paperStatusColor(
                                                paper.status,
                                                colorScheme,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                paper.title,
                                                style: textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                      fontSize: 13,
                                                    ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (paper.status ==
                                                DocumentStatus.needsReindex)
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 14,
                                                ),
                                                tooltip: 'Forget this paper',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                constraints:
                                                    const BoxConstraints(),
                                                padding: EdgeInsets.zero,
                                                onPressed: () => ref
                                                    .read(
                                                      papersProvider.notifier,
                                                    )
                                                    .removePaper(paper.id),
                                              ),
                                          ],
                                        ),
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
                      'Recents',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.25,
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
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    )
                  else
                    ...chats.map((chat) {
                      final isSelected = currentChat?.id == chat.id;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.secondaryContainer
                              : _hoveredChatId == chat.id
                              ? colorScheme.onSurface.withValues(
                                  alpha: isDark ? 0.065 : 0.035,
                                )
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
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
                            ref.read(currentChatProvider.notifier).state = chat;
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline,
                                  size: 17,
                                  color: isSelected
                                      ? colorScheme.onSecondaryContainer
                                      : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    chat.title,
                                    style: textTheme.bodySmall?.copyWith(
                                      fontSize: 14,
                                      color: isSelected
                                          ? colorScheme.onSecondaryContainer
                                          : colorScheme.onSurface,
                                      fontWeight: isSelected
                                          ? FontWeight.w500
                                          : FontWeight.w400,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isSelected)
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      size: 18,
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
              // Release the LanceDB handles before removing the directory:
              // Windows refuses a recursive delete while files are still open,
              // and Riverpod's disposal is not synchronous.
              ref.read(paperRepositoryProvider(col.id)).close();
              ref.invalidate(paperRepositoryProvider(col.id));
              await ref
                  .read(collectionsProvider.notifier)
                  .deleteCollection(col.id);
              if (!mounted) return;
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

IconData _paperStatusIcon(DocumentStatus status) {
  switch (status) {
    case DocumentStatus.ready:
      return Icons.description_outlined;
    case DocumentStatus.processing:
      return Icons.sync;
    case DocumentStatus.needsReindex:
      return Icons.refresh;
    case DocumentStatus.failed:
    case DocumentStatus.deleting:
      return Icons.error_outline;
  }
}

Color _paperStatusColor(DocumentStatus status, ColorScheme colorScheme) {
  switch (status) {
    case DocumentStatus.ready:
      return colorScheme.onSurfaceVariant;
    case DocumentStatus.processing:
      return colorScheme.primary;
    case DocumentStatus.needsReindex:
      return colorScheme.tertiary;
    case DocumentStatus.failed:
    case DocumentStatus.deleting:
      return colorScheme.error;
  }
}

String _paperStatusMessage(PaperDocument paper) {
  switch (paper.status) {
    case DocumentStatus.ready:
      return paper.title;
    case DocumentStatus.processing:
      return 'Importing…';
    case DocumentStatus.needsReindex:
      return paper.error ??
          'Re-import this PDF to make it searchable again.';
    case DocumentStatus.failed:
      return paper.error ?? 'Import failed.';
    case DocumentStatus.deleting:
      return 'Deleting…';
  }
}
