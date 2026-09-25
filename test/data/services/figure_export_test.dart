import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/services/figure_export.dart';
import 'package:lab_05/data/services/local_storage.dart';

void main() {
  late Directory tempDir;
  late LocalStorage storage;
  late FigureExporter exporter;

  const collectionId = 'col_1';

  PaperChunk figureChunk(int ordinal, int page, String name, String caption) =>
      PaperChunk(
        id: 'doc_1:figure:$ordinal',
        vectorId: ordinal,
        page: page,
        ordinal: ordinal,
        section: 'Method',
        startChar: 0,
        endChar: 0,
        text: 'Method\n\n$caption',
        imagePath: name,
        imageMediaType: 'image/png',
      );

  final paper = PaperDocument(
    schemaVersion: 1,
    id: 'doc_1',
    fileName: 'attention.pdf',
    title: 'Attention Is All You Need!',
    sha256: 'hash',
    pageCount: 10,
    status: DocumentStatus.ready,
    createdAt: DateTime.utc(2026),
    embeddingProfileId: 'p1',
    chunks: [
      // Stored out of reading order on purpose.
      figureChunk(1, 5, 'fig_001.png', 'Figure 2: Attention heads.'),
      figureChunk(0, 3, 'fig_000.png', 'Figure 1: The Transformer.'),
      const PaperChunk(
        id: 'doc_1:text:0',
        vectorId: 9,
        page: 1,
        ordinal: 0,
        section: 'Abstract',
        startChar: 0,
        endChar: 10,
        text: 'Plain text',
      ),
    ],
  );

  void writeFigure(String name, List<int> bytes) {
    final file = File(storage.figurePath(collectionId, paper.id, name));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('figure_export_test');
    storage = LocalStorage(rootDir: tempDir);
    exporter = FigureExporter(storage);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('lists only figures, in reading order, with captions', () {
    final figures = exporter.figuresOf(collectionId, paper);

    expect(figures.map((f) => f.page), [3, 5]);
    expect(figures.map((f) => f.number), [1, 2]);
    expect(figures.first.caption, 'Figure 1: The Transformer.');
    expect(figures.first.extension, 'png');
  });

  test('file names say which paper, page and figure they came from', () {
    final figure = exporter.figuresOf(collectionId, paper).last;

    expect(
      FigureExporter.fileNameFor(paper.title, figure),
      'attention_is_all_you_need_p5_fig2.png',
    );
    expect(FigureExporter.slug('!!!'), 'paper');
  });

  test('exportAll copies every figure and writes figures.json', () async {
    writeFigure('fig_000.png', [1, 2, 3]);
    writeFigure('fig_001.png', [4, 5]);
    final target = Directory(p.join(tempDir.path, 'out'))..createSync();

    final result = await exporter.exportAll(
      collectionId: collectionId,
      paper: paper,
      target: target,
    );

    expect(result.exported, 2);
    expect(result.skipped, 0);
    expect(p.basename(result.directory), 'attention_is_all_you_need_figures');
    expect(
      File(
        p.join(result.directory, 'attention_is_all_you_need_p3_fig1.png'),
      ).readAsBytesSync(),
      [1, 2, 3],
    );

    final manifest =
        jsonDecode(
              File(p.join(result.directory, 'figures.json')).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(manifest['paper']['title'], paper.title);
    final entries = manifest['figures'] as List<dynamic>;
    expect(entries.map((e) => e['page']), [3, 5]);
    expect(entries.last['caption'], 'Figure 2: Attention heads.');
  });

  test('a missing image is skipped and a second export gets its own folder',
      () async {
    writeFigure('fig_000.png', [1]);
    final target = Directory(p.join(tempDir.path, 'out'))..createSync();

    final first = await exporter.exportAll(
      collectionId: collectionId,
      paper: paper,
      target: target,
    );
    final second = await exporter.exportAll(
      collectionId: collectionId,
      paper: paper,
      target: target,
    );

    expect(first.exported, 1);
    expect(first.skipped, 1);
    expect(second.directory, isNot(first.directory));
    expect(p.basename(second.directory), 'attention_is_all_you_need_figures_2');
  });
}
