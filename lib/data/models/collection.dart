class EmbeddingProfile {
  final String id;
  final String model;
  final int dimensions;
  final int inputFormatVersion;
  final String normalization;

  const EmbeddingProfile({
    required this.id,
    this.model = 'google/gemini-embedding-2',
    this.dimensions = 768,
    this.inputFormatVersion = 1,
    this.normalization = 'l2',
  });

  factory EmbeddingProfile.fromJson(Map<String, dynamic> json) {
    return EmbeddingProfile(
      id: json['id'] as String? ?? 'default_profile',
      model: json['model'] as String? ?? 'google/gemini-embedding-2',
      dimensions: json['dimensions'] as int? ?? 768,
      inputFormatVersion: json['inputFormatVersion'] as int? ?? 1,
      normalization: json['normalization'] as String? ?? 'l2',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'model': model,
      'dimensions': dimensions,
      'inputFormatVersion': inputFormatVersion,
      'normalization': normalization,
    };
  }
}

class Collection {
  final int schemaVersion;
  final String id;
  final String name;
  final DateTime createdAt;
  final EmbeddingProfile embeddingProfile;

  const Collection({
    this.schemaVersion = 1,
    required this.id,
    required this.name,
    required this.createdAt,
    required this.embeddingProfile,
  });

  Collection copyWith({
    String? name,
    EmbeddingProfile? embeddingProfile,
  }) {
    return Collection(
      schemaVersion: schemaVersion,
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      embeddingProfile: embeddingProfile ?? this.embeddingProfile,
    );
  }

  factory Collection.fromJson(Map<String, dynamic> json) {
    return Collection(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      embeddingProfile: json['embeddingProfile'] != null
          ? EmbeddingProfile.fromJson(
              json['embeddingProfile'] as Map<String, dynamic>,
            )
          : const EmbeddingProfile(id: 'profile_default'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'id': id,
      'name': name,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'embeddingProfile': embeddingProfile.toJson(),
    };
  }
}
