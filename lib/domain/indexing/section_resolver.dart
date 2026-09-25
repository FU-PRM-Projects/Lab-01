import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/services/instruct_document_service.dart';
import 'package:lab_05/domain/indexing/document_transcript.dart';

/// Anchors outline headings in the transcript; each section spans to the next heading.
class SectionResolver {
  /// Name given to the text before the first reported heading — typically the
  /// title block, author list and affiliations.
  static const frontMatterName = 'Front Matter';

  /// Name of the single fallback section used when no heading could be
  /// anchored at all.
  static const wholeDocumentName = 'Document';

  static List<DocumentSection> resolve({
    required String documentId,
    required DocumentTranscript transcript,
    required List<SectionOutline> outlines,
  }) {
    final text = transcript.text;
    if (text.trim().isEmpty) return const [];

    final anchors = <_Anchor>[];
    for (final outline in outlines) {
      final heading = outline.rawHeading ?? outline.name;
      final offset = transcript.findHeading(heading, page: outline.page);
      anchors.add(
        _Anchor(
          offset: offset ?? transcript.startOfPage(outline.page),
          outline: outline,
        ),
      );
    }

    // Reading order is offset order. Sorting is stable, so two headings that
    // fall back to the same page start keep the model's ordering.
    anchors.sort((a, b) => a.offset.compareTo(b.offset));

    final ordered = <_Anchor>[];
    for (final anchor in anchors) {
      final previous = ordered.lastOrNull;
      // Drop headings that land before or on the previous one.
      if (previous != null && anchor.offset <= previous.offset) continue;
      ordered.add(anchor);
    }

    if (ordered.isEmpty) {
      return [
        _section(
          documentId: documentId,
          transcript: transcript,
          ordinal: 0,
          name: wholeDocumentName,
          rawHeading: null,
          level: 1,
          start: 0,
          end: text.length,
        ),
      ];
    }

    final sections = <DocumentSection>[];

    if (ordered.first.offset > 0) {
      sections.add(
        _section(
          documentId: documentId,
          transcript: transcript,
          ordinal: 0,
          name: frontMatterName,
          rawHeading: null,
          level: 1,
          start: 0,
          end: ordered.first.offset,
        ),
      );
    }

    for (var i = 0; i < ordered.length; i++) {
      final anchor = ordered[i];
      final end = i + 1 < ordered.length ? ordered[i + 1].offset : text.length;
      sections.add(
        _section(
          documentId: documentId,
          transcript: transcript,
          ordinal: sections.length,
          name: anchor.outline.name,
          rawHeading: anchor.outline.rawHeading,
          level: anchor.outline.level,
          start: anchor.offset,
          end: end,
        ),
      );
    }

    return sections;
  }

  static DocumentSection _section({
    required String documentId,
    required DocumentTranscript transcript,
    required int ordinal,
    required String name,
    required String? rawHeading,
    required int level,
    required int start,
    required int end,
  }) {
    final safeEnd = end.clamp(start, transcript.length);
    return DocumentSection(
      id: '$documentId:s$ordinal',
      ordinal: ordinal,
      name: name,
      rawHeading: rawHeading,
      level: level,
      kind: classifySection(name),
      startPage: transcript.pageForOffset(start),
      endPage: transcript.pageForOffset(safeEnd > start ? safeEnd - 1 : start),
      startChar: start,
      endChar: safeEnd,
      text: transcript.text.substring(start, safeEnd),
    );
  }
}

class _Anchor {
  final int offset;
  final SectionOutline outline;

  const _Anchor({required this.offset, required this.outline});
}
