import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: scheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    required this.children,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
  });

  final String? title;
  final String? subtitle;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Card(child: Padding(padding: padding, child: Column(children: children))),
      ],
    );
  }
}

class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar({
    super.key,
    this.file,
    required this.name,
    this.size = 48,
    this.radius = 12,
  });

  final File? file;
  final String name;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withOpacity(0.85),
            scheme.primary.withOpacity(0.55),
          ],
        ),
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: file == null
            ? fallback
            : Image.file(
                file!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

/// 打开弹窗/跳转子页前释放输入焦点。
///
/// 有焦点的输入框在弹窗（菜单/底部面板/对话框）打开时会把焦点让给弹窗，
/// 弹窗关闭后焦点又被还原给输入框——于是输入法被重新唤出，看起来就是
/// 「点了空白处关闭弹窗，键盘却弹出来了」。先手动释放焦点，就没有可还原的目标。
void parkKeyboard(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool danger = false,
}) async {
  // 对话框打开前先释放输入焦点：无论从哪个输入框唤起确认框，
  // 关闭时都不会把输入法重新弹出来
  parkKeyboard(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: Text(message, style: const TextStyle(fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelText),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: scheme.error)
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmText),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

void showToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  // 统一在屏幕中部弹出：浮层 SnackBar 靠 margin 把位置抬到约正中，
  // 不压导航胶囊、不挡输入框，横向留 12% 边距
  final size = MediaQuery.maybeOf(context)?.size;
  final bottom = size == null
      ? 320.0
      : (size.height * 0.5 - 48).clamp(160.0, 900.0).toDouble();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        margin: EdgeInsets.fromLTRB(
          (size?.width ?? 420) * 0.12,
          0,
          (size?.width ?? 420) * 0.12,
          bottom,
        ),
        width: null,
      ),
    );
}

/// 调用系统分享面板导出文件。失败时静默降级（调用方仍会提示保存路径）。
Future<void> shareExportedFile(String path) async {
  try {
    await Share.shareXFiles([XFile(path)]);
  } catch (_) {
    // 部分平台（如无分享能力）会抛错，忽略即可
  }
}
