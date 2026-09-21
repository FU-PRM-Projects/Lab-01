import 'package:flutter/material.dart';

import 'package:lab_05/data/models/tool_call_record.dart';
import 'package:lab_05/ui/core/theme.dart';

/// The agent's tool calls for one turn, oldest first.
///
/// Modelled on a coding-assistant transcript: a call is a quiet line of prose,
/// not a panel. A lone call renders as one muted line with a chevron; several
/// collapse into a "Ran N tools" group that opens into a hairline-divided
/// list. The group stays open while a call is still running so progress is
/// visible, then folds itself away once the turn settles.
class ToolCallLog extends StatefulWidget {
  const ToolCallLog({super.key, required this.calls});

  final List<ToolCallRecord> calls;

  @override
  State<ToolCallLog> createState() => _ToolCallLogState();
}

class _ToolCallLogState extends State<ToolCallLog> {
  /// Set once the reader opens or closes the group themselves; until then the
  /// group follows the turn.
  bool? _chosen;

  @override
  Widget build(BuildContext context) {
    final calls = widget.calls;
    if (calls.isEmpty) return const SizedBox.shrink();

    final running = calls.any((call) => call.isRunning);
    final expanded = _chosen ?? running;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (calls.length == 1)
            _CallLine(call: calls.single)
          else ...[
            _GroupHeader(
              count: calls.length,
              running: running,
              expanded: expanded,
              onTap: () => setState(() => _chosen = !expanded),
            ),
            if (expanded) _GroupBody(calls: calls),
          ],
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.count,
    required this.running,
    required this.expanded,
    required this.onTap,
  });

  final int count;
  final bool running;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return _QuietRow(
      onTap: onTap,
      expanded: expanded,
      child: Text(
        running ? 'Running $count tools' : 'Ran $count tools',
        style: mutedLineStyle(context)
            .copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _GroupBody extends StatelessWidget {
  const _GroupBody({required this.calls});

  final List<ToolCallRecord> calls;

  @override
  Widget build(BuildContext context) {
    final hairline = context.colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final call in calls) ...[
            if (call != calls.first)
              Divider(height: 1, thickness: 1, color: hairline),
            _CallLine(
              key: ValueKey(call.id),
              call: call,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            ),
          ],
        ],
      ),
    );
  }
}

/// One tool call: a muted line that opens to show the raw call underneath.
class _CallLine extends StatefulWidget {
  const _CallLine({super.key, required this.call, this.padding});

  final ToolCallRecord call;
  final EdgeInsets? padding;

  @override
  State<_CallLine> createState() => _CallLineState();
}

class _CallLineState extends State<_CallLine> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final call = widget.call;
    final style = mutedLineStyle(context);
    final detail = _detailText(call);

    return _QuietRow(
      padding: widget.padding,
      expanded: _expanded,
      onTap: detail == null
          ? null
          : () => setState(() => _expanded = !_expanded),
      detail: _expanded ? detail : null,
      child: Text.rich(
        TextSpan(
          children: [
            // Failure is carried by the wording, the way a shell transcript
            // reads, rather than by an icon beside the line.
            if (call.isFailed)
              TextSpan(
                text: 'Failed to run ',
                style: style.copyWith(color: colorScheme.error),
              ),
            TextSpan(text: toolLabel(call)),
            if (call.summary case final summary?
                when !call.isFailed && summary.isNotEmpty)
              TextSpan(
                text: '  $summary',
                style: style.copyWith(color: colorScheme.outline),
              ),
            if (call.isFailed && call.summary != null)
              TextSpan(
                text: '  ${call.summary}',
                style: style.copyWith(color: colorScheme.outline),
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }

  /// The raw call, for the expanded line: arguments, what came back, and how
  /// long it took. Returns null when there is nothing worth opening.
  String? _detailText(ToolCallRecord call) {
    final lines = [
      for (final entry in call.arguments.entries)
        '${entry.key}: ${entry.value}',
      if (call.resultPreview case final preview? when preview.isNotEmpty) ...[
        '',
        preview,
      ],
      if (call.durationMs case final ms?) ...[
        '',
        '${(ms / 1000).toStringAsFixed(1)}s',
      ],
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }
}

/// The shared line: text on the left, a chevron on the right, and an optional
/// monospaced block underneath when it is open.
class _QuietRow extends StatelessWidget {
  const _QuietRow({
    required this.child,
    required this.expanded,
    this.onTap,
    this.padding,
    this.detail,
  });

  final Widget child;
  final bool expanded;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              // The chevron sits right after the words, not pinned to the far
              // edge, so the line reads as a sentence.
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: child),
                if (onTap != null) ...[
                  const SizedBox(width: 6),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.chevron_right_rounded,
                    size: 17,
                    color: colorScheme.outline,
                  ),
                ],
              ],
            ),
            if (detail case final text?)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: SelectableText(
                  text,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'Consolas',
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sized and coloured to sit beside the answer as an aside: the prose font at
/// the body size, dimmed, so it never competes with the answer itself.
@visibleForTesting
TextStyle mutedLineStyle(BuildContext context) {
  final colorScheme = context.colorScheme;
  return context.textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontSize: 14,
        height: 1.4,
      ) ??
      TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14);
}

/// A sentence describing the call, in present tense while it runs and past
/// tense once it has settled.
@visibleForTesting
String toolLabel(ToolCallRecord call) {
  final running = call.isRunning;
  final query = call.arguments['query'];
  final document = call.arguments['documentId'];
  final page = call.arguments['page'];

  return switch (call.name) {
    'search_papers' when query is String && query.isNotEmpty =>
      '${running ? 'Searching' : 'Searched'} papers for "$query"',
    'search_papers' => running ? 'Searching papers' : 'Searched papers',
    'read_page' when page != null =>
      '${running ? 'Reading' : 'Read'} page $page of ${document ?? 'a paper'}',
    'read_page' => running ? 'Reading a page' : 'Read a page',
    'list_papers' => running ? 'Listing papers' : 'Listed the papers',
    _ => running ? 'Running ${call.name}' : 'Ran ${call.name}',
  };
}
