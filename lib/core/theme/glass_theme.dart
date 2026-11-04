import 'dart:ui';

import 'package:flutter/material.dart';

import 'fonts.dart';
import 'jelly.dart';

/// 毛玻璃设计系统。
///
/// 配色取自参考前端卡的马卡龙色系（淡蓝 #97D8FA / 淡粉 #F7ADCC），
/// 结构参考「moeli 阅读」：悬浮胶囊导航、磨砂层、大圆角浅色卡片、克制的分隔线。
/// 触摸反馈统一走 [JellyPress] 的果冻液泡物理。
class GlassPalette {
  const GlassPalette._();

  // ── 文字 ──
  static const Color ink = Color(0xFF40566F);
  static const Color inkSoft = Color(0xFF60758D);
  static const Color inkFaint = Color(0xFF91AEC2);

  static const Color inkDark = Color(0xFFE8F0F8);
  static const Color inkSoftDark = Color(0xFFA9BCD0);
  static const Color inkFaintDark = Color(0xFF7C90A6);

  // ── 主色 ──
  static const Color sky = Color(0xFF7FBEE8);
  static const Color skyDeep = Color(0xFF4A8FBF);
  static const Color skySoft = Color(0xFF97D8FA);

  static const Color rose = Color(0xFFE879A9);
  static const Color roseSoft = Color(0xFFF7ADCC);

  static const Color mint = Color(0xFF7FCFB6);
  static const Color amber = Color(0xFFE9B872);
  static const Color lilac = Color(0xFFA99BE0);

  // ── 环境光（背景光斑）──
  static const Color ambientTop = Color(0xFFEAF4FC);
  static const Color ambientBottom = Color(0xFFFBF3F8);
  static const Color ambientDarkTop = Color(0xFF101821);
  static const Color ambientDarkBottom = Color(0xFF171220);

  static Color inkOf(Brightness b) => b == Brightness.dark ? inkDark : ink;
  static Color inkSoftOf(Brightness b) =>
      b == Brightness.dark ? inkSoftDark : inkSoft;
  static Color inkFaintOf(Brightness b) =>
      b == Brightness.dark ? inkFaintDark : inkFaint;

  /// 玻璃填充：亮色是「白上叠白」，暗色是「深蓝上叠亮」
  static Color glassFill(Brightness b, {double alpha = 0.62}) =>
      b == Brightness.dark
          ? const Color(0xFF1A2431).withOpacity(alpha.clamp(0.0, 0.92))
          : Colors.white.withOpacity(alpha.clamp(0.0, 0.96));

  static Color glassBorder(Brightness b) => b == Brightness.dark
      ? Colors.white.withOpacity(0.10)
      : Colors.white.withOpacity(0.62);

  static Color hairline(Brightness b) => b == Brightness.dark
      ? Colors.white.withOpacity(0.06)
      : const Color(0xFF7EBFE7).withOpacity(0.22);

  /// [accent]：投影晕染色。默认是经典雾蓝，各调用方应传入当前主题色，
  /// 这样用户改了「主题色」后，玻璃面板下那团柔光会跟着变。
  static List<BoxShadow> shadow(
    Brightness b, {
    double lift = 1,
    Color? accent,
  }) =>
      b == Brightness.dark
          ? <BoxShadow>[
              BoxShadow(
                color: Colors.black.withOpacity(0.34 * lift),
                blurRadius: 28 * lift,
                offset: Offset(0, 10 * lift),
              ),
            ]
          : <BoxShadow>[
              BoxShadow(
                color: (accent ?? const Color(0xFF457DA4))
                    .withOpacity(0.16 * lift),
                blurRadius: 30 * lift,
                offset: Offset(0, 12 * lift),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.55),
                blurRadius: 0,
                offset: const Offset(0, 1),
                spreadRadius: 0,
              ),
            ];

  /// 按索引取一组柔和的强调色，用于标签/图表
  static const List<Color> accents = <Color>[
    sky,
    rose,
    mint,
    amber,
    lilac,
    skyDeep,
  ];

  static Color accentAt(int i) => accents[i % accents.length];
}

/// 当前主题色。
///
/// AppTheme 会把设置里的「主题色」写进 ColorScheme.primary（亮色取深一档、
/// 暗色取浅一档），所以组件里一律从这里取，不要再写死 GlassPalette.sky ——
/// 写死的话用户改了主题色，这些地方不会跟着变。
Color accentOf(BuildContext context) =>
    Theme.of(context).colorScheme.primary;

/// 主题色的弱化版：用于次要文字/小字，既跟随主题色又不抢主体。
Color accentFaintOf(BuildContext context, [double amount = 0.45]) {
  final brightness = Theme.of(context).brightness;
  return Color.lerp(
    GlassPalette.inkFaintOf(brightness),
    accentOf(context),
    amount,
  )!;
}

