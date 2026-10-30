import 'package:intl/intl.dart';

/// 全部时间以毫秒时间戳存储，避免 TEXT 比较与时区歧义。
int nowMs() => DateTime.now().millisecondsSinceEpoch;

DateTime dateTimeFromMs(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

/// 统计用的「天」键：本地时区的 YYYY-MM-DD
String dayKey(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);

String dayKeyFromMs(int ms) => dayKey(dateTimeFromMs(ms));

DateTime startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// 周一为一周起点
DateTime startOfWeek(DateTime dt) {
  final base = startOfDay(dt);
  return base.subtract(Duration(days: base.weekday - 1));
}

DateTime startOfMonth(DateTime dt) => DateTime(dt.year, dt.month, 1);

String formatClock(int ms) => DateFormat('HH:mm').format(dateTimeFromMs(ms));

String formatDateTime(int ms) =>
    DateFormat('MM-dd HH:mm').format(dateTimeFromMs(ms));

String formatFullDateTime(int ms) =>
    DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTimeFromMs(ms));

/// 会话列表用的相对时间
String formatRelative(int ms) {
  final dt = dateTimeFromMs(ms);
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1 && now.day == dt.day) return formatClock(ms);
  if (diff.inDays < 1) return '昨天 ${formatClock(ms)}';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  if (dt.year == now.year) return DateFormat('MM-dd').format(dt);
  return DateFormat('yyyy-MM-dd').format(dt);
}
