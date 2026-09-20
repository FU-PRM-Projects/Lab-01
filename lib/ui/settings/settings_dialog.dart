import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/app_settings.dart';
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
  late String _selectedTheme;
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

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _apiKeyController = TextEditingController(text: settings.openRouterApiKey);
    _urlController = TextEditingController(text: settings.openRouterBaseUrl);
    _selectedTheme = settings.theme;
    final modelIds = _availableChatModels.map((m) => m['id']!).toList();
    _selectedModel = modelIds.contains(settings.chatModel)
        ? settings.chatModel
        : modelIds.first;
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
                  helperText: 'Standard endpoint: https://openrouter.ai/api/v1',
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
                      _obscureKey ? Icons.visibility_off : Icons.visibility,
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

              // Chat Model Selection
              Text(
                'Default Chat Model',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value:
                        _availableChatModels.any(
                          (m) => m['id'] == _selectedModel,
                        )
                        ? _selectedModel
                        : _availableChatModels.first['id']!,
                    isExpanded: true,
                    dropdownColor: colorScheme.surfaceContainerHigh,
                    items: _availableChatModels.map((model) {
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
                                'Multimodal',
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
                      if (val != null) {
                        setState(() {
                          _selectedModel = val;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Multimodal models (DeepSeek 4.1 Flash & MiMo M3) configured for rich reasoning.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),

              const SizedBox(height: 18),

              // Local Storage Root Path
              Text(
                'Local Data Directory',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
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
                            content: const Text('Path copied to clipboard'),
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
      ),
    );
  }
}
