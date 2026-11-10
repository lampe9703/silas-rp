import 'dart:convert';

import '../../features/characters/domain/character_card.dart';
import 'status_parser.dart';

/// 审校级别。error = 这轮基本白写了；warn = 需要看一眼；info = 仅供参考。
enum AuditSeverity {
  info('提示'),
  warn('注意'),
  error('问题');

  const AuditSeverity(this.label);

  final String label;
}

/// 审校项。每一条都能落到「哪句话有问题」，否则用户无从判断。
enum AuditIssueType {
  emptyReply('回复过短'),
  refusal('疑似拒绝编写'),
  missingStatus('缺少状态块'),
  statusIncomplete('状态块不完整'),
  statusRepeated('状态值未更新'),
  stateJump('记忆体档位跳变'),
  personaDrift('人称漂移'),
  oocMeta('出戏的元话语'),
  decidingForUser('疑似替玩家做决定'),
  repetition('与上一轮重复');

  const AuditIssueType(this.label);

  final String label;
}

class AuditIssue {
  const AuditIssue({
    required this.type,
    required this.severity,
    required this.detail,
    this.evidence,
  });

  final AuditIssueType type;
  final AuditSeverity severity;

  /// 一句话说明「哪里不对、该怎么改」
  final String detail;

  /// 命中的原文片段（截断），没有则为 null
  final String? evidence;

  Map<String, dynamic> toJson() => <String, dynamic>{
        't': type.name,
        's': severity.name,
        'd': detail,
        if (evidence != null && evidence!.isNotEmpty) 'e': evidence,
      };

  static AuditIssue? fromJson(Map<String, dynamic> json) {
    final typeName = json['t'] as String?;
    AuditIssueType? type;
    for (final candidate in AuditIssueType.values) {
      if (candidate.name == typeName) {
        type = candidate;
        break;
      }
    }
    if (type == null) return null;
    final sevName = json['s'] as String?;
    final severity = AuditSeverity.values.firstWhere(
      (s) => s.name == sevName,
      orElse: () => AuditSeverity.info,
    );
    return AuditIssue(
      type: type,
      severity: severity,
      detail: (json['d'] as String?) ?? '',
      evidence: json['e'] as String?,
    );
  }
}

/// 一轮回复的审校结果。
class AuditReport {
  const AuditReport(this.issues);

  static const AuditReport clean = AuditReport(<AuditIssue>[]);

  final List<AuditIssue> issues;

  bool get isClean => issues.isEmpty;

  int countOf(AuditSeverity severity) =>
      issues.where((i) => i.severity == severity).length;

  AuditSeverity get worst {
    if (issues.any((i) => i.severity == AuditSeverity.error)) {
      return AuditSeverity.error;
    }
    if (issues.any((i) => i.severity == AuditSeverity.warn)) {
      return AuditSeverity.warn;
    }
    return AuditSeverity.info;
  }

  /// 排序：问题 → 注意 → 提示
  List<AuditIssue> get sorted {
    final list = List<AuditIssue>.from(issues);
    list.sort((a, b) => b.severity.index.compareTo(a.severity.index));
    return list;
  }

  String toJsonString() => jsonEncode(<String, dynamic>{
        'issues': issues.map((i) => i.toJson()).toList(),
      });

  static AuditReport? fromJsonString(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final list = decoded['issues'];
      if (list is! List) return null;
      final issues = <AuditIssue>[];
      for (final item in list) {
        if (item is! Map) continue;
        final issue = AuditIssue.fromJson(Map<String, dynamic>.from(item));
        if (issue != null) issues.add(issue);
      }
      return AuditReport(issues);
    } catch (_) {
      return null;
    }
  }
}

/// 本地规则审校：零 token、纯确定性。
///
/// 只做「能用代码判」的事。语义层面的好坏（写得像不像人、尺度够不够）
/// 这里一概不碰 —— 那是模型审校的活，也最容易误报。
///
/// 设计原则：**宁可漏报，不可误报**。误报会让用户学会无视提示，
/// 这套东西就废了。所以每条规则都尽量要求「字面证据」。
class ResponseAuditor {
  const ResponseAuditor();

