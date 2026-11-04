import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/fonts.dart';

/// ── 轻量 Markdown 渲染器（零依赖） ──
///
/// 聊天气泡用，语法对齐 SillyTavern 渲染集：
/// * 块级：``` 围栏代码块、#~###### 标题、> 引用（支持嵌套层级）、
///   -/+/1. 列表、- [ ] 任务列表、---/*** 分隔线、| 表格 |
/// * 行内：`code`、**bold**、__bold__、~~strike~~、*italic*、
///   [链接](url)、![图片](url)（对话场景降级为链接文字）
/// * 对话高亮（用户约定）：
///   - `""内容""` → 橙色高亮（强调/引语）
///   - （中文括号）与 (英文括号) 内容 → 绿色高亮（旁白/心理活动）
///
/// 全部用 Flutter 自带 Text.rich 渲染，不引第三方包（保持轻量零依赖）。
/// 不追求完整 CommonMark：未知语法原样显示。

/// 高亮配色（对话气泡专用，亮暗自适应：亮色底深字、暗色底亮字）
///
/// 选色兼顾「与默认主题（浅天蓝）的区分度」和对比度：
/// * 括号用宝蓝而非天蓝 —— 默认主题就是浅蓝，用同色系会糊在一起；
/// * 代码块用翠绿 —— 和主题蓝、引语橙都不撞色。
class MarkdownHighlightColors {
  const MarkdownHighlightColors({
    required this.quote,
    required this.paren,
    required this.code,
  });

  /// `""内容""` 的橙色
  final Color quote;

  /// （内容）/ (内容) 的蓝色
  final Color paren;

  /// ``` 代码块 / `行内代码` 的翠绿色
  final Color code;

  static MarkdownHighlightColors of(Brightness b) => MarkdownHighlightColors(
        quote: b == Brightness.dark
            ? const Color(0xFFF5A55C)
            : const Color(0xFFD97E2B),
        // 宝蓝：亮色 #2563EB（白底对比 ≈6.3:1）、暗色 #7FA8FF（深底 ≈7:1）
        paren: b == Brightness.dark
            ? const Color(0xFF7FA8FF)
            : const Color(0xFF2563EB),
        // 翠绿：亮色 #0E8F63（白底 ≈4:1）、暗色 #4ADE9B（深底 ≈9:1）
        code: b == Brightness.dark
            ? const Color(0xFF4ADE9B)
            : const Color(0xFF0E8F63),
      );
}

