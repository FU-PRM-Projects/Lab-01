import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

// Papers are transcribed with formulas kept as LaTeX (see
// PageTranscriptionService), and the chat model follows the same
// convention when it quotes or restates them. flutter_markdown_plus only
// understands plain Markdown, so without this, a formula like
// `$H_z^o \in \mathbb{R}^{N_z \times D_1}$` shows up as raw text instead
// of a rendered equation.
//
// Display math (`$$...$$`) is a BlockSyntax, not an InlineSyntax: it needs
// to occupy its own line rather than being embedded as a WidgetSpan inside
// a run of text, and MarkdownBody only lays a custom element out as a
// block when both (a) the syntax that produced it is registered via
// `blockSyntaxes` and (b) its builder's `isBlockElement()` returns true.
// Inline math (`$...$`) stays an InlineSyntax and is registered via
// `inlineSyntaxes` as usual.

/// Matches a display ("block") math span opened by a line starting with
/// `$$`, closed either on that same line (`$$formula$$`) or on a later
/// line ending in `$$`.
class MathDisplaySyntax extends md.BlockSyntax {
  const MathDisplaySyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*\$\$');

  @override
  md.Node parse(md.BlockParser parser) {
    final buffer = StringBuffer();
    final opening = parser.current.content.trimLeft();
    final afterOpen = opening.substring(2);

    final trimmedAfterOpen = afterOpen.trimRight();
    if (trimmedAfterOpen.endsWith(r'$$') && trimmedAfterOpen.length > 2) {
      buffer.write(
        trimmedAfterOpen.substring(0, trimmedAfterOpen.length - 2),
      );
      parser.advance();
      return md.Element.text('math_display', buffer.toString().trim());
    }

    if (afterOpen.trim().isNotEmpty) buffer.writeln(afterOpen);
    parser.advance();

    while (!parser.isDone) {
      final line = parser.current.content;
      final trimmedLine = line.trimRight();
      if (trimmedLine.endsWith(r'$$')) {
        buffer.write(trimmedLine.substring(0, trimmedLine.length - 2));
        parser.advance();
        break;
      }
      buffer.writeln(line);
      parser.advance();
    }

    return md.Element.text('math_display', buffer.toString().trim());
  }
}

/// Matches inline math delimited by a single pair of `$...$`.
///
/// The lookaround assertions keep it from firing inside a `$$...$$` span
/// and from treating a lone price-style `$5` as the start of math.
class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax() : super(r'(?<!\$)\$(?!\$)([^\n$]+?)\$(?!\$)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tex = (match[1] ?? '').trim();
    if (tex.isEmpty) return false;
    parser.addNode(md.Element.text('math_inline', tex));
    return true;
  }
}

Widget _mathFallbackText(String tex, bool display, TextStyle? style) {
  return Text(display ? '\$\$$tex\$\$' : '\$$tex\$', style: style);
}

/// Renders a `math_inline` node produced by [MathInlineSyntax] as TeX.
class MathInlineBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final tex = element.textContent;
    return Math.tex(
      tex,
      mathStyle: MathStyle.text,
      textStyle: preferredStyle,
      onErrorFallback: (_) => _mathFallbackText(tex, false, preferredStyle),
    );
  }
}

/// Renders a `math_display` node produced by [MathDisplaySyntax] as TeX, on
/// its own line and horizontally scrollable so a long formula never
/// overflows the chat bubble.
class MathDisplayBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final tex = element.textContent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            tex,
            mathStyle: MathStyle.display,
            textStyle: preferredStyle,
            onErrorFallback: (_) =>
                _mathFallbackText(tex, true, preferredStyle),
          ),
        ),
      ),
    );
  }
}

final List<md.BlockSyntax> _mathBlockSyntaxes = [const MathDisplaySyntax()];

final List<md.InlineSyntax> _mathInlineSyntaxes = [MathInlineSyntax()];

final Map<String, MarkdownElementBuilder> _mathBuilders = {
  'math_display': MathDisplayBuilder(),
  'math_inline': MathInlineBuilder(),
};

/// A [MarkdownBody] that also renders `$...$` and `$$...$$` as TeX.
///
/// Every Markdown view in the app goes through this, so the math syntaxes
/// are registered in one place. A view that needs its own syntax (the source
/// panel's underline) passes it in [extraInlineSyntaxes] and [extraBuilders].
class MathMarkdown extends StatelessWidget {
  const MathMarkdown({
    super.key,
    required this.data,
    this.styleSheet,
    this.selectable = false,
    this.onTapLink,
    this.extraInlineSyntaxes = const [],
    this.extraBuilders = const {},
  });

  final String data;
  final MarkdownStyleSheet? styleSheet;
  final bool selectable;
  final MarkdownTapLinkCallback? onTapLink;
  final List<md.InlineSyntax> extraInlineSyntaxes;
  final Map<String, MarkdownElementBuilder> extraBuilders;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: data,
      selectable: selectable,
      styleSheet: styleSheet,
      blockSyntaxes: _mathBlockSyntaxes,
      inlineSyntaxes: [..._mathInlineSyntaxes, ...extraInlineSyntaxes],
      builders: {..._mathBuilders, ...extraBuilders},
      onTapLink: onTapLink,
    );
  }
}
