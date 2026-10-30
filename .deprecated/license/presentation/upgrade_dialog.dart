import 'package:flutter/material.dart';

import '../../../shared/glass_route.dart';
import '../domain/license_policy.dart';
import 'premium_page.dart';

/// 免费额度用完时的提示弹窗。
///
/// 返回 true 表示用户点进了激活页（调用方可以据此决定要不要重试一次）。
Future<bool> showUpgradeDialog(
  BuildContext context, {
  required int used,
  String? title,
}) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title ?? '免费额度已用完'),
      content: Text(
        LicensePolicy.limitMessage(used),
        style: const TextStyle(fontSize: 13, height: 1.7),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('知道了'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('输入激活码'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;
  await Navigator.of(context).push(glassPageRoute<void>(const PremiumPage()));
  return true;
}
