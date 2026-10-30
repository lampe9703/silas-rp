import '../../features/characters/domain/world_entry.dart';
import 'token_estimator.dart';

/// 世界书激活结果。
class WorldBookActivation {
  const WorldBookActivation({
    this.included = const <WorldEntry>[],
    this.skippedByProbability = const <WorldEntry>[],
    this.droppedByBudget = const <WorldEntry>[],
    this.tokens = 0,
  });

  /// 最终注入的条目（按 insertion_order 升序，越靠后优先级越高）
  final List<WorldEntry> included;

  /// 概率没掷中的条目
  final List<WorldEntry> skippedByProbability;

  /// 命中但超出激活预算被丢弃的条目
  final List<WorldEntry> droppedByBudget;

  final int tokens;

  bool get isEmpty => included.isEmpty;

  /// 拼成一段可直接塞进 system 的文本
  String get text =>
      included.map((e) => e.content.trim()).where((e) => e.isNotEmpty).join('\n\n');
}

/// 世界书触发引擎。
///
/// 对齐幻梦的语义：
/// 1. 常驻条目全量生效；
/// 2. 关键词条目按「最近对话 + 当前输入」做子串匹配；
/// 3. 触发概率按会话种子掷一次，同一会话内结果固定；
/// 4. 全部命中后按 insertion_order 从高到低分配 token，超预算的丢弃。
class WorldBookEngine {
  const WorldBookEngine({this.estimator = const TokenEstimator()});

  final TokenEstimator estimator;

  /// 单次注入的 token 上限（幻梦「最大激活空间」的默认档）
  static const int defaultActivationBudget = 2000;

  WorldBookActivation activate({
    required List<WorldEntry> entries,
    required String recentText,
    int budget = defaultActivationBudget,
    int seed = 0,
  }) {
    if (entries.isEmpty) return const WorldBookActivation();

    final skipped = <WorldEntry>[];
    final candidates = <WorldEntry>[];
    for (final entry in entries) {
      if (!entry.enabled || !entry.hasContent) continue;
      if (!entry.matches(recentText)) continue;
      if (!entry.passesProbability(seed)) {
        skipped.add(entry);
        continue;
      }
      candidates.add(entry);
    }
    if (candidates.isEmpty) {
      return WorldBookActivation(skippedByProbability: skipped);
    }

    // 高优先级（顺序大）先占预算，但最终按顺序升序拼接
    final byPriority = <WorldEntry>[...candidates]
      ..sort((a, b) => b.insertionOrder.compareTo(a.insertionOrder));
    final dropped = <WorldEntry>[];
    final kept = <WorldEntry>[];
    var used = 0;
    for (final entry in byPriority) {
      final cost = estimator.estimate(entry.content) + 4;
      if (used + cost > budget) {
        dropped.add(entry);
        continue;
      }
      used += cost;
      kept.add(entry);
    }
    kept.sort((a, b) => a.insertionOrder.compareTo(b.insertionOrder));

    return WorldBookActivation(
      included: kept,
      skippedByProbability: skipped,
      droppedByBudget: dropped,
      tokens: used,
    );
  }
}
