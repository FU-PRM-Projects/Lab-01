import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/data/models/chat.dart';
import 'package:lab_05/data/models/citation.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/models/paper.dart';

void main() {
  group('Models JSON Roundtrip Tests', () {
    test('Collection serialization', () {
      final col = Collection(
        schemaVersion: 1,
        id: 'col_123',
        name: 'GraphRAG Research',
        createdAt: DateTime.utc(2026, 9, 14, 8, 0, 0),
        embeddingProfile: const EmbeddingProfile(
          id: 'profile_123',
          model: 'google/gemini-embedding-2',
          dimensions: 768,
          inputFormatVersion: 1,
          normalization: 'l2',
        ),
      );

      final json = col.toJson();
      final roundtrip = Collection.fromJson(json);

      expect(roundtrip.id, equals('col_123'));
      expect(roundtrip.name, equals('GraphRAG Research'));
      expect(
        roundtrip.embeddingProfile.model,
        equals('google/gemini-embedding-2'),
      );
      expect(roundtrip.embeddingProfile.dimensions, equals(768));
    });

    test('PaperDocument serialization', () {
      final doc = PaperDocument(
        id: 'doc_1',
        fileName: 'paper.pdf',
        title: 'HippoRAG Paper',
        authors: ['Researcher A', 'Researcher B'],
        sha256: 'abcdef123456',
        pageCount: 12,
        status: DocumentStatus.ready,
        createdAt: DateTime.utc(2026, 9, 14, 8, 5, 0),
        embeddingProfileId: 'profile_123',
      );

      final json = doc.toJson();
      final roundtrip = PaperDocument.fromJson(json);

      expect(roundtrip.id, equals('doc_1'));
      expect(roundtrip.title, equals('HippoRAG Paper'));
      expect(roundtrip.status, equals(DocumentStatus.ready));
      expect(roundtrip.pageCount, equals(12));
      expect(roundtrip.authors, equals(['Researcher A', 'Researcher B']));
    });

    test('Metadata written before the LanceDB migration still parses', () {
      // Chunks and vector ids used to live in this file; both are now owned by
      // the vector store, and the leftover keys must not break loading.
      final legacy = <String, dynamic>{
        'schemaVersion': 1,
        'id': 'doc_1',
        'fileName': 'paper.pdf',
        'title': 'HippoRAG Paper',
        'sha256': 'abcdef123456',
        'pageCount': 12,
        'status': 'ready',
        'createdAt': '2026-09-14T08:05:00.000Z',
        'embeddingProfileId': 'profile_123',
        'chunks': [
          {'id': 'doc_1:p5:c0', 'vectorId': 42, 'page': 5, 'text': 'legacy'},
        ],
      };

      final doc = PaperDocument.fromJson(legacy);

      expect(doc.id, equals('doc_1'));
      expect(doc.status, equals(DocumentStatus.ready));
      expect(doc.toJson().containsKey('chunks'), isFalse);
    });

    test('PaperChunk derives its document id from the chunk id', () {
      const textChunk = PaperChunk(
        id: 'doc_1:p5:c0',
        page: 5,
        ordinal: 0,
        section: 'Methodology',
        startChar: 100,
        endChar: 450,
        text: 'Personalized PageRank on bipartite graph.',
      );
      const ocrChunk = PaperChunk(
        id: 'doc_1:p5:ocr0',
        page: 5,
        ordinal: 1,
        section: '',
        startChar: 0,
        endChar: 10,
        text: 'scanned',
      );

      expect(textChunk.parentDocId, equals('doc_1'));
      // OCR chunks carry ':ocr' so they cannot collide with the text chunks of
      // the same page, and the document id is still the leading segment.
      expect(ocrChunk.parentDocId, equals('doc_1'));
    });

    test('Citation serialization', () {
      final citation = const Citation(
        sourceId: 'S1',
        documentId: 'doc_1',
        documentHash: 'abcdef123456',
        fileName: 'paper.pdf',
        title: 'HippoRAG Paper',
        page: 5,
        section: 'Methodology',
        chunkId: 'doc_1:p5:c0',
        startChar: 100,
        endChar: 450,
        excerpt: 'Personalized PageRank on bipartite graph.',
      );

      final json = citation.toJson();
      final roundtrip = Citation.fromJson(json);

      expect(roundtrip.sourceId, equals('S1'));
      expect(roundtrip.documentId, equals('doc_1'));
      expect(roundtrip.page, equals(5));
      expect(roundtrip.section, equals('Methodology'));
      expect(roundtrip.excerpt, contains('PageRank'));
    });

    test('Chat and ChatMessage serialization', () {
      final message = ChatMessage(
        id: 'msg_1',
        role: 'assistant',
        status: 'complete',
        content: 'HippoRAG uses graph retrieval [S1].',
        createdAt: DateTime.utc(2026, 9, 14, 8, 10, 0),
        model: 'google/gemini-2.0-flash-001',
        citations: [
          const Citation(
            sourceId: 'S1',
            documentId: 'doc_1',
            documentHash: 'abc',
            fileName: 'hippo.pdf',
            title: 'HippoRAG',
            page: 3,
            section: 'Introduction',
            chunkId: 'doc_1:p3:c0',
            startChar: 0,
            endChar: 200,
            excerpt: 'Graph algorithms for LLM indexing.',
          ),
        ],
      );

      final chat = Chat(
        id: 'chat_1',
        collectionId: 'col_123',
        title: 'HippoRAG Discussion',
        createdAt: DateTime.utc(2026, 9, 14, 8, 10, 0),
        updatedAt: DateTime.utc(2026, 9, 14, 8, 11, 0),
        messages: [message],
      );

      final json = chat.toJson();
      final roundtrip = Chat.fromJson(json);

      expect(roundtrip.id, equals('chat_1'));
      expect(roundtrip.collectionId, equals('col_123'));
      expect(roundtrip.messages.length, equals(1));
      expect(roundtrip.messages.first.role, equals('assistant'));
      expect(roundtrip.messages.first.citations.length, equals(1));
      expect(roundtrip.messages.first.citations.first.sourceId, equals('S1'));
    });
  });
}
