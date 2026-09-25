import 'package:lab_05/data/models/document_section.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/domain/indexing/document_transcript.dart';

/// Splits resolved sections into overlapping retrieval chunks, never across sections.
/// Offsets are absolute in [DocumentTranscript.text].
class SectionChunker {
  /// Preferred chunk size. Chosen to sit comfortably inside embedding model
  /// context while still carrying a few paragraphs of argument.
  static const targetChars = 2400;

  /// A section at or below this length stays one chunk.
  static const ceilingChars = 3200;

  /// How much of the previous chunk the next one repeats.
  static const overlapChars = 300;

  /// How far either side of [targetChars] to hunt for a natural break.
  static const breakSearchChars = 400;

  /// Chunks shorter than this carry no retrievable content — a bare heading or
  /// a stray line — and are dropped.
  static const minChunkChars = 16;

  static final _sentenceEnd = RegExp(r'[.!?]["”’)]?\s');

  /// Chunks every section in reading order; skips the bibliography unless [indexReferences].
  static List<PaperChunk> chunk({
    required String documentId,
    required DocumentTranscript transcript,
    required List<DocumentSection> sections,
    bool indexReferences = false,
  }) {
    final chunks = <PaperChunk>[];
    var ordinal = 0;

    for (final section in sections) {
      if (section.isReferences && !indexReferences) continue;
      if (section.text.trim().isEmpty) continue;

      var chunkIndex = 0;
      for (final span in _spans(section.text)) {
        final start = section.startChar + span.start;
        final end = section.startChar + span.end;
        final text = transcript.text.substring(start, end);
        if (text.trim().length < minChunkChars) continue;

        chunks.add(
          PaperChunk(
            id: '$documentId:s${section.ordinal}:c$chunkIndex',
            vectorId: 0,
            page: transcript.pageForOffset(start),
            ordinal: ordinal,
            section: section.name,
            sectionId: section.id,
            startChar: start,
            endChar: end,
            text: text,
          ),
        );
        chunkIndex++;
        ordinal++;
      }
    }

    return chunks;
  }

  /// Splits [text] into overlapping half-open ranges.
  static List<({int start, int end})> _spans(String text) {
    final length = text.length;
    if (length <= ceilingChars) {
      return [(start: 0, end: length)];
    }

    final spans = <({int start, int end})>[];
    var start = 0;

    while (start < length) {
      final end = _breakAfter(text, start, length);
      spans.add((start: start, end: end));
      if (end >= length) break;

      var next = end - overlapChars;
      if (next <= start) {
        next = end;
      } else {
        // Start the overlap on a word boundary so a chunk never opens
        // mid-word.
        final space = text.indexOf(' ', next);
        if (space != -1 && space + 1 < end) next = space + 1;
      }
      start = next;
    }

    return spans;
  }

  /// Picks where the chunk starting at [start] should end.
  static int _breakAfter(String text, int start, int length) {
    final ideal = start + targetChars;
    if (ideal >= length) return length;

    final windowStart = (ideal - breakSearchChars).clamp(start + 1, length);
    final windowEnd = (ideal + breakSearchChars).clamp(windowStart, length);
    final window = text.substring(windowStart, windowEnd);

    final paragraph = window.lastIndexOf('\n\n');
    if (paragraph != -1) return windowStart + paragraph + 2;

    final sentence = _sentenceEnd.allMatches(window).lastOrNull;
    if (sentence != null) return windowStart + sentence.end;

    final space = window.lastIndexOf(' ');
    if (space != -1) return windowStart + space + 1;

    return ideal;
  }
}
