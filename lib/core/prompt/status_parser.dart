import 'dart:convert';

/// 状态块解析结果
class StatusParseResult {
  const StatusParseResult({required this.visibleText, this.status});

  /// 去掉状态块之后、真正展示给用户的正文
  final String visibleText;

  /// 模型给出的状态更新（可能为 null）
  final Map<String, dynamic>? status;
}

/// 状态栏协议解析。
///
/// 支持两种模型输出：
/// * `json`：回复末尾输出
///   ```status
///   {"好感度": 35, "时间": "傍晚"}
///   ```
/// * `template`（幻梦式）：回复末尾输出
///   ```状态
///   心情：紧张
///   好感度：35
///   ```
///
/// 两种块都不会展示给用户，只用来更新会话状态。
class StatusParser {
  const StatusParser._();

  static const String fence = '```status';

  /// 幻梦式文本块的开头
  static const String templateFence = '```状态';

  /// 兼容各种围栏信息串：```status / ```状态 / ```状态栏 / ```state …
  static final RegExp _anyFence = RegExp(
    r'```[ \t]*(?:status|state|状态)[^\n`]*[ \t]*\n([\s\S]*?)```',
    caseSensitive: false,
  );

  /// 完整解析：剥离全部状态块并合并其中的键值。
  ///
  /// 围栏内的内容先按 JSON 解析，失败再按 `键：值` 逐行解析，
  /// 所以卡片里选错格式、或模型混用两种写法时依然能吃下。
  static StatusParseResult parse(String raw, {Set<String>? knownKeys}) {
    final updates = <String, dynamic>{};
    var found = false;

    for (final match in _anyFence.allMatches(raw)) {
      final body = match.group(1)?.trim() ?? '';
      if (body.isEmpty) continue;
      final parsed = _decodeStatusBody(body);
      if (parsed != null) {
        updates.addAll(parsed);
        found = true;
      }
    }

    var visible = raw.replaceAll(_anyFence, '');
    visible = _truncateOpenBlock(visible);

    // 兜底：模型忘了包围栏，但正文末尾是一串已知键的 `键：值`
    if (!found && knownKeys != null && knownKeys.isNotEmpty) {
      final tail = _extractTrailingKnownLines(visible, knownKeys);
      if (tail != null) {
        updates.addAll(tail.values);
        visible = tail.remaining;
        found = true;
      }
    }

    return StatusParseResult(
      visibleText: _tidy(visible),
      status: found ? updates : null,
    );
  }

  /// 从「状态栏模板」生成一份占位初始状态。
  ///
  /// 模板形如 `心情：<当前情绪>` / `好感度：<0-100>`，
  /// 返回 `{'心情': '未设定', '好感度': '未设定'}`。
  ///
  /// 用途：卡片只填了模板、没填初始状态时，让新会话也有状态栏可显示；
  /// 同时让 [parse] 的「尾部已知键提取」有 knownKeys 可用 ——
  /// 否则 knownKeys 为空时，模型忘了输出围栏就永远解析不到状态。
  static Map<String, dynamic> seedFromTemplate(String template) {
    final out = <String, dynamic>{};
    for (final raw in const LineSplitter().convert(template)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final cjk = line.indexOf('：');
      final ascii = line.indexOf(':');
      final sep = cjk >= 0 ? cjk : ascii;
      if (sep <= 0) continue;
      final key = line.substring(0, sep).trim();
      if (key.isEmpty || key.startsWith('#') || key.startsWith('-')) continue;
      out[key] = '未设定';
    }
    return out;
  }

  /// 流式过程中使用：只做展示，不解析（块可能还没写完）
  static String stripForDisplay(String raw) {
    var visible = raw.replaceAll(_anyFence, '');
    visible = _truncateOpenBlock(visible);
    return _tidy(visible);
  }

  /// 围栏内容：JSON 优先，失败退回逐行
  static Map<String, dynamic>? _decodeStatusBody(String body) {
    final json = _tryDecode(body);
    if (json != null) return json;
    return _parseLines(body);
  }

  /// 正文末尾若干行「已知键：值」→ 状态更新，并把这些行从正文里剥掉
  static ({Map<String, dynamic> values, String remaining})?
      _extractTrailingKnownLines(String text, Set<String> knownKeys) {
    final lines = text.split('\n');
    final collected = <MapEntry<String, dynamic>>[];
    var i = lines.length - 1;
    while (i >= 0) {
      final rawLine = lines[i].trim();
      if (rawLine.isEmpty) {
        if (collected.isEmpty) {
          i--;
          continue;
        }
        break;
      }
      final match = RegExp(r'^([^：:\n]{1,24})[：:]\s*(.+)$').firstMatch(rawLine);
      if (match == null) break;
      final key = match.group(1)!.trim();
      if (!knownKeys.contains(key)) break;
      collected.insert(0, MapEntry(key, _normalizeValue(match.group(2)!)));
      i--;
    }
    if (collected.isEmpty) return null;
    final remaining = lines.sublist(0, i + 1).join('\n');
    return (
      values: <String, dynamic>{for (final e in collected) e.key: e.value},
      remaining: remaining,
    );
  }

  /// 把 `键：值` 逐行解析成 map
  static Map<String, dynamic>? parseLines(String body) => _parseLines(body);

