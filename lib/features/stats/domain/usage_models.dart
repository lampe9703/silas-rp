class ApiCallLog {
  const ApiCallLog({
    required this.id,
    required this.requestAt,
    this.sessionId,
    this.messageId,
    this.cardId,
    this.cardName = '',
    this.apiConfigId,
    this.model = '',
    required this.status,
    this.httpStatus,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.isEstimated = false,
    this.costMicros = 0,
    this.latencyMs = 0,
    this.ttftMs,
    this.errorCode,
  });

  final String id;
  final int requestAt;
  final String? sessionId;
  final String? messageId;
  final String? cardId;
  final String cardName;
  final String? apiConfigId;
  final String model;

  /// success | error | cancelled
  final String status;
  final int? httpStatus;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  /// 无 usage 时按规则估算，界面上标注「估算」
  final bool isEstimated;
  final int costMicros;
  final int latencyMs;
  final int? ttftMs;
  final String? errorCode;

  bool get isSuccess => status == 'success';

  factory ApiCallLog.fromRow(Map<String, Object?> row) => ApiCallLog(
        id: row['id']! as String,
        requestAt: (row['request_at'] as int?) ?? 0,
        sessionId: row['session_id'] as String?,
        messageId: row['message_id'] as String?,
        cardId: row['card_id'] as String?,
        cardName: (row['card_name'] as String?) ?? '',
        apiConfigId: row['api_config_id'] as String?,
        model: (row['model'] as String?) ?? '',
        status: (row['status'] as String?) ?? 'success',
        httpStatus: row['http_status'] as int?,
        promptTokens: (row['prompt_tokens'] as int?) ?? 0,
        completionTokens: (row['completion_tokens'] as int?) ?? 0,
        totalTokens: (row['total_tokens'] as int?) ?? 0,
        isEstimated: ((row['is_estimated'] as int?) ?? 0) == 1,
        costMicros: (row['cost_micros'] as int?) ?? 0,
        latencyMs: (row['latency_ms'] as int?) ?? 0,
        ttftMs: row['ttft_ms'] as int?,
        errorCode: row['error_code'] as String?,
      );

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'request_at': requestAt,
        'session_id': sessionId,
        'message_id': messageId,
        'card_id': cardId,
        'card_name': cardName,
        'api_config_id': apiConfigId,
        'model': model,
        'status': status,
        'http_status': httpStatus,
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
        'total_tokens': totalTokens,
        'is_estimated': isEstimated ? 1 : 0,
        'cost_micros': costMicros,
        'latency_ms': latencyMs,
        'ttft_ms': ttftMs,
        'error_code': errorCode,
      };
}

/// 汇总行（按模型 / 按角色卡共用）
class UsageAggregate {
  const UsageAggregate({
    required this.key,
    required this.label,
    this.requests = 0,
    this.errors = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.costMicros = 0,
    this.latencySumMs = 0,
  });

  final String key;
  final String label;
  final int requests;
  final int errors;
  final int promptTokens;
  final int completionTokens;
  final int costMicros;
  final int latencySumMs;

  int get totalTokens => promptTokens + completionTokens;

  double get avgLatencyMs => requests == 0 ? 0 : latencySumMs / requests;
}

class UsagePoint {
  const UsagePoint({
    required this.bucket,
    this.requests = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.costMicros = 0,
  });

  /// 天粒度时为 `MM-dd`，小时粒度时为 `HH:00`
  final String bucket;
  final int requests;
  final int promptTokens;
  final int completionTokens;
  final int costMicros;
}

class UsageTotals {
  const UsageTotals({
    this.requests = 0,
    this.errors = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.costMicros = 0,
    this.estimatedCount = 0,
  });

  final int requests;
  final int errors;
  final int promptTokens;
  final int completionTokens;
  final int costMicros;
  final int estimatedCount;

  int get totalTokens => promptTokens + completionTokens;
  double get successRate => requests == 0 ? 0 : (requests - errors) / requests;
}

enum StatsRangeKind { today, week, month, all, custom }

class StatsRange {
  const StatsRange({
    required this.kind,
    required this.startMs,
    required this.endMs,
    this.label = '',
  });

  final StatsRangeKind kind;
  final int startMs;
  final int endMs;
  final String label;

  /// 跨度 ≤ 1 天时趋势按小时展示（数据来自明细表），否则按天（来自预聚合表）
  bool get hourly => kind == StatsRangeKind.today;
}
