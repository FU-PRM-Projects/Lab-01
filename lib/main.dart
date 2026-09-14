import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lab_05_rust/paper_native.dart';

import 'package:lab_05/app/app.dart';
import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/services/local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeNative();
  final storage = await LocalStorage.createDefault();
  final settings = await storage.loadSettings();
  final collections = await storage.listCollections();
  final initialCollection =
      collections.firstOrNull ??
      Collection(
        id: 'col_lab_05',
        name: 'lab_05',
        createdAt: DateTime.now().toUtc(),
        embeddingProfile: EmbeddingProfile(
          id: 'profile_gemini_2',
          model: settings.defaultEmbeddingModel,
          dimensions: settings.defaultEmbeddingDimensions,
        ),
      );
  if (collections.isEmpty) await storage.saveCollection(initialCollection);

  runApp(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWith((ref) {
          ref.onDispose(storage.dispose);
          return storage;
        }),
        settingsProvider.overrideWith(
          (ref) => SettingsNotifier(storage, settings),
        ),
        currentCollectionProvider.overrideWith((ref) => initialCollection),
      ],
      child: const PaperChatApp(),
    ),
  );
}