  /// 把状态按 `键：值` 拼回纯文本（纯文本状态栏的初始值窗口用）
  static String formatLines(Map<String, dynamic> status) => status.entries
      .map((e) => '${e.key}：${displayValue(e.value)}')
      .join('\n');

  static Map<String, dynamic>? _parseLines(String body) {
    final result = <String, dynamic>{};
    final line = RegExp(r'^\s*([^：:\n]{1,24})[：:]\s*(.+?)\s*$');
    for (final rawLine in body.split('\n')) {
      final match = line.firstMatch(rawLine);
      if (match == null) continue;
      final key = match.group(1)!.trim().replaceAll(RegExp(r'^[-*·]\s*'), '');
      if (key.isEmpty) continue;
      result[key] = _normalizeValue(match.group(2)!);
    }
    return result.isEmpty ? null : result;
  }

  /// 截断未闭合的状态块
  static String _truncateOpenBlock(String text) {
    final lower = text.toLowerCase();
    var idx = lower.lastIndexOf(fence);
    final tplIdx = text.lastIndexOf(templateFence);
    if (tplIdx > idx) idx = tplIdx;
    if (idx >= 0) {
      // 只有当它后面没有闭合的反引号时才算未闭合（已闭合的上面已被移除）
      final rest = text.substring(idx + (idx == tplIdx ? templateFence.length : fence.length));
      if (!rest.contains('```')) {
        return text.substring(0, idx);
      }
    }
    // 结尾可能是半个围栏，例如 "``" / "```statu" / "```状"
    final tail = _partialFenceSuffix(text);
    if (tail > 0) {
      return text.substring(0, text.length - tail);
    }
    return text;
  }

  /// 返回结尾处「半个围栏」的长度
  static int _partialFenceSuffix(String text) {
    var best = 0;
    for (final target in <String>[fence, templateFence]) {
      final max = text.length < target.length ? text.length : target.length;
      for (var len = max; len > 0; len--) {
        final suffix = text.substring(text.length - len).toLowerCase();
        if (target.startsWith(suffix)) {
          // 至少要以反引号开头才算围栏，避免误删正常文字
          if (suffix.startsWith('`') && len > best) best = len;
        }
      }
    }
    return best;
  }

  static String _tidy(String text) {
    var out = text.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return out.trim();
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    // 允许模型加上 ```json 之类的前后缀杂质
    var text = body.trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    text = text.substring(start, end + 1);
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final result = <String, dynamic>{};
      decoded.forEach((key, value) {
        final k = key.toString().trim();
        if (k.isEmpty) return;
        result[k] = _normalizeValue(value);
      });
      return result;
    } catch (_) {
      return null;
    }
  }

  static dynamic _normalizeValue(dynamic value) {
    if (value is num || value is bool || value == null) return value;
    if (value is String) {
      final trimmed = value.trim();
      final asInt = int.tryParse(trimmed);
      if (asInt != null) return asInt;
      final asDouble = double.tryParse(trimmed);
      if (asDouble != null) return asDouble;
      return trimmed;
    }
    return value.toString();
  }

  /// 把状态值转成适合展示的短文本
  static String displayValue(dynamic value) {
    if (value == null) return '—';
    if (value is double) {
      return value == value.roundToDouble()
          ? value.round().toString()
          : value.toStringAsFixed(1);
    }
    return value.toString();
  }

  /// 用状态值渲染「键：值」模板。
  ///
  /// 模板形如：
  /// ```
  /// 心情：<当前情绪>
  /// 好感度：<0-100>
  /// ```
  /// 有同名状态值时把「值」替换成实际值；没有则按 [status] 是否为空决定
  /// 保留原文（作者写的说明）还是显示占位「—」。
  ///
  /// [skipFirst]：跳过第一个条目（以及紧随其后的分隔线）——
  /// 折叠态已经露了第一条，展开时不必重复。
  static String renderTemplate(
    String template,
    Map<String, dynamic> status, {
    bool skipFirst = false,
  }) {
    if (template.trim().isEmpty) return '';
    final lineRe = RegExp(r'^(\s*)([^：:\n]{1,24})[：:]\s*(.*)$');
    final separatorRe = RegExp(r'^[-—_=·*]{3,}$');
    final out = <String>[];
    var skippedFirst = false;

    for (final raw in const LineSplitter().convert(template)) {
      final m = lineRe.firstMatch(raw);
      if (m == null) {
        // 跳过首条后，紧随其后的分隔线也一起去掉，避免展开时顶着一排横线
        if (skipFirst &&
            skippedFirst &&
            out.isEmpty &&
            separatorRe.hasMatch(raw.trim())) {
          continue;
        }
        out.add(raw);
        continue;
      }
      if (skipFirst && !skippedFirst) {
        skippedFirst = true;
        continue;
      }
      final indent = m.group(1)!;
      final key = m.group(2)!.trim();
      if (status.containsKey(key)) {
        out.add('$indent$key：${displayValue(status[key])}');
      } else if (status.isEmpty) {
        // 完全没有状态时保留模板原文，至少能看出条目含义
        out.add(raw);
      } else {
        out.add('$indent$key：—');
      }
    }
    return out.join('\n').trim();
  }
}
