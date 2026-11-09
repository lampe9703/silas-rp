import '../../../core/utils/ids.dart';
import '../../../core/utils/time_utils.dart';
import 'world_entry.dart';

/// 世界书片段：可跨角色卡复用的条目「零件」。
///
/// 卡片是成品，片段是零件。写新卡时把「词汇规范 / 感官规范 / 心理活动格式」
/// 这类通用条目一次性导入，不用每次重新粘一遍。
///
/// 片段是**全局**的，不挂在任何卡上；导入到卡里是**复制快照**，
/// 之后片段再改也不会影响已经导入的卡（导出卡时也不会带走片段库）。
class WorldSnippet {
  const WorldSnippet({
    required this.id,
    required this.title,
    required this.content,
    this.kind = WorldEntryKind.constant,
    this.keywords = '',
    this.insertionOrder = 100,
    this.probability = 100,
    this.tags = const <String>[],
    this.useCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String content;
  final WorldEntryKind kind;
  final String keywords;
  final int insertionOrder;
  final int probability;
  final List<String> tags;

  /// 被导入过多少次，用来把真正通用的片段顶到前面
  final int useCount;

  final int createdAt;
  final int updatedAt;

  bool get hasContent => content.trim().isNotEmpty;

  /// 从卡里的世界书条目生成片段（标题缺省取条目名）
  factory WorldSnippet.fromEntry(
    WorldEntry entry, {
    String? title,
    List<String> tags = const <String>[],
    String? id,
  }) {
    final now = nowMs();
    final name = (title ?? entry.comment).trim();
    return WorldSnippet(
      id: id ?? newId(),
      title: name.isEmpty ? '未命名片段' : name,
      content: entry.content,
      kind: entry.kind,
      keywords: entry.keywords,
      insertionOrder: entry.insertionOrder,
      probability: entry.probability,
      tags: tags,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 转回世界书条目；导入到卡里时用新 id，避免和卡内已有条目撞号
  WorldEntry toEntry({String? id}) => WorldEntry(
        id: id ?? newId(),
        enabled: true,
        kind: kind,
        comment: title,
        keywords: keywords,
        insertionOrder: insertionOrder,
        probability: probability,
        content: content,
      );

  factory WorldSnippet.fromRow(Map<String, Object?> row) => WorldSnippet(
        id: row['id'] as String,
        title: (row['title'] as String?) ?? '',
        content: (row['content'] as String?) ?? '',
        kind: (row['kind'] as String?) == WorldEntryKind.constant.name
            ? WorldEntryKind.constant
            : WorldEntryKind.keyword,
        keywords: (row['keywords'] as String?) ?? '',
        insertionOrder: (row['insertion_order'] as int?) ?? 100,
        probability: (row['probability'] as int?) ?? 100,
        tags: ((row['tags'] as String?) ?? '')
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        useCount: (row['use_count'] as int?) ?? 0,
        createdAt: (row['created_at'] as int?) ?? 0,
        updatedAt: (row['updated_at'] as int?) ?? 0,
      );

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'title': title,
        'content': content,
        'kind': kind.name,
        'keywords': keywords,
        'insertion_order': insertionOrder,
        'probability': probability,
        'tags': tags.join(','),
        'use_count': useCount,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'content': content,
        'kind': kind.name,
        'keywords': keywords,
        'insertion_order': insertionOrder,
        'probability': probability,
        'tags': tags,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  static WorldSnippet? fromJson(Map<String, dynamic> json) {
    final title = (json['title'] as String?)?.trim() ?? '';
    final content = (json['content'] as String?) ?? '';
    if (title.isEmpty && content.trim().isEmpty) return null;
    final now = nowMs();
    return WorldSnippet(
      id: newId(),
      title: title.isEmpty ? '未命名片段' : title,
      content: content,
      kind: (json['kind'] as String?) == WorldEntryKind.constant.name
          ? WorldEntryKind.constant
          : WorldEntryKind.keyword,
      keywords: (json['keywords'] as String?) ?? '',
      insertionOrder: (json['insertion_order'] as num?)?.toInt() ?? 100,
      probability: ((json['probability'] as num?)?.toInt() ?? 100).clamp(0, 100),
      tags: (json['tags'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[],
      createdAt: now,
      updatedAt: now,
    );
  }

  WorldSnippet copyWith({
    String? title,
    String? content,
    WorldEntryKind? kind,
    String? keywords,
    int? insertionOrder,
    int? probability,
    List<String>? tags,
    int? useCount,
    int? updatedAt,
  }) =>
      WorldSnippet(
        id: id,
        title: title ?? this.title,
        content: content ?? this.content,
        kind: kind ?? this.kind,
        keywords: keywords ?? this.keywords,
        insertionOrder: insertionOrder ?? this.insertionOrder,
        probability: probability ?? this.probability,
        tags: tags ?? this.tags,
        useCount: useCount ?? this.useCount,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
