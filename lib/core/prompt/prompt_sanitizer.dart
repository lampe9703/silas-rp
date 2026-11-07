import 'dart:convert';

/// 注入前的文本清洗（**只作用于发给模型的那一份**，数据库里的原文不动）。
///
/// 不少卡习惯用 YAML 块标量写世界书条目，落库后长这样：
///
/// ```
/// 内容: |-
///     # 当角色处于[P2]娇蛮人格时的行为指导
///     # 核心玩法: …
///         - 细节一
/// ```
///
/// 直接注入有三个问题：
/// 1. `内容: |-` 是 YAML 头，模型会当成"某个文件的字段"，不像指令；
/// 2. 整段缩进像代码块，层级反而模糊；
/// 3. **行首 `#` 最要命**——模型容易把 `#` 行当注释/标题跳过，
///    而这些行往往正是「核心玩法 / 态度变化 / 细节描写」这类关键标题。
///
/// 所以注入前做四件事：去 YAML 头 → dedent → 缩进封顶 → `#` 换 `·`。
/// 只在**识别到 YAML 块标量头**时才动手，普通正文原样返回，避免误伤正常排版。
class PromptSanitizer {
  const PromptSanitizer._();

  /// YAML 块标量头：`内容: |-` / `body: >` / `key: |+`
  static final RegExp _yamlHeader =
      RegExp(r'^\s*[^\s:：]{1,12}\s*[:：]\s*[|>][-+]?\s*$');

  /// 缩进上限：超过就压到 4 空格，避免整段看起来像代码块
  static const int _maxIndent = 4;

  /// 清洗一条世界书条目的正文
  static String worldEntry(String raw) {
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (text.trim().isEmpty) return '';

    final lines = text.split('\n');
    var start = 0;
    while (start < lines.length && lines[start].trim().isEmpty) {
      start++;
    }
    if (start >= lines.length) return '';
    if (!_yamlHeader.hasMatch(lines[start])) {
      // 不是 YAML 块：只做最保守的收尾（去行尾空格、压空行）
      return _tidy(lines);
    }

    final body = _dedent(lines.sublist(start + 1));
    return _tidy(body.map(_normalizeLine).toList());
  }

  /// 按最小缩进整体左移，保留相对层级
  static List<String> _dedent(List<String> lines) {
    var min = 1 << 30;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final indent = line.length - line.trimLeft().length;
      if (indent < min) min = indent;
    }
    if (min <= 0 || min == 1 << 30) return lines;
    return lines
        .map((line) =>
            line.trim().isEmpty ? '' : line.substring(min.clamp(0, line.length)))
        .toList();
  }

  /// 缩进封顶 + 行首 `#` 换成 `·`
  static String _normalizeLine(String line) {
    if (line.trim().isEmpty) return '';
    var out = line;
    final indent = out.length - out.trimLeft().length;
    if (indent > _maxIndent) {
      out = '${' ' * _maxIndent}${out.trimLeft()}';
    }
    // `# 小标题` → `· 小标题`；`## x` / `### x` 同理。
    // 用 replaceFirstMapped 而不是 `$1` 模板，避免替换串语义差异。
    return out.replaceFirstMapped(
      RegExp(r'^(\s*)#+\s*'),
      (m) => '${m.group(1)}· ',
    );
  }

  /// 收尾：去行尾空格、连续空行压成一个、去掉首尾空行
  static String _tidy(List<String> lines) {
    final out = <String>[];
    var blank = 0;
    for (final raw in lines) {
      final line = raw.replaceAll(RegExp(r'[ \t]+$'), '');
      if (line.trim().isEmpty) {
        blank++;
        if (blank > 1) continue;
        out.add('');
      } else {
        blank = 0;
        out.add(line);
      }
    }
    while (out.isNotEmpty && out.first.isEmpty) {
      out.removeAt(0);
    }
    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }
    return out.join('\n');
  }

  /// 便于调试：把清洗结果按行打印
  static List<String> debugLines(String raw) =>
      const LineSplitter().convert(worldEntry(raw));
}
