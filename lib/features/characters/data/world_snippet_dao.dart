import '../../../core/db/app_database.dart';
import '../domain/world_snippet.dart';

/// 世界书片段库的数据访问。
///
/// 排序：先用「被导入次数」，再用更新时间 —— 真正通用的片段自然浮到前面。
class WorldSnippetDao {
  WorldSnippetDao(this._db);

  final AppDatabase _db;

  List<WorldSnippet> list({String query = ''}) {
    final q = query.trim();
    final rows = q.isEmpty
        ? _db.select(
            'SELECT * FROM world_snippets '
            'ORDER BY use_count DESC, updated_at DESC',
          )
        : _db.select(
            'SELECT * FROM world_snippets '
            'WHERE title LIKE ? OR content LIKE ? OR tags LIKE ? '
            'ORDER BY use_count DESC, updated_at DESC',
            ['%$q%', '%$q%', '%$q%'],
          );
    return rows.map(WorldSnippet.fromRow).toList();
  }

  WorldSnippet? byId(String id) {
    final rows = _db.select(
      'SELECT * FROM world_snippets WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : WorldSnippet.fromRow(rows.first);
  }

  void save(WorldSnippet snippet) {
    _db.execute(
      'INSERT INTO world_snippets '
      '(id, title, content, kind, keywords, insertion_order, probability, '
      'tags, use_count, created_at, updated_at) '
      'VALUES (?,?,?,?,?,?,?,?,?,?,?) '
      'ON CONFLICT(id) DO UPDATE SET '
      'title = excluded.title, content = excluded.content, '
      'kind = excluded.kind, keywords = excluded.keywords, '
      'insertion_order = excluded.insertion_order, '
      'probability = excluded.probability, tags = excluded.tags, '
      'updated_at = excluded.updated_at',
      [
        snippet.id,
        snippet.title,
        snippet.content,
        snippet.kind.name,
        snippet.keywords,
        snippet.insertionOrder,
        snippet.probability,
        snippet.tags.join(','),
        snippet.useCount,
        snippet.createdAt,
        snippet.updatedAt,
      ],
    );
  }

  void delete(String id) {
    _db.execute('DELETE FROM world_snippets WHERE id = ?', [id]);
  }

  /// 导入后给用到的片段累加使用次数
  void bumpUse(Iterable<String> ids) {
    for (final id in ids) {
      _db.execute(
        'UPDATE world_snippets SET use_count = use_count + 1 WHERE id = ?',
        [id],
      );
    }
  }

  int count() {
    final rows = _db.select('SELECT COUNT(*) AS c FROM world_snippets');
    return (rows.first['c'] as int?) ?? 0;
  }
}
