class Citation {
  final String sourceId;
  final String documentId;
  final String documentHash;
  final String fileName;
  final String title;
  final int page;
  final String section;
  final String chunkId;
  final int extractionVersion;
  final int startChar;
  final int endChar;
  final String excerpt;

  const Citation({
    required this.sourceId,
    required this.documentId,
    required this.documentHash,
    required this.fileName,
    required this.title,
    required this.page,
    required this.section,
    required this.chunkId,
    this.extractionVersion = 1,
    required this.startChar,
    required this.endChar,
    required this.excerpt,
  });

  factory Citation.fromJson(Map<String, dynamic> json) {
    return Citation(
      sourceId: json['sourceId'] as String? ?? '',
      documentId: json['documentId'] as String? ?? '',
      documentHash: json['documentHash'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      title: json['title'] as String? ?? '',
      page: json['page'] as int? ?? 1,
      section: json['section'] as String? ?? '',
      chunkId: json['chunkId'] as String? ?? '',
      extractionVersion: json['extractionVersion'] as int? ?? 1,
      startChar: json['startChar'] as int? ?? 0,
      endChar: json['endChar'] as int? ?? 0,
      excerpt: json['excerpt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sourceId': sourceId,
      'documentId': documentId,
      'documentHash': documentHash,
      'fileName': fileName,
      'title': title,
      'page': page,
      'section': section,
      'chunkId': chunkId,
      'extractionVersion': extractionVersion,
      'startChar': startChar,
      'endChar': endChar,
      'excerpt': excerpt,
    };
  }
}
