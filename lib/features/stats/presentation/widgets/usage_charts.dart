import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/usage_models.dart';

enum TrendMetric { cost, requests, tokens }

class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.points,
    required this.metric,
    this.currency = 'USD',
    this.height = 180,
  });

  final List<UsagePoint> points;
  final TrendMetric metric;
  final String currency;
  final double height;

  double _valueOf(UsagePoint p) {
    switch (metric) {
      case TrendMetric.cost:
        return p.costMicros / 1000000.0;
      case TrendMetric.requests:
        return p.requests.toDouble();
      case TrendMetric.tokens:
        return (p.promptTokens + p.completionTokens).toDouble();
    }
  }

  String _formatValue(double v) {
    switch (metric) {
      case TrendMetric.cost:
        return formatMicros((v * 1000000).round(), currency: currency);
      case TrendMetric.requests:
        return '${v.round()} 次';
      case TrendMetric.tokens:
        return formatTokens(v.round());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final values = points.map(_valueOf).toList();
    final maxValue = values.isEmpty ? 0.0 : values.reduce(math.max);

    if (points.isEmpty || maxValue == 0) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            '这个区间还没有数据',
            style: TextStyle(
              fontSize: 12.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final maxY = maxValue * 1.25;
    final labelStep = (points.length / 5).ceil().clamp(1, points.length);

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 3,
            getDrawingHorizontalLine: (value) => FlLine(
              color: scheme.outlineVariant.withOpacity(0.4),
              strokeWidth: 0.6,
              dashArray: const [4, 4],
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: maxY / 3,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      _compact(value),
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  if (index % labelStep != 0 &&
                      index != points.length - 1) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      points[index].bucket,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItems: (spots) => spots
                  .map((spot) => LineTooltipItem(
                        '${points[spot.x.round()].bucket}\n${_formatValue(spot.y)}',
                        TextStyle(
                          color: scheme.onInverseSurface,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ))
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i]),
              ],
              isCurved: true,
              curveSmoothness: 0.25,
              barWidth: 2.2,
              color: scheme.primary,
              dotData: FlDotData(
                show: points.length <= 12,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: 2.6,
                  color: scheme.primary,
                  strokeWidth: 0,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.primary.withOpacity(0.22),
                    scheme.primary.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _compact(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    if (value >= 1) return value.toStringAsFixed(value >= 10 ? 0 : 1);
    return value.toStringAsFixed(3);
  }
}

class SharePie extends StatelessWidget {
  const SharePie({
    super.key,
    required this.items,
    this.size = 140,
    this.currency = 'USD',
  });

  final List<UsageAggregate> items;
  final double size;
  final String currency;

  static const List<Color> _palette = <Color>[
    Color(0xFF6C5CE7),
    Color(0xFF00B894),
    Color(0xFFE17055),
    Color(0xFF0984E3),
    Color(0xFFFDCB6E),
    Color(0xFFD63031),
    Color(0xFF6D4C41),
    Color(0xFF00CEC9),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = items.take(6).toList();
    if (top.isEmpty) {
      return SizedBox(
        height: size,
        child: Center(
          child: Text(
            '暂无数据',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    // 费用未配置单价时，退化为按请求次数占比
    final useCost = top.any((e) => e.costMicros > 0);
    final total = top.fold<double>(
      0,
      (sum, e) => sum + (useCost ? e.costMicros : e.requests).toDouble(),
    );

    return Row(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: size * 0.28,
              sections: [
                for (var i = 0; i < top.length; i++)
                  PieChartSectionData(
                    value: (useCost ? top[i].costMicros : top[i].requests)
                        .toDouble(),
                    color: _palette[i % _palette.length],
                    radius: size * 0.2,
                    showTitle: total > 0 &&
                        ((useCost ? top[i].costMicros : top[i].requests) /
                                total) >
                            0.12,
                    title:
                        '${(((useCost ? top[i].costMicros : top[i].requests) / total) * 100).round()}%',
                    titleStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < top.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _palette[i % _palette.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          top[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                      Text(
                        useCost
                            ? formatMicros(top[i].costMicros, currency: currency)
                            : '${top[i].requests} 次',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
