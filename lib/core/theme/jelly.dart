import 'package:flutter/material.dart';

import 'glass_theme.dart';

/// ── 果冻液泡交互系统 ──
///
/// 结构参考「moeli 阅读」的分层高亮 + 用户描述的液态形变：
/// * 下层：白色胶囊（按钮 / 导航容器本体），按压时**保持不动**；
/// * 上层：灰色半透明**液泡**（反馈层），按压时放大、上跃，
///   松开后以 `elasticOut` 做 squash & stretch 的类果冻回弹。
///
/// 全 App 的触摸反馈共用 [JellyPhysics] 这一套物理参数，
/// 导航滑块（[JellyIndicator]）与按压反馈（[JellyPress]）手感一致。

/// 果冻物理参数：集中一处调，全 App 一致。
class JellyPhysics {
  const JellyPhysics._();

  /// 按下：液泡快速长大并轻微上跃
  static const Duration pressIn = Duration(milliseconds: 140);

  /// 松开：elasticOut 果冻回弹（含震荡收敛）
  static const Duration release = Duration(milliseconds: 640);

  /// 液泡按压后的过冲大小
  static const double pressScale = 1.22;

  /// 液泡初始（未按压时）相对于本体的比例
  static const double restScale = 0.72;

  /// 液泡上跃距离（逻辑像素，负 = 向上）
  static const double pressLift = -3.0;

  /// 液泡可见度上限（液泡颜色自身的 alpha 之外的整体透明度峰值）
  static const double pressOpacity = 1.0;

  /// 液泡颜色：雾蓝灰（浅色模式更淡，暗色模式提亮）
  static Color bubbleColor(Brightness b) => GlassPalette.ink.withOpacity(
        b == Brightness.dark ? 0.30 : 0.18,
      );
}

/// 通用果冻按压反馈。
///
/// 用法：把任何「白色胶囊本体」包进来，按下时上层灰色液泡放大 + 上跃，
/// 松开后液泡以果冻弹性收缩回原位并渐隐。本体自身不做任何位移动画。
class JellyPress extends StatefulWidget {
  const JellyPress({
    super.key,
    required this.child,
    this.onTap,
    this.onTapDown,
    this.onTapUp,
    this.onLongPress,
    this.radius = 999,
    this.enabled = true,
    this.behavior = HitTestBehavior.opaque,
  });

  /// 白色胶囊本体（下层，动画中不动）
  final Widget child;

  final VoidCallback? onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapUp;
  final VoidCallback? onLongPress;

  /// 液泡圆角半径；999 = 全圆角胶囊
  final double radius;

  final bool enabled;
  final HitTestBehavior behavior;

  @override
  State<JellyPress> createState() => _JellyPressState();
}

