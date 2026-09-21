import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/models/reference.dart';

enum DocumentStatus { processing, ready, failed, needsReindex, deleting }

DocumentStatus parseDocumentStatus(String? status) {
  return DocumentStatus.values
          .where((value) => value.name == status)
          .firstOrNull ??
      DocumentStatus.failed;
}

/// One retrievable passage, cut out of a [DocumentSection] by the chunker.
class PaperChunk {
  final String id;
  final int vectorId;
  final int page;
  final int ordinal;

  /// Display name of the section this passage was cut from.
  final String section;

  /// Id of that section, so a hit can open the whole section it came from.
  final String sectionId;

  /// Half-open span in the document transcript.
  final int startChar;
  final int endChar;
  final String text;

  /// Path to this chunk's image, relative to the document's figure directory,
  /// when the chunk is a figure rather than a text passage. Null for text.
  final String? imagePath;

  /// Media type of [imagePath], e.g. `image/png`.
  final String? imageMediaType;

  // Optional runtime context attached in-memory
  final String? documentId;
  final String? documentTitle;
  final String? documentFileName;

  const PaperChunk({
    required this.id,
    required this.vectorId,
    required this.page,
    required this.ordinal,
    required this.section,
    required this.startChar,
    required this.endChar,
    required this.text,
    this.sectionId = '',
    this.imagePath,
    this.imageMediaType,
    this.documentId,
    this.documentTitle,
    this.documentFileName,
  });

  String get parentDocId => documentId ?? id.split(':').first;

  /// Whether this chunk is a figure, and so should be sent to the model as an
  /// image rather than as text alone.
  bool get isFigure => imagePath != null;

  /// What is actually embedded. The section name is prepended so a passage
  /// carries the part of the paper it argues from — two otherwise similar
  /// paragraphs in Methodology and Related Work then embed apart.
  String get embeddingText =>
      section.trim().isEmpty ? text : '$section\n\n$text';

  PaperChunk copyWith({
    int? vectorId,
    int? ordinal,
    String? documentId,
    String? documentTitle,
    String? documentFileName,
  }) {
    return PaperChunk(
      id: id,
      vectorId: vectorId ?? this.vectorId,
      page: page,
      ordinal: ordinal ?? this.ordinal,
      section: section,
      sectionId: sectionId,
      startChar: startChar,
      endChar: endChar,
      text: text,
      imagePath: imagePath,
      imageMediaType: imageMediaType,
      documentId: documentId ?? this.documentId,
      documentTitle: documentTitle ?? this.documentTitle,
      documentFileName: documentFileName ?? this.documentFileName,
    );
  }

  factory PaperChunk.fromJson(
    Map<String, dynamic> json, {
    String? documentId,
    String? documentTitle,
    String? documentFileName,
  }) {
    return PaperChunk(
      documentId: documentId,
      documentTitle: documentTitle,
      documentFileName: documentFileName,
      id: json['id'] as String,
      vectorId: json['vectorId'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      ordinal: json['ordinal'] as int? ?? 0,
      section: json['section'] as String? ?? '',
      sectionId: json['sectionId'] as String? ?? '',
      startChar: json['startChar'] as int? ?? 0,
      endChar: json['endChar'] as int? ?? 0,
      text: json['text'] as String? ?? '',
      imagePath: json['imagePath'] as String?,
      imageMediaType: json['imageMediaType'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'vectorId': vectorId,
      'page': page,
      'ordinal': ordinal,
      'section': section,
      'sectionId': sectionId,
      'startChar': startChar,
      'endChar': endChar,
      'text': text,
      if (imagePath != null) 'imagePath': imagePath,
      if (imageMediaType != null) 'imageMediaType': imageMediaType,
    };
  }
}

class PaperDocument {
  /// Bumped to 2 when extraction moved to the transcription + instruct model
  /// pipeline, which added [sections] and changed chunk ids.
  static const currentSchemaVersion = 2;

  /// Bumped when the transcript itself would come out different.
  static const currentExtractionVersion = 2;

  /// Bumped when the same transcript would be cut into different chunks.
  static const currentChunkingVersion = 2;

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

  /// The paper's structure, in reading order. Together the sections hold the
  /// whole transcript, so the details view renders from them.
  final List<DocumentSection> sections;

  final List<PaperChunk> chunks;
  final List<PaperReference> references;

  const PaperDocument({
    this.schemaVersion = currentSchemaVersion,
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
    this.extractionVersion = currentExtractionVersion,
    this.chunkingVersion = currentChunkingVersion,
    this.sections = const [],
    this.chunks = const [],
    this.references = const [],
  });

  /// The bibliography section, when the paper has one.
  DocumentSection? get referencesSection =>
      sections.where((section) => section.isReferences).firstOrNull;

  /// True when this document predates the current pipeline and should be
  /// re-imported to gain sections.
  bool get isStale =>
      extractionVersion < currentExtractionVersion ||
      chunkingVersion < currentChunkingVersion;

  PaperDocument copyWith({
    DocumentStatus? status,
    String? error,
    List<DocumentSection>? sections,
    List<PaperChunk>? chunks,
    List<PaperReference>? references,
    String? title,
    List<String>? authors,
    int? pageCount,
  }) {
    return PaperDocument(
      schemaVersion: schemaVersion,
      id: id,
      fileName: fileName,
      title: title ?? this.title,
      authors: authors ?? this.authors,
      sha256: sha256,
      pageCount: pageCount ?? this.pageCount,
      status: status ?? this.status,
      error: error ?? this.error,
      createdAt: createdAt,
      embeddingProfileId: embeddingProfileId,
      extractionVersion: extractionVersion,
      chunkingVersion: chunkingVersion,
      sections: sections ?? this.sections,
      chunks: chunks ?? this.chunks,
      references: references ?? this.references,
    );
  }

  factory PaperDocument.fromJson(Map<String, dynamic> json) {
    final docId = json['id'] as String;
    final docTitle =
        json['title'] as String? ?? json['fileName'] as String? ?? 'Untitled';
    final docFileName = json['fileName'] as String? ?? '';

    final rawChunks = (json['chunks'] as List<dynamic>?) ?? [];
    final parsedChunks = rawChunks
        .map(
          (c) => PaperChunk.fromJson(
            c as Map<String, dynamic>,
            documentId: docId,
            documentTitle: docTitle,
            documentFileName: docFileName,
          ),
        )
        .toList(growable: false);

    final rawSections = (json['sections'] as List<dynamic>?) ?? [];
    final parsedSections = rawSections
        .whereType<Map<String, dynamic>>()
        .map(DocumentSection.fromJson)
        .toList(growable: false);

    final rawReferences = (json['references'] as List<dynamic>?) ?? [];
    final parsedReferences = rawReferences
        .whereType<Map<String, dynamic>>()
        .map(PaperReference.fromJson)
        .toList(growable: false);

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
      sections: parsedSections,
      chunks: parsedChunks,
      references: parsedReferences,
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
      'sections': sections.map((s) => s.toJson()).toList(),
      'chunks': chunks.map((c) => c.toJson()).toList(),
      'references': references.map((r) => r.toJson()).toList(),
    };
  }
}