  /// 审校一轮输出。
  ///
  /// [raw] 是含状态块的原始输出（不是剥掉状态块之后的正文），
  /// 否则状态相关检查全部失效。
  /// [previousStatus] 必须是**合并之前**的状态，用于判断记忆体是否跳档。
  AuditReport audit({
    required String raw,
    required CharacterCard card,
    String narrativeMode = 'character',
    Map<String, dynamic>? previousStatus,
    String? previousAssistantText,
    String? finishReason,
  }) {
    final issues = <AuditIssue>[];
    final knownKeys = <String>{
      ...?previousStatus?.keys,
      ...StatusParser.seedFromTemplate(card.statusTemplate).keys,
      ...card.statusInitial.keys,
    };
    final parsed = StatusParser.parse(raw, knownKeys: knownKeys);
    final body = parsed.visibleText.trim();

    // ---------- 1. 空回复 / 过短 ----------
    final bare = _normalize(body);
    if (bare.length < 12) {
      issues.add(const AuditIssue(
        type: AuditIssueType.emptyReply,
        severity: AuditSeverity.error,
        detail: '正文几乎没有内容。若是被 max_tokens 截断，建议调高「单次回复上限」；'
            '若是模型自己停了，这轮需要重roll。',
      ));
    }

    if (finishReason == 'content_filter') {
      issues.add(const AuditIssue(
        type: AuditIssueType.refusal,
        severity: AuditSeverity.error,
        detail: '服务端返回了内容过滤（content_filter），这轮被上游拦掉了。'
            '可以换个模型或降低触发词密度再试。',
      ));
    }

    // 叙述部分：去掉对白引号与 ``` 块之后的文本。
    // 对白里出现「我不能」「她伸手」都是合法的，必须排除，否则全是误报。
    final narration = _stripDialogue(body);
    final narrationBare = _normalize(narration);

    // ---------- 2. 状态块 ----------
    if (card.statusEnabled) {
      _auditStatus(
        issues: issues,
        card: card,
        parsedStatus: parsed.status,
        previousStatus: previousStatus,
      );
    }

    // ---------- 3. 拒绝编写 ----------
    _auditRefusal(issues, narrationBare, raw);

    // ---------- 4. 人称 / 视角漂移 ----------
    _auditPersona(issues, narrativeMode, narrationBare, raw);

    // ---------- 5. 出戏的元话语 ----------
    _auditMetaTalk(issues, narrationBare);

    // ---------- 6. 替玩家做决定 ----------
    _auditDecidingForUser(issues, narration);

    // ---------- 7. 与上一轮重复 ----------
    if (previousAssistantText != null && previousAssistantText.trim().isNotEmpty) {
      _auditRepetition(issues, bare, previousAssistantText);
    }

    return issues.isEmpty ? AuditReport.clean : AuditReport(issues);
  }

  // ---------------------------------------------------------------------------
  // 状态块
  // ---------------------------------------------------------------------------

  void _auditStatus({
    required List<AuditIssue> issues,
    required CharacterCard card,
    required Map<String, dynamic>? parsedStatus,
    required Map<String, dynamic>? previousStatus,
  }) {
    if (parsedStatus == null || parsedStatus.isEmpty) {
      issues.add(const AuditIssue(
        type: AuditIssueType.missingStatus,
        severity: AuditSeverity.error,
        detail: '这张卡开了状态栏，但本轮没有输出状态块，状态栏会停在上一轮。'
            '检查状态栏规则是否被上下文挤掉，或模型是否漏了结尾的围栏。',
      ));
      return;
    }

    // 期望的键 = 初始状态 + 模板条目
    final expected = <String>{
      ...card.statusInitial.keys,
      ...StatusParser.seedFromTemplate(card.statusTemplate).keys,
    };
    final missing = expected.where((k) => _blank(parsedStatus[k])).toList();
    if (missing.isNotEmpty) {
      issues.add(AuditIssue(
        type: AuditIssueType.statusIncomplete,
        severity: AuditSeverity.warn,
        detail: '状态块缺了 ${missing.length} 项：${missing.join('、')}。'
            '模型常把没变化的项省掉，长期会丢字段。',
        evidence: missing.join('、'),
      ));
    }

    // 值没变：写卡时最常见的「机械重复」
    if (previousStatus != null) {
      final repeated = <String>[];
      for (final entry in parsedStatus.entries) {
        final prev = previousStatus[entry.key];
        if (prev == null) continue;
        final a = _normalize(StatusParser.displayValue(prev));
        final b = _normalize(StatusParser.displayValue(entry.value));
        if (a.isEmpty || b.isEmpty) continue;
        if (a == b && b.length >= 2) repeated.add(entry.key);
      }
      if (repeated.isNotEmpty) {
        issues.add(AuditIssue(
          type: AuditIssueType.statusRepeated,
          severity: AuditSeverity.warn,
          detail: '${repeated.length} 项状态与上一轮一字不差：${repeated.join('、')}。'
              '状态栏应该写「本轮的变化」，不是复述。',
          evidence: repeated.join('、'),
        ));
      }

      // 记忆体档位跳变
      _auditStateJump(issues, parsedStatus, previousStatus);
    }
  }

