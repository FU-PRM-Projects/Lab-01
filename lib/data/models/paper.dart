enum DocumentStatus { processing, ready, failed, needsReindex, deleting }

DocumentStatus parseDocumentStatus(String? status) {
  return DocumentStatus.values
          .where((value) => value.name == status)
          .firstOrNull ??
      DocumentStatus.failed;
}

/// One indexed passage of a paper.
///
/// Chunks are not persisted in the paper's metadata JSON: the LanceDB table for
/// the collection is the only on-disk copy of their text and offsets. Instances
/// are either produced by the import pipeline or reconstructed from a store
/// query, so the document back-pointers are always populated in practice.
class PaperChunk {
  final String id;
  final int page;
  final int ordinal;
  final String section;
  final int startChar;
  final int endChar;
  final String text;

  // Optional runtime context attached in-memory
  final String? documentId;
  final String? documentTitle;
  final String? documentFileName;

  const PaperChunk({
    required this.id,
    required this.page,
    required this.ordinal,
    required this.section,
    required this.startChar,
    required this.endChar,
    required this.text,
    this.documentId,
    this.documentTitle,
    this.documentFileName,
  });

  String get parentDocId => documentId ?? id.split(':').first;
}

class PaperDocument {
  final int schemaVersion;
  final String id;
  final String fileName;
  final String title;
  final List<String> authors;
  final String sha256;
  final int pageCount;
  final DocumentStatus status;
  final String? error;
  final DateTime createdAt;
  final String embeddingProfileId;
  final int extractionVersion;
  final int chunkingVersion;

  const PaperDocument({
    this.schemaVersion = 1,
    required this.id,
    required this.fileName,
    required this.title,
    this.authors = const [],
    required this.sha256,
    required this.pageCount,
    required this.status,
    this.error,
    required this.createdAt,
    required this.embeddingProfileId,
    this.extractionVersion = 1,
    this.chunkingVersion = 1,
  });

  PaperDocument copyWith({
    DocumentStatus? status,
    String? error,
    String? title,
    int? pageCount,
  }) {
    return PaperDocument(
      schemaVersion: schemaVersion,
      id: id,
      fileName: fileName,
      title: title ?? this.title,
      authors: authors,
      sha256: sha256,
      pageCount: pageCount ?? this.pageCount,
      status: status ?? this.status,
      error: error ?? this.error,
      createdAt: createdAt,
      embeddingProfileId: embeddingProfileId,
      extractionVersion: extractionVersion,
      chunkingVersion: chunkingVersion,
    );
  }

  /// Unknown keys are ignored, so metadata written before chunks moved into the
  /// vector store still parses.
  factory PaperDocument.fromJson(Map<String, dynamic> json) {
    final docId = json['id'] as String;
    final docTitle =
        json['title'] as String? ?? json['fileName'] as String? ?? 'Untitled';
    final docFileName = json['fileName'] as String? ?? '';

    return PaperDocument(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      id: docId,
      fileName: docFileName,
      title: docTitle,
      authors:
          (json['authors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      sha256: json['sha256'] as String? ?? '',
      pageCount: json['pageCount'] as int? ?? 0,
      status: parseDocumentStatus(json['status'] as String?),
      error: json['error'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      embeddingProfileId: json['embeddingProfileId'] as String? ?? '',
      extractionVersion: json['extractionVersion'] as int? ?? 1,
      chunkingVersion: json['chunkingVersion'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'id': id,
      'fileName': fileName,
      'title': title,
      'authors': authors,
      'sha256': sha256,
      'pageCount': pageCount,
      'status': status.name,
      'error': error,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'embeddingProfileId': embeddingProfileId,
      'extractionVersion': extractionVersion,
      'chunkingVersion': chunkingVersion,
    };
  }
}
