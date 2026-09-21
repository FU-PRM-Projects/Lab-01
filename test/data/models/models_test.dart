import 'package:flutter_test/flutter_test.dart';
import 'package:lab_05/data/models/chat.dart';
import 'package:lab_05/data/models/citation.dart';
import 'package:lab_05/data/models/collection.dart';
import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/models/tool_call_record.dart';

void main() {
  group('Models JSON Roundtrip Tests', () {
    test('Collection serialization', () {
      final col = Collection(
        schemaVersion: 1,
        id: 'col_123',
        name: 'GraphRAG Research',
        createdAt: DateTime.utc(2026, 9, 14, 8, 0, 0),
        nextVectorId: 101,
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
      expect(roundtrip.nextVectorId, equals(101));
      expect(
        roundtrip.embeddingProfile.model,
        equals('google/gemini-embedding-2'),
      );
      expect(roundtrip.embeddingProfile.dimensions, equals(768));
    });

    test('PaperDocument and PaperChunk serialization', () {
      final chunk = PaperChunk(
        id: 'doc_1:p5:c0',
        vectorId: 42,
        page: 5,
        ordinal: 0,
        section: 'Methodology',
        startChar: 100,
        endChar: 450,
        text: 'Personalized PageRank on bipartite graph.',
      );

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
        chunks: [chunk],
      );

      final json = doc.toJson();
      final roundtrip = PaperDocument.fromJson(json);

      expect(roundtrip.id, equals('doc_1'));
      expect(roundtrip.title, equals('HippoRAG Paper'));
      expect(roundtrip.status, equals(DocumentStatus.ready));
      expect(roundtrip.chunks.length, equals(1));
      expect(roundtrip.chunks.first.vectorId, equals(42));
      expect(roundtrip.chunks.first.section, equals('Methodology'));
      expect(roundtrip.chunks.first.documentId, equals('doc_1'));
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

    test('Tool calls survive a chat round trip', () {
      final message = ChatMessage(
        id: 'msg_1',
        role: 'assistant',
        content: 'Answer [S1].',
        createdAt: DateTime.utc(2026, 9, 14, 8, 10, 0),
        toolCalls: const [
          ToolCallRecord(
            id: 'call-1',
            name: 'read_page',
            arguments: {'documentId': 'doc_1', 'page': 3},
            status: ToolCallRecord.statusOk,
            summary: '2 passages',
            resultPreview: '[S1] HippoRAG, PDF page 3',
            durationMs: 120,
          ),
          // Saved mid-flight, e.g. when the turn was stopped.
          ToolCallRecord(id: 'call-2', name: 'list_papers'),
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

      final calls = Chat.fromJson(chat.toJson()).messages.first.toolCalls;
      expect(calls.length, equals(2));
      expect(calls.first.name, equals('read_page'));
      expect(calls.first.arguments, equals({'documentId': 'doc_1', 'page': 3}));
      expect(calls.first.summary, equals('2 passages'));
      expect(calls.first.resultPreview, equals('[S1] HippoRAG, PDF page 3'));
      expect(calls.first.durationMs, equals(120));
      // A call that never settled must not spin forever when restored.
      expect(calls.last.isRunning, isFalse);
      expect(calls.last.isFailed, isTrue);
    });
  });
}
