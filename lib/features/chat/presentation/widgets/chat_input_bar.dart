import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/glass_theme.dart';

class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isStreaming,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isStreaming;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    // 发送按钮渐变：主档 → 深档，跟随自定义主题色
    final primaryDeep = Color.lerp(scheme.primary, Colors.black, 0.14)!;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? <Color>[
                        Colors.white.withOpacity(0.10),
                        Colors.white.withOpacity(0.05),
                      ]
                    : <Color>[
                        Colors.white.withOpacity(0.88),
                        Colors.white.withOpacity(0.68),
                      ],
              ),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.10)
                    : Colors.white.withOpacity(0.9),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: accentOf(context)
                      .withOpacity(isDark ? 0.22 : 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 132),
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: GlassPalette.inkOf(brightness),
                      ),
                      decoration: InputDecoration(
                        hintText: '说点什么…',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        hintStyle: TextStyle(
                          fontSize: 14.5,
                          color: GlassPalette.inkFaintOf(brightness),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                isStreaming
                    ? _RoundButton(
                        icon: Icons.stop_rounded,
                        colors: const <Color>[
                          Color(0xFFE88A8A),
                          Color(0xFFD9636B),
                        ],
                        onTap: onStop,
                      )
                    : _RoundButton(
                        icon: Icons.arrow_upward_rounded,
                        colors: <Color>[scheme.primary, primaryDeep],
                        onTap: onSend,
                        width: 78,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.colors,
    required this.onTap,
    this.width = 42,
  });

  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(21);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.last.withOpacity(0.36),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: SizedBox(
            width: width,
            height: 42,
            child: Icon(icon, color: Colors.white, size: 21),
          ),
        ),
      ),
    );
  }
}
