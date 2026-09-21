/// What role a section plays in the paper. Drives indexing (the bibliography
/// is not embedded as prose) and display grouping.
enum SectionKind { frontMatter, body, references, appendix, backMatter }

SectionKind parseSectionKind(String? kind) {
  return SectionKind.values.where((value) => value.name == kind).firstOrNull ??
      SectionKind.body;
}

/// One section of a paper, resolved against the page transcripts so it owns a
/// concrete span of the document text.
///
/// Sections are the unit the details view renders; [PaperChunk]s are cut out of
/// them for retrieval, so every chunk can name the section it came from.
class DocumentSection {
  /// `<documentId>:s<ordinal>`.
  final String id;

  /// Position in reading order, 0-based.
  final int ordinal;

  /// Clean Title Case name with any leading numbering stripped.
  final String name;

  /// The heading exactly as printed in the paper, when there was one.
  final String? rawHeading;

  /// 1 for a top-level section, 2 for a subsection, and so on.
  final int level;

  final SectionKind kind;

  /// 1-based page range the section spans.
  final int startPage;
  final int endPage;

  /// Half-open span in the document transcript.
  final int startChar;
  final int endChar;

  /// The section body as Markdown, taken verbatim from the transcript.
  final String text;

  const DocumentSection({
    required this.id,
    required this.ordinal,
    required this.name,
    required this.kind,
    required this.startPage,
    required this.endPage,
    required this.startChar,
    required this.endChar,
    required this.text,
    this.rawHeading,
    this.level = 1,
  });

  bool get isReferences => kind == SectionKind.references;

  /// Numbered heading path for display, e.g. "Methodology" or "  3.2 Setup".
  String get displayName =>
      rawHeading?.trim().isNotEmpty == true ? rawHeading!.trim() : name;

  DocumentSection copyWith({
    int? endChar,
    int? endPage,
    String? text,
    int? ordinal,
    String? id,
  }) {
    return DocumentSection(
      id: id ?? this.id,
      ordinal: ordinal ?? this.ordinal,
      name: name,
      rawHeading: rawHeading,
      level: level,
      kind: kind,
      startPage: startPage,
      endPage: endPage ?? this.endPage,
      startChar: startChar,
      endChar: endChar ?? this.endChar,
      text: text ?? this.text,
    );
  }

  factory DocumentSection.fromJson(Map<String, dynamic> json) {
    return DocumentSection(
      id: json['id'] as String? ?? '',
      ordinal: (json['ordinal'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? 'Section',
      rawHeading: json['rawHeading'] as String?,
      level: (json['level'] as num?)?.toInt() ?? 1,
      kind: parseSectionKind(json['kind'] as String?),
      startPage: (json['startPage'] as num?)?.toInt() ?? 1,
      endPage: (json['endPage'] as num?)?.toInt() ?? 1,
      startChar: (json['startChar'] as num?)?.toInt() ?? 0,
      endChar: (json['endChar'] as num?)?.toInt() ?? 0,
      text: json['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ordinal': ordinal,
      'name': name,
      'rawHeading': rawHeading,
      'level': level,
      'kind': kind.name,
      'startPage': startPage,
      'endPage': endPage,
      'startChar': startChar,
      'endChar': endChar,
      'text': text,
    };
  }
}

/// Classifies a section name into the role it plays in the paper.
SectionKind classifySection(String name) {
  final normalized = name.toLowerCase().trim();
  if (RegExp(r'\b(references|bibliography|works\s+cited|literature\s+cited)\b')
      .hasMatch(normalized)) {
    return SectionKind.references;
  }
  if (normalized.startsWith('appendix') ||
      RegExp(r'^supplement(ary|al)?\b').hasMatch(normalized)) {
    return SectionKind.appendix;
  }
  if (RegExp(
    r'^(acknowledge?ments?|funding|author\s+contributions|'
    r'conflicts?\s+of\s+interest|ethics\s+statement|'
    r'data\s+availability)\b',
  ).hasMatch(normalized)) {
    return SectionKind.backMatter;
  }
  if (normalized == 'front matter' ||
      normalized == 'title' ||
      normalized == 'keywords') {
    return SectionKind.frontMatter;
  }
  return SectionKind.body;
}
