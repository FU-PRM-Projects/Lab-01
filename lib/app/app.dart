import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/ui/core/theme.dart';
import 'package:lab_05/ui/shell/app_shell.dart';

class PaperChatApp extends ConsumerWidget {
  const PaperChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSetting = ref.watch(settingsProvider.select((s) => s.theme));

    final ThemeMode themeMode;
    if (themeSetting == 'light') {
      themeMode = ThemeMode.light;
    } else if (themeSetting == 'system') {
      themeMode = ThemeMode.system;
    } else {
      themeMode = ThemeMode.dark;
    }

    return MaterialApp(
      title: 'PaperChat',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      home: const AppShell(),
    );
  }
}
