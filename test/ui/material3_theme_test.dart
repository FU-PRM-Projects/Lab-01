import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/app/app.dart';
import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/app_settings.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/services/local_storage.dart';
import 'package:lab_05/ui/core/theme.dart';

void main() {
  testWidgets('Material 3 Dynamic Theme Switching Test', (
    WidgetTester tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('paperchat_m3_test');
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final storage = LocalStorage(rootDir: tempDir);
    final initialCollection = Collection(
      id: 'col_m3_test',
      name: 'M3 Research',
      createdAt: DateTime.now().toUtc(),
      embeddingProfile: const EmbeddingProfile(id: 'profile_test'),
    );
    await tester.runAsync(() async {
      await storage.saveCollection(initialCollection);
      await storage.saveSettings(const AppSettings(theme: 'dark'));
    });

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    late WidgetRef capturedRef;

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageProvider.overrideWithValue(storage),
            currentCollectionProvider.overrideWith((ref) => initialCollection),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              capturedRef = ref;
              return const PaperChatApp();
            },
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    // Verify Dark Theme is active initially
    final scaffoldDark = tester.firstWidget<Scaffold>(find.byType(Scaffold));
    expect(scaffoldDark.backgroundColor, equals(const Color(0xFF171717)));

    // Verify M3 Navigation elements
    expect(find.text('PaperChat'), findsOneWidget);
    expect(find.text('M3 Research'), findsWidgets);
    expect(find.text('New chat'), findsOneWidget);

    // Switch theme to Light Mode
    await tester.runAsync(() async {
      await capturedRef
          .read(settingsProvider.notifier)
          .update(const AppSettings(theme: 'light'));
    });
    await tester.pumpAndSettle();

    // Verify Light Theme is active
    final scaffoldLight = tester.firstWidget<Scaffold>(find.byType(Scaffold));
    expect(scaffoldLight.backgroundColor, equals(const Color(0xFFFFFFFF)));

    // Verify M3 Theme builders output valid ThemeData with useMaterial3 true
    final darkTheme = buildDarkTheme();
    final lightTheme = buildLightTheme();
    expect(darkTheme.useMaterial3, isTrue);
    expect(lightTheme.useMaterial3, isTrue);
    expect(darkTheme.brightness, equals(Brightness.dark));
    expect(lightTheme.brightness, equals(Brightness.light));
  });
}
