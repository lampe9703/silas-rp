/// 金额统一用「微单位」（1e-6 货币单位）的整数存储与传递。
/// 浮点数累加在统计场景会漂，这是必须的。
String currencySymbol(String currency) {
  switch (currency.toUpperCase()) {
    case 'CNY':
    case 'RMB':
      return '¥';
    case 'USD':
      return r'$';
    case 'EUR':
      return '€';
    default:
      return '';
  }
}

String formatMicros(int micros, {String currency = 'USD'}) {
  final value = micros / 1000000.0;
  final symbol = currencySymbol(currency);
  if (value == 0) return '$symbol${0.toStringAsFixed(4)}';
  if (value < 0.0001) return '$symbol<0.0001';
  if (value < 1) return '$symbol${value.toStringAsFixed(4)}';
  return '$symbol${value.toStringAsFixed(3)}';
}

/// 单价输入框友好展示：微单位 / 1M token → 货币值
String formatUnitPrice(int microsPer1M, {String currency = 'USD'}) {
  final value = microsPer1M / 1000000.0;
  return '${currencySymbol(currency)}${value.toStringAsFixed(value >= 1 ? 2 : 4)}';
}

String formatTokens(int tokens) {
  if (tokens < 1000) return '$tokens';
  if (tokens < 1000000) {
    final v = tokens / 1000.0;
    return '${v.toStringAsFixed(v >= 100 ? 0 : 1)}k';
  }
  final v = tokens / 1000000.0;
  return '${v.toStringAsFixed(v >= 100 ? 0 : 2)}M';
}

String formatDuration(int ms) {
  if (ms < 1000) return '${ms}ms';
  final s = ms / 1000.0;
  if (s < 60) return '${s.toStringAsFixed(1)}s';
  return '${(s / 60).floor()}m${(s % 60).round()}s';
}
