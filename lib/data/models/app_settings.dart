class AppSettings {
  final int schemaVersion;
  final String theme;
  final String chatModel;
  final String defaultEmbeddingModel;
  final int defaultEmbeddingDimensions;
  final String openRouterBaseUrl;
  final String openRouterApiKey;
  final List<String> pinnedCollectionIds;

  static const String defaultOpenRouterBaseUrl = 'https://openrouter.ai/api/v1';
  static const String defaultChatModel = 'deepseek/deepseek-v4.1-flash';

  const AppSettings({
    this.schemaVersion = 1,
    this.theme = 'dark',
    this.chatModel = defaultChatModel,
    this.defaultEmbeddingModel = 'google/gemini-embedding-2',
    this.defaultEmbeddingDimensions = 768,
    this.openRouterBaseUrl = defaultOpenRouterBaseUrl,
    this.openRouterApiKey = '',
    this.pinnedCollectionIds = const [],
  });

  String get apiBaseUrl {
    final base = openRouterBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return (base.isEmpty ? defaultOpenRouterBaseUrl : base).replaceFirst(
      RegExp(r'/(chat/completions|embeddings)$'),
      '',
    );
  }

  String get chatCompletionsUrl => '$apiBaseUrl/chat/completions';
  String get embeddingsUrl => '$apiBaseUrl/embeddings';

  AppSettings copyWith({
    String? theme,
    String? chatModel,
    String? defaultEmbeddingModel,
    int? defaultEmbeddingDimensions,
    String? openRouterBaseUrl,
    String? openRouterApiKey,
    List<String>? pinnedCollectionIds,
  }) {
    return AppSettings(
      schemaVersion: schemaVersion,
      theme: theme ?? this.theme,
      chatModel: chatModel ?? this.chatModel,
      defaultEmbeddingModel:
          defaultEmbeddingModel ?? this.defaultEmbeddingModel,
      defaultEmbeddingDimensions:
          defaultEmbeddingDimensions ?? this.defaultEmbeddingDimensions,
      openRouterBaseUrl: openRouterBaseUrl ?? this.openRouterBaseUrl,
      openRouterApiKey: openRouterApiKey ?? this.openRouterApiKey,
      pinnedCollectionIds: pinnedCollectionIds ?? this.pinnedCollectionIds,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      theme: json['theme'] as String? ?? 'dark',
      chatModel: json['chatModel'] as String? ?? defaultChatModel,
      defaultEmbeddingModel:
          json['defaultEmbeddingModel'] as String? ??
          'google/gemini-embedding-2',
      defaultEmbeddingDimensions:
          json['defaultEmbeddingDimensions'] as int? ?? 768,
      openRouterBaseUrl:
          (json['openRouterBaseUrl'] as String?)?.trim().isNotEmpty == true
          ? (json['openRouterBaseUrl'] as String).trim()
          : (json['baseUrl'] as String?)?.trim().isNotEmpty == true
          ? (json['baseUrl'] as String).trim()
          : defaultOpenRouterBaseUrl,
      openRouterApiKey:
          (json['openRouterApiKey'] as String?)?.trim() ??
          (json['apiKey'] as String?)?.trim() ??
          '',
      pinnedCollectionIds:
          (json['pinnedCollectionIds'] as List<dynamic>?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'theme': theme,
      'chatModel': chatModel,
      'defaultEmbeddingModel': defaultEmbeddingModel,
      'defaultEmbeddingDimensions': defaultEmbeddingDimensions,
      'openRouterBaseUrl': openRouterBaseUrl,
      'openRouterApiKey': openRouterApiKey,
      'pinnedCollectionIds': pinnedCollectionIds,
    };
  }
}
