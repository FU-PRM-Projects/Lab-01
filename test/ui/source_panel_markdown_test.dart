import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/app/providers.dart';
import 'package:lab_05/data/models/citation.dart';
import 'package:lab_05/data/services/local_storage.dart';
import 'package:lab_05/ui/sources/source_panel.dart';

void main() {
  const sampleExcerpt = '''<u>From RAG to Memory: Non-Parametric Continual Learning for Large Language Models</u>

els with this continual learning capacity. These approaches generally fall into three categories: continual fine-tuning, model editing, and RAG (Shi et al.,2024).

**Continual fine-tuning** involves periodically training an LLM on new data. This can be achieved through methods like continual pretraining (Jin et al.,2022), instruction tuning (Zhang et al.,2023), and alignment fine-tuning (Zhang et al.,2024).

## 2.2. Non-Parametric Continual Learning for LLMs

**Encoder model improvements** particularly with LLM backbones''';

  final citation = Citation(
    sourceId: 'p3',
    title: 'From RAG to Memory: Non-Parametric Continual Learning',
    fileName: 'paper.pdf',
    page: 3,
    section: 'Related Work',
    chunkId: 'c1',
    documentId: 'doc1',
    documentHash: 'hash123',
    startChar: 0,
    endChar: 500,
    excerpt: sampleExcerpt,
  );

  testWidgets(
    'SourcePanel renders excerpt in markdown by default and can toggle to raw text',
    (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('source_panel_test');
      addTearDown(() {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final storage = LocalStorage(rootDir: tempDir);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [localStorageProvider.overrideWithValue(storage)],
          child: MaterialApp(
            home: Scaffold(
              body: SourcePanel(citation: citation, onClose: () {}),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify MarkdownBody is present by default
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(
        find.textContaining('From RAG to Memory', findRichText: true),
        findsWidgets,
      );
      expect(
        find.textContaining(
          '2.2. Non-Parametric Continual Learning for LLMs',
          findRichText: true,
        ),
        findsOneWidget,
      );

      // Find the toggle button
      final toggleBtn = find.byTooltip('View raw text');
      expect(toggleBtn, findsOneWidget);

      // Tap toggle to raw text
      await tester.tap(toggleBtn);
      await tester.pumpAndSettle();

      // Now MarkdownBody should not be present, raw text view is active
      expect(find.byType(MarkdownBody), findsNothing);
      expect(find.byTooltip('View formatted markdown'), findsOneWidget);

      // Tap toggle back to markdown
      await tester.tap(find.byTooltip('View formatted markdown'));
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownBody), findsOneWidget);
    },
  );
}
