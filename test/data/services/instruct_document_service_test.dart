import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lab_05/data/models/app_settings.dart';
import 'package:lab_05/data/services/instruct_document_service.dart';

const _settings = AppSettings(
  openRouterApiKey: 'test-key',
  chatModel: 'test/model',
);

http.Response completionOf(Object content, {String finishReason = 'stop'}) {
  return http.Response(
    jsonEncode({
      'choices': [
        {
          'finish_reason': finishReason,
          'message': {'content': content},
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  group('InstructDocumentService.parseOutline', () {
    test('parses title, authors and the heading outline', () {
      const raw = '''
{
  "title": "Attention Is All You Need",
  "authors": ["Ashish Vaswani", "Noam Shazeer"],
  "sections": [
    {"name": "Abstract", "rawHeading": "Abstract", "page": 1, "level": 1},
    {"name": "Threat Model", "rawHeading": "3.2 Threat Model", "page": 4, "level": 2}
  ]
}''';

      final outline = InstructDocumentService.parseOutline(raw);

      expect(outline.title, 'Attention Is All You Need');
      expect(outline.authors, ['Ashish Vaswani', 'Noam Shazeer']);
      expect(outline.sections, hasLength(2));
      expect(outline.sections[1].rawHeading, '3.2 Threat Model');
      expect(outline.sections[1].level, 2);
      expect(outline.sections[1].page, 4);
    });

    test('unwraps a fenced JSON block', () {
      final outline = InstructDocumentService.parseOutline(
        '```json\n{"title": "T", "sections": []}\n```',
      );
      expect(outline.title, 'T');
      expect(outline.sections, isEmpty);
    });

    test('defaults missing fields instead of throwing', () {
      final outline = InstructDocumentService.parseOutline('{}');
      expect(outline.title, isNull);
      expect(outline.authors, isEmpty);
      expect(outline.sections, isEmpty);
    });

    test('throws on empty or non-JSON output', () {
      expect(
        () => InstructDocumentService.parseOutline('   '),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => InstructDocumentService.parseOutline('I could not read that.'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('InstructDocumentService.parseReferences', () {
    test('parses entries with their identifier fields', () {
      final references = InstructDocumentService.parseReferences('''
{
  "references": [
    {
      "marker": "[1]",
      "raw": "Author A. A Paper. NeurIPS, 2020. doi:10.1000/182",
      "authors": "Author A",
      "title": "A Paper",
      "venue": "NeurIPS",
      "year": 2020,
      "doi": "10.1000/182",
      "arxivId": null,
      "url": null
    }
  ]
}''');

      final reference = references.single;
      expect(reference.marker, '[1]');
      expect(reference.venue, 'NeurIPS');
      expect(reference.doi, '10.1000/182');
      expect(reference.arxivId, isNull);
      expect(reference.resolvedUrl, 'https://doi.org/10.1000/182');
    });

    test('treats "null" and blank identifier strings as missing', () {
      final references = InstructDocumentService.parseReferences(
        '{"references": [{"raw": "Entry", "doi": "null", "arxivId": "", '
        '"url": "  "}]}',
      );
      expect(references.single.doi, isNull);
      expect(references.single.arxivId, isNull);
      expect(references.single.url, isNull);
    });

    test('numbers entries within the window', () {
      final references = InstructDocumentService.parseReferences(
        '{"references": [{"raw": "First"}, {"raw": "Second"}]}',
      );
      expect(references.map((r) => r.index), [1, 2]);
    });
  });

  group('InstructDocumentService.splitBibliography', () {
    test('keeps a short list in one window', () {
      final windows = InstructDocumentService.splitBibliography(
        '[1] First entry.\n[2] Second entry.',
      );
      expect(windows, hasLength(1));
    });

    test('splits a long list at line ends, never mid-entry', () {
      final entries = List.generate(
        400,
        (i) => '[${i + 1}] Author $i. A Paper Titled Something. Venue, 2020.',
      );
      final windows = InstructDocumentService.splitBibliography(
        entries.join('\n'),
      );

      expect(windows.length, greaterThan(1));
      for (final window in windows) {
        expect(
          window.length,
          lessThanOrEqualTo(InstructDocumentService.bibliographyWindowChars),
        );
        for (final line in window.split('\n')) {
          expect(entries, contains(line));
        }
      }
      // Every entry survives the split exactly once.
      expect(windows.expand((w) => w.split('\n')).toList(), entries);
    });

    test('an empty bibliography yields no windows', () {
      expect(InstructDocumentService.splitBibliography('   '), isEmpty);
    });
  });

  group('InstructDocumentService.analyzeOutline', () {
    test('posts the transcript and parses the reply', () async {
      late Map<String, dynamic> sentBody;
      final service = InstructDocumentService(
        settings: _settings,
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return completionOf(
            '{"title": "Paper", "sections": [{"name": "Introduction", '
            '"rawHeading": "1 Introduction", "page": 1}]}',
          );
        }),
      );
      addTearDown(service.close);

      final outline = await service.analyzeOutline(
        '<!-- PAGE 1 -->\n1 Introduction\nText.',
        modelId: 'test/model',
      );

      expect(sentBody['model'], 'test/model');
      expect(sentBody['temperature'], 0);
      expect(sentBody['response_format'], {'type': 'json_object'});
      final messages = sentBody['messages'] as List<dynamic>;
      expect(messages.first['role'], 'system');
      expect(messages.last['content'], contains('<!-- PAGE 1 -->'));

      expect(outline.title, 'Paper');
      expect(outline.sections.single.name, 'Introduction');
    });

    test('names truncation as the cause instead of a parse error', () async {
      final service = InstructDocumentService(
        settings: _settings,
        client: MockClient(
          // A cut-off object, exactly as the provider returns it.
          (_) async => completionOf(
            '{"title": "Paper", "sections": [{"name": "Intro',
            finishReason: 'length',
          ),
        ),
      );
      addTearDown(service.close);

      await expectLater(
        service.analyzeOutline('text', modelId: 'test/model'),
        throwsA(
          isA<InstructTruncatedException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('output limit'), contains('outline')),
          ),
        ),
      );
    });

    test(
      'throws on a non-200 response, keeping the provider message',
      () async {
        final service = InstructDocumentService(
          settings: _settings,
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': {'message': 'Insufficient credits'},
              }),
              402,
            ),
          ),
        );
        addTearDown(service.close);

        await expectLater(
          service.analyzeOutline('text', modelId: 'test/model'),
          throwsA(
            isA<HttpException>().having(
              (e) => e.message,
              'message',
              allOf(contains('402'), contains('Insufficient credits')),
            ),
          ),
        );
      },
    );

    test('throws when the API key is missing', () async {
      final service = InstructDocumentService(
        settings: const AppSettings(),
        client: MockClient((_) async => completionOf('{}')),
      );
      addTearDown(service.close);

      await expectLater(
        service.analyzeOutline('text', modelId: 'test/model'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('InstructDocumentService.extractReferences', () {
    test('walks every window and numbers entries across them', () async {
      final sent = <String>[];
      final service = InstructDocumentService(
        settings: _settings,
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final content = (body['messages'] as List).last['content'] as String;
          sent.add(content);
          // Two entries per window, always numbered from 1 by the model.
          return completionOf(
            '{"references": [{"marker": "[1]", "raw": "Entry A"}, '
            '{"marker": "[2]", "raw": "Entry B"}]}',
          );
        }),
      );
      addTearDown(service.close);

      final bibliography = List.generate(
        400,
        (i) => '[${i + 1}] Author $i. A Paper Titled Something. Venue, 2020.',
      ).join('\n');

      final progress = <String>[];
      final references = await service.extractReferences(
        bibliography,
        modelId: 'test/model',
        onProgress: (done, count) => progress.add('$done/$count'),
      );

      expect(sent.length, greaterThan(1));
      // Progress counts finished windows: it opens at 0 so the stage label
      // appears before the first window returns, and closes at the total.
      expect(progress.length, sent.length + 1);
      expect(progress.first, '0/${sent.length}');
      expect(progress.last, '${sent.length}/${sent.length}');
      // Indices continue across windows rather than restarting at 1.
      expect(
        references.map((r) => r.index),
        List.generate(references.length, (i) => i + 1),
      );
      expect(references.length, sent.length * 2);
    });

    test('halves a window and retries when the model truncates', () async {
      final sentLengths = <int>[];
      final service = InstructDocumentService(
        settings: _settings,
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final content = (body['messages'] as List).last['content'] as String;
          sentLengths.add(content.length);

          // The first, full-size window truncates; the smaller halves succeed.
          if (content.length > 400) {
            return completionOf(
              '{"references": [{"marker": "',
              finishReason: 'length',
            );
          }
          return completionOf('{"references": [{"raw": "An entry."}]}');
        }),
      );
      addTearDown(service.close);

      final references = await service.extractReferences(
        List.generate(
          12,
          (i) => '[${i + 1}] Author $i. A Paper Titled Something. Venue, 2020.',
        ).join('\n'),
        modelId: 'test/model',
      );

      // It retried with smaller inputs instead of failing the import.
      expect(sentLengths.first, greaterThan(sentLengths.last));
      expect(references, isNotEmpty);
      expect(
        references.map((r) => r.index),
        List.generate(references.length, (i) => i + 1),
      );
    });

    test('retries unparseable JSON the same way', () async {
      var calls = 0;
      final service = InstructDocumentService(
        settings: _settings,
        client: MockClient((request) async {
          calls++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final content = (body['messages'] as List).last['content'] as String;
          if (content.length > 400) {
            return completionOf('Sorry, I cannot help with that.');
          }
          return completionOf('{"references": [{"raw": "An entry."}]}');
        }),
      );
      addTearDown(service.close);

      final references = await service.extractReferences(
        List.generate(
          12,
          (i) => '[${i + 1}] Author $i. A Paper Titled Something. Venue, 2020.',
        ).join('\n'),
        modelId: 'test/model',
      );

      expect(calls, greaterThan(1));
      expect(references, isNotEmpty);
    });

    test('gives up rather than retrying forever', () async {
      var calls = 0;
      final service = InstructDocumentService(
        settings: _settings,
        client: MockClient((_) async {
          calls++;
          return completionOf(
            '{"references": [{"marker": "',
            finishReason: 'length',
          );
        }),
      );
      addTearDown(service.close);

      await expectLater(
        service.extractReferences(
          List.generate(
            40,
            (i) =>
                '[${i + 1}] Author $i. A Paper Titled Something. Venue, 2020.',
          ).join('\n'),
          modelId: 'test/model',
        ),
        throwsA(isA<InstructTruncatedException>()),
      );
      // Bounded by maxBibliographyRetries rather than looping.
      expect(calls, lessThan(20));
    });

    test('halves a window and retries when the model truncates', () async {
      final sentLengths = <int>[];
      final service = InstructDocumentService(
        settings: _settings,
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final content = (body['messages'] as List).last['content'] as String;
          sentLengths.add(content.length);

          // The first, full-size window truncates; the smaller halves succeed.
          if (content.length > 400) {
            return completionOf(
              '{"references": [{"marker": "',
              finishReason: 'length',
            );
          }
          return completionOf('{"references": [{"raw": "An entry."}]}');
        }),
      );
      addTearDown(service.close);

      final bibliography = List.generate(
        12,
        (i) => '[${i + 1}] Author $i. A Paper Titled Something. Venue, 2020.',
      ).join('\n');

      final references = await service.extractReferences(
        bibliography,
        modelId: 'test/model',
      );

      // It retried with smaller inputs instead of failing the import.
      expect(sentLengths.first, greaterThan(sentLengths.last));
      expect(references, isNotEmpty);
      expect(
        references.map((r) => r.index),
        List.generate(references.length, (i) => i + 1),
      );
    });

    test('retries unparseable JSON the same way', () async {
      var calls = 0;
      final service = InstructDocumentService(
        settings: _settings,
        client: MockClient((request) async {
          calls++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final content = (body['messages'] as List).last['content'] as String;
          if (content.length > 400) {
            return completionOf('Sorry, I cannot help with that.');
          }
          return completionOf('{"references": [{"raw": "An entry."}]}');
        }),
      );
      addTearDown(service.close);

      final references = await service.extractReferences(
        List.generate(
          12,
          (i) => '[${i + 1}] Author $i. A Paper Titled Something. Venue, 2020.',
        ).join('\n'),
        modelId: 'test/model',
      );

      expect(calls, greaterThan(1));
      expect(references, isNotEmpty);
    });

    test('gives up rather than retrying forever', () async {
      var calls = 0;
      final service = InstructDocumentService(
        settings: _settings,
        client: MockClient((_) async {
          calls++;
          return completionOf(
            '{"references": [{"marker": "',
            finishReason: 'length',
          );
        }),
      );
      addTearDown(service.close);

      await expectLater(
        service.extractReferences(
          List.generate(40, (i) => '[${i + 1}] Author $i. A Paper. 2020.')
              .join('\n'),
          modelId: 'test/model',
        ),
        throwsA(isA<InstructTruncatedException>()),
      );
      // Bounded by maxBibliographyRetries rather than looping.
      expect(calls, lessThan(20));
    });

    test('an empty bibliography makes no requests', () async {
      var calls = 0;
      final service = InstructDocumentService(
        settings: _settings,
        client: MockClient((_) async {
          calls++;
          return completionOf('{"references": []}');
        }),
      );
      addTearDown(service.close);

      expect(
        await service.extractReferences('  ', modelId: 'test/model'),
        isEmpty,
      );
      expect(calls, 0);
    });

    test('names truncation as the cause for a window', () async {
      final service = InstructDocumentService(
        settings: _settings,
        client: MockClient(
          (_) async => completionOf(
            '{"references": [{"marker": "',
            finishReason: 'length',
          ),
        ),
      );
      addTearDown(service.close);

      await expectLater(
        service.extractReferences('[1] An entry.', modelId: 'test/model'),
        throwsA(
          isA<InstructTruncatedException>().having(
            (e) => e.toString(),
            'message',
            contains('bibliography'),
          ),
        ),
      );
    });
  });

  group('reasoning effort', () {
    test('the bibliography pass asks for minimal reasoning', () async {
      late Map<String, dynamic> sentBody;
      final service = InstructDocumentService(
        settings: _settings,
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return completionOf('{"references": []}');
        }),
      );
      addTearDown(service.close);

      await service.extractReferences(
        '[1] A. Smith. A paper. Journal, 2019.',
        modelId: 'test/model',
      );

      // Splitting a citation into fields is pattern work, so thinking tokens
      // only cost latency.
      expect(sentBody['reasoning'], {'effort': 'minimal'});
    });

    test('the outline pass also asks for minimal reasoning', () async {
      late Map<String, dynamic> sentBody;
      final service = InstructDocumentService(
        settings: _settings,
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return completionOf('{"title": "P", "sections": []}');
        }),
      );
      addTearDown(service.close);

      await service.analyzeOutline('text', modelId: 'test/model');

      // Reporting printed headings and their pages is reading, not deduction.
      expect(sentBody['reasoning'], {'effort': 'minimal'});
    });

    test('an empty outline effort omits the field entirely', () async {
      late Map<String, dynamic> sentBody;
      final service = InstructDocumentService(
        settings: _settings.copyWith(indexingReasoningEffort: ''),
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return completionOf('{"title": "P", "sections": []}');
        }),
      );
      addTearDown(service.close);

      await service.analyzeOutline('text', modelId: 'test/model');

      expect(sentBody.containsKey('reasoning'), isFalse);
    });

    test('an empty effort omits the field entirely', () async {
      late Map<String, dynamic> sentBody;
      final service = InstructDocumentService(
        settings: _settings.copyWith(referenceReasoningEffort: ''),
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return completionOf('{"references": []}');
        }),
      );
      addTearDown(service.close);

      await service.extractReferences(
        '[1] A. Smith. A paper. Journal, 2019.',
        modelId: 'test/model',
      );

      // A model without the parameter rejects the request rather than
      // ignoring it, so the field must be absent, not empty.
      expect(sentBody.containsKey('reasoning'), isFalse);
    });
  });
}
