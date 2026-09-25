import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/models/paper.dart';

class SectionRevision {
  final int schemaVersion;
  final String id;
  final String documentId;
  final String? parentRevisionId;
  final String status;
  final String indexStatus;
  final String createdBy;
  final String? instruction;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<DocumentSection> sections;
  final List<PaperChunk> chunks;

  const SectionRevision({
    this.schemaVersion = 1,
    required this.id,
    required this.documentId,
    this.parentRevisionId,
    required this.status,
    required this.indexStatus,
    required this.createdBy,
    this.instruction,
    required this.createdAt,
    required this.updatedAt,
    required this.sections,
    this.chunks = const [],
  });

  bool get isPending => status == 'pending';
  bool get isIndexed => indexStatus == 'indexed';

  SectionRevision copyWith({
    String? status,
    String? indexStatus,
    DateTime? updatedAt,
    List<DocumentSection>? sections,
    List<PaperChunk>? chunks,
  }) => SectionRevision(
    schemaVersion: schemaVersion,
    id: id,
    documentId: documentId,
    parentRevisionId: parentRevisionId,
    status: status ?? this.status,
    indexStatus: indexStatus ?? this.indexStatus,
    createdBy: createdBy,
    instruction: instruction,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    sections: sections ?? this.sections,
    chunks: chunks ?? this.chunks,
  );

  factory SectionRevision.fromJson(Map<String, dynamic> json) {
    final documentId = json['documentId'] as String;
    return SectionRevision(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      id: json['id'] as String,
      documentId: documentId,
      parentRevisionId: json['parentRevisionId'] as String?,
      status: json['status'] as String? ?? 'pending',
      indexStatus: json['indexStatus'] as String? ?? 'pending',
      createdBy: json['createdBy'] as String? ?? 'ai_edit',
      instruction: json['instruction'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      sections: ((json['sections'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(DocumentSection.fromJson)
          .toList(growable: false),
      chunks: ((json['chunks'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map((value) => PaperChunk.fromJson(value, documentId: documentId))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'documentId': documentId,
    'parentRevisionId': parentRevisionId,
    'status': status,
    'indexStatus': indexStatus,
    'createdBy': createdBy,
    'instruction': instruction,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'sections': sections.map((section) => section.toJson()).toList(),
    'chunks': chunks.map((chunk) => chunk.toJson()).toList(),
  };
}

class RevisionManifest {
  final String documentId;
  final String originalRevisionId;
  final String currentRevisionId;

  const RevisionManifest({
    required this.documentId,
    required this.originalRevisionId,
    required this.currentRevisionId,
  });

  factory RevisionManifest.fromJson(Map<String, dynamic> json) =>
      RevisionManifest(
        documentId: json['documentId'] as String,
        originalRevisionId: json['originalRevisionId'] as String,
        currentRevisionId: json['currentRevisionId'] as String,
      );

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'documentId': documentId,
    'originalRevisionId': originalRevisionId,
    'currentRevisionId': currentRevisionId,
  };
}
