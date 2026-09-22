import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lab_05_rust/paper_native.dart';

import 'package:lab_05/app/app.dart';
import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/services/local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeNative();
  final storage = await LocalStorage.createDefault();
  final settings = await storage.loadSettings();
  final collections = await storage.listCollections();
  // No collection is auto-created here: an empty list means the user has
  // not made a project yet, and the UI shows its own empty state for that.
  final initialCollection = collections.firstOrNull;

  runApp(
    ProviderScope(
      overrides: [
        storageStateProvider.overrideWith((ref) {
          ref.onDispose(storage.dispose);
          return storage;
        }),
        settingsProvider.overrideWith(
          (ref) => SettingsNotifier(ref.watch(localStorageProvider), settings),
        ),
        currentCollectionProvider.overrideWith((ref) => initialCollection),
      ],
      child: const PaperChatApp(),
    ),
  );
}