class _JellyPressState extends State<JellyPress>
    with TickerProviderStateMixin {
  /// 形变进度：unbounded，elasticOut 的过冲不会被 clamp 掉。
  /// 按下：→ 1（easeOutCubic）；松开：→ 0（elasticOut，中途会冲到负值=果冻震荡）。
  late final AnimationController _morph = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  /// 透明度单独走有界控制器：果冻回弹的「渗回」比形变更快收敛。
  late final AnimationController _fade = AnimationController(
    vsync: this,
    value: 0,
  );

  bool _pressed = false;

  @override
  void dispose() {
    _morph.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _down() {
    if (!widget.enabled) return;
    _pressed = true;
    widget.onTapDown?.call();
    _morph.animateTo(1.0,
        duration: JellyPhysics.pressIn, curve: Curves.easeOutCubic);
    _fade.animateTo(1.0,
        duration: JellyPhysics.pressIn, curve: Curves.easeOutCubic);
  }

  void _up() {
    if (!_pressed) return;
    _pressed = false;
    widget.onTapUp?.call();
    // 果冻回弹：elasticOut 让 value 冲过 0（负值），驱动 squash 震荡。
    _morph.animateTo(0.0,
        duration: JellyPhysics.release, curve: Curves.elasticOut);
    // 液泡「渗回」透明：比形变先结束，避免结尾啪一下消失。
    _fade.animateTo(0.0,
        duration: JellyPhysics.release * 0.55, curve: Curves.easeOut);
  }

  void _cancel() {
    _pressed = false;
    _morph.animateTo(0.0, duration: JellyPhysics.release, curve: Curves.easeOut);
    _fade.animateTo(0.0, duration: JellyPhysics.release, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bubble = DecoratedBox(
      decoration: BoxDecoration(
        color: JellyPhysics.bubbleColor(brightness),
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );

    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.enabled ? widget.onTap : null,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _cancel,
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          // ── 下层：白色胶囊本体，全程不动 ──
          widget.child,
          // ── 上层：灰色液泡，负责全部形变 ──
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: Listenable.merge(<Listenable>[_morph, _fade]),
                builder: (context, _) {
                  final t = _morph.value;
                  final opacity = _fade.value;
                  if (opacity <= 0.01) return const SizedBox.shrink();

                  final double scale;
                  final double lift;
                  if (_pressed || t > 1.0) {
                    // 按下阶段：从 0.72 长大到过冲值并上跃
                    final k = t.clamp(0.0, 1.0);
                    scale = JellyPhysics.restScale +
                        (JellyPhysics.pressScale - JellyPhysics.restScale) * k;
                    lift = JellyPhysics.pressLift * k;
                  } else {
                    // 回弹阶段：e 围绕 1 震荡（elastic 过冲），scale 围绕 1 收敛
                    final e = 1.0 - t; // t<0 时 e>1：落地压扁方向
                    scale = JellyPhysics.pressScale +
                        (1.0 - JellyPhysics.pressScale) * e;
                    lift = JellyPhysics.pressLift * (1.0 - e);
                  }

                  // 果冻体积守恒：纵向压缩时横向鼓出
                  final sy = scale.clamp(0.6, 1.5);
                  final sx = (2.0 - sy).clamp(0.6, 1.5);

                  return Transform.translate(
                    offset: Offset(0, lift),
                    child: Transform.scale(
                      scaleX: sx,
                      scaleY: sy,
                      child: Opacity(
                        opacity: opacity * JellyPhysics.pressOpacity,
                        child: bubble,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 导航滑块：灰色液泡在白色胶囊容器内滑动。
///
/// 一次点击 = 起跳（蓄力收缩）→ 飞行（横向拉伸）→ 落地（elasticOut
/// squash 震荡）。容器与图标文字都不动，只有液泡在形变。
class JellyIndicator extends StatefulWidget {
  const JellyIndicator({
    super.key,
    required this.cellWidth,
    required this.index,
    this.height = 56,
    this.radius = 18,
    this.color,
  });

  /// 滑块颜色；不传则退回墨色。导航栏会传当前主题色进来。
  final Color? color;

  /// 单元格宽度
  final double cellWidth;

  /// 当前落位索引
  final int index;

  final double height;
  final double radius;

  @override
  State<JellyIndicator> createState() => _JellyIndicatorState();
}

class _JellyIndicatorState extends State<JellyIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: 1,
  );

  /// 起点用连续坐标：连点时从当前视觉位置平滑接续，不跳半格
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.index.toDouble();
  }

  @override
  void didUpdateWidget(JellyIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      // 尚在动画中：按位置进度反推当前视觉位置作为新起点
      if (_controller.isAnimating) {
        final progress = _positionProgress(_controller.value);
        _from = _from + (oldWidget.index - _from) * progress;
      } else {
        _from = oldWidget.index.toDouble();
      }
      _controller.forward(from: 0);
    }
  }

  double _positionProgress(double t) =>
      Curves.easeInOutCubic.transform(const Interval(0.0, 0.74).transform(t));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final bubbleColor = isDark
        ? Colors.white.withOpacity(0.16)
        : (widget.color ?? GlassPalette.ink).withOpacity(0.14);

    final leftTween = Tween<double>(
      begin: _from * widget.cellWidth,
      end: widget.index * widget.cellWidth,
    );

    // 纵向：起跳膨胀 → 飞行微缩 → 落地压扁后弹性回 1
    final sy = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 1.14),
        weight: 24,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.14, end: 0.97)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 26,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.92, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 50,
      ),
    ]);

    // 横向：起跳收缩蓄力 → 飞行拉伸 → 落地鼓出后弹性回 1
    final sx = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 0.88),
        weight: 24,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.88, end: 1.10)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 26,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.10, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 50,
      ),
    ]);

    // 上跃：离开原位时抬升，落地前归零
    final lift = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.0, end: -4.0),
        weight: 24,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: -4.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 26,
      ),
      TweenSequenceItem<double>(
        tween: ConstantTween<double>(0.0),
        weight: 50,
      ),
    ]);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final left = leftTween.transform(_positionProgress(t));
        final syv = sy.transform(t).clamp(0.6, 1.5);
        final sxv = sx.transform(t).clamp(0.6, 1.5);
        final liftV = lift.transform(t);

        return Positioned(
          left: left,
          top: 0,
          bottom: 0,
          width: widget.cellWidth,
          child: Center(
            child: Transform.translate(
              offset: Offset(0, liftV),
              child: Transform.scale(
                scaleX: sxv,
                scaleY: syv,
                child: Container(
                  height: widget.height,
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(widget.radius),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