/// 把一段文本解析成块级 widget 列表。
List<Widget> buildMarkdownBlocks(
  String source, {
  required TextStyle base,
  Color? codeBackground,
  Color? quoteBarColor,
  MarkdownHighlightColors? highlights,
}) {
  final hl = highlights ?? MarkdownHighlightColors.of(Brightness.light);
  final blocks = <Widget>[];
  final lines = const LineSplitter().convert(source);

  var i = 0;
  final paragraph = StringBuffer();

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    final text = paragraph.toString();
    paragraph.clear();
    blocks.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text.rich(
          TextSpan(children: parseInline(text, base, highlights: hl)),
          textAlign: TextAlign.left,
        ),
      ),
    );
  }

  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trim();

    // 空行：段落结束
    if (trimmed.isEmpty) {
      flushParagraph();
      i++;
      continue;
    }

    // 围栏代码块 ```
    if (trimmed.startsWith('```')) {
      flushParagraph();
      final code = StringBuffer();
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        code.writeln(lines[i]);
        i++;
      }
      i++; // 跳过闭合 ```
      blocks.add(_CodeBlock(
        code: code.toString(),
        style: base.copyWith(
          // monospace 没有中文字形，必须挂回退链，否则中文会掉到系统字体
          fontFamily: 'monospace',
          fontFamilyFallback: kCjkFallback,
          fontSize: base.fontSize! * 0.9,
          // 代码块内容统一翠绿
          color: hl.code,
        ),
        background: codeBackground,
      ));
      continue;
    }

    // 表格：当前行含 | 且下一行是分隔行 |---|---|
    if (trimmed.contains('|') && i + 1 < lines.length) {
      final sep = lines[i + 1].trim();
      final isTableSep = RegExp(
        r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$',
      ).hasMatch(sep);
      if (isTableSep) {
        flushParagraph();
        final rows = <List<String>>[];
        // 头行 + 后续数据行
        rows.add(_splitTableRow(trimmed));
        var j = i + 2;
        while (j < lines.length &&
            lines[j].trim().isNotEmpty &&
            lines[j].trim().contains('|')) {
          rows.add(_splitTableRow(lines[j].trim()));
          j++;
        }
        blocks.add(_Table(rows: rows, base: base));
        i = j;
        continue;
      }
    }

    // 标题 # ~ ######
    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
    if (heading != null) {
      flushParagraph();
      final level = heading.group(1)!.length;
      final scale = <double>[1.5, 1.32, 1.18, 1.08, 1.02, 1.0][level - 1];
      blocks.add(Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 3),
        child: Text.rich(
          TextSpan(children: parseInline(
            heading.group(2)!,
            base.copyWith(
              fontSize: base.fontSize! * scale,
              fontWeight: FontWeight.w700,
            ),
            highlights: hl,
          )),
        ),
      ));
      i++;
      continue;
    }

    // 分隔线 --- / *** / ___
    if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
      flushParagraph();
      blocks.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Divider(height: 1, color: base.color?.withOpacity(0.25)),
      ));
      i++;
      continue;
    }

    // 引用 > （支持 > 一级、>> 二级嵌套缩进）
    if (trimmed.startsWith('>')) {
      flushParagraph();
      final quote = StringBuffer();
      var level = 1;
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        final t = lines[i].trim();
        final currentLevel = RegExp(r'^>+').firstMatch(t)!.group(0)!.length;
        if (level == 1 && currentLevel > 1) level = currentLevel;
        quote.writeln(t.replaceFirst(RegExp(r'^>+'), ''));
        i++;
      }
      blocks.add(_QuoteBlock(
        text: quote.toString().trim(),
        base: base,
        barColor: quoteBarColor,
        indent: (level - 1).clamp(0, 2) * 12.0,
        highlights: hl,
      ));
      continue;
    }

    // 任务列表 - [ ] / - [x]
    final task = RegExp(r'^[-*+]\s+\[([ xX])\]\s+(.*)$').firstMatch(trimmed);
    if (task != null) {
      flushParagraph();
      blocks.add(_ListItem(
        marker: (task.group(1)!.toLowerCase() == 'x') ? '☑  ' : '☐  ',
        text: task.group(2)!,
        base: base,
        highlights: hl,
      ));
      i++;
      continue;
    }

    // 无序列表 - / * / +
    final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
    if (bullet != null) {
      flushParagraph();
      blocks.add(_ListItem(
        marker: '•  ',
        text: bullet.group(1)!,
        base: base,
        highlights: hl,
      ));
      i++;
      continue;
    }

    // 有序列表 1. / 1)
    final ordered = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(trimmed);
    if (ordered != null) {
      flushParagraph();
      blocks.add(_ListItem(
        marker: '${ordered.group(1)}. ',
        text: ordered.group(2)!,
        base: base,
        highlights: hl,
      ));
      i++;
      continue;
    }

    // 普通文本：攒段落（软换行合并为空格——对话场景简化）
    if (paragraph.isNotEmpty) paragraph.write(' ');
    paragraph.write(trimmed);
    i++;
  }
  flushParagraph();
  return blocks;
}

List<String> _splitTableRow(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|')) s = s.substring(0, s.length - 1);
  return s.split('|').map((e) => e.trim()).toList();
}

/// 行内解析：`code` → 链接/图片 → **bold**/~~strike~~/*italic* →
/// ""橙色高亮"" → （绿色高亮）
List<InlineSpan> parseInline(
  String text,
  TextStyle base, {
  MarkdownHighlightColors? highlights,
}) {
  final hl = highlights ?? MarkdownHighlightColors.of(Brightness.light);
  final spans = <InlineSpan>[];

  // 1) 先按行内代码 `...` 切：代码段内不再解析任何语法
  final codeParts = text.split('`');
  for (var c = 0; c < codeParts.length; c++) {
    if (c.isOdd) {
      spans.add(TextSpan(
        text: codeParts[c],
        style: base.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: kCjkFallback,
          fontSize: (base.fontSize ?? 14) * 0.92,
          // 行内代码同样翠绿，和围栏代码块保持一致
          color: hl.code,
          backgroundColor: hl.code.withOpacity(0.10),
        ),
      ));
      continue;
    }
    // 2) 偶数段继续解析强调/高亮/链接
    spans.addAll(_parseEmphasisAndHighlights(codeParts[c], base, hl));
  }
  return spans;
}