/// 毛玻璃面板：背景模糊 + 半透明渐变 + 1px 高光描边 + 柔和投影。
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = const EdgeInsets.all(16),
    this.blur = 18,
    this.alpha = 0.62,
    this.tint,
    this.margin,
    this.onTap,
    this.borderAlpha,
    this.lift = 1,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final double alpha;
  final Color? tint;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double? borderAlpha;
  final double lift;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final radiusValue = BorderRadius.circular(radius);
    final baseFill = GlassPalette.glassFill(brightness, alpha: alpha);
    final topColor = tint == null ? baseFill : Color.alphaBlend(tint!, baseFill);
    final bottomColor = Color.alphaBlend(
      (tint ?? (brightness == Brightness.dark
              ? const Color(0xFF22303F)
              : Colors.white))
          .withOpacity(0.10),
      baseFill,
    );

    final content = Container(
      decoration: BoxDecoration(
        borderRadius: radiusValue,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[topColor, bottomColor],
        ),
        border: Border.all(
          color: GlassPalette.glassBorder(brightness)
              .withOpacity(borderAlpha ?? (brightness == Brightness.dark ? 0.10 : 0.62)),
          width: 1,
        ),
        boxShadow: GlassPalette.shadow(
          brightness,
          lift: lift,
          accent: Theme.of(context).colorScheme.primary,
        ),
      ),
      child: Padding(padding: padding, child: child),
    );

    final clipped = ClipRRect(
      borderRadius: radiusValue,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: content,
      ),
    );

    if (onTap == null) {
      return margin == null ? clipped : Padding(padding: margin!, child: clipped);
    }
    // 果冻液泡按压：本体（磨砂片）不动，上层灰色液泡放大上跃后弹性回缩
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: JellyPress(
        radius: radius,
        onTap: onTap,
        child: clipped,
      ),
    );
  }
}

/// 全局环境光背景：三团柔和光斑 + 渐变底色，供玻璃层模糊取色。
///
/// [accent] / [spot] 为用户自定义的主题色 / 点缀色（十六进制解析而来）；
/// null 时用默认的马卡龙淡蓝 / 粉红。
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    super.key,
    required this.child,
    this.accent,
    this.spot,
  });

  final Widget child;

  /// 主题色（默认淡蓝 skySoft）
  final Color? accent;

  /// 点缀色（默认粉红 roseSoft）
  final Color? spot;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = this.accent ?? GlassPalette.skySoft;
    final spot = this.spot ?? GlassPalette.roseSoft;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const <Color>[GlassPalette.ambientDarkTop, GlassPalette.ambientDarkBottom]
              : const <Color>[GlassPalette.ambientTop, GlassPalette.ambientBottom],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -140,
            left: -110,
            child: _Blob(
              size: 420,
              color: accent.withOpacity(isDark ? 0.22 : 0.55),
            ),
          ),
          Positioned(
            top: 180,
            right: -150,
            child: _Blob(
              size: 460,
              color: spot.withOpacity(isDark ? 0.18 : 0.42),
            ),
          ),
          Positioned(
            bottom: -180,
            left: -60,
            child: _Blob(
              size: 420,
              color: (isDark ? GlassPalette.skyDeep : GlassPalette.mint)
                  .withOpacity(isDark ? 0.20 : 0.30),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withOpacity(0)],
            stops: const <double>[0.0, 1.0],
          ),
        ),
      ),
    );
  }
}

