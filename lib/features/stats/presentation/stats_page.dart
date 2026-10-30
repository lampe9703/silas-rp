import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../shared/glass_route.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/time_utils.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../settings/presentation/pricing_page.dart';
import '../domain/usage_models.dart';
import 'controllers/stats_controller.dart';
import 'widgets/usage_charts.dart';

class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  TrendMetric _metric = TrendMetric.cost;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent - 200) {
        ref.read(statsProvider.notifier).loadMoreLogs();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String get _currency {
    final pricings = ref.read(settingsRepositoryProvider).pricings();
    return pricings.isEmpty ? 'USD' : pricings.first.currency;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(statsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('API 统计'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.read(statsProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) async {
              if (value == 'clear') {
                final ok = await showConfirmDialog(
                  context,
                  title: '清空统计数据',
                  message: '所有调用明细与汇总数据都会被删除，角色卡和会话不受影响。',
                  confirmText: '清空',
                  danger: true,
                );
                if (ok) ref.read(statsProvider.notifier).clearAll();
              } else if (value == 'pricing') {
                Navigator.of(context).push(
                  glassPageRoute<void>(const PricingPage()),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'pricing', child: Text('模型单价设置')),
              PopupMenuItem(value: 'clear', child: Text('清空统计数据')),
            ],
          ),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 150),
        children: [
          _buildRangeBar(state),
          const SizedBox(height: 16),
          _buildSummary(state),
          const SizedBox(height: 20),
          _buildTrendCard(state),
          const SizedBox(height: 20),
          _buildModelShare(state),
          const SizedBox(height: 20),
          _buildByCard(state),
          const SizedBox(height: 20),
          _buildDetailList(state),
          if (state.totals.estimatedCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '其中 ${state.totals.estimatedCount} 次调用未返回 usage，token 与费用为估算值。',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRangeBar(StatsState state) {
    const kinds = <StatsRangeKind>[
      StatsRangeKind.today,
      StatsRangeKind.week,
      StatsRangeKind.month,
      StatsRangeKind.all,
      StatsRangeKind.custom,
    ];
    const labels = <StatsRangeKind, String>{
      StatsRangeKind.today: '今日',
      StatsRangeKind.week: '本周',
      StatsRangeKind.month: '本月',
      StatsRangeKind.all: '全部',
      StatsRangeKind.custom: '自定义',
    };

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kinds.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final kind = kinds[index];
          final selected = state.range.kind == kind;
          return ChoiceChip(
            label: Text(labels[kind]!),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) async {
              if (kind == StatsRangeKind.custom) {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                  initialDateRange: DateTimeRange(
                    start: startOfMonth(DateTime.now()),
                    end: DateTime.now(),
                  ),
                );
                if (picked == null) return;
                ref
                    .read(statsProvider.notifier)
                    .setKind(StatsRangeKind.custom, custom: picked);
              } else {
                ref.read(statsProvider.notifier).setKind(kind);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildSummary(StatsState state) {
    final totals = state.totals;
    return Row(
      children: [
        _summaryTile('请求次数', '${totals.requests}', '失败 ${totals.errors}'),
        const SizedBox(width: 10),
        _summaryTile(
          'Tokens',
          formatTokens(totals.totalTokens),
          '入 ${formatTokens(totals.promptTokens)} / 出 ${formatTokens(totals.completionTokens)}',
        ),
        const SizedBox(width: 10),
        _summaryTile(
          '估算费用',
          formatMicros(totals.costMicros, currency: _currency),
          '单价可在设置中配置',
        ),
      ],
    );
  }

  Widget _summaryTile(String label, String value, String hint) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  color: scheme.onSurfaceVariant.withOpacity(0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrendCard(StatsState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '调用趋势',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                _metricChip('费用', TrendMetric.cost),
                const SizedBox(width: 6),
                _metricChip('请求', TrendMetric.requests),
                const SizedBox(width: 6),
                _metricChip('Tokens', TrendMetric.tokens),
              ],
            ),
            const SizedBox(height: 12),
            TrendChart(
              points: state.trend,
              metric: _metric,
              currency: _currency,
            ),
            const SizedBox(height: 4),
            Text(
              state.range.hourly ? '按小时（今日）' : '按天',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricChip(String label, TrendMetric metric) {
    final selected = _metric == metric;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => setState(() => _metric = metric),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildModelShare(StatsState state) {
    final scheme = Theme.of(context).colorScheme;
    if (state.byModel.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '按模型',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (state.detailFilterModel != null)
                  TextButton(
                    onPressed: () =>
                        ref.read(statsProvider.notifier).filterByModel(null),
                    child: const Text('清除筛选', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SharePie(items: state.byModel, currency: _currency),
            const SizedBox(height: 10),
            const Divider(height: 1),
            for (final item in state.byModel.take(6))
              InkWell(
                onTap: () => ref
                    .read(statsProvider.notifier)
                    .filterByModel(
                      state.detailFilterModel == item.key ? null : item.key,
                    ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      SizedBox(
                        width: 52,
                        child: Text(
                          '${item.requests} 次',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 78,
                        child: Text(
                          formatTokens(item.totalTokens),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 74,
                        child: Text(
                          formatMicros(item.costMicros, currency: _currency),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildByCard(StatsState state) {
    if (state.byCard.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final maxRequests = state.byCard
        .map((e) => e.requests)
        .reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '按角色卡',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            for (final item in state.byCard.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        Text(
                          '${item.requests} 次 · ${formatMicros(item.costMicros, currency: _currency)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: maxRequests == 0
                            ? 0
                            : item.requests / maxRequests,
                        minHeight: 5,
                        backgroundColor: scheme.primary.withOpacity(0.08),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailList(StatsState state) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '调用明细',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            if (state.detailFilterModel != null)
              Chip(
                label: Text(state.detailFilterModel!),
                onDeleted: () =>
                    ref.read(statsProvider.notifier).filterByModel(null),
                visualDensity: VisualDensity.compact,
              ),
            const Spacer(),
            Text(
              '${state.logs.length}${state.hasMoreLogs ? '+' : ''} 条',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (state.logs.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: Text(
              '该区间没有调用记录',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < state.logs.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
                  _LogTile(log: state.logs[i], currency: _currency),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log, required this.currency});

  final ApiCallLog log;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final success = log.isSuccess;
    final color = success ? scheme.primary : scheme.error;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        log.model.isEmpty ? '(未指定模型)' : log.model,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      formatDateTime(log.requestAt),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        [
                          if (log.cardName.isNotEmpty) log.cardName,
                          '${formatTokens(log.totalTokens)} tok',
                          formatDuration(log.latencyMs),
                          if (!success) _statusLabel(log.status),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (log.isEstimated)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: scheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '估算',
                          style: TextStyle(
                            fontSize: 9,
                            color: scheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    Text(
                      formatMicros(log.costMicros, currency: currency),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'error':
        return '失败';
      case 'cancelled':
        return '已取消';
      default:
        return status;
    }
  }
}
