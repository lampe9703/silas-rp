import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_providers.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/glass_theme.dart';

/// 路由级环境光底。
///
/// 全局的 [AmbientBackdrop] 挂在 MaterialApp.builder 里、位于**整个 Navigator
/// 之后**；而被推入的页面自身是透明玻璃底。于是旧问题的链条是：
/// 转场期间新页从自己的透明背景里「透出」下面旧页的内容（浑浊的中间态），
/// 转场结束的瞬间旧路由被裁剪，透出来的内容啪地消失——即所谓中间态。
///
/// 修复：让每条 glass 路由**自带一份与环境光逐像素一致的不透明底**
/// （同一渐变、同一组光斑、同一份自定义主题色）。转场时背景视觉恒定，
/// 只有页面内容在交叉淡入，旧页被新页的环境光底干净地覆盖。
class _RouteAmbient extends ConsumerWidget {
  const _RouteAmbient({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final accent = AppTheme.parseHexColor(settings.themeAccent);
    final spot = AppTheme.parseHexColor(settings.themeSpot);
    return AmbientBackdrop(accent: accent, spot: spot, child: child);
  }
}

/// 统一的玻璃风页面转场：内容淡入 + 轻微上浮，背景（环境光）全程恒定。
///
/// 不用 MaterialPageRoute 默认的缩放转场：它在透明背景的页面上会短暂露出黑底。
Route<T> glassPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    opaque: true,
    pageBuilder: (_, __, ___) => _RouteAmbient(child: page),
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
