import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

// Papers are transcribed with formulas kept as LaTeX (see
// PageTranscriptionService), and the chat model follows the same
// convention when it quotes or restates them. flutter_markdown_plus only
// understands plain Markdown, so without this, a formula like
// `$H_z^o \in \mathbb{R}^{N_z \times D_1}$` shows up as raw text instead
// of a rendered equation. These two InlineSyntax classes recognize
// `$$...$$` (display/block) and `$...$` (inline) math spans and hand them
// off to flutter_math_fork for rendering.

/// Matches display ("block") math delimited by `$$...$$`.
///
/// Registered before [MathInlineSyntax] so a `$$...$$` span is consumed in
/// full rather than being picked apart by the single-`$` pattern.
class MathDisplaySyntax extends md.InlineSyntax {
  MathDisplaySyntax() : super(r'\$\$([\s\S]+?)\$\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tex = (match[1] ?? '').trim();
    if (tex.isEmpty) return false;
    parser.addNode(md.Element.text('math_display', tex));
    return true;
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

/// Pass as a `MarkdownBody`'s `inlineSyntaxes` (merge with any others).
final List<md.InlineSyntax> mathInlineSyntaxes = [
  MathDisplaySyntax(),
  MathInlineSyntax(),
];

/// Merge into a `MarkdownBody`'s `builders` (keys must stay unique).
final Map<String, MarkdownElementBuilder> mathBuilders = {
  'math_display': MathDisplayBuilder(),
  'math_inline': MathInlineBuilder(),
};
