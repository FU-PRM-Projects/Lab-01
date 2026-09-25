import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/services/local_storage.dart';

/// One figure of a paper, as the gallery and the exporter see it.
class PaperFigure {
  const PaperFigure({
    required this.chunk,
    required this.number,
    required this.path,
  });

  /// The figure chunk the image was indexed as.
  final PaperChunk chunk;

  /// 1-based position among the paper's figures, in reading order.
  final int number;

  /// Absolute path of the image inside the app's data directory.
  final String path;

  int get page => chunk.page;
  String get section => chunk.section;

  /// The caption on its own. The chunk's text is the section heading and the
  /// caption joined for embedding, so the heading is taken back off here.
  String get caption {
    final text = chunk.text.trim();
    final heading = chunk.section.trim();
    if (heading.isNotEmpty && text.startsWith(heading)) {
      return text.substring(heading.length).trim();
    }
    return text;
  }

  String get extension {
    final ext = p.extension(path);
    return ext.isEmpty ? 'png' : ext.substring(1);
  }

  bool get exists => File(path).existsSync();
}

/// What [FigureExporter.exportAll] wrote.
class FigureExportResult {
  const FigureExportResult({
    required this.directory,
    required this.exported,
    required this.skipped,
  });

  /// The folder the images and `figures.json` were written to, or null when
  /// there was nothing to export and no folder was created.
  final String? directory;
  final int exported;

  /// Figures whose image file was missing from the data directory.
  final int skipped;
}

/// Lists a paper's figures and writes them out of the app's data directory.
class FigureExporter {
  const FigureExporter(this.storage);

  final LocalStorage storage;

  /// The paper's figures in reading order: by page, then position on the
  /// page.
  List<PaperFigure> figuresOf(String collectionId, PaperDocument paper) {
    final chunks = paper.chunks.where((c) => c.isFigure).toList()
      ..sort((a, b) {
        final byPage = a.page.compareTo(b.page);
        return byPage != 0 ? byPage : a.ordinal.compareTo(b.ordinal);
      });
    return [
      for (var i = 0; i < chunks.length; i++)
        PaperFigure(
          chunk: chunks[i],
          number: i + 1,
          path: storage.figurePath(collectionId, paper.id, chunks[i].imagePath!),
        ),
    ];
  }

  /// A readable file name such as `attention_is_all_you_need_p3_fig2.png`,
  /// so an exported image still says where it came from.
  static String fileNameFor(String paperTitle, PaperFigure figure) =>
      '${slug(paperTitle)}_p${figure.page}_fig${figure.number}'
      '.${figure.extension}';

  /// Lower-case ASCII letters and digits joined by underscores, at most 60
  /// characters, never empty.
  static String slug(String text) {
    final cleaned = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final short = cleaned.length > 60
        ? cleaned.substring(0, 60).replaceAll(RegExp(r'_+$'), '')
        : cleaned;
    return short.isEmpty ? 'paper' : short;
  }

  /// Copies all figures of [paper] into a new folder under [target] with a `figures.json` index.
  Future<FigureExportResult> exportAll({
    required String collectionId,
    required PaperDocument paper,
    required Directory target,
  }) async {
    final figures = figuresOf(collectionId, paper);
    final onDisk = [
      for (final figure in figures)
        if (await File(figure.path).exists()) figure,
    ];
    final skipped = figures.length - onDisk.length;
    // With no image to copy, a folder holding only figures.json would be
    // a misleading export, so none is created.
    if (onDisk.isEmpty) {
      return FigureExportResult(directory: null, exported: 0, skipped: skipped);
    }

    final dir = await _freshDirectory(target, '${slug(paper.title)}_figures');
    final entries = <Map<String, Object?>>[];

    for (final figure in onDisk) {
      final name = fileNameFor(paper.title, figure);
      await File(figure.path).copy(p.join(dir.path, name));
      entries.add({
        'file': name,
        'number': figure.number,
        'page': figure.page,
        'section': figure.section,
        'caption': figure.caption,
        'mediaType': figure.chunk.imageMediaType,
      });
    }

    final manifest = {
      'paper': {
        'title': paper.title,
        'authors': paper.authors,
        'fileName': paper.fileName,
        'pageCount': paper.pageCount,
      },
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'figures': entries,
    };
    await File(p.join(dir.path, 'figures.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );

    return FigureExportResult(
      directory: dir.path,
      exported: entries.length,
      skipped: skipped,
    );
  }

  /// A folder named [name] under [parent], suffixed `_2`, `_3`, ... if that
  /// name is taken, so an earlier export is never overwritten.
  static Future<Directory> _freshDirectory(Directory parent, String name) async {
    var candidate = Directory(p.join(parent.path, name));
    var n = 2;
    while (await candidate.exists()) {
      candidate = Directory(p.join(parent.path, '${name}_$n'));
      n++;
    }
    return candidate.create(recursive: true);
  }
}
