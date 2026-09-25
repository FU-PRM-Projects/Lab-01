import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/chat.dart';
import 'package:lab_05/data/models/chat_artifact.dart';
import 'package:lab_05/data/models/citation.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/models/tool_call_record.dart';
import 'package:lab_05/data/services/embedding_client.dart';
import 'package:lab_05/domain/research_agent.dart';
import 'package:lab_05/ui/artifacts/artifact_controller.dart';

class ChatState {
  final bool isStreaming;
  final String? statusMessage;
  final String? streamingText;
  final Map<String, Citation> streamingSources;

  /// Tools run so far in this turn, oldest first. Running calls are included.
  final List<ToolCallRecord> toolCalls;
  final List<ChatArtifact> artifacts;
  final String? errorMessage;

  const ChatState({
    this.isStreaming = false,
    this.statusMessage,
    this.streamingText,
    this.streamingSources = const {},
    this.toolCalls = const [],
    this.artifacts = const [],
    this.errorMessage,
  });

  ChatState copyWith({
    bool? isStreaming,
    String? statusMessage,
    String? streamingText,
    Map<String, Citation>? streamingSources,
    List<ToolCallRecord>? toolCalls,
    List<ChatArtifact>? artifacts,
    String? errorMessage,
  }) {
    return ChatState(
      isStreaming: isStreaming ?? this.isStreaming,
      statusMessage: statusMessage,
      streamingText: streamingText ?? this.streamingText,
      streamingSources: streamingSources ?? this.streamingSources,
      toolCalls: toolCalls ?? this.toolCalls,
      artifacts: artifacts ?? this.artifacts,
      errorMessage: errorMessage,
    );
  }
}

class ChatController extends StateNotifier<ChatState> {
  ChatController(this._ref) : super(const ChatState());

  final Ref _ref;
  ResearchAgent? _agent;
  EmbeddingClient? _embeddings;
  StreamSubscription<ChatEvent>? _subscription;
  Timer? _timer;
  _ChatTurn? _turn;
  int _generation = 0;

  bool _isCurrent(int generation) => mounted && generation == _generation;

  @override
  void dispose() {
    _generation++;
    _releaseRequests();
    super.dispose();
  }

