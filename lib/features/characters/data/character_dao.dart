import '../../../core/db/app_database.dart';
import '../domain/character_card.dart';
import '../domain/world_entry.dart';

enum CardSort { updated, name, lastChat }

class CardCursor {
  const CardCursor({required this.sortValue, required this.id});
  final Object sortValue;
  final String id;
}

/// 角色卡数据访问。
///
/// 说明：标签与开场白是 1:N，列表页用 `group_concat` 子查询一次带出，
/// 避免「先查 N 张卡再逐张查标签」的 N+1。
class CharacterDao {
  CharacterDao(this._db);

  final AppDatabase _db;

  static const String _tagSeparator = '\u001f';

  /// 列表查询（键集分页）。
  ///
  /// [cursor] 为上一页最后一行的排序值与 id，避免 OFFSET 在大数据量下的线性扫描。
  List<CharacterCard> list({
    String? query,
    List<String> tags = const <String>[],
    CardSort sort = CardSort.updated,
    CardCursor? cursor,
    int limit = 30,
  }) {
    final where = <String>[];
    final params = <Object?>[];

    final keyword = query?.trim();
    if (keyword != null && keyword.isNotEmpty) {
      if (_db.ftsAvailable && keyword.length >= 3) {
        // trigram 分词：>=3 字符才能命中，按短语匹配避免被拆成多个词
        where.add(
          'c.rowid IN (SELECT rowid FROM character_cards_fts '
          'WHERE character_cards_fts MATCH ?)',
        );
        params.add('"${keyword.replaceAll('"', '""')}"');
      } else {
        // 1~2 字符或 FTS 不可用：LIKE 兜底
        where.add('(c.name LIKE ? OR c.description LIKE ?)');
        params.add('%$keyword%');
        params.add('%$keyword%');
      }
    }

    for (final tag in tags) {
      where.add(
        'EXISTS (SELECT 1 FROM character_tags t WHERE t.card_id = c.id AND t.tag = ?)',
      );
      params.add(tag);
    }

    String orderBy;
    switch (sort) {
      case CardSort.name:
        orderBy = 'c.name COLLATE NOCASE ASC, c.id ASC';
        break;
      case CardSort.lastChat:
        orderBy = 'COALESCE(c.last_chat_at, 0) DESC, c.id DESC';
        break;
      case CardSort.updated:
        orderBy = 'c.updated_at DESC, c.id DESC';
        break;
    }

    if (cursor != null) {
      final cmp = sort == CardSort.name ? '>' : '<';
      switch (sort) {
        case CardSort.name:
          where.add('(c.name COLLATE NOCASE, c.id) $cmp (?, ?)');
          break;
        case CardSort.lastChat:
          where.add('(COALESCE(c.last_chat_at, 0), c.id) $cmp (?, ?)');
          break;
        case CardSort.updated:
          where.add('(c.updated_at, c.id) $cmp (?, ?)');
          break;
      }
      params
        ..add(cursor.sortValue)
        ..add(cursor.id);
    }

    final sql = StringBuffer(
      'SELECT c.*, ('
      '  SELECT group_concat(t.tag, ?) FROM character_tags t WHERE t.card_id = c.id'
      ') AS tag_blob FROM character_cards c',
    );
    if (where.isNotEmpty) {
      sql.write(' WHERE ${where.join(' AND ')}');
    }
    sql.write(' ORDER BY $orderBy LIMIT ?');

    final args = <Object?>[_tagSeparator, ...params, limit];
    final rows = _db.select(sql.toString(), args);
    if (rows.isEmpty) return const <CharacterCard>[];

    final ids = rows.map((r) => r['id'] as String).toList();
    final greetings = _greetingsFor(ids);

    return rows.map((row) {
      final id = row['id'] as String;
      final blob = row['tag_blob'] as String?;
      return CharacterCard.fromRow(
        row,
        tags: (blob == null || blob.isEmpty)
            ? const <String>[]
            : blob.split(_tagSeparator),
        alternateGreetings: greetings[id] ?? const <String>[],
      );
    }).toList();
  }

  /// 批量取开场白，一次查询解决多张卡
  Map<String, List<String>> _greetingsFor(List<String> cardIds) {
    if (cardIds.isEmpty) return const <String, List<String>>{};
    final placeholders = List.filled(cardIds.length, '?').join(',');
    final rows = _db.select(
      'SELECT card_id, content FROM character_greetings '
      'WHERE card_id IN ($placeholders) ORDER BY card_id, seq',
      cardIds,
    );
    final result = <String, List<String>>{};
    for (final row in rows) {
      final cardId = row['card_id'] as String;
      (result[cardId] ??= <String>[]).add((row['content'] as String?) ?? '');
    }
    return result;
  }

  CharacterCard? byId(String id) {
    final rows = _db.select('SELECT * FROM character_cards WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final tagRows = _db.select(
      'SELECT tag FROM character_tags WHERE card_id = ? ORDER BY tag',
      [id],
    );
    final greetingRows = _db.select(
      'SELECT content FROM character_greetings WHERE card_id = ? ORDER BY seq',
      [id],
    );
    return CharacterCard.fromRow(
      rows.first,
      tags: tagRows.map((r) => r['tag'] as String).toList(),
      alternateGreetings:
          greetingRows.map((r) => (r['content'] as String?) ?? '').toList(),
    );
  }

  /// 保存（插入或更新）。
  ///
  /// 必须用 ON CONFLICT DO UPDATE 而非 INSERT OR REPLACE：
  /// REPLACE 会先 DELETE 旧行，触发 chat_sessions 的 ON DELETE CASCADE，把聊天记录一起清掉。
  void save(CharacterCard card) {
    _db.transaction(() => _saveInner(card));
  }

  /// 实际的写入逻辑（不自带事务）。
  ///
  /// 拆出来的原因：`importAll` 要把整批卡放在**同一个事务**里，
  /// 历史版本在事务里循环调 `save`（各自又 BEGIN）直接嵌套事务崩溃，
  /// 即导入必报 `cannot start a transaction within a transaction`。
  void _saveInner(CharacterCard card) {
    _db.transaction(() {
      _db.execute(
        '''
INSERT INTO character_cards (
  id, name, summary, description, personality, scenario, first_mes, mes_example,
  system_prompt, post_history_instructions, creator, card_version,
  avatar_path, source, spec, raw_json, is_favorite, created_at, updated_at, last_chat_at,
  status_enabled, status_initial, status_rules, status_template, status_format, world_book
) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(id) DO UPDATE SET
  name = excluded.name,
  summary = excluded.summary,
  description = excluded.description,
  personality = excluded.personality,
  scenario = excluded.scenario,
  first_mes = excluded.first_mes,
  mes_example = excluded.mes_example,
  system_prompt = excluded.system_prompt,
  post_history_instructions = excluded.post_history_instructions,
  creator = excluded.creator,
  card_version = excluded.card_version,
  avatar_path = excluded.avatar_path,
  source = excluded.source,
  spec = excluded.spec,
  raw_json = excluded.raw_json,
  is_favorite = excluded.is_favorite,
  status_enabled = excluded.status_enabled,
  status_initial = excluded.status_initial,
  status_rules = excluded.status_rules,
  status_template = excluded.status_template,
  status_format = excluded.status_format,
  world_book = excluded.world_book,
  updated_at = excluded.updated_at
''',
        <Object?>[
          card.id,
          card.name,
          card.summary,
          card.description,
          card.personality,
          card.scenario,
          card.firstMes,
          card.mesExample,
          card.systemPrompt,
          card.postHistoryInstructions,
          card.creator,
          card.cardVersion,
          card.avatarPath,
          card.source,
          card.spec,
          card.rawJson,
          card.isFavorite ? 1 : 0,
          card.createdAt,
          card.updatedAt,
          card.lastChatAt,
          card.statusEnabled ? 1 : 0,
          CharacterCard.encodeMap(card.statusInitial),
          card.statusRules,
          card.statusTemplate,
          card.statusFormat,
          WorldEntry.encodeList(card.worldBook),
        ],
      );

      _db.execute('DELETE FROM character_tags WHERE card_id = ?', [card.id]);
      for (final tag in card.tags) {
        final trimmed = tag.trim();
        if (trimmed.isEmpty) continue;
        _db.execute(
          'INSERT OR IGNORE INTO character_tags(card_id, tag) VALUES (?, ?)',
          [card.id, trimmed],
        );
      }

      _db.execute('DELETE FROM character_greetings WHERE card_id = ?', [
        card.id,
      ]);
      for (var i = 0; i < card.alternateGreetings.length; i++) {
        final content = card.alternateGreetings[i];
        if (content.trim().isEmpty) continue;
        _db.execute(
          'INSERT INTO character_greetings(id, card_id, seq, content) VALUES (?,?,?,?)',
          ['${card.id}_g$i', card.id, i, content],
        );
      }
    });
  }

  /// 批量导入：单事务，1000 张卡百毫秒级
  int importAll(List<CharacterCard> cards) {
    if (cards.isEmpty) return 0;
    _db.transaction(() {
      for (final card in cards) {
        _saveInner(card);
      }
    });
    return cards.length;
  }

  void delete(String id) {
    _db.execute('DELETE FROM character_cards WHERE id = ?', [id]);
  }

  void toggleFavorite(String id, bool value) {
    _db.execute(
      'UPDATE character_cards SET is_favorite = ? WHERE id = ?',
      [value ? 1 : 0, id],
    );
  }

  void touchLastChat(String id, int at) {
    _db.execute(
      'UPDATE character_cards SET last_chat_at = ? WHERE id = ?',
      [at, id],
    );
  }

  /// 全部标签及其使用次数，用于筛选栏
  List<({String tag, int count})> tagStats() {
    final rows = _db.select(
      'SELECT tag, COUNT(*) AS cnt FROM character_tags '
      'GROUP BY tag ORDER BY cnt DESC, tag ASC',
    );
    return rows
        .map((r) => (tag: r['tag'] as String, count: (r['cnt'] as int?) ?? 0))
        .toList();
  }

  int count() {
    final rows = _db.select('SELECT COUNT(*) AS c FROM character_cards');
    return (rows.first['c'] as int?) ?? 0;
  }
}