/// 悬浮胶囊导航（参考 moeli 阅读）。
///
/// 关键：每个 tab 固定等宽，选中态由背后一块**独立滑动的灰色液泡**表示
/// （[JellyIndicator]：起跳膨胀 → 飞行拉伸 → 落地果冻回弹）。
/// 不要用「改选中项 padding」来做高亮——那会让整行每帧重新布局，正是之前卡顿的来源。
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<GlassNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const Duration _duration = Duration(milliseconds: 260);
  static const Curve _curve = Curves.easeOutCubic;

  /// 导航胶囊高度：从 60 提到 68，图标与文字都更从容，页面不再显得紧凑
  static const double barHeight = 68;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        const double padH = 6;
        // floor 取整：否则 4 * cellWidth 可能比可用宽度多出零点几像素，
        // Flutter 会把它判定为 RenderFlex 溢出并画出黄黑警示条。
        final cellWidth =
            ((constraints.maxWidth - padH * 2) / items.length).floorToDouble();

        return ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
              height: barHeight,
              padding: const EdgeInsets.symmetric(horizontal: padH, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? <Color>[
                          Colors.white.withOpacity(0.12),
                          Colors.white.withOpacity(0.06),
                        ]
                      : <Color>[
                          Colors.white.withOpacity(0.92),
                          Colors.white.withOpacity(0.74),
                        ],
                ),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.10)
                      : Colors.white.withOpacity(0.95),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    // 晕染色跟随当前主题色（默认雾蓝只是初值）
                    color: accentOf(context)
                        .withOpacity(isDark ? 0.30 : 0.16),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              // 液泡上跃/膨胀会超出胶囊内边距，不能裁剪
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  JellyIndicator(
                    cellWidth: cellWidth,
                    index: currentIndex,
                    height: barHeight - 12,
                    radius: 22,
                    color: accentOf(context),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (var i = 0; i < items.length; i++)
                        SizedBox(
                          width: cellWidth,
                          child: _NavCell(
                            item: items[i],
                            selected: i == currentIndex,
                            onTap: () => onSelected(i),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class GlassNavItem {
  const GlassNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 选中态用主题色：改「主题色」时导航栏要跟着变
    final activeColor = accentOf(context);
    final idleColor = GlassPalette.inkFaintOf(
      isDark ? Brightness.dark : Brightness.light,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedScale(
              scale: selected ? 1.0 : 0.92,
              duration: GlassNavBar._duration,
              curve: GlassNavBar._curve,
              child: Icon(
                selected ? item.activeIcon : item.icon,
                size: 22,
                color: selected ? activeColor : idleColor,
              ),
            ),
            const SizedBox(height: 3),
            // 只动画颜色，不动字号字重，避免文本重新测量；
            // FittedBox 兜底：标签再长也只是等比缩小，不会撑破单元格
            AnimatedDefaultTextStyle(
              duration: GlassNavBar._duration,
              curve: GlassNavBar._curve,
              // AnimatedDefaultTextStyle 会整段替换上层 DefaultTextStyle，
              // 不显式带字体族的话，导航标签会掉回系统字体
              style: TextStyle(
                fontSize: 10.5,
                height: 1.1,
                fontFamily: kCjkFamily,
                fontWeight: FontWeight.w500,
                color: selected ? activeColor : idleColor,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(item.label, maxLines: 1, softWrap: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 与导航胶囊同高的圆形玻璃按钮（搜索入口等）
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 60,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final button = ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? <Color>[
                      Colors.white.withOpacity(0.12),
                      Colors.white.withOpacity(0.06),
                    ]
                  : <Color>[
                      Colors.white.withOpacity(0.92),
                      Colors.white.withOpacity(0.74),
                    ],
            ),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.10)
                  : Colors.white.withOpacity(0.95),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accentOf(context).withOpacity(isDark ? 0.30 : 0.16),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Icon(
                icon,
                size: 22,
                color: isDark ? Colors.white : GlassPalette.ink,
              ),
            ),
          ),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// 右下角悬浮玻璃胶囊按钮（搜索入口）。
///
/// 形状参考旧版角色卡仓库右下角的「编写角色卡」悬浮框：大圆角矩形胶囊、
/// 轻投影悬浮感；配色保持现有玻璃白。按压反馈是果冻液泡。
/// 高度 54：与 68 的导航胶囊形成主次分明的比例，不再显得小气。
class GlassPillButton extends StatelessWidget {
  const GlassPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.height = 54,
    this.width,
    this.iconSize = 24,
    this.labelSize = 15,
    this.hPadding = 24,
    this.tooltip,
  });

  /// 统一宽度：多个入口用同一个值就等宽（搜索、收起人设等）
  static const double sharedWidth = 112;

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double height;

  /// 传了就固定宽度，内容超出时整体等比缩小
  final double? width;
  final double iconSize;
  final double labelSize;
  final double hPadding;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : GlassPalette.ink;

    final capsule = ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          width: width,
          height: height,
          padding: EdgeInsets.symmetric(horizontal: hPadding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? <Color>[
                      Colors.white.withOpacity(0.12),
                      Colors.white.withOpacity(0.06),
                    ]
                  : <Color>[
                      Colors.white.withOpacity(0.92),
                      Colors.white.withOpacity(0.74),
                    ],
            ),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.10)
                  : Colors.white.withOpacity(0.95),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accentOf(context).withOpacity(isDark ? 0.30 : 0.16),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: iconSize, color: foreground),
                const SizedBox(width: 9),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: labelSize,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final wrapped = JellyPress(
      radius: height / 2,
      onTap: onTap,
      child: capsule,
    );

    if (tooltip == null) return wrapped;
    return Tooltip(message: tooltip!, child: wrapped);
  }
}

/// 小标签胶囊（标签、模型名、状态值等）
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.label,
    this.color,
    this.onTap,
    this.onDeleted,
    this.dense = false,
    this.selected = false,
  });

  final String label;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;
  final bool dense;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    // 默认 accent 跟随主题色（用户自定义主题色后标签也换色）
    final accent = color ?? Theme.of(context).colorScheme.primary;
    final bg = selected
        ? accent.withOpacity(brightness == Brightness.dark ? 0.34 : 0.22)
        : (brightness == Brightness.dark
            ? Colors.white.withOpacity(0.07)
            : Colors.white.withOpacity(0.62));
    final fg = selected
        ? (brightness == Brightness.dark ? Colors.white : GlassPalette.ink)
        : GlassPalette.inkSoftOf(brightness);

    final content = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 10,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected
              ? accent.withOpacity(0.55)
              : GlassPalette.hairline(brightness),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 10.5 : 12,
              height: 1.2,
              color: fg,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (onDeleted != null) ...<Widget>[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onDeleted,
              child: Icon(Icons.close_rounded, size: 12, color: fg),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}

/// 分组标题（参考 moeli 的浅灰小标题）
class GlassSectionLabel extends StatelessWidget {
  const GlassSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: Row(
        children: <Widget>[
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
              color: GlassPalette.inkFaintOf(brightness),
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
