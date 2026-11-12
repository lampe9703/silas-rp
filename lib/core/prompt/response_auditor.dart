import 'dart:convert';

import 'status_parser.dart';

/// 审校级别。
enum AuditSeverity {
  info('提示'),
  warn('注意'),
  error('问题');

  const AuditSeverity(this.label);

  final String label;
}

/// 审校项。
///
/// 目前只保留「拒绝编写」一类：模型在正文里说"不写了"是本应用唯一
/// 必须让用户看见的失败 —— 这轮直接作废，重 roll 就行。
/// 其余检查（状态块、记忆体跳档、人称漂移、重复、替玩家决定）在实际使用中
/// 误报偏多，用户会习惯性无视，反而稀释了这一条的份量，已移除。
enum AuditIssueType {
  refusal('拒绝编写');

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

  /// 一句话说明「哪里不对、该怎么办」
  final String detail;

  /// 命中的原文片段（截断），没有则为 null
  final String? evidence;

  Map<String, dynamic> toJson() => <String, dynamic>{
        't': type.name,
        's': severity.name,
        'd': detail,
        if (evidence != null && evidence!.isNotEmpty) 'e': evidence,
      };

  /// 无法识别的类型返回 null：旧版本存下来的其它检查项会被静默丢弃，
  /// 不会因为枚举收缩而解析失败。
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
      orElse: () => AuditSeverity.error,
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

  AuditSeverity get worst {
    if (issues.any((i) => i.severity == AuditSeverity.error)) {
      return AuditSeverity.error;
    }
    if (issues.any((i) => i.severity == AuditSeverity.warn)) {
      return AuditSeverity.warn;
    }
    return AuditSeverity.info;
  }

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
/// 只查一件事：**模型有没有拒绝写**。语义好坏一概不碰。
class ResponseAuditor {
  const ResponseAuditor();

  /// 审校一轮输出。[raw] 是含状态块的原始输出。
  AuditReport audit({required String raw, String? finishReason}) {
    final issues = <AuditIssue>[];

    if (finishReason == 'content_filter') {
      issues.add(const AuditIssue(
        type: AuditIssueType.refusal,
        severity: AuditSeverity.error,
        detail: '服务端返回了内容过滤（content_filter），这轮被上游拦掉了。'
            '可以换个模型，或把这段改得含蓄一点再试。',
      ));
      return AuditReport(issues);
    }

    // 状态块先剥掉：状态值里也可能出现"抱歉"之类的词，不该算拒绝。
    final body = StatusParser.parse(raw).visibleText;
    // 只留旁白：对白里的「我不能」是角色在说话，合法。
    final bare = _normalize(_stripDialogue(body));

    for (final pattern in _refusalPatterns) {
      final m = pattern.firstMatch(bare);
      if (m == null) continue;
      issues.add(AuditIssue(
        type: AuditIssueType.refusal,
        severity: AuditSeverity.error,
        detail: '模型在正文里说了「不做」的话，这轮基本作废。'
            '多半是提示词被截断、或卡里的内容触发了上游安全策略。',
        evidence: _excerpt(bare, m.start, m.end),
      ));
      break;
    }

    return issues.isEmpty ? AuditReport.clean : AuditReport(issues);
  }

  static final List<RegExp> _refusalPatterns = <RegExp>[
    RegExp(r'作为(一个)?(ai|人工智能|语言模型|助手)', caseSensitive: false),
    RegExp(r'(我|本模型)(无法|不能|不方便)(继续|生成|提供|完成|描写)'),
    RegExp(r'(抱歉|对不起)[，,。！!]?\s*(我|这个|此类)'),
    RegExp(r'涉及(到)?(不适当|不当|敏感|违规)'),
    RegExp(r'(不符合|违反)(内容|社区|安全)(政策|准则|规范)'),
    RegExp(r'建议(你|您)(换个|调整|修改)(话题|方向|内容)'),
    RegExp(r'as an ai|i (can ?not|can\x27t|am unable to)', caseSensitive: false),
  ];

  /// 只保留汉字、字母、数字，用于关键词匹配。
  /// 用白名单而不是黑名单：标点形态太多（全角/半角/引号/省略号），
  /// 漏掉一个就会让匹配失效。
  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'[^\u4e00-\u9fa5A-Za-z0-9]'), '');

  static final RegExp _fenceBlock = RegExp(r'```[\s\S]*?```');
  static final RegExp _quoted = RegExp(
    r'"[^"\n]{0,600}"|“[^”\n]{0,600}”|「[^」\n]{0,600}」|『[^』\n]{0,600}』',
  );

  /// 去掉 ``` 块（心理活动）与对白引号内容，只留旁白
  static String _stripDialogue(String text) =>
      text.replaceAll(_fenceBlock, '\n').replaceAll(_quoted, ' ');

  static String _excerpt(String text, int start, int end) {
    final from = start - 12 < 0 ? 0 : start - 12;
    final to = end + 12 > text.length ? text.length : end + 12;
    return text.substring(from, to);
  }
}
