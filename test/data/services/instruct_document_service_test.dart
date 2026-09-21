import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lab_05/data/models/app_settings.dart';
import 'package:lab_05/data/services/instruct_document_service.dart';

void main() {
  group('InstructDocumentService.assembleMarkdown', () {
    test('assembles pages in order with <!-- PAGE N --> markers', () {
      final pages = {
        1: '# Title\nAbstract paragraph.',
        2: '## Introduction\nIntro text here.',
        3: '## References\n[1] Sample citation.',
      };

      final assembled = InstructDocumentService.assembleMarkdown(pages, 3);

      expect(assembled, contains('<!-- PAGE 1 -->'));
      expect(assembled, contains('# Title\nAbstract paragraph.'));
      expect(assembled, contains('<!-- PAGE 2 -->'));
      expect(assembled, contains('## Introduction\nIntro text here.'));
      expect(assembled, contains('<!-- PAGE 3 -->'));
      expect(assembled, contains('## References\n[1] Sample citation.'));
      expect(
        assembled.indexOf('<!-- PAGE 1 -->'),
        lessThan(assembled.indexOf('<!-- PAGE 2 -->')),
      );
      expect(
        assembled.indexOf('<!-- PAGE 2 -->'),
        lessThan(assembled.indexOf('<!-- PAGE 3 -->')),
      );
    });

    test('handles empty or missing pages gracefully', () {
      final pages = {
        1: 'Content on page 1',
        3: 'Content on page 3',
      };

      final assembled = InstructDocumentService.assembleMarkdown(pages, 3);

      expect(assembled, contains('<!-- PAGE 1 -->\nContent on page 1'));
      expect(assembled, contains('<!-- PAGE 2 -->'));
      expect(assembled, contains('<!-- PAGE 3 -->\nContent on page 3'));
    });
  });

  group('InstructDocumentService.parseJsonResult', () {
    test('parses clean JSON into DocumentSections and PaperReferences', () {
      const jsonStr = '''
{
  "sections": [
    {"name": "Abstract", "page": 1, "rawHeading": "Abstract"},
    {"name": "Introduction", "page": 1, "rawHeading": "1. Introduction"},
    {"name": "Methodology", "page": 4, "rawHeading": "2. Methods"},
    {"name": "References", "page": 9, "rawHeading": "References"}
  ],
  "references": [
    {
      "index": 1,
      "marker": "[1]",
      "raw": "A. Vaswani et al. Attention is All You Need. NeurIPS 2017.",
      "authors": "A. Vaswani et al.",
      "title": "Attention is All You Need",
      "year": 2017,
      "doi": null,
      "arxivId": "1706.03762",
      "url": "https://arxiv.org/abs/1706.03762"
    },
    {
      "index": 2,
      "marker": "[2]",
      "raw": "J. Devlin et al. BERT. NAACL 2019. doi:10.18653/v1/N19-1423",
      "authors": "J. Devlin et al.",
      "title": "BERT",
      "year": 2019,
      "doi": "10.18653/v1/N19-1423",
      "arxivId": null,
      "url": null
    }
  ]
}
''';

      final result = InstructDocumentService.parseJsonResult(jsonStr);

      expect(result.sections, hasLength(4));
      expect(result.sections[0].name, 'Abstract');
      expect(result.sections[0].page, 1);
      expect(result.sections[1].name, 'Introduction');
      expect(result.sections[2].name, 'Methodology');
      expect(result.sections[2].page, 4);
      expect(result.sections[3].name, 'References');
      expect(result.sections[3].page, 9);

      expect(result.references, hasLength(2));
      expect(result.references[0].index, 1);
      expect(result.references[0].marker, '[1]');
      expect(result.references[0].title, 'Attention is All You Need');
      expect(result.references[0].arxivId, '1706.03762');
      expect(result.references[0].year, 2017);

      expect(result.references[1].index, 2);
      expect(result.references[1].doi, '10.18653/v1/N19-1423');
      expect(result.references[1].year, 2019);
    });

    test('parses arbitrary/custom section titles not in standard lists', () {
      const jsonStr = '''
{
  "sections": [
    {"name": "System Architecture", "page": 2, "rawHeading": "2. SYSTEM ARCHITECTURE"},
    {"name": "Threat Model & Security", "page": 4, "rawHeading": "IV. Threat Model & Security"},
    {"name": "Autonomous Driving Case Study", "page": 7, "rawHeading": "Case Study: Autonomous Driving"}
  ],
  "references": []
}
''';

      final result = InstructDocumentService.parseJsonResult(jsonStr);

      expect(result.sections, hasLength(3));
      expect(result.sections[0].name, 'System Architecture');
      expect(result.sections[0].page, 2);
      expect(result.sections[1].name, 'Threat Model & Security');
      expect(result.sections[1].page, 4);
      expect(result.sections[2].name, 'Autonomous Driving Case Study');
      expect(result.sections[2].page, 7);
    });

    test('strips markdown code fence wrappers from JSON output', () {
      const wrapped = '''```json
{
  "sections": [{"name": "Introduction", "page": 1}],
  "references": []
}
```''';

      final result = InstructDocumentService.parseJsonResult(wrapped);
      expect(result.sections, hasLength(1));
      expect(result.sections.first.name, 'Introduction');
      expect(result.references, isEmpty);
    });

    test('throws FormatException on malformed JSON without falling back', () {
      expect(
        () => InstructDocumentService.parseJsonResult('Not a json at all'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException on empty output', () {
      expect(
        () => InstructDocumentService.parseJsonResult('   '),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('InstructDocumentService API execution', () {
    test('throws StateError immediately when API key is missing', () async {
      const settings = AppSettings(openRouterApiKey: '');
      final service = InstructDocumentService(settings: settings);

      expect(
        () => service.parseStructure('# Document'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('API key is required'),
        )),
      );
    });

    test('throws HttpException immediately on non-200 response from OpenRouter', () async {
      const settings = AppSettings(openRouterApiKey: 'test-key');
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'message': 'Rate limit exceeded or balance too low'}
          }),
          402,
        );
      });

      final service = InstructDocumentService(
        settings: settings,
        client: mockClient,
      );

      expect(
        () => service.parseStructure('# Document'),
        throwsA(isA<HttpException>().having(
          (e) => e.message,
          'message',
          contains('Rate limit exceeded or balance too low'),
        )),
      );
    });

    test('successfully parses when OpenRouter responds with valid JSON', () async {
      const settings = AppSettings(openRouterApiKey: 'test-key');
      final mockClient = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-key');
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'sections': [
                      {'name': 'Introduction', 'page': 1},
                      {'name': 'References', 'page': 3}
                    ],
                    'references': [
                      {
                        'index': 1,
                        'marker': '[1]',
                        'raw': 'Test Reference. 2024.',
                        'title': 'Test Reference',
                        'year': 2024
                      }
                    ]
                  })
                }
              }
            ]
          }),
          200,
        );
      });

      final service = InstructDocumentService(
        settings: settings,
        client: mockClient,
      );

      final result = await service.parseStructure('<!-- PAGE 1 -->\n# Test');
      expect(result.sections, hasLength(2));
      expect(result.sections.first.name, 'Introduction');
      expect(result.references, hasLength(1));
      expect(result.references.first.title, 'Test Reference');
      expect(result.references.first.year, 2024);
    });
  });
}
