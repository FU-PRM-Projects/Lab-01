class ChatArtifact {
  final String id;
  final String type;
  final String collectionId;
  final String documentId;
  final String title;
  final int sectionCount;
  final String requestedFormat;
  final String? artifactId;
  final String? revisionId;
  final String? parentRevisionId;
  final String? status;
  final DateTime createdAt;

  const ChatArtifact({
    required this.id,
    this.type = 'sectionExport',
    required this.collectionId,
    required this.documentId,
    required this.title,
    required this.sectionCount,
    this.requestedFormat = 'both',
    this.artifactId,
    this.revisionId,
    this.parentRevisionId,
    this.status,
    required this.createdAt,
  });

  factory ChatArtifact.fromJson(Map<String, dynamic> json) => ChatArtifact(
    id: json['id'] as String,
    type: json['type'] as String? ?? 'sectionExport',
    collectionId: json['collectionId'] as String,
    documentId: json['documentId'] as String,
    title: json['title'] as String? ?? 'Section export',
    sectionCount: json['sectionCount'] as int? ?? 0,
    requestedFormat: json['requestedFormat'] as String? ?? 'both',
    artifactId: json['artifactId'] as String?,
    revisionId: json['revisionId'] as String?,
    parentRevisionId: json['parentRevisionId'] as String?,
    status: json['status'] as String?,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'collectionId': collectionId,
    'documentId': documentId,
    'title': title,
    'sectionCount': sectionCount,
    'requestedFormat': requestedFormat,
    'artifactId': artifactId,
    'revisionId': revisionId,
    'parentRevisionId': parentRevisionId,
    'status': status,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  ChatArtifact copyWith({
    String? type,
    String? status,
    String? artifactId,
    String? requestedFormat,
  }) => ChatArtifact(
    id: id,
    type: type ?? this.type,
    collectionId: collectionId,
    documentId: documentId,
    title: title,
    sectionCount: sectionCount,
    requestedFormat: requestedFormat ?? this.requestedFormat,
    artifactId: artifactId ?? this.artifactId,
    revisionId: revisionId,
    parentRevisionId: parentRevisionId,
    status: status ?? this.status,
    createdAt: createdAt,
  );
}
