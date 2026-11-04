/// 内置的简体中文字族（见 pubspec 的 fonts 段）。
///
/// 实际字体为霞鹜文楷（LXGW WenKai）的子集，按 OFL 保留字体名要求
/// 已改名为「Silas WenKai」，此处的 family 与 pubspec 保持一致。
///
/// 单独拆成一个文件，是为了让 `glass_theme.dart` 这类被 `app_theme.dart`
/// 依赖的模块也能拿到族名，而不用反过来 import 主题（避免循环依赖）。
const String kCjkFamily = 'SilasWenKai';

/// 需要「拉丁/等宽字形 + 中文」混排时的回退链。
///
/// 例如提示词预览用 monospace 对齐缩进，但 `monospace` 没有中文字形，
/// 不挂回退就会掉到系统字体上（就是「字体残留」的来源之一）。
const List<String> kCjkFallback = <String>[kCjkFamily];
