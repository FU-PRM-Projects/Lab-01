import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/models/paper.dart';

/// Section artifacts (JSON + Markdown) derived from one indexed paper, text kept verbatim.
class SectionArtifactBundle {
  final String markdown;
  final Map<String, dynamic> json;

  const SectionArtifactBundle({required this.markdown, required this.json});

  String get jsonText => const JsonEncoder.withIndent('  ').convert(json);
}

class SectionArtifactService {
  static const schemaVersion = 1;

  /// Removes YAML front matter for the in-app preview.
  static String readableMarkdown(String markdown) {
    final lines = markdown.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') return markdown;
    final closing = lines.indexWhere((line) => line.trim() == '---', 1);
    if (closing == -1) return markdown;
    return lines.skip(closing + 1).join('\n').trimLeft();
  }

  static SectionArtifactBundle build(
    PaperDocument paper, {
    String? revisionId,
    String? artifactId,
  }) {
    final sections = [...paper.sections]
      ..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    final enriched = _withHierarchy(sections);

    return SectionArtifactBundle(
      markdown: _markdown(
        paper,
        enriched,
        revisionId: revisionId,
        artifactId: artifactId,
      ),
      json: {
        'schemaVersion': schemaVersion,
        'artifactType': 'paper-sections',
        'documentId': paper.id,
        'revisionId': ?revisionId,
        'artifactId': ?artifactId,
        'sourceFile': paper.fileName,
        'sourceSha256': paper.sha256,
        'title': paper.title,
        'authors': paper.authors,
        'pageCount': paper.pageCount,
        'extractionVersion': paper.extractionVersion,
        'offsetUnit': 'utf16CodeUnit',
        'sections': [for (final entry in enriched) entry.json],
      },
    );
  }

  static List<_ExportSection> _withHierarchy(List<DocumentSection> sections) {
    final stack = <DocumentSection>[];
    final result = <_ExportSection>[];

    for (final section in sections) {
      while (stack.isNotEmpty && stack.last.level >= section.level) {
        stack.removeLast();
      }
      final parentId = stack.lastOrNull?.id;
      final path = [...stack.map((parent) => parent.name), section.name];
      result.add(
        _ExportSection(
          section: section,
          parentId: parentId,
          path: path,
          slug: _slug(section.name, section.ordinal),
          contentSha256: sha256.convert(utf8.encode(section.text)).toString(),
        ),
      );
      stack.add(section);
    }
    return result;
  }

  static String _markdown(
    PaperDocument paper,
    List<_ExportSection> sections, {
    String? revisionId,
    String? artifactId,
  }) {
    final out = StringBuffer()
      ..writeln('---')
      ..writeln('schema_version: $schemaVersion')
      ..writeln('artifact_type: "paper-sections"')
      ..writeln('document_id: ${jsonEncode(paper.id)}')
      ..writeln('revision_id: ${jsonEncode(revisionId)}')
      ..writeln('artifact_id: ${jsonEncode(artifactId)}')
      ..writeln('title: ${jsonEncode(paper.title)}')
      ..writeln('source_file: ${jsonEncode(paper.fileName)}')
      ..writeln('source_sha256: ${jsonEncode(paper.sha256)}')
      ..writeln('page_count: ${paper.pageCount}')
      ..writeln('extraction_version: ${paper.extractionVersion}')
      ..writeln('---');

    for (final entry in sections) {
      final section = entry.section;
      out
        ..writeln()
        ..writeln(
          '<!-- SECTION id=${jsonEncode(section.id)} '
          'level=${section.level} pages=${section.startPage}-${section.endPage} -->',
        )
        ..write(section.text.trim());
      if (section.text.trim().isNotEmpty) out.writeln();
    }
    return '${out.toString().trimRight()}\n';
  }

  static String _slug(String name, int ordinal) {
    final value = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return value.isEmpty ? 'section-${ordinal + 1}' : value;
  }
}

class _ExportSection {
  final DocumentSection section;
  final String? parentId;
  final List<String> path;
  final String slug;
  final String contentSha256;

  const _ExportSection({
    required this.section,
    required this.parentId,
    required this.path,
    required this.slug,
    required this.contentSha256,
  });

  Map<String, dynamic> get json => {
    ...section.toJson(),
    'slug': slug,
    'parentId': parentId,
    'path': path,
    'contentSha256': contentSha256,
  };
}
