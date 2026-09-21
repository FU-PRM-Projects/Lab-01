import 'package:lab_05/data/models/citation.dart';
import 'package:lab_05/data/models/tool_call_record.dart';

class ChatMessage {
  final String id;
  final String role; // "user", "assistant", "system"
  final String status; // "complete", "cancelled", "failed", "streaming"
  final String content;
  final DateTime createdAt;
  final String? model;
  final List<Citation> citations;

  /// Tools the agent ran while producing this message, in the order it ran
  /// them. Always empty for user messages.
  final List<ToolCallRecord> toolCalls;

  const ChatMessage({
    required this.id,
    required this.role,
    this.status = 'complete',
    required this.content,
    required this.createdAt,
    this.model,
    this.citations = const [],
    this.toolCalls = const [],
  });

  ChatMessage copyWith({
    String? status,
    String? content,
    List<Citation>? citations,
    String? model,
    List<ToolCallRecord>? toolCalls,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      status: status ?? this.status,
      content: content ?? this.content,
      createdAt: createdAt,
      model: model ?? this.model,
      citations: citations ?? this.citations,
      toolCalls: toolCalls ?? this.toolCalls,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawCitations = (json['citations'] as List<dynamic>?) ?? [];
    final rawToolCalls = (json['toolCalls'] as List<dynamic>?) ?? [];
    return ChatMessage(
      id: json['id'] as String,
      role: json['role'] as String? ?? 'user',
      status: json['status'] as String? ?? 'complete',
      content: json['content'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      model: json['model'] as String?,
      citations: rawCitations
          .map((c) => Citation.fromJson(c as Map<String, dynamic>))
          .toList(),
      toolCalls: rawToolCalls
          .map((t) => ToolCallRecord.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'status': status,
      'content': content,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'model': model,
      'citations': citations.map((c) => c.toJson()).toList(),
      'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
    };
  }
}

class Chat {
  final int schemaVersion;
  final String id;
  final String collectionId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  const Chat({
    this.schemaVersion = 1,
    required this.id,
    required this.collectionId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
  });

  Chat copyWith({
    String? title,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) {
    return Chat(
      schemaVersion: schemaVersion,
      id: id,
      collectionId: collectionId,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
    );
  }

  factory Chat.fromJson(Map<String, dynamic> json) {
    final rawMessages = (json['messages'] as List<dynamic>?) ?? [];
    return Chat(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      id: json['id'] as String,
      collectionId: json['collectionId'] as String,
      title: json['title'] as String? ?? 'New Chat',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      messages: rawMessages
          .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'id': id,
      'collectionId': collectionId,
      'title': title,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'messages': messages.map((m) => m.toJson()).toList(),
    };
  }
}
