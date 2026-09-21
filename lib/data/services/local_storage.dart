import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:lab_05/data/models/app_settings.dart';
import 'package:lab_05/data/models/index_state.dart';

import 'package:lab_05/data/models/chat.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/models/paper.dart';

class LocalStorage {
  final Directory rootDir;
  RandomAccessFile? _lockFileHandle;

  LocalStorage({required this.rootDir});

  @visibleForTesting
  static Directory? overrideAppSupportDir;

  static Future<Directory> getDefaultDataDirectory() async {
    final Directory appSupport;
    if (overrideAppSupportDir != null) {
      appSupport = overrideAppSupportDir!;
    } else {
      appSupport = await getApplicationSupportDirectory();
    }
    return Directory(p.join(appSupport.path, 'PaperChat'));
  }

  static Future<File> _getDataDirectoryConfigFile() async {
    final Directory appSupport;
    if (overrideAppSupportDir != null) {
      appSupport = overrideAppSupportDir!;
    } else {
      appSupport = await getApplicationSupportDirectory();
    }
    final configDir = Directory(p.join(appSupport.path, 'PaperChat'));
    if (!configDir.existsSync()) {
      configDir.createSync(recursive: true);
    }
    return File(p.join(configDir.path, 'data_directory.txt'));
  }

  static Future<String?> getCustomDataDirectoryPath() async {
    try {
      final file = await _getDataDirectoryConfigFile();
      if (await file.exists()) {
        final path = (await file.readAsString()).trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> setCustomDataDirectoryPath(String? newPath) async {
    try {
      final file = await _getDataDirectoryConfigFile();
      if (newPath == null || newPath.trim().isEmpty) {
        if (await file.exists()) {
          await file.delete();
        }
      } else {
        await file.writeAsString(newPath.trim(), flush: true);
      }
    } catch (e) {
      debugPrint('Warning: Could not save data directory config: $e');
    }
  }

  static Future<Directory> resolveDataDirectory([Directory? overrideDir]) async {
    if (overrideDir != null) return overrideDir;
    final customPath = await getCustomDataDirectoryPath();
    if (customPath != null) {
      final dir = Directory(customPath);
      if (dir.existsSync()) {
        return dir;
      }
    }
    return getDefaultDataDirectory();
  }

  static Future<LocalStorage> createForDirectory(Directory dir) async {
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final storage = LocalStorage(rootDir: dir);
    await storage._acquireAppLock();
    await storage.runStartupRecovery();
    return storage;
  }

  static Future<LocalStorage> createDefault([Directory? overrideDir]) async {
    final baseDir = await resolveDataDirectory(overrideDir);
    return createForDirectory(baseDir);
  }

  Future<void> _acquireAppLock() async {
    try {
      final lockPath = p.join(rootDir.path, 'app.lock');
      final file = File(lockPath);
      _lockFileHandle = await file.open(mode: FileMode.write);
      await _lockFileHandle?.lock(FileLock.exclusive);
    } catch (e) {
      debugPrint('Warning: Could not acquire exclusive lock: $e');
    }
  }

  void dispose() {
    try {
      _lockFileHandle?.unlockSync();
      _lockFileHandle?.closeSync();
    } catch (_) {}
  }

  // Paths
  String get collectionsPath => p.join(rootDir.path, 'collections');
  String get settingsFilePath => p.join(rootDir.path, 'settings.json');

  String collectionDir(String collectionId) =>
      p.join(collectionsPath, collectionId);
  String collectionJsonPath(String collectionId) =>
      p.join(collectionDir(collectionId), 'collection.json');
  String documentsDir(String collectionId) =>
      p.join(collectionDir(collectionId), 'documents');
  String metadataDir(String collectionId) =>
      p.join(collectionDir(collectionId), 'metadata');
  String indexDir(String collectionId) =>
      p.join(collectionDir(collectionId), 'index');
  String chatsDir(String collectionId) =>
      p.join(collectionDir(collectionId), 'chats');
  String referencesDir(String collectionId) =>
      p.join(collectionDir(collectionId), 'references');

  String paperPdfPath(String collectionId, String documentId) =>
      p.join(documentsDir(collectionId), '$documentId.pdf');
  String paperMetadataPath(String collectionId, String documentId) =>
      p.join(metadataDir(collectionId), '$documentId.json');
  String referencesPath(String collectionId, String documentId) =>
      p.join(referencesDir(collectionId), '$documentId.json');
  String indexVectorsPath(String collectionId) =>
      p.join(indexDir(collectionId), 'vectors.tvim');
  String indexStatePath(String collectionId) =>
      p.join(indexDir(collectionId), 'state.json');
  String chatJsonPath(String collectionId, String chatId) =>
      p.join(chatsDir(collectionId), '$chatId.json');

  // Safe file write using atomic temporary sibling replacement
  Future<void> writeJsonSafely(
    String filePath,
    Map<String, dynamic> data,
  ) async {
    final parent = Directory(p.dirname(filePath));
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    final tempPath = '$filePath.tmp_${DateTime.now().microsecondsSinceEpoch}';
    final tempFile = File(tempPath);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    await tempFile.writeAsString(jsonStr, flush: true);

    try {
      await tempFile.rename(filePath);
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  Future<Map<String, dynamic>?> readJsonSafely(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error reading JSON at $filePath: $e');
      return null;
    }
  }

  // Settings
  Future<AppSettings> loadSettings() async {
    final json = await readJsonSafely(settingsFilePath);
    var settings = json == null
        ? const AppSettings()
        : AppSettings.fromJson(json);
    // Read the old key file once, then use settings as the single source of truth.
    final legacyKey = File(p.join(rootDir.path, '.key_store'));
    if (settings.openRouterApiKey.isEmpty && await legacyKey.exists()) {
      settings = settings.copyWith(
        openRouterApiKey: (await legacyKey.readAsString()).trim(),
      );
      await saveSettings(settings);
    }
    return settings;
  }

  Future<void> saveSettings(AppSettings settings) async {
    await writeJsonSafely(settingsFilePath, settings.toJson());
    final legacyKey = File(p.join(rootDir.path, '.key_store'));
    if (await legacyKey.exists()) await legacyKey.delete();
  }

  // Collections
  Future<List<Collection>> listCollections() async {
    final colDir = Directory(collectionsPath);
    if (!await colDir.exists()) return [];
    final List<Collection> collections = [];
    final entities = colDir.listSync();
    for (final entity in entities) {
      if (entity is Directory) {
        final colJsonPath = p.join(entity.path, 'collection.json');
        final json = await readJsonSafely(colJsonPath);
        if (json != null) {
          try {
            collections.add(Collection.fromJson(json));
          } catch (e) {
            debugPrint('Error parsing collection at $colJsonPath: $e');
          }
        }
      }
    }
    collections.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return collections;
  }

  Future<Collection?> loadCollection(String id) async {
    final json = await readJsonSafely(collectionJsonPath(id));
    if (json == null) return null;
    return Collection.fromJson(json);
  }

  Future<void> saveCollection(Collection collection) async {
    final cDir = Directory(collectionDir(collection.id));
    if (!await cDir.exists()) {
      await cDir.create(recursive: true);
      await Directory(documentsDir(collection.id)).create(recursive: true);
      await Directory(metadataDir(collection.id)).create(recursive: true);
      await Directory(indexDir(collection.id)).create(recursive: true);
      await Directory(chatsDir(collection.id)).create(recursive: true);
    }
    await writeJsonSafely(
      collectionJsonPath(collection.id),
      collection.toJson(),
    );
  }

  Future<void> deleteCollection(String id) async {
    final cDir = Directory(collectionDir(id));
    if (await cDir.exists()) {
      await cDir.delete(recursive: true);
    }
  }

  // Papers
  Future<List<PaperDocument>> listPapers(String collectionId) async {
    final metaDir = Directory(metadataDir(collectionId));
    if (!await metaDir.exists()) return [];
    final List<PaperDocument> papers = [];
    final entities = metaDir.listSync();
    for (final entity in entities) {
      if (entity is File &&
          entity.path.endsWith('.json') &&
          !entity.path.endsWith('.tmp')) {
        final json = await readJsonSafely(entity.path);
        if (json != null) {
          try {
            papers.add(PaperDocument.fromJson(json));
          } catch (e) {
            debugPrint('Error parsing paper at ${entity.path}: $e');
          }
        }
      }
    }
    papers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return papers;
  }

  Future<PaperDocument?> loadPaper(
    String collectionId,
    String documentId,
  ) async {
    final json = await readJsonSafely(
      paperMetadataPath(collectionId, documentId),
    );
    if (json == null) return null;
    return PaperDocument.fromJson(json);
  }

  Future<void> savePaper(String collectionId, PaperDocument paper) async {
    await writeJsonSafely(
      paperMetadataPath(collectionId, paper.id),
      paper.toJson(),
    );
  }

  Future<void> deletePaper(String collectionId, String documentId) async {
    final metaFile = File(paperMetadataPath(collectionId, documentId));
    if (await metaFile.exists()) {
      await metaFile.delete();
    }
    final pdfFile = File(paperPdfPath(collectionId, documentId));
    if (await pdfFile.exists()) {
      try {
        await pdfFile.delete();
      } catch (e) {
        debugPrint('Warning: Could not delete PDF file: $e');
      }
    }
    final referenceFile = File(referencesPath(collectionId, documentId));
    if (await referenceFile.exists()) {
      await referenceFile.delete();
    }
  }

  // Resolved bibliography links (Crossref lookups are cached so a paper is
  // only ever resolved once).
  Future<Map<String, dynamic>?> loadResolvedReferences(
    String collectionId,
    String documentId,
  ) => readJsonSafely(referencesPath(collectionId, documentId));

  Future<void> saveResolvedReferences(
    String collectionId,
    String documentId,
    Map<String, dynamic> data,
  ) => writeJsonSafely(referencesPath(collectionId, documentId), data);

  // Chats
  Future<List<Chat>> listChats(String collectionId) async {
    final cDir = Directory(chatsDir(collectionId));
    if (!await cDir.exists()) return [];
    final List<Chat> chats = [];
    final entities = cDir.listSync();
    for (final entity in entities) {
      if (entity is File &&
          entity.path.endsWith('.json') &&
          !entity.path.endsWith('.tmp')) {
        final json = await readJsonSafely(entity.path);
        if (json != null) {
          try {
            chats.add(Chat.fromJson(json));
          } catch (e) {
            debugPrint('Error parsing chat at ${entity.path}: $e');
          }
        }
      }
    }
    chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return chats;
  }

  Future<Chat?> loadChat(String collectionId, String chatId) async {
    final json = await readJsonSafely(chatJsonPath(collectionId, chatId));
    if (json == null) return null;
    return Chat.fromJson(json);
  }

  Future<void> saveChat(String collectionId, Chat chat) async {
    await writeJsonSafely(chatJsonPath(collectionId, chat.id), chat.toJson());
  }

  Future<void> deleteChat(String collectionId, String chatId) async {
    final chatFile = File(chatJsonPath(collectionId, chatId));
    if (await chatFile.exists()) {
      await chatFile.delete();
    }
  }

  // Index state
  Future<IndexState> loadIndexState(
    String collectionId, {
    required String embeddingProfileId,
  }) async {
    final json = await readJsonSafely(indexStatePath(collectionId));
    if (json == null) {
      final defaultState = IndexState(embeddingProfileId: embeddingProfileId);
      await saveIndexState(collectionId, defaultState);
      return defaultState;
    }
    return IndexState.fromJson(json);
  }

  Future<void> saveIndexState(String collectionId, IndexState state) async {
    await writeJsonSafely(indexStatePath(collectionId), state.toJson());
  }

  // Startup Recovery
  Future<void> runStartupRecovery() async {
    final colDir = Directory(collectionsPath);
    if (!await colDir.exists()) return;

    for (final entity in colDir.listSync()) {
      if (entity is Directory) {
        final collectionId = p.basename(entity.path);
        try {
          // 1. Recover dirty index state if pending
          final indexFile = File(indexStatePath(collectionId));
          if (await indexFile.exists()) {
            final stateJson = await readJsonSafely(indexFile.path);
            if (stateJson != null) {
              final status = stateJson['status'];
              if (status == 'dirty') {
                debugPrint(
                  'Reconciling dirty index state for collection $collectionId',
                );
                stateJson['status'] = 'needsReindex';
                stateJson['pending'] = null;
                await writeJsonSafely(indexFile.path, stateJson);
              }
            }
          }

          // 2. Mark any dangling processing documents as failed
          final metaD = Directory(metadataDir(collectionId));
          if (await metaD.exists()) {
            for (final metaEntity in metaD.listSync()) {
              if (metaEntity is File && metaEntity.path.endsWith('.json')) {
                final json = await readJsonSafely(metaEntity.path);
                if (json != null && json['status'] == 'processing') {
                  debugPrint(
                    'Found dangling processing document: ${json['id']}',
                  );
                  json['status'] = 'failed';
                  json['error'] = 'Import interrupted during previous session. Retry import.';
                  await writeJsonSafely(metaEntity.path, json);
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Recovery error for collection $collectionId: $e');
        }
      }
    }
  }
}
