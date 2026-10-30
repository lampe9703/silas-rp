import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_providers.dart';
import '../../../../core/utils/time_utils.dart';
import '../../domain/usage_models.dart';

class StatsState {
  const StatsState({
    required this.range,
    this.totals = const UsageTotals(),
    this.byModel = const <UsageAggregate>[],
    this.byCard = const <UsageAggregate>[],
    this.trend = const <UsagePoint>[],
    this.logs = const <ApiCallLog>[],
    this.hasMoreLogs = false,
    this.loading = false,
    this.detailFilterModel,
  });

  final StatsRange range;
  final UsageTotals totals;
  final List<UsageAggregate> byModel;
  final List<UsageAggregate> byCard;
  final List<UsagePoint> trend;
  final List<ApiCallLog> logs;
  final bool hasMoreLogs;
  final bool loading;
  final String? detailFilterModel;

  StatsState copyWith({
    StatsRange? range,
    UsageTotals? totals,
    List<UsageAggregate>? byModel,
    List<UsageAggregate>? byCard,
    List<UsagePoint>? trend,
    List<ApiCallLog>? logs,
    bool? hasMoreLogs,
    bool? loading,
    String? detailFilterModel,
    bool clearModelFilter = false,
  }) =>
      StatsState(
        range: range ?? this.range,
        totals: totals ?? this.totals,
        byModel: byModel ?? this.byModel,
        byCard: byCard ?? this.byCard,
        trend: trend ?? this.trend,
        logs: logs ?? this.logs,
        hasMoreLogs: hasMoreLogs ?? this.hasMoreLogs,
        loading: loading ?? this.loading,
        detailFilterModel:
            clearModelFilter ? null : (detailFilterModel ?? this.detailFilterModel),
      );
}

class StatsController extends Notifier<StatsState> {
  static const int logPageSize = 30;

  @override
  StatsState build() {
    final range = _buildRange(StatsRangeKind.today);
    return _load(range);
  }

  static StatsRange _buildRange(
    StatsRangeKind kind, {
    DateTimeRange? custom,
  }) {
    final now = DateTime.now();
    switch (kind) {
      case StatsRangeKind.today:
        final start = startOfDay(now);
        return StatsRange(
          kind: kind,
          startMs: start.millisecondsSinceEpoch,
          endMs: now.millisecondsSinceEpoch,
          label: '今日',
        );
      case StatsRangeKind.week:
        final start = startOfWeek(now);
        return StatsRange(
          kind: kind,
          startMs: start.millisecondsSinceEpoch,
          endMs: now.millisecondsSinceEpoch,
          label: '本周',
        );
      case StatsRangeKind.month:
        final start = startOfMonth(now);
        return StatsRange(
          kind: kind,
          startMs: start.millisecondsSinceEpoch,
          endMs: now.millisecondsSinceEpoch,
          label: '本月',
        );
      case StatsRangeKind.all:
        return StatsRange(
          kind: kind,
          startMs: DateTime(2020, 1, 1).millisecondsSinceEpoch,
          endMs: now.millisecondsSinceEpoch,
          label: '全部',
        );
      case StatsRangeKind.custom:
        final start = custom?.start ?? startOfMonth(now);
        final end = custom?.end ?? now;
        return StatsRange(
          kind: kind,
          startMs: startOfDay(start).millisecondsSinceEpoch,
          endMs: DateTime(end.year, end.month, end.day, 23, 59, 59)
              .millisecondsSinceEpoch,
          label: '自定义',
        );
    }
  }

  StatsState _load(StatsRange range, {String? modelFilter}) {
    final dao = ref.read(usageDaoProvider);
    final fromDay = dayKeyFromMs(range.startMs);
    final toDay = dayKeyFromMs(range.endMs);

    final trend = range.hourly
        ? dao.trendByHour(range.startMs, range.endMs)
        : dao.trendByDay(fromDay, toDay);

    final logs = dao.logs(
      fromMs: range.startMs,
      toMs: range.endMs,
      model: modelFilter,
      limit: logPageSize,
    );

    return StatsState(
      range: range,
      totals: dao.totals(fromDay, toDay),
      byModel: dao.byModel(fromDay, toDay),
      byCard: dao.byCard(fromDay, toDay),
      trend: trend,
      logs: logs,
      hasMoreLogs: logs.length >= logPageSize,
      detailFilterModel: modelFilter,
    );
  }

  void setKind(StatsRangeKind kind, {DateTimeRange? custom}) {
    state = state.copyWith(loading: true);
    state = _load(_buildRange(kind, custom: custom));
  }

  void refresh() {
    state = _load(state.range, modelFilter: state.detailFilterModel);
  }

  void filterByModel(String? model) {
    state = state.copyWith(loading: true);
    state = _load(state.range, modelFilter: model);
  }

  void loadMoreLogs() {
    if (!state.hasMoreLogs || state.logs.isEmpty) return;
    final last = state.logs.last;
    final more = ref.read(usageDaoProvider).logs(
          fromMs: state.range.startMs,
          toMs: state.range.endMs,
          model: state.detailFilterModel,
          cursorAt: last.requestAt,
          cursorId: last.id,
          limit: logPageSize,
        );
    state = state.copyWith(
      logs: <ApiCallLog>[...state.logs, ...more],
      hasMoreLogs: more.length >= logPageSize,
    );
  }

  void clearAll() {
    ref.read(usageDaoProvider).clearAll();
    state = _load(state.range);
  }
}

final statsProvider = NotifierProvider<StatsController, StatsState>(
  StatsController.new,
);
