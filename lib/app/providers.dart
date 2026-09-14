import 'package:uuid/uuid.dart';
import 'package:lab_05/data/models/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:lab_05/data/services/collection_index.dart';
import 'package:lab_05/data/repositories/paper_repository.dart';
import 'package:lab_05/data/models/chat.dart';
import 'package:lab_05/data/models/citation.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/services/local_storage.dart';

// Storage Provider
final localStorageProvider = Provider<LocalStorage>((ref) {
  throw UnimplementedError('Initialize localStorageProvider in main');
});

// Settings Provider
class SettingsNotifier extends StateNotifier<AppSettings> {
  final LocalStorage _storage;
  SettingsNotifier(this._storage, AppSettings initial) : super(initial);

  Future<void> update(AppSettings newSettings) async {
    await _storage.saveSettings(newSettings);
    state = newSettings;
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  final storage = ref.watch(localStorageProvider);
  return SettingsNotifier(storage, const AppSettings());
});

// API Key Provider
final apiKeyProvider = Provider<String>(
  (ref) => ref.watch(
    settingsProvider.select((settings) => settings.openRouterApiKey),
  ),
);

// Collections Notifier
class CollectionsNotifier extends StateNotifier<List<Collection>> {
  final LocalStorage _storage;
  CollectionsNotifier(this._storage) : super([]) {
    refresh();
  }

  Future<void> refresh() async {
    final list = await _storage.listCollections();
    if (mounted) state = List.unmodifiable(list);
  }

  Future<Collection> createCollection(String name) async {
    final id = 'col_${const Uuid().v4()}';
    final collection = Collection(
      id: id,
      name: name,
      createdAt: DateTime.now().toUtc(),
      embeddingProfile: const EmbeddingProfile(id: 'profile_default'),
    );
    await _storage.saveCollection(collection);
    await refresh();
    return collection;
  }

  Future<void> deleteCollection(String id) async {
    await _storage.deleteCollection(id);
    await refresh();
  }

  Future<void> renameCollection(String id, String newName) async {
    final col = await _storage.loadCollection(id);
    if (col != null) {
      await _storage.saveCollection(col.copyWith(name: newName));
      await refresh();
    }
  }
}

final collectionsProvider =
    StateNotifierProvider<CollectionsNotifier, List<Collection>>((ref) {
      final storage = ref.watch(localStorageProvider);
      return CollectionsNotifier(storage);
    });

// Current Collection Provider
final currentCollectionProvider = StateProvider<Collection?>((ref) => null);

// Each collection owns its native index; changing selection cannot reuse another index.
final paperRepositoryProvider = Provider.family<PaperRepository, String>((
  ref,
  id,
) {
  final repository = PaperRepository(
    storage: ref.watch(localStorageProvider),
    collectionId: id,
  );
  ref.onDispose(repository.close);
  return repository;
});

// Papers Notifier for the current collection
class PapersNotifier extends StateNotifier<List<PaperDocument>> {
  final LocalStorage _storage;
  final String? _collectionId;

  PapersNotifier(this._storage, this._collectionId) : super([]) {
    refresh();
  }

  Future<void> refresh() async {
    if (_collectionId == null) {
      state = [];
      return;
    }
    final papers = await _storage.listPapers(_collectionId);
    if (mounted) state = List.unmodifiable(papers);
  }

  Future<void> removePaper(
    String documentId,
    List<int> vectorIds,
    CollectionIndex index,
  ) async {
    if (_collectionId == null) return;
    await index.removeVectors(vectorIds);
    await index.save(_storage.indexVectorsPath(_collectionId));
    await _storage.deletePaper(_collectionId, documentId);
    await refresh();
  }
}

final papersProvider =
    StateNotifierProvider<PapersNotifier, List<PaperDocument>>((ref) {
      final storage = ref.watch(localStorageProvider);
      final currentCol = ref.watch(currentCollectionProvider);
      return PapersNotifier(storage, currentCol?.id);
    });

// Chats Notifier for current collection
class ChatsNotifier extends StateNotifier<List<Chat>> {
  final LocalStorage _storage;
  final String? _collectionId;

  ChatsNotifier(this._storage, this._collectionId) : super([]) {
    refresh();
  }

  Future<void> refresh() async {
    if (_collectionId == null) {
      state = [];
      return;
    }
    final chats = await _storage.listChats(_collectionId);
    if (mounted) state = List.unmodifiable(chats);
  }

  Future<Chat> createNewChat(String title) async {
    if (_collectionId == null) throw StateError('No collection selected');
    final chatId = 'chat_${const Uuid().v4()}';
    final chat = Chat(
      id: chatId,
      collectionId: _collectionId,
      title: title,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      messages: [],
    );
    await _storage.saveChat(_collectionId, chat);
    await refresh();
    return chat;
  }

  Future<void> deleteChat(String chatId) async {
    if (_collectionId == null) return;
    await _storage.deleteChat(_collectionId, chatId);
    await refresh();
  }
}

final chatsProvider = StateNotifierProvider<ChatsNotifier, List<Chat>>((ref) {
  final storage = ref.watch(localStorageProvider);
  final currentCol = ref.watch(currentCollectionProvider);
  return ChatsNotifier(storage, currentCol?.id);
});

// Current Active Chat Provider
final currentChatProvider = StateProvider<Chat?>((ref) => null);

// Source Panel Citation Provider
final activeCitationProvider = StateProvider<Citation?>((ref) => null);