List<InlineSpan> _parseEmphasisAndHighlights(
  String text,
  TextStyle base,
  MarkdownHighlightColors hl,
) {
  final spans = <InlineSpan>[];
  // 匹配顺序（先长后短避免吞并）：
  // **bold** / __bold__ / ~~strike~~ / *italic* / [链接](url) / ![图片](url)
  // / ""橙色"" / （绿色）/ (绿色)
  final pattern = RegExp(
    r'\*\*(.+?)\*\*'
    r'|__(.+?)__'
    r'|~~(.+?)~~'
    r'|\*(.+?)\*'
    r'|!\[(.*?)\]\((.*?)\)'
    r'|\[(.*?)\]\((.*?)\)'
    r'|""(.+?)""'
    r'|（(.+?)）'
    r'|\((.+?)\)'
    // 中文引号对："内容"。模型在中文语境下几乎总是输出中文标点，
    // 提示词很难扭转，所以在这里兜底识别，统一转成英文引号显示。
    r'|“(.+?)”'
    // 直角引号对：「内容」。同样当对话高亮，但保留原符号不转换。
    r'|「(.+?)」'
    // 英文引号对："内容"。入库时会把中文引号替换成英文，
    // 若不单独识别，替换后反而失去高亮。不跨行、内部不含引号。
    r'|"([^"\n]+)"',
    dotAll: true,
  );
  var last = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start), style: base));
    }
    final bold = m.group(1) ?? m.group(2);
    final strike = m.group(3);
    final italic = m.group(4);
    final imageAlt = m.group(5);
    final imageUrl = m.group(6);
    final linkText = m.group(7);
    final linkUrl = m.group(8);
    final quoteHl = m.group(9);
    final parenHl = m.group(10) ?? m.group(11);
    final cjkQuote = m.group(12);
    final cornerQuote = m.group(13);
    final asciiQuote = m.group(14);

    if (bold != null) {
      spans.add(TextSpan(
        text: bold,
        style: base.copyWith(fontWeight: FontWeight.w700),
      ));
    } else if (strike != null) {
      spans.add(TextSpan(
        text: strike,
        style: base.copyWith(decoration: TextDecoration.lineThrough),
      ));
    } else if (italic != null) {
      spans.add(TextSpan(
        text: italic,
        style: base.copyWith(fontStyle: FontStyle.italic),
      ));
    } else if (linkText != null && linkUrl != null) {
      // 对话气泡内不加载网页图，链接显示为主题色下划线文字
      spans.add(TextSpan(
        text: linkText,
        style: base.copyWith(
          color: hl.paren,
          decoration: TextDecoration.underline,
          decorationColor: hl.paren.withOpacity(0.5),
        ),
        recognizer: null,
      ));
    } else if (imageAlt != null && imageUrl != null) {
      // 图片降级为「alt（链接样式）」
      spans.add(TextSpan(
        text: imageAlt.isEmpty ? '图片' : imageAlt,
        style: base.copyWith(
          color: hl.paren,
          decoration: TextDecoration.underline,
          decorationColor: hl.paren.withOpacity(0.5),
        ),
      ));
    } else if (quoteHl != null) {
      // ""内容""（SillyTavern 写法）：显示为英文引号，内部橙色
      spans.add(TextSpan(
        text: '"$quoteHl"',
        style: base.copyWith(color: hl.quote, fontWeight: FontWeight.w600),
      ));
    } else if (cjkQuote != null) {
      // "内容"（模型实际输出的中文引号）：同样显示为英文引号
      spans.add(TextSpan(
        text: '"$cjkQuote"',
        style: base.copyWith(color: hl.quote, fontWeight: FontWeight.w600),
      ));
    } else if (cornerQuote != null) {
      // 「内容」：与对话同色，符号保持原样
      spans.add(TextSpan(
        text: '「$cornerQuote」',
        style: base.copyWith(color: hl.quote, fontWeight: FontWeight.w600),
      ));
    } else if (asciiQuote != null) {
      // "内容"（入库替换后的形态）：对话高亮
      spans.add(TextSpan(
        text: '"$asciiQuote"',
        style: base.copyWith(color: hl.quote, fontWeight: FontWeight.w600),
      ));
    } else if (parenHl != null) {
      // （绿色）/ (绿色)：保留括号本体，内部绿色
      final isCjk = text.substring(m.start, m.end).startsWith('（');
      spans.add(TextSpan(
        text: isCjk ? '（$parenHl）' : '($parenHl)',
        style: base.copyWith(color: hl.paren),
      ));
    }
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: base));
  }
  return spans;
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.style, this.background});

  final String code;
  final TextStyle style;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background ??
            (style.color?.withOpacity(0.07) ?? const Color(0x11000000)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        code,
        style: style.copyWith(height: 1.5),
        softWrap: true,
      ),
    );
  }
}