  /// 记忆体（`P3-C1-S1-T3-X2` 这种）逐段比对：
  /// 前进两档以上、或回退两档以上，都说明「没有事件驱动就跳了」。
  void _auditStateJump(
    List<AuditIssue> issues,
    Map<String, dynamic> current,
    Map<String, dynamic> previous,
  ) {
    String? memKey;
    for (final key in current.keys) {
      if (key.contains('记忆')) {
        memKey = key;
        break;
      }
    }
    if (memKey == null) return;

    final prev = _parseMemory(StatusParser.displayValue(previous[memKey]));
    final cur = _parseMemory(StatusParser.displayValue(current[memKey]));
    if (prev.isEmpty || cur.isEmpty) return;

    final jumps = <String>[];
    for (final entry in cur.entries) {
      final before = prev[entry.key];
      if (before == null) continue;
      final delta = entry.value - before;
      if (delta >= 2) {
        jumps.add('${entry.key}$before → ${entry.key}${entry.value}');
      } else if (delta <= -2) {
        jumps.add('${entry.key}$before 回退到 ${entry.key}${entry.value}');
      }
    }
    if (jumps.isEmpty) return;
    issues.add(AuditIssue(
      type: AuditIssueType.stateJump,
      severity: AuditSeverity.warn,
      detail: '记忆体一跨就是两档以上：${jumps.join('；')}。'
          '档位应该由具体事件逐步推进，跨档会让角色语气断层。',
      evidence: jumps.join('；'),
    ));
  }

