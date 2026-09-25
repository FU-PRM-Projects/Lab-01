/// One tool call made by the research agent, emitted on start and on settle.
class ToolCallRecord {
  static const statusRunning = 'running';
  static const statusOk = 'ok';
  static const statusFailed = 'failed';

  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  /// One of [statusRunning], [statusOk], [statusFailed].
  final String status;

  /// Short outcome, e.g. "4 passages" or the reason the call failed.
  final String? summary;

  /// Opening lines of what the tool returned, capped by [_maxPreviewChars].
  /// The full result goes to the model, not to the log.
  final String? resultPreview;

  final int? durationMs;

  const ToolCallRecord({
    required this.id,
    required this.name,
    this.arguments = const {},
    this.status = statusRunning,
    this.summary,
    this.resultPreview,
    this.durationMs,
  });

  bool get isRunning => status == statusRunning;
  bool get isFailed => status == statusFailed;

  ToolCallRecord settled({
    required bool ok,
    required String summary,
    String? result,
    int? durationMs,
  }) {
    return ToolCallRecord(
      id: id,
      name: name,
      arguments: arguments,
      status: ok ? statusOk : statusFailed,
      summary: summary,
      resultPreview: result == null ? null : preview(result),
      durationMs: durationMs ?? this.durationMs,
    );
  }

  static const _maxPreviewChars = 400;

  /// Trims a tool result down to a few lines for the expanded row.
  static String preview(String result) {
    final trimmed = result.trim();
    if (trimmed.length <= _maxPreviewChars) return trimmed;
    return '${trimmed.substring(0, _maxPreviewChars).trimRight()}...';
  }

  factory ToolCallRecord.fromJson(Map<String, dynamic> json) {
    final rawArguments = json['arguments'];
    return ToolCallRecord(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'tool',
      arguments: rawArguments is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawArguments)
          : const {},
      // A call saved while running never settled, so it is shown as failed
      // rather than spinning forever in a restored transcript.
      status: switch (json['status'] as String?) {
        statusOk => statusOk,
        statusRunning => statusFailed,
        _ => statusFailed,
      },
      summary: json['summary'] as String?,
      resultPreview: json['resultPreview'] as String?,
      durationMs: json['durationMs'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'arguments': arguments,
      'status': status,
      'summary': summary,
      'resultPreview': resultPreview,
      'durationMs': durationMs,
    };
  }
}
