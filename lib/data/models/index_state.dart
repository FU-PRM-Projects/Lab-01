class IndexState {
  final int schemaVersion;
  final String status; // "clean" or "dirty" or "needsReindex"
  final String embeddingProfileId;
  final int dimensions;
  final int bitWidth;
  final int vectorCount;
  final Map<String, dynamic>? pending;

  const IndexState({
    this.schemaVersion = 1,
    this.status = 'clean',
    required this.embeddingProfileId,
    this.dimensions = 768,
    this.bitWidth = 4,
    this.vectorCount = 0,
    this.pending,
  });

  factory IndexState.fromJson(Map<String, dynamic> json) {
    return IndexState(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      status: json['status'] as String? ?? 'clean',
      embeddingProfileId: json['embeddingProfileId'] as String? ?? '',
      dimensions: json['dimensions'] as int? ?? 768,
      bitWidth: json['bitWidth'] as int? ?? 4,
      vectorCount: json['vectorCount'] as int? ?? 0,
      pending: json['pending'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'status': status,
      'embeddingProfileId': embeddingProfileId,
      'dimensions': dimensions,
      'bitWidth': bitWidth,
      'vectorCount': vectorCount,
      'pending': pending,
    };
  }
}
