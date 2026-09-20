class AppSettings {
  final int schemaVersion;
  final String theme;

  /// Which backend answers chat turns: 'openrouter' (OpenAI-compatible,
  /// routed through OpenRouter) or 'gemini' (calls Google's Gemini API
  /// directly via [GeminiClient]). Embeddings always go through OpenRouter
  /// regardless of this setting.
  final String provider;
  final String chatModel;
  final String defaultEmbeddingModel;
  final int defaultEmbeddingDimensions;
  final String openRouterBaseUrl;
  final String openRouterApiKey;
  final String geminiApiKey;
  final String geminiModel;

  static const String defaultOpenRouterBaseUrl = 'https://openrouter.ai/api/v1';
  static const String defaultChatModel = 'deepseek/deepseek-v4.1-flash';
  static const String defaultProvider = 'openrouter';
  static const String defaultGeminiModel = 'gemini-2.5-flash';

  const AppSettings({
    this.schemaVersion = 1,
    this.theme = 'dark',
    this.provider = defaultProvider,
    this.chatModel = defaultChatModel,
    this.defaultEmbeddingModel = 'google/gemini-embedding-2',
    this.defaultEmbeddingDimensions = 768,
    this.openRouterBaseUrl = defaultOpenRouterBaseUrl,
    this.openRouterApiKey = '',
    this.geminiApiKey = '',
    this.geminiModel = defaultGeminiModel,
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
    String? provider,
    String? chatModel,
    String? defaultEmbeddingModel,
    int? defaultEmbeddingDimensions,
    String? openRouterBaseUrl,
    String? openRouterApiKey,
    String? geminiApiKey,
    String? geminiModel,
  }) {
    return AppSettings(
      schemaVersion: schemaVersion,
      theme: theme ?? this.theme,
      provider: provider ?? this.provider,
      chatModel: chatModel ?? this.chatModel,
      defaultEmbeddingModel:
          defaultEmbeddingModel ?? this.defaultEmbeddingModel,
      defaultEmbeddingDimensions:
          defaultEmbeddingDimensions ?? this.defaultEmbeddingDimensions,
      openRouterBaseUrl: openRouterBaseUrl ?? this.openRouterBaseUrl,
      openRouterApiKey: openRouterApiKey ?? this.openRouterApiKey,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      geminiModel: geminiModel ?? this.geminiModel,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      theme: json['theme'] as String? ?? 'dark',
      provider: json['provider'] as String? ?? defaultProvider,
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
      geminiApiKey: (json['geminiApiKey'] as String?)?.trim() ?? '',
      geminiModel: json['geminiModel'] as String? ?? defaultGeminiModel,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'theme': theme,
      'provider': provider,
      'chatModel': chatModel,
      'defaultEmbeddingModel': defaultEmbeddingModel,
      'defaultEmbeddingDimensions': defaultEmbeddingDimensions,
      'openRouterBaseUrl': openRouterBaseUrl,
      'openRouterApiKey': openRouterApiKey,
      'geminiApiKey': geminiApiKey,
      'geminiModel': geminiModel,
    };
  }
}