  void _releaseRequests() {
    _agent?.cancel();
    _agent = null;
    _embeddings?.close();
    _embeddings = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> stop() => _finish('cancelled');

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || state.isStreaming) return;
    final collection = _ref.read(currentCollectionProvider);
    final settings = _ref.read(settingsProvider);
    final isDirectExport =
        ResearchAgent.directSectionExportFormat(text) != null;
    if (collection == null ||
        (settings.openRouterApiKey.trim().isEmpty && !isDirectExport)) {
      state = ChatState(
        errorMessage: collection == null
            ? 'Please select or create a collection first'
            : 'Please enter your OpenRouter API Key in Settings',
      );
      return;
    }
    final generation = ++_generation;
    state = const ChatState(
      isStreaming: true,
      statusMessage: 'Preparing evidence...',
      streamingText: '',
    );
    try {
      final storage = _ref.read(localStorageProvider);
      var chat = _ref.read(currentChatProvider);
      if (chat == null) {
        final title = text.length > 35 ? '${text.substring(0, 32)}...' : text;
        chat = await _ref
            .read(projectChatsProvider(collection.id).notifier)
            .createNewChat(title);
      }
      if (!_isCurrent(generation)) return;
      final history = <Map<String, String>>[];
      for (final message in chat.messages) {
        final parts = <String>[message.content];
        for (final artifact in message.artifacts) {
          final revisionId = artifact.revisionId;
          if (revisionId == null) continue;
          parts.add(
            '[${artifact.status ?? 'saved'} ${artifact.type} '
            'revisionId=$revisionId documentId=${artifact.documentId} '
            'title="${artifact.title}"]',
          );
          if (artifact.type == 'sectionChangeDraft' &&
              artifact.status == 'pending') {
            final revision = await storage.loadRevision(
              collection.id,
              artifact.documentId,
              revisionId,
            );
            final parentId = revision?.parentRevisionId;
            final parent = parentId == null
                ? null
                : await storage.loadRevision(
                    collection.id,
                    artifact.documentId,
                    parentId,
                  );
            if (revision != null) {
              final parentText = {
                for (final section in parent?.sections ?? const [])
                  section.id: section.text,
              };
              for (final section in revision.sections) {
                if (parentText[section.id] != section.text) {
                  parts.add(
                    'Pending draft for "${section.displayName}":\n'
                    '${section.text}',
                  );
                }
              }
            }
          }
        }
        history.add({
          'role': message.role,
          'content': parts.where((part) => part.isNotEmpty).join('\n'),
        });
      }
      final updated = chat.copyWith(
        messages: [
          ...chat.messages,
          ChatMessage(
            id: 'msg_${const Uuid().v4()}',
            role: 'user',
            content: text.trim(),
            createdAt: DateTime.now().toUtc(),
          ),
        ],
        updatedAt: DateTime.now().toUtc(),
      );
      await storage.saveChat(collection.id, updated);
      if (!_isCurrent(generation)) return;
      _ref.read(currentChatProvider.notifier).state = updated;
      final turn = _ChatTurn(updated, settings.chatModel);
      _turn = turn;
      unawaited(
        _ref.read(projectChatsProvider(collection.id).notifier).refresh(),
      );
      final index = await _ref
          .read(paperRepositoryProvider(collection.id))
          .openIndex();
      if (!_isCurrent(generation)) return;
      final embeddings = EmbeddingClient(
        apiKey: settings.openRouterApiKey,
        baseUrl: settings.openRouterBaseUrl,
        model: collection.embeddingProfile.model,
        dimensions: collection.embeddingProfile.dimensions,
      );
      _embeddings = embeddings;
      final agent = ResearchAgent(
        apiKey: settings.openRouterApiKey,
        chatModel: settings.chatModel,
        baseUrl: settings.openRouterBaseUrl,
        storage: storage,
        embeddings: embeddings,
        index: index,
      );
      _agent = agent;
      var pendingUpdate = false;
      _timer = Timer.periodic(const Duration(milliseconds: 45), (_) {
        if (_isCurrent(generation) && pendingUpdate) {
          state = state.copyWith(
            streamingText: turn.text.toString(),
            streamingSources: turn.sources,
            toolCalls: turn.snapshot(),
          );
          pendingUpdate = false;
        }
      });
      _subscription = agent
          .streamAnswer(
            collectionId: collection.id,
            userQuestion: text.trim(),
            previousMessages: history,
          )
          .listen(
            (event) {
              if (!_isCurrent(generation)) return;
              switch (event) {
                case ToolStatus(:final message):
                  state = state.copyWith(statusMessage: message);
                case ToolCallStarted(:final call):
                  turn.toolCalls.add(call);
                  state = state.copyWith(
                    statusMessage: state.statusMessage,
                    toolCalls: turn.snapshot(),
                  );
                case ToolCallFinished(:final call):
                  turn.settle(call);
                  state = state.copyWith(
                    statusMessage: state.statusMessage,
                    toolCalls: turn.snapshot(),
                  );
                case SourcesUpdated(:final sourceMap):
                  turn.sources = sourceMap;
                  pendingUpdate = true;
                case TextChunk(:final text):
                  final isFirstChunk = turn.text.isEmpty;
                  turn.text.write(text);
                  if (isFirstChunk) {
                    state = state.copyWith(
                      statusMessage: null,
                      streamingText: turn.text.toString(),
                      streamingSources: turn.sources,
                      toolCalls: turn.snapshot(),
                    );
                  } else {
                    pendingUpdate = true;
                  }
                case ArtifactCreated(:final artifact):
                  turn.artifacts.add(artifact);
                  state = state.copyWith(
                    statusMessage: state.statusMessage,
                    artifacts: turn.artifactSnapshot(),
                  );
                case ChatDone(:final fullAnswer, :final sources):
                  turn.text.clear();
                  turn.text.write(fullAnswer);
                  turn.sources = sources;
                  unawaited(_finish('complete'));
                case ChatError(:final error):
                  unawaited(_finish('failed', error: error));
              }
            },
            onError: (Object error) {
              if (_isCurrent(generation)) {
                unawaited(_finish('failed', error: error.toString()));
              }
            },
          );
    } catch (error) {
      if (_isCurrent(generation)) {
        await _finish('failed', error: error.toString());
      }
    }
  }

  Future<ChatArtifact> exportSectionsFromPanel(
    PaperDocument paper, {
    required String format,
  }) async {
    if (state.isStreaming) {
      throw StateError('Wait for the current response to finish first.');
    }
    if (!const {'markdown', 'json', 'both'}.contains(format)) {
      throw ArgumentError.value(format, 'format');
    }
    final collection = _ref.read(currentCollectionProvider);
    if (collection == null) throw StateError('No collection selected.');

    final generation = ++_generation;
    final runningCall = ToolCallRecord(
      id: 'panel-export-${const Uuid().v4()}',
      name: 'export_sections',
      arguments: {
        'documentId': paper.id,
        'paperTitle': paper.title,
        'format': format,
      },
    );
    state = ChatState(
      isStreaming: true,
      statusMessage: 'Preparing export review...',
      streamingText: '',
      toolCalls: [runningCall],
    );

    try {
      final storage = _ref.read(localStorageProvider);
      var chat = _ref.read(currentChatProvider);
      chat ??= await _ref
          .read(projectChatsProvider(collection.id).notifier)
          .createNewChat('Section export · ${paper.title}');
      if (!_isCurrent(generation)) throw StateError('Export was cancelled.');

      final label = switch (format) {
        'markdown' => 'Markdown',
        'json' => 'JSON',
        _ => 'Markdown and JSON',
      };
      final withRequest = chat.copyWith(
        updatedAt: DateTime.now().toUtc(),
        messages: [
          ...chat.messages,
          ChatMessage(
            id: 'msg_${const Uuid().v4()}',
            role: 'user',
            content: 'Export sections as $label',
            createdAt: DateTime.now().toUtc(),
          ),
        ],
      );
      await storage.saveChat(collection.id, withRequest);
      if (!_isCurrent(generation)) throw StateError('Export was cancelled.');
      _ref.read(currentChatProvider.notifier).state = withRequest;

      final turn = _ChatTurn(withRequest, 'Local export');
      turn.toolCalls.add(runningCall);
      _turn = turn;
      final started = DateTime.now();
      final revision = await storage.createExportReview(
        collectionId: collection.id,
        paper: paper,
      );
      if (!_isCurrent(generation)) throw StateError('Export was cancelled.');

      final artifact = ChatArtifact(
        id: 'draft_${revision.id}',
        type: 'sectionDraft',
        collectionId: collection.id,
        documentId: paper.id,
        title: paper.title,
        sectionCount: revision.sections.length,
        requestedFormat: format,
        revisionId: revision.id,
        parentRevisionId: revision.parentRevisionId,
        status: 'pending',
        createdAt: revision.createdAt,
      );
      turn.artifacts.add(artifact);
      turn.settle(
        runningCall.settled(
          ok: true,
          summary: 'Prepared ${paper.sections.length} sections for review',
          result: 'Pending revision: ${revision.id}',
          durationMs: DateTime.now().difference(started).inMilliseconds,
        ),
      );
      turn.text.write(
        'Đã tạo bản review cho ${paper.sections.length} section từ '
        '"${paper.title}". Hãy mở để kiểm tra, chỉnh tiếp bằng chat nếu cần, '
        'rồi bấm Save trên thẻ.',
      );
      state = state.copyWith(
        statusMessage: null,
        streamingText: turn.text.toString(),
        toolCalls: turn.snapshot(),
        artifacts: turn.artifactSnapshot(),
      );
      await _finish('complete');
      return artifact;
    } catch (error) {
      if (_isCurrent(generation)) {
        await _finish('failed', error: error.toString());
      }
      rethrow;
    }
  }

  Future<void> saveDraftRevision(ChatArtifact draft) async {
    final revisionId = draft.revisionId;
    if (revisionId == null || !_isPendingDraft(draft)) return;
    if (state.isStreaming) {
      throw StateError('Wait for the current response to finish first.');
    }
    final collection = _ref.read(currentCollectionProvider);
    if (collection == null) throw StateError('No collection selected.');
    final storage = _ref.read(localStorageProvider);
    final revision = await storage.loadRevision(
      collection.id,
      draft.documentId,
      revisionId,
    );
    if (revision == null) throw StateError('Draft revision was deleted.');

    // An untouched export review only writes files; no embeddings or API call needed.
    if (revision.createdBy == 'export_review') {
      state = const ChatState(
        isStreaming: true,
        statusMessage: 'Saving reviewed artifact...',
        streamingText: '',
      );
      try {
        final paper = await storage.loadPaper(collection.id, draft.documentId);
        if (paper == null) throw StateError('Source paper was deleted.');
        final savedRevision = revision.copyWith(
          status: 'saved',
          updatedAt: DateTime.now().toUtc(),
        );
        await storage.saveRevision(collection.id, savedRevision);
        final paths = await storage.saveSectionArtifacts(
          collection.id,
          paper,
          revision: savedRevision,
        );
        await _replaceArtifactInCurrentChat(
          draft.copyWith(
            type: 'sectionExport',
            status: 'saved',
            artifactId: paths.artifactId,
          ),
          appendMessage:
              'Bản export đã được lưu. Bạn có thể Open hoặc Download từ thẻ.',
        );
        state = const ChatState();
        return;
      } catch (error) {
        state = ChatState(errorMessage: 'Could not save export: $error');
        rethrow;
      }
    }

    final settings = _ref.read(settingsProvider);
    if (settings.openRouterApiKey.trim().isEmpty) {
      throw StateError('An OpenRouter API key is required to re-index edits.');
    }

    state = const ChatState(
      isStreaming: true,
      statusMessage: 'Saving revision and updating search index...',
      streamingText: '',
    );
    final embeddings = EmbeddingClient(
      apiKey: settings.openRouterApiKey,
      baseUrl: settings.openRouterBaseUrl,
      model: collection.embeddingProfile.model,
      dimensions: collection.embeddingProfile.dimensions,
    );
    try {
      final result = await _ref
          .read(paperRepositoryProvider(collection.id))
          .saveDraftRevision(
            documentId: draft.documentId,
            revisionId: revisionId,
            embeddings: embeddings,
          );
      final savedArtifact = draft.copyWith(
        type: 'sectionRevision',
        status: 'saved',
        artifactId: result.artifactId,
      );
      await _replaceArtifactInCurrentChat(
        savedArtifact,
        appendMessage:
            'Revision đã được lưu và index đã chuyển sang bản mới nhất.',
      );
      _ref.invalidate(activeRevisionProvider(draft.documentId));
      state = const ChatState();
    } catch (error) {
      await _replaceArtifactInCurrentChat(
        draft.copyWith(status: 'index_failed'),
        appendMessage: 'Revision đã được giữ lại nhưng cập nhật index thất bại. Bạn có thể thử lại.',
      );
      state = ChatState(errorMessage: 'Could not save revision: $error');
      rethrow;
    } finally {
      embeddings.close();
    }
  }

  Future<void> discardDraftRevision(ChatArtifact draft) async {
    final revisionId = draft.revisionId;
    if (revisionId == null || !_isPendingDraft(draft)) return;
    final collection = _ref.read(currentCollectionProvider);
    if (collection == null) return;
    await _ref
        .read(localStorageProvider)
        .deletePendingRevision(collection.id, draft.documentId, revisionId);
    await _replaceArtifactInCurrentChat(
      draft.copyWith(status: 'discarded'),
      appendMessage: 'Draft revision đã được bỏ.',
    );
  }

  Future<void> revertRevision(ChatArtifact artifact) async {
    final target = artifact.parentRevisionId;
    final collection = _ref.read(currentCollectionProvider);
    if (target == null || collection == null) return;
    state = const ChatState(
      isStreaming: true,
      statusMessage: 'Switching active revision...',
      streamingText: '',
    );
    try {
      await _ref
          .read(paperRepositoryProvider(collection.id))
          .revertToRevision(
            documentId: artifact.documentId,
            revisionId: target,
          );
      await _replaceArtifactInCurrentChat(
        artifact.copyWith(status: 'reverted'),
        appendMessage:
            'Đã quay lại revision trước. Retrieval từ bây giờ sẽ dùng bản này.',
      );
      _ref.invalidate(activeRevisionProvider(artifact.documentId));
      state = const ChatState();
    } catch (error) {
      state = ChatState(errorMessage: 'Could not revert revision: $error');
      rethrow;
    }
  }

  Future<void> _replaceArtifactInCurrentChat(
    ChatArtifact replacement, {
    required String appendMessage,
  }) async {
    final chat = _ref.read(currentChatProvider);
    if (chat == null) return;
    final updated = chat.copyWith(
      updatedAt: DateTime.now().toUtc(),
      messages: [
        for (final message in chat.messages)
          message.copyWith(
            artifacts: [
              for (final artifact in message.artifacts)
                if (artifact.id == replacement.id) replacement else artifact,
            ],
          ),
        ChatMessage(
          id: 'msg_${const Uuid().v4()}',
          role: 'assistant',
          content: appendMessage,
          createdAt: DateTime.now().toUtc(),
        ),
      ],
    );
    await _ref.read(localStorageProvider).saveChat(chat.collectionId, updated);
    _ref.read(currentChatProvider.notifier).state = updated;
    await _ref.read(projectChatsProvider(chat.collectionId).notifier).refresh();
  }

  Future<void> _finish(String status, {String? error}) async {
    // Detach the turn before awaiting so Stop, completion, and errors save it once.
    final turn = _turn;
    _turn = null;
    final generation = ++_generation;
    _releaseRequests();
    if (!mounted) return;
    // A turn that ran tools and then failed still has a record worth keeping,
    // so an empty answer is saved when there is tool activity behind it.
    if (turn != null && (turn.text.isNotEmpty || turn.toolCalls.isNotEmpty)) {
      final supersededRevisionIds = turn.artifacts
          .where(
            (artifact) =>
                _isPendingDraft(artifact) && artifact.parentRevisionId != null,
          )
          .map((artifact) => artifact.parentRevisionId!)
          .toSet();
      final updated = turn.chat.copyWith(
        updatedAt: DateTime.now().toUtc(),
        messages: [
          for (final message in turn.chat.messages)
            message.copyWith(
              artifacts: [
                for (final artifact in message.artifacts)
                  if (_isPendingDraft(artifact) &&
                      supersededRevisionIds.contains(artifact.revisionId))
                    artifact.copyWith(status: 'superseded')
                  else
                    artifact,
              ],
            ),
          ChatMessage(
            id: 'msg_${const Uuid().v4()}',
            role: 'assistant',
            status: status,
            content: turn.text.toString(),
            createdAt: DateTime.now().toUtc(),
            model: turn.model,
            citations: turn.sources.values.toList(growable: false),
            toolCalls: turn.snapshot(),
            artifacts: turn.artifactSnapshot(),
          ),
        ],
      );
      if (_ref.read(currentChatProvider)?.id == turn.chat.id) {
        _ref.read(currentChatProvider.notifier).state = updated;
      }
      try {
        await _ref
            .read(localStorageProvider)
            .saveChat(turn.chat.collectionId, updated);
        if (_isCurrent(generation)) {
          await _ref
              .read(projectChatsProvider(turn.chat.collectionId).notifier)
              .refresh();
        }
      } catch (saveError) {
        error = 'Answer could not be saved: $saveError';
      }
    }
    if (_isCurrent(generation)) state = ChatState(errorMessage: error);
  }

  static bool _isPendingDraft(ChatArtifact artifact) =>
      artifact.type == 'sectionDraft' || artifact.type == 'sectionChangeDraft';
}

class _ChatTurn {
  _ChatTurn(this.chat, this.model);
  final Chat chat;
  final String model;
  final text = StringBuffer();
  Map<String, Citation> sources = const {};
  final toolCalls = <ToolCallRecord>[];
  final artifacts = <ChatArtifact>[];

  /// Replaces the running record for a settled call, keeping its position in
  /// the log. An id the turn has not seen is appended rather than dropped.
  void settle(ToolCallRecord call) {
    final at = toolCalls.indexWhere((existing) => existing.id == call.id);
    if (at == -1) {
      toolCalls.add(call);
    } else {
      toolCalls[at] = call;
    }
  }

  /// A copy for the immutable state, so later mutations do not edit it in place.
  List<ToolCallRecord> snapshot() => List.unmodifiable(toolCalls);
  List<ChatArtifact> artifactSnapshot() => List.unmodifiable(artifacts);
}

final chatControllerProvider = StateNotifierProvider<ChatController, ChatState>(
  (ref) => ChatController(ref),
);
