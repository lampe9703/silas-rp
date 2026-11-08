import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../domain/character_card.dart';

/// 单张卡的生成参数：叙述视角 / 温度 / 上下文上限 / 单次回复上限。
///
/// 值存在独立的 `card_generation` 表里，**不动角色卡结构**。
/// 设置页不再提供这四项的全局入口，全部按卡设置；没有记录时用内置默认值。
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

  var temperature = saved?.temperature ?? settings.temperature;
  var contextLimit = saved?.contextLimit ?? settings.contextLimit;
  var narrativeMode = saved?.narrativeMode ?? settings.narrativeMode;
  var maxReplyLength = saved?.maxReplyLength ?? settings.maxReplyLength;
  var acknowledged = saved?.paramsAck ?? false;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final muted = scheme.onSurfaceVariant;
        return SafeArea(
          child: SingleChildScrollView(
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Expanded(
                      child: Text('叙述视角', style: TextStyle(fontSize: 13)),
                    ),
                    SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment(value: 'character', label: Text('角色')),
                        ButtonSegment(value: 'author', label: Text('作者')),
                      ],
                      selected: <String>{narrativeMode},
                      onSelectionChanged: (v) =>
                          setSheetState(() => narrativeMode = v.first),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '角色：以角色本人第一人称回应；作者：第三人称全知，可描写所有角色',
                  style: TextStyle(fontSize: 11, height: 1.5, color: muted),
                ),
                const SizedBox(height: 10),
                _SliderRow(
                  label: '温度',
                  value: temperature,
                  min: 0,
                  max: 2,
                  divisions: 40,
                  display: temperature.toStringAsFixed(2),
                  onChanged: (v) => setSheetState(() => temperature = v),
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
                _SliderRow(
                  label: '单次回复上限',
                  value: maxReplyLength.toDouble(),
                  min: 0,
                  max: 2000,
                  divisions: 40,
                  display: maxReplyLength == 0 ? '不限' : '$maxReplyLength 字',
                  onChanged: (v) =>
                      setSheetState(() => maxReplyLength = v.round()),
                ),
                const SizedBox(height: 2),
                Text(
                  '优先级：这张卡 > API 配置（温度）> 内置默认。上下文越长费用越高。',
                  style: TextStyle(fontSize: 11.5, height: 1.5, color: muted),
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: acknowledged,
                  onChanged: (v) =>
                      setSheetState(() => acknowledged = v ?? false),
                  title: const Text(
                    '已确认这些参数符合我的需求',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    '勾选后，这张卡不会再弹参数提示；取消勾选会恢复提示',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      dao.save(
                        card.id,
                        temperature: temperature,
                        contextLimit: contextLimit,
                        narrativeMode: narrativeMode,
                        maxReplyLength: maxReplyLength,
                      );
                      // 确认标记单独写，避免和参数保存互相覆盖
                      dao.setAcknowledged(card.id, acknowledged);
                      Navigator.of(sheetContext).pop();
                      showToast(
                        context,
                        acknowledged
                            ? '已保存，这张卡不再提示参数'
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
