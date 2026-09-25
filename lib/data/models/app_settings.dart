class AppSettings {
  final int schemaVersion;
  final String theme;
  final String chatModel;

  /// Multimodal model that transcribes rendered PDF pages. Must accept image
  /// input; a text-only model cannot read a page image.
  final String transcriptionModel;

  /// Instruct model that reads the full transcript to extract outline and bibliography.
  final String indexingModel;

  /// Reasoning effort sent with the outline pass; empty to omit it.
  final String indexingReasoningEffort;

  /// Model that parses bibliography windows.
  final String referenceModel;

  /// Reasoning effort sent with the bibliography pass; empty to omit it.
  final String referenceReasoningEffort;

  /// Model the PDF parsing request is addressed to; its reply is discarded.
  final String ocrCarrierModel;

  final String defaultEmbeddingModel;
  final int defaultEmbeddingDimensions;
  final String openRouterBaseUrl;
  final String openRouterApiKey;
  final List<String> pinnedCollectionIds;

  static const String defaultOpenRouterBaseUrl = 'https://openrouter.ai/api/v1';
  static const String defaultChatModel = 'deepseek/deepseek-v4.1-flash';
  static const String defaultTranscriptionModel =
      'qwen/qwen3-vl-235b-a22b-instruct';
  static const String defaultIndexingModel = 'z-ai/glm-5.3-flashx';

  /// Reasoning budget for the outline pass.
  static const String defaultIndexingReasoningEffort = 'minimal';

  /// Small, fast model for the bibliography pass.
  static const String defaultReferenceModel = 'z-ai/glm-5.3-flashx';

  /// Reasoning budget for the bibliography pass (sent only if the model supports it).
  static const String defaultReferenceReasoningEffort = 'minimal';

  /// Cheap carrier model for the PDF `file-parser` request; its reply is discarded.
  static const String defaultOcrCarrierModel = 'google/gemini-2.5-flash-lite';

  const AppSettings({
    this.schemaVersion = 1,
    this.theme = 'dark',
    this.chatModel = defaultChatModel,
    this.transcriptionModel = defaultTranscriptionModel,
    this.indexingModel = defaultIndexingModel,
    this.indexingReasoningEffort = defaultIndexingReasoningEffort,
    this.referenceModel = defaultReferenceModel,
    this.referenceReasoningEffort = defaultReferenceReasoningEffort,
    this.ocrCarrierModel = defaultOcrCarrierModel,
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
    String? transcriptionModel,
    String? indexingModel,
    String? indexingReasoningEffort,
    String? referenceModel,
    String? referenceReasoningEffort,
    String? ocrCarrierModel,
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
      transcriptionModel: transcriptionModel ?? this.transcriptionModel,
      indexingModel: indexingModel ?? this.indexingModel,
      indexingReasoningEffort:
          indexingReasoningEffort ?? this.indexingReasoningEffort,
      referenceModel: referenceModel ?? this.referenceModel,
      referenceReasoningEffort:
          referenceReasoningEffort ?? this.referenceReasoningEffort,
      ocrCarrierModel: ocrCarrierModel ?? this.ocrCarrierModel,
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
      transcriptionModel:
          (json['transcriptionModel'] as String?)?.trim().isNotEmpty == true
          ? (json['transcriptionModel'] as String).trim()
          : defaultTranscriptionModel,
      indexingModel:
          (json['indexingModel'] as String?)?.trim().isNotEmpty == true
          ? (json['indexingModel'] as String).trim()
          : defaultIndexingModel,
      indexingReasoningEffort:
          (json['indexingReasoningEffort'] as String?)?.trim().isNotEmpty ==
              true
          ? (json['indexingReasoningEffort'] as String).trim()
          : defaultIndexingReasoningEffort,
      referenceModel:
          (json['referenceModel'] as String?)?.trim().isNotEmpty == true
          ? (json['referenceModel'] as String).trim()
          : defaultReferenceModel,
      referenceReasoningEffort:
          (json['referenceReasoningEffort'] as String?)?.trim().isNotEmpty ==
              true
          ? (json['referenceReasoningEffort'] as String).trim()
          : defaultReferenceReasoningEffort,
      ocrCarrierModel:
          (json['ocrCarrierModel'] as String?)?.trim().isNotEmpty == true
          ? (json['ocrCarrierModel'] as String).trim()
          : defaultOcrCarrierModel,
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
      'transcriptionModel': transcriptionModel,
      'indexingModel': indexingModel,
      'indexingReasoningEffort': indexingReasoningEffort,
      'referenceModel': referenceModel,
      'referenceReasoningEffort': referenceReasoningEffort,
      'ocrCarrierModel': ocrCarrierModel,
      'defaultEmbeddingModel': defaultEmbeddingModel,
      'defaultEmbeddingDimensions': defaultEmbeddingDimensions,
      'openRouterBaseUrl': openRouterBaseUrl,
      'openRouterApiKey': openRouterApiKey,
      'pinnedCollectionIds': pinnedCollectionIds,
    };
  }
}
