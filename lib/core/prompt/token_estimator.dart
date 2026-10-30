import 'dart:math' as math;

/// token 估算器。
///
/// 只在 API 未返回 usage 时使用，结果一律标注「估算」。
/// 规则可配置：默认按「中日韩字符 1 token ≈ 1.5 字，其他 1 token ≈ 4 字符」。
class TokenEstimator {
  const TokenEstimator({this.charsPerToken = 3.0, this.cjkOnly = false});

  /// 平均每 token 字符数（配置项，粗略调节）
  final double charsPerToken;

  /// 是否强制使用平均字符数规则（忽略中英文差异）
  final bool cjkOnly;

  static final RegExp _cjk = RegExp(
    r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff00-\uffef]',
  );

  int estimate(String text) {
    if (text.isEmpty) return 0;
    if (cjkOnly) {
      return math.max(1, (text.length / charsPerToken).ceil());
    }
    var cjk = 0;
    for (final rune in text.runes) {
      if (_cjk.hasMatch(String.fromCharCode(rune))) cjk++;
    }
    final other = text.length - cjk;
    final tokens = cjk / 1.5 + other / 4.0;
    return math.max(1, tokens.ceil());
  }

  int estimateMessages(Iterable<String> contents) =>
      contents.fold<int>(0, (sum, c) => sum + estimate(c)) +
      contents.length * 4; // 每条消息的 role/分隔开销
}

/// 费用计算。单价为「微单位 / 1M token」，结果为微单位整数。
class CostCalculator {
  const CostCalculator();

  static int costMicros({
    required int promptTokens,
    required int completionTokens,
    required int inputPer1M,
    required int outputPer1M,
  }) {
    if (inputPer1M <= 0 && outputPer1M <= 0) return 0;
    final raw = promptTokens * inputPer1M + completionTokens * outputPer1M;
    return raw ~/ 1000000;
  }
}
