import 'dart:convert';

import '../../../core/db/app_database.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/time_utils.dart';
import '../domain/chat_models.dart';

class SessionDao {
  SessionDao(this._db);

  final AppDatabase _db;

  ChatSession create({
    required String cardId,
    String title = '',
    int greetingSeq = 0,
  }) {
    final now = nowMs();
    final session = ChatSession(
      id: newId(),
      cardId: cardId,
      title: title,
      greetingSeq: greetingSeq,
      createdAt: now,
      updatedAt: now,
    );
    _db.execute(
      'INSERT INTO chat_sessions(id, card_id, title, greeting_seq, created_at, updated_at) '
      'VALUES (?,?,?,?,?,?)',
      [session.id, cardId, title, greetingSeq, now, now],
    );
    return session;
  }

  ChatSession? byId(String id) {
    final rows = _db.select('SELECT * FROM chat_sessions WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return ChatSession.fromRow(rows.first);
  }

  List<ChatSession> listByCard(String cardId) {
    final rows = _db.select(
      'SELECT * FROM chat_sessions WHERE card_id = ? '
      'ORDER BY COALESCE(last_message_at, created_at) DESC',
      [cardId],
    );
    return rows.map(ChatSession.fromRow).toList();
  }

  List<ChatSession> recent({int limit = 20}) {
    final rows = _db.select(
      'SELECT * FROM chat_sessions WHERE is_archived = 0 '
      'ORDER BY COALESCE(last_message_at, created_at) DESC LIMIT ?',
      [limit],
    );
    return rows.map(ChatSession.fromRow).toList();
  }

  void rename(String id, String title) {
    _db.execute(
      'UPDATE chat_sessions SET title = ?, updated_at = ? WHERE id = ?',
      [title, nowMs(), id],
    );
  }

  /// 写入状态栏快照
  void setStatusState(String id, Map<String, dynamic> state) {
    _db.execute(
      'UPDATE chat_sessions SET status_state = ? WHERE id = ?',
      [jsonEncode(state), id],
    );
  }

  void setGreetingSeq(String id, int seq) {
    _db.execute(
      'UPDATE chat_sessions SET greeting_seq = ?, updated_at = ? WHERE id = ?',
      [seq, nowMs(), id],
    );
  }

  /// 清空会话消息（保留会话本身）
  void clearMessages(String id) {
    _db.transaction(() {
      _db.execute('DELETE FROM messages WHERE session_id = ?', [id]);
      _db.execute(
        'UPDATE chat_sessions SET message_count = 0, preview_text = ?, '
        'last_message_at = NULL, last_message_role = NULL, updated_at = ? WHERE id = ?',
        ['', nowMs(), id],
      );
    });
  }

  void delete(String id) {
    _db.execute('DELETE FROM chat_sessions WHERE id = ?', [id]);
  }

  int countByCard(String cardId) {
    final rows = _db.select(
      'SELECT COUNT(*) AS c FROM chat_sessions WHERE card_id = ?',
      [cardId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }
}
