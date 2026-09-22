import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/app_settings.dart';
import 'package:lab_05/data/models/chat.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/services/local_storage.dart';
import 'package:lab_05/ui/artifacts/artifact_panel.dart';
import 'package:lab_05/ui/collections/sidebar.dart';

void main() {
  testWidgets(
    'Sidebar displays per-project chat sections and does not show Recents',
    (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('ui_feature_test1');
      addTearDown(() {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final storage = LocalStorage(rootDir: tempDir);
      final col1 = Collection(
        id: 'col_alpha',
        name: 'Alpha Project',
        createdAt: DateTime.now().toUtc(),
        embeddingProfile: const EmbeddingProfile(id: 'p1'),
      );
      final col2 = Collection(
        id: 'col_beta',
        name: 'Beta Project',
        createdAt: DateTime.now().toUtc(),
        embeddingProfile: const EmbeddingProfile(id: 'p2'),
      );

      final chat1 = Chat(
        id: 'chat_alpha_1',
        collectionId: col1.id,
        title: 'Alpha Discussion',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        messages: const [],
      );
      final chat2 = Chat(
        id: 'chat_beta_1',
        collectionId: col2.id,
        title: 'Beta Discussion',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        messages: const [],
      );

      await tester.runAsync(() async {
        await storage.saveCollection(col1);
        await storage.saveCollection(col2);
        await storage.saveChat(col1.id, chat1);
        await storage.saveChat(col2.id, chat2);
      });

      tester.view.physicalSize = const Size(1280, 800);
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
              settingsProvider.overrideWith(
                (ref) => SettingsNotifier(storage, const AppSettings()),
              ),
              currentCollectionProvider.overrideWith((ref) => col1),
              projectChatsProvider(
                col1.id,
              ).overrideWith((ref) => ChatsNotifier(storage, col1.id, [chat1])),
              projectChatsProvider(
                col2.id,
              ).overrideWith((ref) => ChatsNotifier(storage, col2.id, [chat2])),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: AppSidebar(onNewChat: () {}, onImportPaper: () {}),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // Verify there is NO "Recents" text anywhere in sidebar
      expect(find.text('Recents'), findsNothing);
      expect(find.text('No recent chats'), findsNothing);

      // Verify both projects are present
      expect(find.text('Alpha Project'), findsOneWidget);
      expect(find.text('Beta Project'), findsOneWidget);

      // Alpha Project is currentCollectionProvider so it is expanded
      // Its chat "Alpha Discussion" should be visible
      expect(find.text('Alpha Discussion'), findsOneWidget);

      // Switch to Beta Project
      await tester.runAsync(() async {
        await tester.tap(find.text('Beta Project'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // Now Beta Project's chat should be visible
      expect(find.text('Beta Discussion'), findsOneWidget);

      // Still no "Recents" section
      expect(find.text('Recents'), findsNothing);
    },
  );

  testWidgets('ArtifactPanel shows Delete PDF button and confirmation dialog', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('ui_feature_test2');
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final storage = LocalStorage(rootDir: tempDir);
    final col = Collection(
      id: 'col_pdf_test',
      name: 'PDF Test Project',
      createdAt: DateTime.now().toUtc(),
      embeddingProfile: const EmbeddingProfile(id: 'p1'),
    );

    final paper = PaperDocument(
      schemaVersion: 1,
      id: 'doc_101',
      fileName: 'attention_is_all_you_need.pdf',
      title: 'Attention Is All You Need',
      sha256: 'sha256_hash_123',
      pageCount: 15,
      status: DocumentStatus.ready,
      createdAt: DateTime.now().toUtc(),
      embeddingProfileId: 'p1',
      chunks: const [],
    );

    await tester.runAsync(() async {
      await storage.saveCollection(col);
      await storage.savePaper(col.id, paper);
    });

    tester.view.physicalSize = const Size(1280, 800);
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
            currentCollectionProvider.overrideWith((ref) => col),
          ],
          child: MaterialApp(
            home: Scaffold(body: ArtifactPanel(onImportPaper: () {})),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    // Verify paper card is shown
    expect(find.text('Attention Is All You Need'), findsOneWidget);

    // Verify Delete PDF button is present on paper card
    final deleteButtons = find.byTooltip('Delete PDF');
    expect(deleteButtons, findsOneWidget);

    // Tap Delete PDF button
    await tester.tap(deleteButtons.first);
    await tester.pump();

    // Verify confirmation dialog appears
    expect(find.text('Delete "Attention Is All You Need"?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    // Tap Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    // Dialog dismissed and paper still exists
    expect(find.text('Delete "Attention Is All You Need"?'), findsNothing);
    expect(find.text('Attention Is All You Need'), findsOneWidget);
  });
}
