import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../domain/character_card.dart';

/// 单张卡的生成参数（温度 / 上下文上限）。
///
/// 值存在独立的 `card_generation` 表里，**不动角色卡结构**；
/// 两个参数都可留空 —— 留空即「跟随全局默认」。
/// 入口：卡库长按菜单、聊天页右上角菜单，两处共用这一个面板。
Future<void> showCardGenerationSheet(
  BuildContext context,
  WidgetRef ref,
  CharacterCard card,
) async {
  parkKeyboard(context);
  final settings = ref.read(appSettingsProvider);
  final dao = ref.read(cardGenerationDaoProvider);
  final saved = dao.byCard(card.id);

  var followGlobal = saved == null || saved.isEmpty;
  var temperature = saved?.temperature ?? settings.temperature;
  var contextLimit = saved?.contextLimit ?? settings.contextLimit;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final muted = scheme.onSurfaceVariant;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '生成参数',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '仅对「${card.name}」生效',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('跟随全局默认', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '打开时不写入这张卡的参数；关闭后下面的数值才生效',
                    style: TextStyle(fontSize: 11.5, color: muted),
                  ),
                  value: followGlobal,
                  onChanged: (v) => setSheetState(() => followGlobal = v),
                ),
                const Divider(height: 20),
                Opacity(
                  opacity: followGlobal ? 0.45 : 1,
                  child: IgnorePointer(
                    ignoring: followGlobal,
                    child: Column(
                      children: [
                        _SliderRow(
                          label: '温度',
                          value: temperature,
                          min: 0,
                          max: 2,
                          divisions: 40,
                          display: temperature.toStringAsFixed(2),
                          onChanged: (v) =>
                              setSheetState(() => temperature = v),
                        ),
                        _SliderRow(
                          label: '上下文上限',
                          value: contextLimit.toDouble(),
                          min: 1024,
                          max: 32768,
                          divisions: 31,
                          display: '$contextLimit tokens',
                          onChanged: (v) =>
                              setSheetState(() => contextLimit = v.round()),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '优先级：这张卡 > API 配置 > 全局默认。上下文越长费用越高。',
                  style: TextStyle(fontSize: 11.5, height: 1.5, color: muted),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (followGlobal) {
                        dao.clear(card.id);
                      } else {
                        dao.save(
                          card.id,
                          temperature: temperature,
                          contextLimit: contextLimit,
                        );
                      }
                      Navigator.of(sheetContext).pop();
                      showToast(
                        context,
                        followGlobal
                            ? '已改为跟随全局默认'
                            : '已保存「${card.name}」的生成参数',
                      );
                    },
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text(
              display,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
