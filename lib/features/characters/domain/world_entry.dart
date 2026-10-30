import 'dart:convert';

/// 世界书条目。
///
/// 契约对齐「幻梦」的写卡表单：
/// * `constant`：常驻条目，相当于往角色定义里追加一段设定；
/// * `keyword`：命中 keywords 里的任意词时才注入。
///
/// 条目随身携带顺序与触发概率：顺序越大越靠近 context 结尾（优先级越高），
/// 概率按会话种子掷一次并固定，避免同一会话里人设忽有忽无。
enum WorldEntryKind { constant, keyword }

class WorldEntry {
  const WorldEntry({
    this.id = '',
    this.enabled = true,
    this.kind = WorldEntryKind.keyword,
    this.comment = '',
    this.keywords = '',
    this.insertionOrder = 100,
    this.probability = 100,
    this.content = '',
  });

  final String id;

  /// 条目名，仅用于编辑器里辨认
  final String comment;
  final bool enabled;
  final WorldEntryKind kind;

  /// 半角逗号分隔的关键词，仅 keyword 条目使用
  final String keywords;
  final int insertionOrder;

  /// 0–100，100 表示必定触发
  final int probability;
  final String content;

  bool get isConstant => kind == WorldEntryKind.constant;

  bool get hasContent => content.trim().isNotEmpty;

  List<String> get keywordList => keywords
      .split(RegExp(r'[,，]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// 关键词命中（大小写不敏感的子串匹配，中文不分词）
  bool matches(String text) {
    if (!enabled || !hasContent) return false;
    if (isConstant) return true;
    final lower = text.toLowerCase();
    for (final word in keywordList) {
      if (lower.contains(word.toLowerCase())) return true;
    }
    return false;
  }

  /// 按概率掷一次。种子固定时结果固定（同一会话内不会来回跳）。
  bool passesProbability(int seed) {
    if (probability >= 100) return true;
    if (probability <= 0) return false;
    final mixed = (seed ^ (id.hashCode * 2654435761)) & 0x7fffffff;
    return mixed % 100 < probability;
  }

  WorldEntry copyWith({
    String? id,
    bool? enabled,
    WorldEntryKind? kind,
    String? comment,
    String? keywords,
    int? insertionOrder,
    int? probability,
    String? content,
  }) =>
      WorldEntry(
        id: id ?? this.id,
        enabled: enabled ?? this.enabled,
        kind: kind ?? this.kind,
        comment: comment ?? this.comment,
        keywords: keywords ?? this.keywords,
        insertionOrder: insertionOrder ?? this.insertionOrder,
        probability: probability ?? this.probability,
        content: content ?? this.content,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'enabled': enabled,
        'kind': kind.name,
        'comment': comment,
        'keywords': keywords,
        'insertion_order': insertionOrder,
        'probability': probability,
        'content': content,
      };

  factory WorldEntry.fromJson(Map<String, dynamic> json) => WorldEntry(
        id: (json['id'] as String?) ?? '',
        enabled: (json['enabled'] as bool?) ?? true,
        kind: (json['kind'] as String?) == WorldEntryKind.constant.name
            ? WorldEntryKind.constant
            : WorldEntryKind.keyword,
        comment: (json['comment'] as String?) ?? '',
        keywords: (json['keywords'] as String?) ?? '',
        insertionOrder: (json['insertion_order'] as num?)?.toInt() ?? 100,
        probability: ((json['probability'] as num?)?.toInt() ?? 100)
            .clamp(0, 100)
            .toInt(),
        content: (json['content'] as String?) ?? '',
      );

  /// 解析卡片里存的世界书 JSON；坏数据一律按空处理
  static List<WorldEntry> decodeList(Object? raw) {
    if (raw == null) return const <WorldEntry>[];
    Object? decoded = raw;
    if (raw is String) {
      if (raw.trim().isEmpty) return const <WorldEntry>[];
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return const <WorldEntry>[];
      }
    }
    if (decoded is! List) return const <WorldEntry>[];
    return decoded
        .whereType<Map>()
        .map((e) => WorldEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static String encodeList(List<WorldEntry> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());
}
