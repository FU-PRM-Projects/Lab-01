import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/chat.dart';
import 'package:lab_05/data/models/citation.dart';
import 'package:lab_05/data/services/embedding_client.dart';
import 'package:lab_05/domain/research_agent.dart';

class ChatState {
  final bool isStreaming;
  final String? statusMessage;
  final String? streamingText;
  final Map<String, Citation> streamingSources;
  final String? errorMessage;

  const ChatState({
    this.isStreaming = false,
    this.statusMessage,
    this.streamingText,
    this.streamingSources = const {},
    this.errorMessage,
  });

  ChatState copyWith({
    bool? isStreaming,
    String? statusMessage,
    String? streamingText,
    Map<String, Citation>? streamingSources,
    String? errorMessage,
  }) {
    return ChatState(
      isStreaming: isStreaming ?? this.isStreaming,
      statusMessage: statusMessage,
      streamingText: streamingText ?? this.streamingText,
      streamingSources: streamingSources ?? this.streamingSources,
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
    final usingGemini = settings.provider == 'gemini';
    // Embeddings always go through OpenRouter, so that key is required
    // regardless of which provider answers the chat turn.
    final missingOpenRouterKey = settings.openRouterApiKey.trim().isEmpty;
    final missingChatKey = usingGemini
        ? settings.geminiApiKey.trim().isEmpty
        : missingOpenRouterKey;
    if (collection == null || missingOpenRouterKey || missingChatKey) {
      state = ChatState(
        errorMessage: collection == null
            ? 'Please select or create a collection first'
            : missingOpenRouterKey
            ? 'Please enter your OpenRouter API Key in Settings'
            : 'Please enter your Gemini API Key in Settings',
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
      final history = chat.messages
          .map((message) => {'role': message.role, 'content': message.content})
          .toList();
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
      final turn = _ChatTurn(
        updated,
        usingGemini ? settings.geminiModel : settings.chatModel,
      );
      _turn = turn;
      unawaited(
        _ref
            .read(projectChatsProvider(collection.id).notifier)
            .refresh(),
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
        apiKey: usingGemini ? settings.geminiApiKey : settings.openRouterApiKey,
        chatModel: usingGemini ? settings.geminiModel : settings.chatModel,
        baseUrl: settings.openRouterBaseUrl,
        storage: storage,
        embeddings: embeddings,
        index: index,
        provider: settings.provider,
      );
      _agent = agent;
      var pendingUpdate = false;
      _timer = Timer.periodic(const Duration(milliseconds: 45), (_) {
        if (_isCurrent(generation) && pendingUpdate) {
          state = state.copyWith(
            streamingText: turn.text.toString(),
            streamingSources: turn.sources,
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
                    );
                  } else {
                    pendingUpdate = true;
                  }
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

  Future<void> _finish(String status, {String? error}) async {
    // Detach the turn before awaiting so Stop, completion, and errors save it once.
    final turn = _turn;
    _turn = null;
    final generation = ++_generation;
    _releaseRequests();
    if (!mounted) return;
    if (turn != null && turn.text.isNotEmpty) {
      final updated = turn.chat.copyWith(
        updatedAt: DateTime.now().toUtc(),
        messages: [
          ...turn.chat.messages,
          ChatMessage(
            id: 'msg_${const Uuid().v4()}',
            role: 'assistant',
            status: status,
            content: turn.text.toString(),
            createdAt: DateTime.now().toUtc(),
            model: turn.model,
            citations: turn.sources.values.toList(growable: false),
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
}

class _ChatTurn {
  _ChatTurn(this.chat, this.model);
  final Chat chat;
  final String model;
  final text = StringBuffer();
  Map<String, Citation> sources = const {};
}

final chatControllerProvider = StateNotifierProvider<ChatController, ChatState>(
  (ref) => ChatController(ref),
);
