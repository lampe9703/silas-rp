/// 会话标签（标签库中的一条）。
///
/// 标签是全局复用的：同一张卡下多个会话可以贴同一个标签，
/// [useCount] 记录被贴了多少次，用来把常用的排到前面。
class SessionTag {
  const SessionTag({
    required this.id,
    required this.name,
    this.useCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int useCount;
  final int createdAt;
  final int updatedAt;

  factory SessionTag.fromRow(Map<String, Object?> row) => SessionTag(
        id: row['id'] as String,
        name: (row['name'] as String?) ?? '',
        useCount: (row['use_count'] as int?) ?? 0,
        createdAt: (row['created_at'] as int?) ?? 0,
        updatedAt: (row['updated_at'] as int?) ?? 0,
      );
}
