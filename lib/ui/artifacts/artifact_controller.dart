import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/services/crossref_client.dart';
import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/models/reference.dart';

/// Which artifact the panel is showing, for one chat.
class ArtifactPanelView {
  final bool isOpen;
  final String? selectedPaperId;

  const ArtifactPanelView({this.isOpen = false, this.selectedPaperId});

  ArtifactPanelView copyWith({bool? isOpen, String? selectedPaperId}) {
    return ArtifactPanelView(
      isOpen: isOpen ?? this.isOpen,
      selectedPaperId: selectedPaperId ?? this.selectedPaperId,
    );
  }

  ArtifactPanelView clearSelection() => ArtifactPanelView(isOpen: isOpen);
}

/// Panel state keyed by chat, so every conversation keeps its own artifact
/// sidebar: which papers list it is on, and which one is open.
class ArtifactPanelNotifier
    extends StateNotifier<Map<String, ArtifactPanelView>> {
  ArtifactPanelNotifier() : super(const {});

  ArtifactPanelView viewFor(String scope) =>
      state[scope] ?? const ArtifactPanelView();

  void _set(String scope, ArtifactPanelView view) {
    state = {...state, scope: view};
  }

  void toggle(String scope) {
    final view = viewFor(scope);
    _set(scope, view.copyWith(isOpen: !view.isOpen));
  }

  void open(String scope, {String? paperId}) {
    final view = viewFor(scope);
    _set(
      scope,
      ArtifactPanelView(
        isOpen: true,
        selectedPaperId: paperId ?? view.selectedPaperId,
      ),
    );
  }

  void close(String scope) {
    _set(scope, viewFor(scope).copyWith(isOpen: false));
  }

  void select(String scope, String paperId) {
    _set(scope, ArtifactPanelView(isOpen: true, selectedPaperId: paperId));
  }

  void clearSelection(String scope) {
    _set(scope, viewFor(scope).clearSelection());
  }

  void forget(String scope) {
    if (!state.containsKey(scope)) return;
    state = {...state}..remove(scope);
  }
}

final artifactPanelProvider =
    StateNotifierProvider<
      ArtifactPanelNotifier,
      Map<String, ArtifactPanelView>
    >((ref) => ArtifactPanelNotifier());

/// The key of the artifact sidebar that belongs to the chat on screen. A chat
/// that has not been saved yet still gets its own draft scope per collection.
final artifactScopeProvider = Provider<String>((ref) {
  final chat = ref.watch(currentChatProvider);
  if (chat != null) return 'chat:${chat.id}';
  final collection = ref.watch(currentCollectionProvider);
  return 'draft:${collection?.id ?? 'none'}';
});

final artifactViewProvider = Provider<ArtifactPanelView>((ref) {
  final scope = ref.watch(artifactScopeProvider);
  return ref.watch(artifactPanelProvider)[scope] ?? const ArtifactPanelView();
});

/// Chunk ids this chat has already cited, used to mark them in the chunk list.
final citedChunkIdsProvider = Provider<Set<String>>((ref) {
  final chat = ref.watch(currentChatProvider);
  if (chat == null) return const {};
  return {
    for (final message in chat.messages)
      for (final citation in message.citations) citation.chunkId,
  };
});

final paperByIdProvider = Provider.family<PaperDocument?, String>((
  ref,
  documentId,
) {
  final papers = ref.watch(papersProvider);
  for (final paper in papers) {
    if (paper.id == documentId) return paper;
  }
  return null;
});

/// Chunks of one paper in reading order.
final paperChunksProvider = Provider.family<List<PaperChunk>, String>((
  ref,
  documentId,
) {
  final paper = ref.watch(paperByIdProvider(documentId));
  if (paper == null) return const [];
  final chunks = [...paper.chunks];
  chunks.sort((a, b) {
    final byPage = a.page.compareTo(b.page);
    return byPage != 0 ? byPage : a.ordinal.compareTo(b.ordinal);
  });
  return List.unmodifiable(chunks);
});

/// Sections of one paper in reading order.
final paperSectionsProvider = Provider.family<List<DocumentSection>, String>((
  ref,
  documentId,
) {
  final paper = ref.watch(paperByIdProvider(documentId));
  if (paper == null) return const [];
  final sections = [...paper.sections]
    ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
  return List.unmodifiable(sections);
});

/// Bibliography entries the instruct model extracted during indexing.
final paperReferencesProvider = Provider.family<List<PaperReference>, String>((
  ref,
  documentId,
) {
  final paper = ref.watch(paperByIdProvider(documentId));
  return paper?.references ?? const [];
});