class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({
    required this.text,
    required this.base,
    this.barColor,
    this.indent = 0,
    this.highlights,
  });

  final String text;
  final TextStyle base;
  final Color? barColor;
  final double indent;
  final MarkdownHighlightColors? highlights;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            width: 3,
            color: barColor ?? base.color?.withOpacity(0.35) ?? Colors.grey,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(left: indent),
        child: Text.rich(
          TextSpan(children: parseInline(
            text,
            base.copyWith(height: 1.55),
            highlights: highlights,
          )),
        ),
      ),
    );
  }
}

class _ListItem extends StatelessWidget {
  const _ListItem({
    required this.marker,
    required this.text,
    required this.base,
    this.highlights,
  });

  final String marker;
  final String text;
  final TextStyle base;
  final MarkdownHighlightColors? highlights;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 1, bottom: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 22,
            child: Text(marker, style: base.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text.rich(TextSpan(
              children: parseInline(text, base, highlights: highlights),
            )),
          ),
        ],
      ),
    );
  }
}

/// 简易表格：第一行为表头（加粗 + 浅底），其余为数据行；
/// 列宽由 Table 布局器均分。支持行内语法解析。
class _Table extends StatelessWidget {
  const _Table({required this.rows, required this.base});

  final List<List<String>> rows;
  final TextStyle base;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final colCount = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: base.color?.withOpacity(0.18) ?? Colors.grey),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder.symmetric(
            inside: BorderSide(color: base.color?.withOpacity(0.12) ?? Colors.grey),
          ),
          children: <TableRow>[
            for (var r = 0; r < rows.length; r++)
              TableRow(
                decoration: BoxDecoration(
                  color: r == 0
                      ? base.color?.withOpacity(0.08)
                      : (r.isOdd ? base.color?.withOpacity(0.03) : null),
                ),
                children: <Widget>[
                  for (var c = 0; c < colCount; c++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Text.rich(
                        TextSpan(children: parseInline(
                          c < rows[r].length ? rows[r][c] : '',
                          base.copyWith(
                            fontSize: (base.fontSize ?? 14) * 0.92,
                            fontWeight: r == 0 ? FontWeight.w700 : null,
                          ),
                        )),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 对话气泡里的 Markdown 渲染入口。
///
/// 与 [Text] 同参用法，但支持常见 Markdown 与对话高亮；
/// 不识别任何语法时表现与普通 [Text] 一致（性能差异可忽略：一次正则扫描）。
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.data, {super.key, this.style, this.highlights});

  final String data;
  final TextStyle? style;

  /// 传了就整套替换高亮色（气泡里需要单色时用），不传按主题明暗取默认色
  final MarkdownHighlightColors? highlights;

  @override
  Widget build(BuildContext context) {
    final effective = style ??
        DefaultTextStyle.of(context).style.copyWith(fontSize: 15, height: 1.6);
    final brightness = Theme.of(context).brightness;
    final blocks = buildMarkdownBlocks(
      data,
      base: effective,
      codeBackground: effective.color?.withOpacity(0.08),
      quoteBarColor: effective.color?.withOpacity(0.30),
      highlights: highlights ?? MarkdownHighlightColors.of(brightness),
    );
    if (blocks.length == 1) return blocks.first;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }
}