  Map<String, int> _parseMemory(String value) {
    final out = <String, int>{};
    final segRe = RegExp(r'^([A-Za-z]+)(\d+)$');
    for (final seg in value.split(RegExp(r'[-–—\s]+'))) {
      final m = segRe.firstMatch(seg.trim());
      if (m == null) continue;
      final letter = m.group(1)!.toUpperCase();
      final num = int.tryParse(m.group(2)!);
      if (num == null) continue;
      out[letter] = num;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // 拒绝 / 漂移 / 元话语
  // ---------------------------------------------------------------------------

  static final List<RegExp> _refusalPatterns = <RegExp>[
    RegExp(r'作为(一个)?(ai|人工智能|语言模型|助手)'),
    RegExp(r'(我|本模型)(无法|不能|不方便)(继续|生成|提供|完成|描写)'),
    RegExp(r'(抱歉|对不起)[，,。！!]?\s*(我|这个|此类)'),
    RegExp(r'涉及(到)?(不适当|不当|敏感|违规)'),
    RegExp(r'(不符合|违反)(内容|社区|安全)(政策|准则|规范)'),
    RegExp(r'建议(你|您)(换个|调整|修改)(话题|方向|内容)'),
    RegExp(r'as an ai|i (can ?not|can\x27t|am unable to)'),
  ];

  void _auditRefusal(List<AuditIssue> issues, String narrationBare, String raw) {
    for (final pattern in _refusalPatterns) {
      final m = pattern.firstMatch(narrationBare);
      if (m == null) continue;
      issues.add(AuditIssue(
        type: AuditIssueType.refusal,
        severity: AuditSeverity.error,
        detail: '模型在正文里说了「不做」的话，这轮基本作废。'
            '多半是提示词被截断、或卡里的露骨内容触发了上游安全策略。',
        evidence: _excerpt(narrationBare, m.start, m.end),
      ));
      return;
    }
    // 元标记泄漏：模型把 char / user / {{}} 当字面量写进正文
    final leak = RegExp(r'\{\{\s*(char|user)\s*\}\}').firstMatch(raw);
    if (leak != null) {
      issues.add(AuditIssue(
        type: AuditIssueType.personaDrift,
        severity: AuditSeverity.warn,
        detail: '正文里出现了未替换的占位符，模型把「${leak.group(0)}」当字面量抄了。'
            '这类残留会顺着历史喂回去，越滚越多。',
        evidence: leak.group(0),
      ));
    }
  }

  void _auditPersona(
    List<AuditIssue> issues,
    String narrativeMode,
    String narrationBare,
    String raw,
  ) {
    if (narrativeMode != 'author') return;
    // 第三人称叙述者不该出现第一人称自述
    final m = RegExp(r'我(们)?(?!方)').firstMatch(narrationBare);
    if (m == null) return;
    issues.add(AuditIssue(
      type: AuditIssueType.personaDrift,
      severity: AuditSeverity.warn,
      detail: '这张卡是第三人称叙述，但旁白里出现了第一人称。'
          '要么是模型把自己当成了在场角色，要么是在用旁白口吻说话。',
      evidence: _excerpt(narrationBare, m.start, m.end),
    ));
  }

  static final List<RegExp> _metaPatterns = <RegExp>[
    RegExp(r'以上(就是|便是|是)'),
    RegExp(r'(希望|祝)(你|您)(喜欢|满意|玩得)'),
    RegExp(r'让我们(继续|开始|看看)'),
    RegExp(r'这段(剧情|故事|对话)(到此|就)'),
    RegExp(r'(本次|这轮)(回复|输出)(结束|完毕)'),
    RegExp(r'如果(你|您)(想|需要|希望)(继续|更多|调整)'),
    RegExp(r'[（(]注[:：]'),
  ];

  void _auditMetaTalk(List<AuditIssue> issues, String narrationBare) {
    for (final pattern in _metaPatterns) {
      final m = pattern.firstMatch(narrationBare);
      if (m == null) continue;
      issues.add(AuditIssue(
        type: AuditIssueType.oocMeta,
        severity: AuditSeverity.warn,
        detail: '旁白里出现了对剧情的总结/引导/服务性话语，属于出戏。'
            '角色卡通常明令禁止这类「作者冒头」。',
        evidence: _excerpt(narrationBare, m.start, m.end),
      ));
      return;
    }
  }

  /// 「替玩家做决定」只抓强意图词，避免把被动生理反应误判。
  static final RegExp _decideStrong = RegExp(
    r'(她|他|少女|user|她则|只见她)\s*(决定|选择|打算|主动|试图|准备|想要|情愿|同意)',
  );
  static final RegExp _decideWeak = RegExp(
    r'(她|少女)\s*(伸手|抬起|走向|转身|站起|坐下|跪下|脱下|解开|凑近|抱住|握住|开口说)',
  );

  void _auditDecidingForUser(List<AuditIssue> issues, String narration) {
    final strong = _decideStrong.firstMatch(narration);
    if (strong != null) {
      issues.add(AuditIssue(
        type: AuditIssueType.decidingForUser,
        severity: AuditSeverity.warn,
        detail: '旁白替玩家做了决定（「${strong.group(2)}」这类意图）。'
            '多数角色卡要求玩家的关键行动只能由玩家输入，'
            '这里应改成被动反应（她被碰到时缩了一下），而不是主动意愿。',
        evidence: _excerpt(narration, strong.start, strong.end),
      ));
      return;
    }
    final weak = _decideWeak.firstMatch(narration);
    if (weak != null) {
      issues.add(AuditIssue(
        type: AuditIssueType.decidingForUser,
        severity: AuditSeverity.info,
        detail: '旁白写了一个主动动作（「${weak.group(2)}」），可能是替玩家做了行动。'
            '如果这不是玩家上一条输入里说的，建议改成被动描写。',
        evidence: _excerpt(narration, weak.start, weak.end),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // 重复
  // ---------------------------------------------------------------------------

  void _auditRepetition(
    List<AuditIssue> issues,
    String currentBare,
    String previousRaw,
  ) {
    final prevBare = _normalize(previousRaw);
    if (prevBare.isEmpty || currentBare.isEmpty) return;

    // 1) 8 字以上的连续相同片段 —— 基本等于复制
    final run = _longestSharedRun(currentBare, prevBare, minLen: 8);
    if (run != null) {
      issues.add(AuditIssue(
        type: AuditIssueType.repetition,
        severity: AuditSeverity.warn,
        detail: '与上一轮有 ${run.length} 个字完全一样，属于复制上一轮的句子。'
            '同类描写要换角度（写变化、写另一处细节），不是换个同义词。',
        evidence: run,
      ));
    }

    // 2) 整体措辞高度重合（bigram 相似度）
    final ratio = _bigramSimilarity(currentBare, prevBare);
    if (ratio >= 0.55) {
      issues.add(AuditIssue(
        type: AuditIssueType.repetition,
        severity: AuditSeverity.info,
        detail: '本轮与上一轮的用词重合度 ${(ratio * 100).round()}%，'
            '读起来会像在原地打转。',
      ));
    }
  }

  String? _longestSharedRun(String a, String b, {int minLen = 8}) {
    if (a.length < minLen || b.length < minLen) return null;
    final limit = a.length > 6000 ? 6000 : a.length;
    String? best;
    var bestLen = minLen - 1;
    var i = 0;
    while (i + minLen <= limit) {
      final probe = a.substring(i, i + minLen);
      if (!b.contains(probe)) {
        i++;
        continue;
      }
      var len = minLen;
      while (i + len < limit && b.contains(a.substring(i, i + len + 1))) {
        len++;
      }
      if (len > bestLen) {
        bestLen = len;
        best = a.substring(i, i + len);
      }
      i += len;
    }
    return best;
  }

  double _bigramSimilarity(String a, String b) {
    final sa = _bigrams(a);
    final sb = _bigrams(b);
    if (sa.isEmpty || sb.isEmpty) return 0;
    final inter = sa.intersection(sb).length;
    final union = sa.union(sb).length;
    return union == 0 ? 0 : inter / union;
  }

  Set<String> _bigrams(String s) {
    final out = <String>{};
    for (var i = 0; i + 1 < s.length; i++) {
      out.add(s.substring(i, i + 2));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // 工具
  // ---------------------------------------------------------------------------

  /// 只保留汉字、字母、数字，用于相似度与关键词匹配。
  /// 用白名单而不是黑名单：标点形态太多（全角/半角/引号/省略号），
  /// 漏掉一个就会让相似度虚高。
  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'[^\u4e00-\u9fa5A-Za-z0-9]'), '');

  static final RegExp _fenceBlock = RegExp(r'```[\s\S]*?```');
  static final RegExp _quoted = RegExp(
    r'"[^"\n]{0,600}"|“[^”\n]{0,600}”|「[^」\n]{0,600}」|『[^』\n]{0,600}』',
  );

  /// 去掉 ``` 块（心理活动）与对白引号内容，只留旁白
  static String _stripDialogue(String text) =>
      text.replaceAll(_fenceBlock, '\n').replaceAll(_quoted, ' ');

  /// 状态值是否为空。displayValue 对 null 返回 '—'，要单独认一下。
  static bool _blank(dynamic value) {
    if (value == null) return true;
    final text = StatusParser.displayValue(value).trim();
    return text.isEmpty || text == '—';
  }

  static String _excerpt(String text, int start, int end) {
    final from = start - 12 < 0 ? 0 : start - 12;
    final to = end + 12 > text.length ? text.length : end + 12;
    return text.substring(from, to);
  }
}
