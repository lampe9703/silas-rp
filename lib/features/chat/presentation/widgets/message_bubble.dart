import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/glass_theme.dart';
import '../../../../core/utils/markdown.dart';
import '../../../../core/utils/time_utils.dart';
import '../../../characters/domain/character_card.dart';
import '../../domain/chat_models.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.card,
    required this.cardAvatar,
    required this.onLongPress,
  });

  final ChatMessage message;
  final CharacterCard card;
  final File? cardAvatar;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    // 主题色加深一档：气泡渐变的主档 → 深档，跟随用户自定义主题色
    final primaryDeep = Color.lerp(scheme.primary, Colors.black, 0.14)!;
    final isUser = message.isUser;
    // user 气泡单独配文字色，两种模式各一套；气泡本身保持原样
    // 亮色模式文字用 Alice Blue #F0F8FF
    final userTextColor = brightness == Brightness.dark
        ? const Color(0xFF082033)
        : const Color(0xFFF0F8FF);
    final userBubbleStart = scheme.primary;
    final userBubbleEnd = primaryDeep;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(isUser ? 20 : 6),
      bottomRight: Radius.circular(isUser ? 6 : 20),
    );

    final maxWidth = MediaQuery.of(context).size.width * 0.78;

    final body = message.content.isEmpty && message.isBusy
        ? _TypingDots(
            color: isUser
                ? userTextColor.withOpacity(0.7)
                : GlassPalette.inkSoftOf(brightness),
          )
        : isUser
            // 用户消息不解析 markdown：原样显示，整段统一一个颜色
            ? Text(
                message.content,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: userTextColor,
                ),
              )
            : MarkdownText(
                message.content,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: GlassPalette.inkOf(brightness),
                ),
              );

    final extras = <Widget>[
      if (message.status == MessageStatus.error &&
          (message.errorMessage?.isNotEmpty ?? false)) ...<Widget>[
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.error_outline_rounded,
              size: 13,
              color: isUser ? userTextColor : const Color(0xFFD9636B),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                message.errorMessage!,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: isUser ? userTextColor : const Color(0xFFD9636B),
                ),
              ),
            ),
          ],
        ),
      ],
      if (message.status == MessageStatus.cancelled) ...<Widget>[
        const SizedBox(height: 6),
        Text(
          '已取消生成',
          style: TextStyle(
            fontSize: 10.5,
            color: isUser
                ? userTextColor.withOpacity(0.7)
                : GlassPalette.inkFaintOf(brightness),
          ),
        ),
      ],
    ];

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: isUser
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[userBubbleStart, userBubbleEnd],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: userBubbleEnd.withOpacity(0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[body, ...extras],
              ),
            )
          : Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: brightness == Brightness.dark
                          ? <Color>[
                              Colors.white.withOpacity(0.10),
                              Colors.white.withOpacity(0.05),
                            ]
                          : <Color>[
                              Colors.white.withOpacity(0.82),
                              Colors.white.withOpacity(0.62),
                            ],
                    ),
                    border: Border.all(
                      color: brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.10)
                          : Colors.white.withOpacity(0.85),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: accentOf(context).withOpacity(
                          brightness == Brightness.dark ? 0.20 : 0.10,
                        ),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[body, ...extras],
                  ),
                ),
    );

    final avatar = _Avatar(
      isUser: isUser,
      card: card,
      cardAvatar: cardAvatar,
      brightness: brightness,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!isUser) ...<Widget>[avatar, const SizedBox(width: 9)],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 3, right: 3),
                  child: Text(
                    '${isUser ? '我' : card.name} · ${formatClock(message.createdAt)}',
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.2,
                      color: GlassPalette.inkFaintOf(brightness),
                    ),
                  ),
                ),
                GestureDetector(onLongPress: onLongPress, child: bubble),
                if (message.isAssistant &&
                    message.status == MessageStatus.done &&
                    message.tokenCount != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      '${message.tokenCount} tokens'
                      '${message.latencyMs != null ? ' · ${(message.latencyMs! / 1000).toStringAsFixed(1)}s' : ''}',
                      style: TextStyle(
                        fontSize: 9.5,
                        color:
                            GlassPalette.inkFaintOf(brightness).withOpacity(0.8),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isUser) ...<Widget>[const SizedBox(width: 9), avatar],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.isUser,
    required this.card,
    required this.cardAvatar,
    required this.brightness,
  });

  final bool isUser;
  final CharacterCard card;
  final File? cardAvatar;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isUser
              ? <Color>[
                  scheme.primary.withOpacity(0.30),
                  scheme.primary.withOpacity(0.16),
                ]
              : <Color>[
                  scheme.secondary.withOpacity(0.24),
                  scheme.primary.withOpacity(0.18),
                ],
        ),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.12)
              : Colors.white.withOpacity(0.9),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: isUser
          ? Icon(
              Icons.person_rounded,
              size: 18,
              color: isDark ? Colors.white70 : scheme.primary,
            )
          : (cardAvatar == null
              ? Center(
                  child: Text(
                    card.name.isEmpty ? '?' : card.name.substring(0, 1),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : scheme.secondary,
                    ),
                  ),
                )
              : Image.file(
                  cardAvatar!,
                  fit: BoxFit.cover,
                  cacheWidth: 120,
                )),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});

  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_controller.value + i * 0.22) % 1.0;
            final opacity = 0.25 + 0.75 * (1 - (phase - 0.5).abs() * 2);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity.clamp(0.2, 1.0),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
