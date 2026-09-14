import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/services/embedding_client.dart';

class ImportController extends StateNotifier<(String, double)?> {
  ImportController(this._ref) : super(null);

  final Ref _ref;

  Future<void> import(Collection collection, File file) async {
    if (state != null) return;
    state = ('Starting import...', 0.05);
    final settings = _ref.read(settingsProvider);
    final embeddings = EmbeddingClient(
      apiKey: settings.openRouterApiKey,
      baseUrl: settings.openRouterBaseUrl,
      model: collection.embeddingProfile.model,
      dimensions: collection.embeddingProfile.dimensions,
    );
    try {
      await _ref
          .read(paperRepositoryProvider(collection.id))
          .importPaper(
            sourcePdfFile: file,
            embeddings: embeddings,
            onProgress: (stage, progress) {
              if (mounted) state = (stage, progress);
            },
          );
    } finally {
      embeddings.close();
      if (mounted) {
        await _ref.read(papersProvider.notifier).refresh();
        if (mounted) state = null;
      }
    }
  }
}

final importControllerProvider =
    StateNotifierProvider<ImportController, (String, double)?>(
      (ref) => ImportController(ref),
    );
