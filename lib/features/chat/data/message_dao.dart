import '../../../core/db/app_database.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/time_utils.dart';
import '../domain/chat_models.dart';

/// 消息数据访问。
///
/// 性能要点：
/// 1. 分页用 seq 游标（键集分页），不用 OFFSET；
/// 2. 流式过程中只更新 content 单列，靠 250ms 节流控制写入频率；
/// 3. 上下文构建从近到远取，由上层按 token 预算裁剪。
class MessageDao {
  MessageDao(this._db);

  final AppDatabase _db;

  int nextSeq(String sessionId) {
    final rows = _db.select(
      'SELECT COALESCE(MAX(seq), 0) + 1 AS s FROM messages WHERE session_id = ?',
      [sessionId],
    );
    return (rows.first['s'] as int?) ?? 1;
  }

  ChatMessage append({
    required String sessionId,
    required ChatRole role,
    required String content,
    String reasoning = '',
    MessageStatus status = MessageStatus.done,
    int? seq,
    String? variantGroup,
    int variantIndex = 0,
    String? model,
    String? apiConfigId,
    int? tokenCount,
  }) {
    final now = nowMs();
    final message = ChatMessage(
      id: newId(),
      sessionId: sessionId,
      seq: seq ?? nextSeq(sessionId),
      role: role,
      content: content,
      reasoning: reasoning,
      status: status,
      variantGroup: variantGroup,
      variantIndex: variantIndex,
      model: model,
      apiConfigId: apiConfigId,
      tokenCount: tokenCount,
      createdAt: now,
      updatedAt: now,
    );
    _db.execute(
      '''
INSERT INTO messages (
  id, session_id, seq, role, content, reasoning, status, variant_group,
  variant_index, is_active_variant, excluded_from_context, token_count, model,
  api_config_id, created_at, updated_at
) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
''',
      <Object?>[
        message.id,
        message.sessionId,
        message.seq,
        message.role.name,
        message.content,
        message.reasoning,
        message.status.name,
        message.variantGroup,
        message.variantIndex,
        1,
        0,
        message.tokenCount,
        message.model,
        message.apiConfigId,
        message.createdAt,
        message.updatedAt,
      ],
    );
    return message;
  }

  /// 流式增量写入：只更新 content 单列
  void updateContent(String messageId, String content) {
    _db.execute(
      'UPDATE messages SET content = ?, updated_at = ? WHERE id = ?',
      [content, nowMs(), messageId],
    );
  }

  /// 流式增量写入思考过程（与 content 分开一列，互不覆盖）
  void updateReasoning(String messageId, String reasoning) {
    _db.execute(
      'UPDATE messages SET reasoning = ?, updated_at = ? WHERE id = ?',
      [reasoning, nowMs(), messageId],
    );
  }

  void finalize(
    String messageId, {
    required MessageStatus status,
    required String content,
    String? reasoning,
    int? tokenCount,
    String? finishReason,
    int? latencyMs,
    String? errorMessage,
  }) {
    _db.execute(
      'UPDATE messages SET content = ?, status = ?, token_count = ?, '
      'finish_reason = ?, latency_ms = ?, error_message = ?, '
      'reasoning = COALESCE(?, reasoning), updated_at = ? WHERE id = ?',
      [
        content,
        status.name,
        tokenCount,
        finishReason,
        latencyMs,
        errorMessage,
        reasoning,
        nowMs(),
        messageId,
      ],
    );
  }

  /// 键集分页：取 seq < beforeSeq 的最近 [limit] 条（倒序返回）
  List<ChatMessage> page(
    String sessionId, {
    int? beforeSeq,
    int limit = 40,
  }) {
    final rows = beforeSeq == null
        ? _db.select(
            'SELECT * FROM messages WHERE session_id = ? AND is_active_variant = 1 '
            'ORDER BY seq DESC LIMIT ?',
            [sessionId, limit],
          )
        : _db.select(
            'SELECT * FROM messages WHERE session_id = ? AND is_active_variant = 1 '
            'AND seq < ? ORDER BY seq DESC LIMIT ?',
            [sessionId, beforeSeq, limit],
          );
    return rows.map(ChatMessage.fromRow).toList();
  }

  /// 上下文构建：从近到远，最多取 [limit] 条
  List<ChatMessage> contextWindow(String sessionId, {int limit = 200}) {
    final rows = _db.select(
      'SELECT * FROM messages WHERE session_id = ? AND is_active_variant = 1 '
      'AND excluded_from_context = 0 AND length(content) > 0 '
      'ORDER BY seq DESC LIMIT ?',
      [sessionId, limit],
    );
    final list = rows.map(ChatMessage.fromRow).toList();
    return list.reversed.toList();
  }

  List<ChatMessage> variants(String sessionId, int seq) {
    final rows = _db.select(
      'SELECT * FROM messages WHERE session_id = ? AND seq = ? ORDER BY variant_index',
      [sessionId, seq],
    );
    return rows.map(ChatMessage.fromRow).toList();
  }

  /// 切换变体：先取消旧的 active，再置新的（唯一索引要求顺序）
  void activateVariant(String sessionId, int seq, String messageId) {
    _db.transaction(() {
      _db.execute(
        'UPDATE messages SET is_active_variant = 0 '
        'WHERE session_id = ? AND seq = ? AND is_active_variant = 1',
        [sessionId, seq],
      );
      _db.execute(
        'UPDATE messages SET is_active_variant = 1 WHERE id = ?',
        [messageId],
      );
    });
  }

  /// 取消某条消息的生效状态（重新生成时，先置旧变体为非激活再插入新变体）
  void deactivateVariant(String messageId) {
    _db.execute(
      'UPDATE messages SET is_active_variant = 0 WHERE id = ?',
      [messageId],
    );
  }

  void updateContentById(String messageId, String content, int? tokenCount) {
    _db.execute(
      'UPDATE messages SET content = ?, token_count = ?, updated_at = ? WHERE id = ?',
      [content, tokenCount, nowMs(), messageId],
    );
  }

  void setExcluded(String messageId, bool excluded) {
    _db.execute(
      'UPDATE messages SET excluded_from_context = ? WHERE id = ?',
      [excluded ? 1 : 0, messageId],
    );
  }

  void delete(String messageId) {
    _db.execute('DELETE FROM messages WHERE id = ?', [messageId]);
  }

  /// 删除某条及之后的所有消息（编辑上一条消息时使用）
  void deleteFrom(String sessionId, int seq) {
    _db.execute(
      'DELETE FROM messages WHERE session_id = ? AND seq >= ?',
      [sessionId, seq],
    );
  }

  int countBySession(String sessionId) {
    final rows = _db.select(
      'SELECT COUNT(*) AS c FROM messages WHERE session_id = ?',
      [sessionId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }
}
