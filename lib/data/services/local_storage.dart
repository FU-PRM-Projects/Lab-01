import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:lab_05/data/models/app_settings.dart';
import 'package:lab_05/data/models/index_state.dart';

import 'package:lab_05/data/models/chat.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/models/section_revision.dart';
import 'package:lab_05/data/services/section_artifact_service.dart';

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

  static Future<Directory> resolveDataDirectory([
    Directory? overrideDir,
  ]) async {
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
  String artifactsDir(String collectionId, String documentId) =>
      p.join(collectionDir(collectionId), 'artifacts', documentId);
  String artifactDir(
    String collectionId,
    String documentId,
    String artifactId,
  ) => p.join(artifactsDir(collectionId, documentId), artifactId);
  String revisionsDir(String collectionId, String documentId) =>
      p.join(collectionDir(collectionId), 'revisions', documentId);
  String revisionManifestPath(String collectionId, String documentId) =>
      p.join(revisionsDir(collectionId, documentId), 'manifest.json');
  String revisionPath(
    String collectionId,
    String documentId,
    String revisionId,
  ) => p.join(revisionsDir(collectionId, documentId), '$revisionId.json');

  String paperPdfPath(String collectionId, String documentId) =>
      p.join(documentsDir(collectionId), '$documentId.pdf');
  String paperMetadataPath(String collectionId, String documentId) =>
      p.join(metadataDir(collectionId), '$documentId.json');
  String referencesPath(String collectionId, String documentId) =>
      p.join(referencesDir(collectionId), '$documentId.json');
  String sectionsMarkdownPath(
    String collectionId,
    String documentId, [
    String? artifactId,
  ]) => p.join(
    artifactId == null
        ? artifactsDir(collectionId, documentId)
        : artifactDir(collectionId, documentId, artifactId),
    'sections.md',
  );
  String sectionsJsonPath(
    String collectionId,
    String documentId, [
    String? artifactId,
  ]) => p.join(
    artifactId == null
        ? artifactsDir(collectionId, documentId)
        : artifactDir(collectionId, documentId, artifactId),
    'sections.json',
  );

  /// Directory holding one document's extracted figures.
  String figuresDir(String collectionId, String documentId) =>
      p.join(collectionDir(collectionId), 'figures', documentId);

  /// Absolute path of a figure, given the name stored on its chunk.
  String figurePath(String collectionId, String documentId, String name) =>
      p.join(figuresDir(collectionId, documentId), name);

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

  /// Writes text through a temporary sibling so an interrupted export cannot
  /// leave a truncated artifact at the final path.
  Future<void> writeStringSafely(String filePath, String content) async {
    final parent = Directory(p.dirname(filePath));
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    final tempPath = '$filePath.tmp_${DateTime.now().microsecondsSinceEpoch}';
    final tempFile = File(tempPath);
    await tempFile.writeAsString(content, flush: true);

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

  Future<SectionRevision> ensureOriginalRevision(
    String collectionId,
    PaperDocument paper,
  ) async {
    final manifestJson = await readJsonSafely(
      revisionManifestPath(collectionId, paper.id),
    );
    if (manifestJson != null) {
      final manifest = RevisionManifest.fromJson(manifestJson);
      final existing = await loadRevision(
        collectionId,
        paper.id,
        manifest.originalRevisionId,
      );
      if (existing != null) return existing;
    }

    final now = DateTime.now().toUtc();
    final original = SectionRevision(
      id: 'rev_original',
      documentId: paper.id,
      status: 'saved',
      indexStatus: 'indexed',
      createdBy: 'original_extraction',
      createdAt: paper.createdAt,
      updatedAt: now,
      sections: paper.sections,
      chunks: paper.chunks.where((chunk) => !chunk.isFigure).toList(),
    );
    await saveRevision(collectionId, original);
    await writeJsonSafely(
      revisionManifestPath(collectionId, paper.id),
      RevisionManifest(
        documentId: paper.id,
        originalRevisionId: original.id,
        currentRevisionId: original.id,
      ).toJson(),
    );
    return original;
  }

  Future<void> saveRevision(String collectionId, SectionRevision revision) =>
      writeJsonSafely(
        revisionPath(collectionId, revision.documentId, revision.id),
        revision.toJson(),
      );

  Future<SectionRevision?> loadRevision(
    String collectionId,
    String documentId,
    String revisionId,
  ) async {
    final json = await readJsonSafely(
      revisionPath(collectionId, documentId, revisionId),
    );
    return json == null ? null : SectionRevision.fromJson(json);
  }

  Future<List<SectionRevision>> listRevisions(
    String collectionId,
    String documentId,
  ) async {
    final dir = Directory(revisionsDir(collectionId, documentId));
    if (!await dir.exists()) return const [];
    final revisions = <SectionRevision>[];
    for (final entity in dir.listSync()) {
      if (entity is! File ||
          !entity.path.endsWith('.json') ||
          p.basename(entity.path) == 'manifest.json') {
        continue;
      }
      final json = await readJsonSafely(entity.path);
      if (json != null) revisions.add(SectionRevision.fromJson(json));
    }
    revisions.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return revisions;
  }

  Future<RevisionManifest?> loadRevisionManifest(
    String collectionId,
    String documentId,
  ) async {
    final json = await readJsonSafely(
      revisionManifestPath(collectionId, documentId),
    );
    return json == null ? null : RevisionManifest.fromJson(json);
  }

  Future<SectionRevision?> loadActiveRevision(
    String collectionId,
    PaperDocument paper,
  ) async {
    final original = await ensureOriginalRevision(collectionId, paper);
    final manifest = await loadRevisionManifest(collectionId, paper.id);
    if (manifest == null || manifest.currentRevisionId == original.id) {
      return original;
    }
    return loadRevision(collectionId, paper.id, manifest.currentRevisionId);
  }

  Future<void> activateRevision(
    String collectionId,
    String documentId,
    String revisionId,
  ) async {
    final revision = await loadRevision(collectionId, documentId, revisionId);
    if (revision == null || !revision.isIndexed || revision.status != 'saved') {
      throw StateError('Only a saved, indexed revision can become active.');
    }
    final manifest = await loadRevisionManifest(collectionId, documentId);
    if (manifest == null) throw StateError('Revision manifest is missing.');
    await writeJsonSafely(
      revisionManifestPath(collectionId, documentId),
      RevisionManifest(
        documentId: documentId,
        originalRevisionId: manifest.originalRevisionId,
        currentRevisionId: revisionId,
      ).toJson(),
    );
  }

  Future<void> deletePendingRevision(
    String collectionId,
    String documentId,
    String revisionId,
  ) async {
    final revision = await loadRevision(collectionId, documentId, revisionId);
    if (revision == null) return;
    final manifest = await loadRevisionManifest(collectionId, documentId);
    if (revision.isIndexed || manifest?.currentRevisionId == revisionId) {
      throw StateError('An active or indexed revision cannot be discarded.');
    }
    final file = File(revisionPath(collectionId, documentId, revisionId));
    if (await file.exists()) await file.delete();
  }

  Future<SectionRevision> createPendingRevision({
    required String collectionId,
    required PaperDocument paper,
    required String sectionId,
    required String revisedContent,
    required String instruction,
    String? baseRevisionId,
  }) async {
    final base = baseRevisionId == null
        ? await loadActiveRevision(collectionId, paper)
        : await loadRevision(collectionId, paper.id, baseRevisionId);
    if (base == null || base.documentId != paper.id) {
      throw StateError('No valid base revision is available.');
    }
    if (!base.sections.any((section) => section.id == sectionId)) {
      throw StateError('Section not found: $sectionId');
    }
    final now = DateTime.now().toUtc();
    final edited = [
      for (final section in base.sections)
        section.id == sectionId
            ? section.copyWith(text: revisedContent.trim())
            : section,
    ];
    var offset = 0;
    final normalized = <DocumentSection>[];
    for (final section in edited) {
      normalized.add(
        section.copyWith(
          startChar: offset,
          endChar: offset + section.text.length,
        ),
      );
      offset += section.text.length + 2;
    }
    final revision = SectionRevision(
      id: 'rev_${const Uuid().v4()}',
      documentId: paper.id,
      parentRevisionId: base.id,
      status: 'pending',
      indexStatus: 'pending',
      createdBy: 'ai_edit',
      instruction: instruction,
      createdAt: now,
      updatedAt: now,
      sections: normalized,
    );
    await saveRevision(collectionId, revision);
    return revision;
  }

  /// Starts an export review without writing Markdown or JSON files.
  ///
  /// The review is a pending revision cloned from the currently active
  /// revision. Chat edits can branch from it, and files are only materialized
  /// after the user explicitly saves the reviewed revision.
  Future<SectionRevision> createExportReview({
    required String collectionId,
    required PaperDocument paper,
  }) async {
    final base = await loadActiveRevision(collectionId, paper);
    if (base == null || base.sections.isEmpty) {
      throw StateError('This paper has no extracted sections to review.');
    }
    final now = DateTime.now().toUtc();
    final revision = SectionRevision(
      id: 'rev_${const Uuid().v4()}',
      documentId: paper.id,
      parentRevisionId: base.id,
      status: 'pending',
      indexStatus: 'pending',
      createdBy: 'export_review',
      instruction: 'Review before export',
      createdAt: now,
      updatedAt: now,
      sections: base.sections,
    );
    await saveRevision(collectionId, revision);
    return revision;
  }

  /// Creates a versioned portable artifact. The source revision is recorded
  /// beside the files so an export can always be traced and reproduced.
  Future<
    ({
      String markdownPath,
      String jsonPath,
      String artifactId,
      String revisionId,
    })
  >
  saveSectionArtifacts(
    String collectionId,
    PaperDocument paper, {
    SectionRevision? revision,
    String? artifactId,
  }) async {
    final source = revision ?? await loadActiveRevision(collectionId, paper);
    if (source == null || source.sections.isEmpty) {
      throw StateError('This paper has no extracted sections to export.');
    }
    final id = artifactId ?? 'artifact_${const Uuid().v4()}';
    final exportedPaper = paper.copyWith(sections: source.sections);
    final bundle = SectionArtifactService.build(
      exportedPaper,
      revisionId: source.id,
      artifactId: id,
    );
    final markdownPath = sectionsMarkdownPath(collectionId, paper.id, id);
    final jsonPath = sectionsJsonPath(collectionId, paper.id, id);
    await writeStringSafely(markdownPath, bundle.markdown);
    await writeJsonSafely(jsonPath, bundle.json);
    await writeJsonSafely(
      p.join(artifactDir(collectionId, paper.id, id), 'manifest.json'),
      {
        'schemaVersion': 1,
        'artifactId': id,
        'documentId': paper.id,
        'revisionId': source.id,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    return (
      markdownPath: markdownPath,
      jsonPath: jsonPath,
      artifactId: id,
      revisionId: source.id,
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
    final artifactDir = Directory(artifactsDir(collectionId, documentId));
    if (await artifactDir.exists()) {
      await artifactDir.delete(recursive: true);
    }
    final revisionDir = Directory(revisionsDir(collectionId, documentId));
    if (await revisionDir.exists()) {
      await revisionDir.delete(recursive: true);
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
