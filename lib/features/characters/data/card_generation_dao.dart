import '../../../core/db/app_database.dart';
import '../../../core/utils/time_utils.dart';

/// 一张卡的生成参数覆盖值。
///
/// 两个字段都可空：null 表示「跟随全局默认」。
class CardGeneration {
  const CardGeneration({this.temperature, this.contextLimit});

  final double? temperature;
  final int? contextLimit;

  bool get isEmpty => temperature == null && contextLimit == null;
}

/// 每张卡的生成参数（温度 / 上下文上限）。
///
/// 存在独立表里，不改 character_cards 结构；卡被删时随外键级联删除。
class CardGenerationDao {
  CardGenerationDao(this._db);

  final AppDatabase _db;

  CardGeneration? byCard(String cardId) {
    final rows = _db.select(
      'SELECT temperature, context_limit FROM card_generation WHERE card_id = ?',
      [cardId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return CardGeneration(
      temperature: (row['temperature'] as num?)?.toDouble(),
      contextLimit: (row['context_limit'] as num?)?.toInt(),
    );
  }

  void save(
    String cardId, {
    double? temperature,
    int? contextLimit,
  }) {
    if (temperature == null && contextLimit == null) {
      clear(cardId);
      return;
    }
    _db.execute(
      'INSERT INTO card_generation (card_id, temperature, context_limit, updated_at) '
      'VALUES (?,?,?,?) '
      'ON CONFLICT(card_id) DO UPDATE SET '
      'temperature = excluded.temperature, '
      'context_limit = excluded.context_limit, '
      'updated_at = excluded.updated_at',
      [cardId, temperature, contextLimit, nowMs()],
    );
  }

  void clear(String cardId) {
    _db.execute('DELETE FROM card_generation WHERE card_id = ?', [cardId]);
  }
}
