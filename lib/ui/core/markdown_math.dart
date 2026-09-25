import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

// LaTeX support for flutter_markdown_plus: `$$...$$` as a block syntax,
// `$...$` as an inline syntax.

/// Matches display math starting with `$$`, closed on the same or a later line.
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

/// Matches inline `$...$` math (not `$$` or prices like `$5`).
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

/// Renders display math on its own, horizontally scrollable line.
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
