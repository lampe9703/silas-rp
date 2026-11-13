import '../../../core/db/app_database.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/time_utils.dart';
import '../domain/session_tag.dart';

/// 会话标签的数据访问。
///
/// 标签库（[SessionTag]）+ 关联表（谁贴了哪个）分开存，
/// 会话被删时关联行随外键级联消失，标签本身留在库里继续复用。
class SessionTagDao {
  SessionTagDao(this._db);

  final AppDatabase _db;

  /// 标签库，按使用次数排序：常用的自然浮到前面。
  ///
  /// use_count 现算而不是读缓存列：会话被删时关联行是外键级联清的，
  /// 缓存列不会跟着变，留着旧数字反而误导。
  List<SessionTag> all() => _db
      .select(
        'SELECT t.id, t.name, t.created_at, t.updated_at, '
        '  (SELECT COUNT(*) FROM session_tag_links WHERE tag_id = t.id) '
        '    AS use_count '
        'FROM session_tags t '
        'ORDER BY use_count DESC, t.name COLLATE NOCASE ASC',
      )
      .map(SessionTag.fromRow)
      .toList();

  /// 批量取多个会话的标签：`sessionId -> tags`
  Map<String, List<SessionTag>> bySessions(List<String> sessionIds) {
    if (sessionIds.isEmpty) return const <String, List<SessionTag>>{};
    final placeholders = List<String>.filled(sessionIds.length, '?').join(',');
    final rows = _db.select(
      'SELECT l.session_id AS link_session_id, t.* FROM session_tag_links l '
      'JOIN session_tags t ON t.id = l.tag_id '
      'WHERE l.session_id IN ($placeholders) '
      'ORDER BY t.name COLLATE NOCASE ASC',
      sessionIds,
    );
    final out = <String, List<SessionTag>>{};
    for (final row in rows) {
      final sid = row['link_session_id'] as String?;
      if (sid == null) continue;
      out.putIfAbsent(sid, () => <SessionTag>[]).add(SessionTag.fromRow(row));
    }
    return out;
  }

  /// 按名字取标签，没有就建一个（大小写与空格都规整过）
  SessionTag ensure(String rawName) {
    final name = rawName.trim();
    final rows = _db.select(
      'SELECT * FROM session_tags WHERE name = ? COLLATE NOCASE',
      [name],
    );
    if (rows.isNotEmpty) return SessionTag.fromRow(rows.first);

    final now = nowMs();
    final tag = SessionTag(
      id: newId(),
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    _db.execute(
      'INSERT INTO session_tags (id, name, use_count, created_at, updated_at) '
      'VALUES (?,?,0,?,?)',
      [tag.id, tag.name, now, now],
    );
    return tag;
  }

  /// 给一批会话贴一批标签（重复贴不会报错）
  void attachMany(List<String> sessionIds, List<String> tagIds) {
    if (sessionIds.isEmpty || tagIds.isEmpty) return;
    final now = nowMs();
    for (final sessionId in sessionIds) {
      for (final tagId in tagIds) {
        _db.execute(
          'INSERT OR IGNORE INTO session_tag_links '
          '(session_id, tag_id, created_at) VALUES (?,?,?)',
          [sessionId, tagId, now],
        );
      }
    }
  }

  /// 从一批会话上摘掉一个标签
  void detachMany(List<String> sessionIds, String tagId) {
    if (sessionIds.isEmpty) return;
    final placeholders = List<String>.filled(sessionIds.length, '?').join(',');
    _db.execute(
      'DELETE FROM session_tag_links '
      'WHERE tag_id = ? AND session_id IN ($placeholders)',
      <Object?>[tagId, ...sessionIds],
    );
  }

  /// 删掉整个标签（关联行随外键级联清除）
  void deleteTag(String tagId) {
    _db.execute('DELETE FROM session_tags WHERE id = ?', [tagId]);
  }

}
