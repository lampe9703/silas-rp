import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_providers.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../presentation/controllers/chat_controller.dart';

/// 聊天中切换模型（API 配置）。
///
/// 只影响**当前会话**，从下一条消息开始生效；已经聊过的内容保持原样，
/// 每条消息自己记着当时用的是哪个模型。
Future<void> showModelPickerSheet(
  BuildContext context,
  WidgetRef ref,
  ChatController controller,
) async {
  parkKeyboard(context);
  final repo = ref.read(settingsRepositoryProvider);
  final configs = repo.apiConfigs();
  final defaultConfig = repo.defaultApiConfig();
  final current = controller.resolveApiConfig();
  final followsGlobal = controller.followsGlobalConfig;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      final muted = scheme.onSurfaceVariant;

      Widget row({
        required String title,
        required String subtitle,
        required bool selected,
        required VoidCallback onTap,
      }) {
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(title, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: muted),
          ),
          trailing: selected
              ? Icon(Icons.check_circle_rounded, size: 20, color: scheme.primary)
              : Icon(Icons.circle_outlined, size: 20, color: scheme.outline),
          onTap: onTap,
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
              child: Row(
                children: <Widget>[
                  const Text(
                    '切换模型',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      current == null ? '未配置' : current.model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text(
                '只对当前会话生效，从下一条消息开始；已聊过的内容不会改变。',
                style: TextStyle(fontSize: 11, height: 1.5, color: muted),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  row(
                    title: '跟随全局默认',
                    subtitle: defaultConfig == null
                        ? '当前没有默认配置'
                        : '默认：${defaultConfig.name.isEmpty ? defaultConfig.model : defaultConfig.name}',
                    selected: followsGlobal,
                    onTap: () {
                      controller.switchApiConfig(null);
                      Navigator.of(sheetContext).pop();
                      showToast(context, '已改为跟随全局默认');
                    },
                  ),
                  const Divider(height: 1, indent: 20, endIndent: 20),
                  if (configs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: Text(
                        '还没有 API 配置，去「设置 → API 配置」添加。',
                        style: TextStyle(fontSize: 12.5, color: muted),
                      ),
                    )
                  else
                    for (final config in configs)
                      row(
                        title: config.name.isEmpty ? config.model : config.name,
                        subtitle: '${config.model} · ${config.baseUrl}',
                        selected: !followsGlobal && current?.id == config.id,
                        onTap: () {
                          controller.switchApiConfig(config.id);
                          Navigator.of(sheetContext).pop();
                          showToast(context, '本会话已切换到 ${config.model}');
                        },
                      ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
