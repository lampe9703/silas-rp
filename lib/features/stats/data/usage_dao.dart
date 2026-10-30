import '../../../core/db/app_database.dart';
import '../../../core/utils/time_utils.dart';
import '../domain/usage_models.dart';

/// 调用统计的数据访问。
///
/// 核心策略：明细表 `api_call_logs` 只服务「明细列表」（键集分页）；
/// 所有汇总/图表都读预聚合表 `api_usage_daily`，查询成本与历史总量无关。
class UsageDao {
  UsageDao(this._db);

  final AppDatabase _db;

  /// 记账：明细 + 预聚合增量，同一事务保证一致
  void record(ApiCallLog log) {
    final day = dayKeyFromMs(log.requestAt);
    final cardId = log.cardId ?? '';
    final isError = log.isSuccess ? 0 : 1;
    final total = log.totalTokens == 0
        ? log.promptTokens + log.completionTokens
        : log.totalTokens;

    _db.transaction(() {
      _db.execute(
        '''
INSERT INTO api_call_logs (
  id, request_at, session_id, message_id, card_id, card_name, api_config_id,
  model, status, http_status, prompt_tokens, completion_tokens, total_tokens,
  is_estimated, cost_micros, latency_ms, ttft_ms, error_code
) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
''',
        <Object?>[
          log.id,
          log.requestAt,
          log.sessionId,
          log.messageId,
          log.cardId,
          log.cardName,
          log.apiConfigId,
          log.model,
          log.status,
          log.httpStatus,
          log.promptTokens,
          log.completionTokens,
          total,
          log.isEstimated ? 1 : 0,
          log.costMicros,
          log.latencyMs,
          log.ttftMs,
          log.errorCode,
        ],
      );

      _db.execute(
        '''
INSERT INTO api_usage_daily
  (day, model, card_id, card_name, requests, errors, prompt_tokens,
   completion_tokens, cost_micros, latency_sum_ms)
VALUES (?,?,?,?,1,?,?,?,?,?)
ON CONFLICT(day, model, card_id) DO UPDATE SET
  requests          = requests + 1,
  errors            = errors + excluded.errors,
  prompt_tokens     = prompt_tokens + excluded.prompt_tokens,
  completion_tokens = completion_tokens + excluded.completion_tokens,
  cost_micros       = cost_micros + excluded.cost_micros,
  latency_sum_ms    = latency_sum_ms + excluded.latency_sum_ms,
  card_name         = excluded.card_name
''',
        <Object?>[
          day,
          log.model,
          cardId,
          log.cardName,
          isError,
          log.promptTokens,
          log.completionTokens,
          log.costMicros,
          log.latencyMs,
        ],
      );
    });
  }

  UsageTotals totals(String fromDay, String toDay) {
    final rows = _db.select(
      'SELECT COALESCE(SUM(requests),0) AS req, COALESCE(SUM(errors),0) AS err, '
      'COALESCE(SUM(prompt_tokens),0) AS pt, COALESCE(SUM(completion_tokens),0) AS ct, '
      'COALESCE(SUM(cost_micros),0) AS cost '
      'FROM api_usage_daily WHERE day BETWEEN ? AND ?',
      [fromDay, toDay],
    );
    final row = rows.first;
    // 估算条数只能从明细表拿，但只在当前范围内扫描，成本可控
    final est = _db.select(
      'SELECT COUNT(*) AS c FROM api_call_logs WHERE is_estimated = 1 '
      'AND request_at BETWEEN ? AND ?',
      [_msFromDay(fromDay), _msToDay(toDay)],
    );
    return UsageTotals(
      requests: (row['req'] as int?) ?? 0,
      errors: (row['err'] as int?) ?? 0,
      promptTokens: (row['pt'] as int?) ?? 0,
      completionTokens: (row['ct'] as int?) ?? 0,
      costMicros: (row['cost'] as int?) ?? 0,
      estimatedCount: (est.first['c'] as int?) ?? 0,
    );
  }

  List<UsageAggregate> byModel(String fromDay, String toDay) {
    final rows = _db.select(
      'SELECT model, SUM(requests) AS req, SUM(errors) AS err, '
      'SUM(prompt_tokens) AS pt, SUM(completion_tokens) AS ct, '
      'SUM(cost_micros) AS cost, SUM(latency_sum_ms) AS lat '
      'FROM api_usage_daily WHERE day BETWEEN ? AND ? '
      'GROUP BY model ORDER BY cost DESC, req DESC',
      [fromDay, toDay],
    );
    return rows.map((r) {
      final model = (r['model'] as String?) ?? '';
      return UsageAggregate(
        key: model,
        label: model.isEmpty ? '(未指定模型)' : model,
        requests: (r['req'] as int?) ?? 0,
        errors: (r['err'] as int?) ?? 0,
        promptTokens: (r['pt'] as int?) ?? 0,
        completionTokens: (r['ct'] as int?) ?? 0,
        costMicros: (r['cost'] as int?) ?? 0,
        latencySumMs: (r['lat'] as int?) ?? 0,
      );
    }).toList();
  }

