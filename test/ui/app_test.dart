import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/app/app.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/services/local_storage.dart';
import 'package:lab_05/app/providers.dart';

void main() {
  testWidgets('PaperChatApp smoke test', (WidgetTester tester) async {
    final tempDir = Directory.systemTemp.createTempSync('paperchat_test');
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final storage = LocalStorage(rootDir: tempDir);
    final initialCollection = Collection(
      id: 'col_test',
      name: 'lab_05',
      createdAt: DateTime.now().toUtc(),
      embeddingProfile: const EmbeddingProfile(id: 'profile_test'),
    );
    await tester.runAsync(() async {
      await storage.saveCollection(initialCollection);
    });

    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageProvider.overrideWithValue(storage),
            currentCollectionProvider.overrideWith((ref) => initialCollection),
          ],
          child: const PaperChatApp(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // Verify app brand and empty state headline
    expect(find.text('PaperChat'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('New chat'), findsOneWidget);
    expect(find.text('Summarize main methodology and novelty'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText().contains('What should we explore in lab_05?'),
      ),
      findsOneWidget,
    );

    // Verify Settings button is present in UI
    final settingsButtons = find.byTooltip('Settings');
    expect(settingsButtons, findsWidgets);

    // Tap Settings button and verify SettingsDialog opens with URL and API key inputs
    await tester.tap(settingsButtons.first);
    await tester.pumpAndSettle();

    expect(find.text('Application Settings'), findsOneWidget);
    expect(find.text('OpenRouter Base URL'), findsOneWidget);
    expect(find.text('OpenRouter API Key'), findsOneWidget);
    expect(find.text('Save Settings'), findsOneWidget);

    // Appearance changes apply immediately from the segmented control.
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    final scaffoldLight = tester.firstWidget<Scaffold>(find.byType(Scaffold));
    expect(scaffoldLight.backgroundColor, equals(const Color(0xFFFFFFFF)));

    // Tap Cancel to close dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Application Settings'), findsNothing);
  });
}
