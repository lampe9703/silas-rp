import '../../../core/db/app_database.dart';
import '../../../core/utils/time_utils.dart';

/// 一张卡的生成参数覆盖值。
///
/// 每个字段都可空：null 表示「用内置默认」（AppSettings 里的值）。
class CardGeneration {
  const CardGeneration({
    this.temperature,
    this.contextLimit,
    this.narrativeMode,
    this.maxReplyLength,
    this.paramsAck = false,
  });

  final double? temperature;
  final int? contextLimit;

  /// 'character' = 角色视角，'author' = 作者视角
  final String? narrativeMode;

  /// 单次回复字数上限，0 = 不限
  final int? maxReplyLength;

  /// 玩家是否已确认这张卡的参数（确认后不再弹提示）
  final bool paramsAck;

  bool get isEmpty =>
      temperature == null &&
      contextLimit == null &&
      narrativeMode == null &&
      maxReplyLength == null;
}

/// 每张卡的生成参数（叙述视角 / 温度 / 上下文上限 / 单次回复上限）。
///
/// 存在独立表里，不改 character_cards 结构；卡被删时随外键级联删除。
class CardGenerationDao {
  CardGenerationDao(this._db);

  final AppDatabase _db;

  CardGeneration? byCard(String cardId) {
    final rows = _db.select(
      'SELECT temperature, context_limit, narrative_mode, max_reply_length, '
      'params_ack FROM card_generation WHERE card_id = ?',
      [cardId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return CardGeneration(
      temperature: (row['temperature'] as num?)?.toDouble(),
      contextLimit: (row['context_limit'] as num?)?.toInt(),
      narrativeMode: row['narrative_mode'] as String?,
      maxReplyLength: (row['max_reply_length'] as num?)?.toInt(),
      paramsAck: ((row['params_ack'] as num?)?.toInt() ?? 0) == 1,
    );
  }

  void save(
    String cardId, {
    double? temperature,
    int? contextLimit,
    String? narrativeMode,
    int? maxReplyLength,
  }) {
    if (temperature == null &&
        contextLimit == null &&
        narrativeMode == null &&
        maxReplyLength == null) {
      clear(cardId);
      return;
    }
    _db.execute(
      'INSERT INTO card_generation '
      '(card_id, temperature, context_limit, narrative_mode, max_reply_length, updated_at) '
      'VALUES (?,?,?,?,?,?) '
      'ON CONFLICT(card_id) DO UPDATE SET '
      'temperature = excluded.temperature, '
      'context_limit = excluded.context_limit, '
      'narrative_mode = excluded.narrative_mode, '
      'max_reply_length = excluded.max_reply_length, '
      'updated_at = excluded.updated_at',
      [
        cardId,
        temperature,
        contextLimit,
        narrativeMode,
        maxReplyLength,
        nowMs(),
      ],
    );
  }

  /// 记录「已确认参数」。单独一个方法，避免保存参数时把确认状态覆盖掉。
  void setAcknowledged(String cardId, bool acknowledged) {
    _db.execute(
      'INSERT INTO card_generation (card_id, params_ack, updated_at) '
      'VALUES (?,?,?) '
      'ON CONFLICT(card_id) DO UPDATE SET '
      'params_ack = excluded.params_ack, updated_at = excluded.updated_at',
      [cardId, acknowledged ? 1 : 0, nowMs()],
    );
  }

  bool isAcknowledged(String cardId) => byCard(cardId)?.paramsAck ?? false;

  void clear(String cardId) {
    _db.execute('DELETE FROM card_generation WHERE card_id = ?', [cardId]);
  }
}