  List<UsageAggregate> byCard(String fromDay, String toDay, {int limit = 20}) {
    final rows = _db.select(
      'SELECT card_id, MAX(card_name) AS card_name, SUM(requests) AS req, '
      'SUM(errors) AS err, SUM(prompt_tokens) AS pt, SUM(completion_tokens) AS ct, '
      'SUM(cost_micros) AS cost, SUM(latency_sum_ms) AS lat '
      'FROM api_usage_daily WHERE day BETWEEN ? AND ? '
      'GROUP BY card_id ORDER BY req DESC, cost DESC LIMIT ?',
      [fromDay, toDay, limit],
    );
    return rows.map((r) {
      final cardId = (r['card_id'] as String?) ?? '';
      final name = (r['card_name'] as String?) ?? '';
      return UsageAggregate(
        key: cardId,
        label: name.isNotEmpty ? name : (cardId.isEmpty ? '(未归属)' : '已删除角色卡'),
        requests: (r['req'] as int?) ?? 0,
        errors: (r['err'] as int?) ?? 0,
        promptTokens: (r['pt'] as int?) ?? 0,
        completionTokens: (r['ct'] as int?) ?? 0,
        costMicros: (r['cost'] as int?) ?? 0,
        latencySumMs: (r['lat'] as int?) ?? 0,
      );
    }).toList();
  }

  /// 天粒度趋势（读预聚合表）
  List<UsagePoint> trendByDay(String fromDay, String toDay) {
    final rows = _db.select(
      'SELECT day, SUM(requests) AS req, SUM(prompt_tokens) AS pt, '
      'SUM(completion_tokens) AS ct, SUM(cost_micros) AS cost '
      'FROM api_usage_daily WHERE day BETWEEN ? AND ? '
      'GROUP BY day ORDER BY day',
      [fromDay, toDay],
    );
    return rows
        .map((r) => UsagePoint(
              bucket: (r['day'] as String?) ?? '',
              requests: (r['req'] as int?) ?? 0,
              promptTokens: (r['pt'] as int?) ?? 0,
              completionTokens: (r['ct'] as int?) ?? 0,
              costMicros: (r['cost'] as int?) ?? 0,
            ))
        .toList();
  }

  /// 小时粒度趋势（今日）：走明细表，当天数据量小，扫描成本可忽略
  List<UsagePoint> trendByHour(int fromMs, int toMs) {
    final rows = _db.select(
      "SELECT strftime('%H', request_at / 1000, 'unixepoch', 'localtime') AS h, "
      'COUNT(*) AS req, COALESCE(SUM(prompt_tokens),0) AS pt, '
      'COALESCE(SUM(completion_tokens),0) AS ct, COALESCE(SUM(cost_micros),0) AS cost '
      'FROM api_call_logs WHERE request_at BETWEEN ? AND ? '
      'GROUP BY h ORDER BY h',
      [fromMs, toMs],
    );
    final map = <String, UsagePoint>{};
    for (final r in rows) {
      final h = (r['h'] as String?) ?? '00';
      map[h] = UsagePoint(
        bucket: '${h.padLeft(2, '0')}:00',
        requests: (r['req'] as int?) ?? 0,
        promptTokens: (r['pt'] as int?) ?? 0,
        completionTokens: (r['ct'] as int?) ?? 0,
        costMicros: (r['cost'] as int?) ?? 0,
      );
    }
    // 补齐 0~23 点，图表不跳点
    return List.generate(24, (i) {
      final key = i.toString().padLeft(2, '0');
      return map[key] ??
          UsagePoint(bucket: '$key:00');
    });
  }

  /// 明细列表（键集分页：request_at + id）
  List<ApiCallLog> logs({
    required int fromMs,
    required int toMs,
    String? model,
    String? cardId,
    int? cursorAt,
    String? cursorId,
    int limit = 40,
  }) {
    final where = <String>['request_at BETWEEN ? AND ?'];
    final params = <Object?>[fromMs, toMs];
    if (model != null && model.isNotEmpty) {
      where.add('model = ?');
      params.add(model);
    }
    if (cardId != null && cardId.isNotEmpty) {
      where.add('card_id = ?');
      params.add(cardId);
    }
    if (cursorAt != null) {
      where.add('(request_at, id) < (?, ?)');
      params
        ..add(cursorAt)
        ..add(cursorId ?? '');
    }
    final rows = _db.select(
      'SELECT * FROM api_call_logs WHERE ${where.join(' AND ')} '
      'ORDER BY request_at DESC, id DESC LIMIT ?',
      [...params, limit],
    );
    return rows.map(ApiCallLog.fromRow).toList();
  }

  int countLogs() {
    final rows = _db.select('SELECT COUNT(*) AS c FROM api_call_logs');
    return (rows.first['c'] as int?) ?? 0;
  }

  /// 清空统计：明细与预聚合必须一起清，否则图表与明细会对不上
  void clearAll() {
    _db.transaction(() {
      _db.execute('DELETE FROM api_call_logs');
      _db.execute('DELETE FROM api_usage_daily');
    });
    _db.execute('PRAGMA incremental_vacuum');
  }

  static int _msFromDay(String day) =>
      DateTime.parse('$day 00:00:00').millisecondsSinceEpoch;

  static int _msToDay(String day) =>
      DateTime.parse('$day 23:59:59.999').millisecondsSinceEpoch;
}
