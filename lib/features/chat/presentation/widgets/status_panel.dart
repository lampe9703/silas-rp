import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/prompt/status_parser.dart';
import '../../../../core/theme/glass_theme.dart';

/// 暗色模式状态栏的钢灰（边框、粗条、条目文字统一用它）
const Color _steelGray = Color(0xFF8A9299);

/// 对话页的状态栏面板 · v2「记忆卡」外框模式。
///
/// 外框语言参考用户提供的参考图与前端卡（SillyTavern 卡 CSS）：
/// * 收起态：保持玻璃胶囊一行（与全 App 玻璃系统一致），露出 2~3 个关键值；
/// * 展开态：大圆角（24）实感外框卡，**左侧 4dp 粗边** + 其余 1dp 细边
///   （不对称边框强化层级 + 形成左侧视觉引导），内部是圆角 16 的
///   「主题色 → 点缀色」低饱和渐变内容块，块内键值同行 + 数值进度条；
/// * 全部颜色从 ColorScheme 派生（跟随用户自定义主题色/点缀色），
///   亮色马卡龙、暗色深蓝调各自适配。
class StatusPanel extends StatefulWidget {
  const StatusPanel({
    super.key,
    required this.status,
    this.template = '',
    this.title = '状态',
  });

  final Map<String, dynamic> status;
  final String template;
  final String title;

  @override
  State<StatusPanel> createState() => StatusPanelState();
}

class StatusPanelState extends State<StatusPanel> {
  bool _expanded = false;

