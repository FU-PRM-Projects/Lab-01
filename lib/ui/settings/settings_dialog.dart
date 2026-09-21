import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/app_settings.dart';
import 'package:lab_05/data/services/local_storage.dart';
import 'package:lab_05/ui/core/theme.dart';

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  late TextEditingController _urlController;
  late TextEditingController _apiKeyController;
  late String _selectedModel;
  late String _selectedTranscriptionModel;
  late String _selectedIndexingModel;
  late String _selectedTheme;
  String? _defaultDirPath;
  bool _obscureKey = true;

  static const List<Map<String, String>> _availableChatModels = [
    {
      'id': 'deepseek/deepseek-v4.1-flash',
      'name': 'DeepSeek V4.1 Flash',
      'badge': 'Multimodal',
    },
    {
      'id': 'minimax/minimax-m3',
      'name': 'MiMo M3 (MiniMax M3)',
      'badge': 'Multimodal',
    },
  ];

  /// Transcribes rendered pages, so every entry must accept image input.
  static const List<Map<String, String>> _availableTranscriptionModels = [
    {
      'id': 'qwen/qwen3-vl-235b-a22b-instruct',
      'name': 'Qwen3 VL 235B A22B Instruct',
      'badge': 'Vision',
    },
    {
      'id': 'deepseek/deepseek-v4.1-flash',
      'name': 'DeepSeek V4.1 Flash',
      'badge': 'Vision',
    },
    {
      'id': 'minimax/minimax-m3',
      'name': 'MiMo M3 (MiniMax M3)',
      'badge': 'Vision',
    },
  ];

  /// Reads the assembled transcript. Text-only models are fine here, and a
  /// long context matters more than vision.
  static const List<Map<String, String>> _availableIndexingModels = [
    {
      'id': 'qwen/qwen3-235b-a22b-2507',
      'name': 'Qwen3 235B A22B Instruct 2507',
      'badge': '262K ctx',
    },
    {
      'id': 'deepseek/deepseek-v4.1-flash',
      'name': 'DeepSeek V4.1 Flash',
      'badge': 'Multimodal',
    },
    {
      'id': 'minimax/minimax-m3',
      'name': 'MiMo M3 (MiniMax M3)',
      'badge': 'Multimodal',
    },
  ];

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _apiKeyController = TextEditingController(text: settings.openRouterApiKey);
    _urlController = TextEditingController(text: settings.openRouterBaseUrl);
    _selectedTheme = settings.theme;
    _selectedModel = _pick(_availableChatModels, settings.chatModel);
    _selectedTranscriptionModel = _pick(
      _availableTranscriptionModels,
      settings.transcriptionModel,
    );
    _selectedIndexingModel = _pick(
      _availableIndexingModels,
      settings.indexingModel,
    );
    _checkDefaultDir();
  }

  /// Keeps a configured model if the dialog offers it, otherwise falls back
  /// to the first entry rather than showing an empty dropdown.
  static String _pick(List<Map<String, String>> catalogue, String configured) {
    return catalogue.any((model) => model['id'] == configured)
        ? configured
        : catalogue.first['id']!;
  }

  Future<void> _checkDefaultDir() async {
    try {
      final defaultDir = await LocalStorage.getDefaultDataDirectory();
      if (mounted) {
        setState(() {
          _defaultDirPath = defaultDir.path;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _applyTheme(String theme) async {
    final previousTheme = ref.read(settingsProvider).theme;
    setState(() => _selectedTheme = theme);

    try {
      final currentSettings = ref.read(settingsProvider);
      await ref
          .read(settingsProvider.notifier)
          .update(currentSettings.copyWith(theme: theme));
    } catch (error) {
      if (!mounted) return;
      setState(() => _selectedTheme = previousTheme);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not change appearance: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;
    final storage = ref.watch(localStorageProvider);
    final settings = ref.watch(settingsProvider);

    return Dialog(
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The settings scroll; the actions below stay pinned so Save is
            // reachable however many pickers this dialog grows.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.tune,
                            color: colorScheme.onPrimaryContainer,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Application Settings',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(color: colorScheme.outlineVariant),
                    const SizedBox(height: 16),

                    // Appearance Theme Mode Selector (Material 3 SegmentedButton)
                    Text(
                      'Appearance',
                      style: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'dark',
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode_outlined, size: 16),
                        ),
                        ButtonSegment<String>(
                          value: 'light',
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode_outlined, size: 16),
                        ),
                        ButtonSegment<String>(
                          value: 'system',
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto_outlined, size: 16),
                        ),
                      ],
                      selected: {_selectedTheme},
                      onSelectionChanged: (Set<String> newSelection) {
                        _applyTheme(newSelection.first);
                      },
                    ),

                    const SizedBox(height: 20),

                    // OpenRouter Base URL
                    Row(
                      children: [
                        Text(
                          'OpenRouter Base URL',
                          style: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            _urlController.text =
                                AppSettings.defaultOpenRouterBaseUrl;
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Reset default'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        hintText: AppSettings.defaultOpenRouterBaseUrl,
                        helperText:
                            'Standard endpoint: https://openrouter.ai/api/v1',
                        helperStyle: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // OpenRouter API Key
                    Text(
                      'OpenRouter API Key',
                      style: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _apiKeyController,
                      obscureText: _obscureKey,
                      decoration: InputDecoration(
                        hintText: 'sk-or-v1-...',
                        helperText: 'Saved securely locally in settings.json. Never uploaded.',
                        helperStyle: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureKey
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureKey = !_obscureKey;
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    _modelPicker(
                      context,
                      label: 'Default Chat Model',
                      hint: 'Used by the research agent when answering questions.',
                      catalogue: _availableChatModels,
                      value: _selectedModel,
                      onChanged: (val) => setState(() => _selectedModel = val),
                    ),

                    const SizedBox(height: 18),

                    _modelPicker(
                      context,
                      label: 'PDF Page Transcription Model',
                      hint:
                          'Reads each rendered page image during import, so it must '
                          'accept image input.',
                      catalogue: _availableTranscriptionModels,
                      value: _selectedTranscriptionModel,
                      onChanged: (val) =>
                          setState(() => _selectedTranscriptionModel = val),
                    ),

                    const SizedBox(height: 18),

                    _modelPicker(
                      context,
                      label: 'Document Structure Model',
                      hint:
                          'Reads the assembled transcript and reports the outline '
                          'and bibliography. Text-only is fine; long context helps.',
                      catalogue: _availableIndexingModels,
                      value: _selectedIndexingModel,
                      onChanged: (val) =>
                          setState(() => _selectedIndexingModel = val),
                    ),

                    const SizedBox(height: 18),

                    // Local Storage Root Path
                    Row(
                      children: [
                        Text(
                          'Local Data Directory',
                          style: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        if (_defaultDirPath != null &&
                            p.normalize(storage.rootDir.path) !=
                                p.normalize(_defaultDirPath!))
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            icon: const Icon(Icons.restore_outlined, size: 14),
                            label: const Text(
                              'Reset to Default',
                              style: TextStyle(fontSize: 12),
                            ),
                            onPressed: () async {
                              try {
                                await ref
                                    .read(dataDirectoryControllerProvider)
                                    .resetToDefault();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Reset to default data directory',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Failed to reset directory: $e',
                                      ),
                                      backgroundColor: colorScheme.error,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              storage.rootDir.path,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                fontFamily: 'Consolas',
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.folder_open_outlined,
                              size: 18,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            tooltip: 'Change directory',
                            visualDensity: VisualDensity.compact,
                            onPressed: () async {
                              final selectedPath =
                                  await FilePicker.getDirectoryPath(
                                    dialogTitle: 'Select Local Data Directory',
                                    initialDirectory: storage.rootDir.path,
                                  );
                              if (selectedPath != null &&
                                  selectedPath.isNotEmpty) {
                                try {
                                  await ref
                                      .read(dataDirectoryControllerProvider)
                                      .changeDirectory(Directory(selectedPath));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Data directory updated: $selectedPath',
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Failed to change directory: $e',
                                        ),
                                        backgroundColor: colorScheme.error,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.copy_outlined,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            tooltip: 'Copy path',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: storage.rootDir.path),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Path copied to clipboard',
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Collections, documents, and chat histories will be stored in this directory.',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () async {
                    final key = _apiKeyController.text.trim();
                    var url = _urlController.text.trim();
                    if (url.isEmpty) {
                      url = AppSettings.defaultOpenRouterBaseUrl;
                    }

                    final newSettings = settings.copyWith(
                      theme: _selectedTheme,
                      openRouterBaseUrl: url,
                      openRouterApiKey: key,
                      chatModel: _selectedModel,
                      transcriptionModel: _selectedTranscriptionModel,
                      indexingModel: _selectedIndexingModel,
                    );
                    try {
                      await ref
                          .read(settingsProvider.notifier)
                          .update(newSettings);
                      if (context.mounted) Navigator.of(context).pop();
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Could not save settings: $error'),
                            backgroundColor: colorScheme.error,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Save Settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One labelled model dropdown. The three pickers differ only in their
  /// catalogue and hint, so the markup lives here once.
  Widget _modelPicker(
    BuildContext context, {
    required String label,
    required String hint,
    required List<Map<String, String>> catalogue,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _pick(catalogue, value),
              isExpanded: true,
              dropdownColor: colorScheme.surfaceContainerHigh,
              items: catalogue.map((model) {
                return DropdownMenuItem<String>(
                  value: model['id']!,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          model['name']!,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
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
                          model['badge'] ?? '',
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) onChanged(val);
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