class ResolvedReferencesState {
  /// Crossref matches keyed by the fingerprint of the raw reference text.
  final Map<String, CrossrefMatch> matches;
  final bool isResolving;
  final int resolvedCount;
  final int totalCount;
  final String? errorMessage;

  const ResolvedReferencesState({
    this.matches = const {},
    this.isResolving = false,
    this.resolvedCount = 0,
    this.totalCount = 0,
    this.errorMessage,
  });

  ResolvedReferencesState copyWith({
    Map<String, CrossrefMatch>? matches,
    bool? isResolving,
    int? resolvedCount,
    int? totalCount,
    String? errorMessage,
  }) {
    return ResolvedReferencesState(
      matches: matches ?? this.matches,
      isResolving: isResolving ?? this.isResolving,
      resolvedCount: resolvedCount ?? this.resolvedCount,
      totalCount: totalCount ?? this.totalCount,
      errorMessage: errorMessage,
    );
  }

  double get progress => totalCount == 0 ? 0 : resolvedCount / totalCount;
}

/// Looks bibliography entries up in Crossref and caches the answers on disk so
/// each paper is only ever resolved once.
class ResolvedReferencesNotifier
    extends StateNotifier<ResolvedReferencesState> {
  ResolvedReferencesNotifier(this._ref, this._documentId)
    : super(const ResolvedReferencesState()) {
    _loadCache();
  }

  final Ref _ref;
  final String _documentId;
  CrossrefClient? _client;

  static String fingerprint(String raw) {
    final normalised = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    return sha256.convert(utf8.encode(normalised)).toString().substring(0, 16);
  }

  String? get _collectionId => _ref.read(currentCollectionProvider)?.id;

  Future<void> _loadCache() async {
    final collectionId = _collectionId;
    if (collectionId == null) return;
    final json = await _ref
        .read(localStorageProvider)
        .loadResolvedReferences(collectionId, _documentId);
    if (!mounted || json == null) return;
    final entries = (json['entries'] as Map<String, dynamic>?) ?? const {};
    state = state.copyWith(
      matches: {
        for (final entry in entries.entries)
          entry.key: CrossrefMatch.fromCache(
            entry.value as Map<String, dynamic>,
          ),
      },
    );
  }

  Future<void> _saveCache(String collectionId) async {
    await _ref.read(localStorageProvider).saveResolvedReferences(
      collectionId,
      _documentId,
      {
        'schemaVersion': 1,
        'documentId': _documentId,
        'resolvedAt': DateTime.now().toUtc().toIso8601String(),
        'entries': {
          for (final entry in state.matches.entries)
            entry.key: entry.value.toJson(),
        },
      },
    );
  }

  /// Resolves only the entries that carry no DOI, arXiv id or URL of their own.
  Future<void> resolve(List<PaperReference> references) async {
    if (state.isResolving) return;
    final pending = <int, String>{};
    final fingerprints = <int, String>{};
    for (final reference in references) {
      if (reference.hasDirectLink) continue;
      final key = fingerprint(reference.raw);
      if (state.matches.containsKey(key)) continue;
      pending[reference.index] = reference.raw;
      fingerprints[reference.index] = key;
    }
    if (pending.isEmpty) return;

    // This provider is keyed by document alone, so the collection is captured
    // before the first await: switching collections mid-resolution would
    // otherwise file this paper's matches under the collection now selected.
    final collectionId = _collectionId;
    if (collectionId == null) return;

    state = state.copyWith(
      isResolving: true,
      resolvedCount: 0,
      totalCount: pending.length,
      errorMessage: null,
    );

    final client = CrossrefClient();
    _client = client;
    try {
      final results = await client.resolveAll(
        pending,
        onProgress: (done, total) {
          if (mounted) {
            state = state.copyWith(resolvedCount: done, totalCount: total);
          }
        },
      );
      if (!mounted) return;
      state = state.copyWith(
        matches: {
          ...state.matches,
          for (final entry in results.entries)
            fingerprints[entry.key]!: entry.value,
        },
        isResolving: false,
      );
      await _saveCache(collectionId);
    } catch (error) {
      if (mounted) {
        state = state.copyWith(
          isResolving: false,
          errorMessage: 'Could not reach Crossref: $error',
        );
      }
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
    }
  }

  CrossrefMatch? matchFor(PaperReference reference) =>
      state.matches[fingerprint(reference.raw)];

  @override
  void dispose() {
    _client?.close();
    _client = null;
    super.dispose();
  }
}

final resolvedReferencesProvider =
    StateNotifierProvider.family<
      ResolvedReferencesNotifier,
      ResolvedReferencesState,
      String
    >((ref, documentId) => ResolvedReferencesNotifier(ref, documentId));