  /// 收起面板。供聊天页在「点消息区任意位置」时调用。
  /// 已经是收起态就什么都不做，避免无谓重建。
  void collapse() {
    if (!_expanded) return;
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    // 不再在「状态为空且没有模板」时直接返回空盒子：
    // 那样面板会凭空消失，用户会以为状态栏坏了/关了。这里保留一行胶囊，
    // 收起态显示「未设定」，展开态给一句说明。
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _expanded
            ? _expandedCard(brightness)
            : _collapsedRow(brightness),
      ),
    );
  }

  // ───────────────────────── 收起态：玻璃胶囊一行 ─────────────────────────

  Widget _collapsedRow(Brightness brightness) {
    final scheme = Theme.of(context).colorScheme;

    return GlassSurface(
      radius: 18,
      blur: 16,
      alpha: brightness == Brightness.dark ? 0.55 : 0.52,
      padding: EdgeInsets.zero,
      lift: 0.6,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _expanded = true),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 13,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: GlassPalette.inkOf(brightness),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _compactPreview(brightness)),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: GlassPalette.inkFaintOf(brightness),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 收起时只露第一个条目：多条拼一行会互相挤压，
  /// 值的多行内容也只取第一行（以换行作分界）。
  Widget _compactPreview(Brightness brightness) {
    final style = TextStyle(
      fontSize: 11,
      color: GlassPalette.inkSoftOf(brightness),
    );
    if (widget.status.isEmpty) {
      return Text(
        '未设定',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final first = widget.status.entries.first;
    final value =
        StatusParser.displayValue(first.value).split('\n').first.trim();
    return Text(
      '${first.key} $value',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  // ───────────────────────── 展开态：记忆卡外框 ─────────────────────────

  Widget _expandedCard(Brightness brightness) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = brightness == Brightness.dark;
    // 头部与外框用同一套点缀色：亮色 = 主题点缀色，暗色 = 钢灰。
    // 之前头部用 primary、外框用 secondary，两套颜色在一张卡里打架。
    final accent = isDark ? _steelGray : scheme.secondary;

    // 外框：
    // * 上/右/下 1px 细边框 → 跟随点缀色（原设计 secondary 26%）；
    // * 左侧 4dp 粗边 → 同样跟随点缀色（58%）；
    // * 底色 → 参考图采样的淡粉白 (253,247,250)，圆角 20。
    final frameBorder = isDark
        ? _steelGray.withOpacity(0.55)
        : scheme.secondary.withOpacity(0.40);
    final frameBg = isDark ? const Color(0xFF1E2430) : const Color(0xFFFDF7FA);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        // 关键：给外框本身填充底色。
        // BoxDecoration 的 border 在圆角处是描边，抗锯齿后与内层内容之间
        // 会留 1px 级缝隙（右上/右下「小白角」就是缝里透出的页面背景）。
        // 填上同色底之后，缝隙里露出的仍是 frameBg，与内容同色 → 不可见。
        color: frameBg,
        border: Border.all(color: frameBorder, width: 1.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.30)
                : const Color(0xFF6E7FA8).withOpacity(0.10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        // 必须比外框半径小「边框宽度」：Container 有 1.2px border，
        // 内容尺寸比外框小 2.4px；若仍用 20，圆角处会留 1~2px 缝隙，
        // 透出背景就是右上/右下那两个「小白角」。
        borderRadius: BorderRadius.circular(18.8),
        child: Stack(
          children: <Widget>[
            // 底色：参考图是接近纯色的淡粉白，不需要多层渐变
            Positioned.fill(
              child: ColoredBox(color: frameBg),
            ),
            // 左粗边：跟随点缀色。
            // 半径必须等于外层 ClipRRect 的 18.8（不是外框的 20）：
            // 若按 20 画，粗边外缘会被裁掉 1.2px，与细边框之间就空出一条白缝
            // （左上/左下角那条缝就是这么来的）。
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: RoundedSideEdgePainter(
                    radius: 18.8,
                    thickness: 4,
                    color: isDark
                        ? _steelGray
                        : scheme.secondary.withOpacity(0.58),
                  ),
                ),
              ),
            ),
            // 内容层
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
          // ── 头部：图标 + 标题 + 数量 chip + 收起箭头 ──
          Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  // 与收起态同一套：点缀色淡底，不用红蓝渐变
                  color: accent.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withOpacity(isDark ? 0.22 : 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${widget.status.length} 项',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
              const Spacer(),
              // 收起按钮：纯箭头，无外框容器（v5：去掉红色圈注的圆形描边底）
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _expanded = false),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 22,
                    color: GlassPalette.inkFaintOf(brightness),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // ── 内容：模板模式 / 键值块列表 ──
          _expandedBody(brightness, scheme, isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expandedBody(
    Brightness brightness,
    ColorScheme scheme,
    bool isDark,
  ) {
    final template = widget.template.trim();
    if (template.isEmpty && widget.status.isEmpty) {
      return Text(
        '还没有状态数据。角色回复时会自动填充；'
        '也可以在角色卡里写好「初始状态」或「状态栏模板」。',
        style: TextStyle(
          fontSize: 12,
          height: 1.6,
          color: GlassPalette.inkSoftOf(brightness),
        ),
      );
    }
    if (template.isNotEmpty) {
      // 折叠态已经露了第一条，展开时从第二条开始，避免重复。
      var rendered = StatusParser.renderTemplate(
        template,
        widget.status,
        skipFirst: true,
      );
      if (rendered.trim().isEmpty) {
        // 模板只有一条时回退成完整内容，避免展开后一片空白
        rendered = StatusParser.renderTemplate(template, widget.status);
      }
      if (rendered.trim().isNotEmpty) {
        return _gradientBlock(
          brightness: brightness,
          scheme: scheme,
          isDark: isDark,
          child: _buildKeyValueRich(rendered, brightness),
        );
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < widget.status.entries.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 8),
          _StatusRow(
            label: widget.status.entries.elementAt(i).key,
            value: widget.status.entries.elementAt(i).value,
            brightness: brightness,
          ),
        ],
      ],
    );
  }

  /// 渐变内容块（记忆卡模式：主题色 → 点缀色低饱和渐变，圆角 16）
  /// 把「键：值」多行文本渲染成富文本：**键名用点缀色**，值用正文色。
  ///
  /// 展开态的详情条目按行拆分，键名承担视觉引导（与外框左粗边呼应）。
  Widget _buildKeyValueRich(String text, Brightness brightness) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = brightness == Brightness.dark;
    final base = TextStyle(
      fontSize: 13.5,
      height: 1.65,
      color: GlassPalette.inkOf(brightness),
    );
    final keyStyle = base.copyWith(
      // 暗色模式：小标题用钢灰；亮色沿用点缀色
      color: isDark ? _steelGray : scheme.secondary,
      fontWeight: FontWeight.w700,
    );
    final lineRe = RegExp(r'^(\s*)([^：:\n]{1,24})[：:]\s*(.*)$');
    final lines = text.split('\n');
    final spans = <TextSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final m = lineRe.firstMatch(lines[i]);
      if (m == null) {
        spans.add(TextSpan(text: lines[i], style: base));
      } else {
        spans.add(TextSpan(
          text: '${m.group(1)!}${m.group(2)!.trim()}',
          style: keyStyle,
        ));
        spans.add(TextSpan(text: '：${m.group(3)!}', style: base));
      }
      if (i != lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: base));
      }
    }
    return Text.rich(TextSpan(children: spans, style: base));
  }

  Widget _gradientBlock({
    required Brightness brightness,
    required ColorScheme scheme,
    required bool isDark,
    required Widget child,
  }) {
    // 左上蓝 (235,245,254) → 右下粉白 (253,247,250)，淡粉边框。
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-0.57, -0.82),
          end: const Alignment(0.57, 0.82),
          colors: isDark
              ? <Color>[
                  const Color(0xFF22303F),
                  const Color(0xFF2A2530),
                ]
              : <Color>[
                  const Color(0xFFEBF5FE),
                  const Color(0xFFFDF7FA),
                ],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

/// 展开态的单行状态块：渐变底 + 键值同行 + 数值进度条。
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    required this.brightness,
  });

  final String label;
  final dynamic value;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = brightness == Brightness.dark;
    final numeric = value is num ? (value as num).toDouble() : null;
    final showMeter = numeric != null && numeric >= 0 && numeric <= 100;
    final meterColor = showMeter
        ? Color.lerp(
            scheme.primary,
            scheme.secondary,
            (numeric / 100).clamp(0.0, 1.0),
          )!
        : scheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-0.57, -0.82),
          end: const Alignment(0.57, 0.82),
          colors: isDark
              ? <Color>[const Color(0xFF22303F), const Color(0xFF2A2530)]
              : <Color>[const Color(0xFFEBF5FE), const Color(0xFFFDF7FA)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              // 键名（左侧视觉引导的起点，与外框左粗边呼应）
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  // 键名用点缀色；暗色模式改用钢灰
                  color: isDark ? _steelGray : scheme.secondary,
                ),
              ),
              const Spacer(),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  StatusParser.displayValue(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    color: GlassPalette.inkSoftOf(brightness),
                  ),
                ),
              ),
            ],
          ),
          if (showMeter) ...<Widget>[
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (numeric / 100).clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: meterColor.withOpacity(0.16),
                valueColor: AlwaysStoppedAnimation<Color>(meterColor),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 左粗「」形圆角边画笔（锥形收尾版，v5.2）。
///
/// 形态（用户澄清的预期）：
/// * 左直边：全宽 [thickness]；
/// * 圆角弧靠近左直边的半段：保持全宽；
/// * 从圆弧中段开始：宽度**线性收窄**；
/// * 到上/下直线段起点处宽度恰好为 0 —— **直线段完全没有粗描边**，
///   也没有突然截断的等宽延伸段。
///
/// 实现：单一填充多边形（非分段 stroke）。外缘逐点贴卡片外圆角，
/// 内缘按宽度函数沿法线内缩；两缘在直线段起点自然汇合闭合，
/// 全程平滑无接缝。
@visibleForTesting
class RoundedSideEdgePainter extends CustomPainter {
  const RoundedSideEdgePainter({
    required this.radius,
    required this.thickness,
    required this.color,
  });

  /// 圆角半径（与卡片 borderRadius 一致）
  final double radius;

  /// 粗边厚度（左直边全宽）
  final double thickness;

  final Color color;

  /// 弧离散步数（保证圆角平滑）
  static const int _steps = 32;

  /// 收窄起点：比弧中点（1.25π）更靠近左直边，留在卡片中部一侧
  static const double _fadeStartTop = 1.16 * math.pi;

  /// 下弧对称的收窄终点（原 0.75π）
  static const double _fadeStartBottom = 0.84 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final t = thickness;
    final r = radius;
    if (r <= 0 || t <= 0 || h <= 0) return;

    // 弧参数（屏幕坐标，y 向下）：
    // 左上弧圆心 O1=(r, r)：α=π 是左直边顶端，α=3π/2 是上边左端
    // 左下弧圆心 O2=(r, h-r)：α=π 是左直边底端，α=π/2 是下边左端
    //
    // 宽度函数：收窄起点比弧中点更靠近左直边（向卡片中部走），
    // 再用 smoothstep 过渡，起止两端导数为 0，视觉上不再有突然变化。

    List<Offset> arc(Offset c, double a0, double a1,
        double Function(double) w) {
      return <Offset>[
        for (var i = 0; i <= _steps; i++)
          () {
            final a = a0 + (a1 - a0) * i / _steps;
            final rr = r - w(a);
            return Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
          }(),
      ];
    }

    final topLeft = Offset(r, r);
    final botLeft = Offset(r, h - r);

    double smooth(double p) {
      final x = p.clamp(0.0, 1.0);
      return x * x * (3 - 2 * x);
    }

    double wTop(double a) {
      if (a <= _fadeStartTop) return t;
      if (a >= 1.5 * math.pi) return 0;
      final p = (a - _fadeStartTop) / (1.5 * math.pi - _fadeStartTop);
      return t * (1 - smooth(p));
    }

    double wBot(double a) {
      if (a >= _fadeStartBottom) return t;
      if (a <= 0.5 * math.pi) return 0;
      final p = (a - 0.5 * math.pi) / (_fadeStartBottom - 0.5 * math.pi);
      return t * smooth(p);
    }

    // 外缘宽度恒 0（即半径恒为 r）
    const zero = 0.0;

    final path = Path()..moveTo(r, 0);
    // 左上外弧：α 3π/2 → π（上边左端 → 左直边顶端）
    for (final p in arc(topLeft, 1.5 * math.pi, math.pi, (_) => zero)) {
      path.lineTo(p.dx, p.dy);
    }
    // 左直边外缘
    path.lineTo(0, h - r);
    // 左下外弧：α π → π/2（左直边底端 → 下边左端）
    for (final p in arc(botLeft, math.pi, 0.5 * math.pi, (_) => zero)) {
      path.lineTo(p.dx, p.dy);
    }
    // 左下内弧：α π/2 → π（锥形内缩，下边端宽度 0 → 左边端全宽）
    for (final p in arc(botLeft, 0.5 * math.pi, math.pi, wBot)) {
      path.lineTo(p.dx, p.dy);
    }
    // 左直边内缘
    path.lineTo(t, r);
    // 左上内弧：α π → 3π/2（锥形内缩，左边端全宽 → 上边端宽度 0，
    // 终点与外缘起点 (r, 0) 重合，闭合）
    for (final p in arc(topLeft, math.pi, 1.5 * math.pi, wTop)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant RoundedSideEdgePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.thickness != thickness ||
      oldDelegate.radius != radius;
}


