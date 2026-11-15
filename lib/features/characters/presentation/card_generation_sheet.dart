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
                        ButtonSegment(value: 'character', label: Text('第一人称')),
                        ButtonSegment(value: 'author', label: Text('第三人称')),
                      ],
                      selected: <String>{narrativeMode},
                      onSelectionChanged: (v) =>
                          setSheetState(() => narrativeMode = v.first),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '第一人称：以角色「我」叙述；第三人称：作者视角，可写所有角色。'
                  '两套各有一份系统提示词，在设置页可以改',
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
                _ContextLimitRow(
                  value: contextLimit,
                  onChanged: (v) => setSheetState(() => contextLimit = v),
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
                  '优先级：这张卡 > API 配置（温度）> 内置默认。'
                  '每轮都会把全部历史重发一次，所以上限就是每轮的成本；'
                  '一般 32k 够用，长线存档再往上调。',
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

/// 上下文上限：按档位走，不用连续滑杆。
///
/// 0~200000 的连续滑杆有两个毛病：拖一下跳 6000 token（根本对不准），
/// 而且 65537 这种值没有任何意义。这里给一组人真正会选的档位。
class _ContextLimitRow extends StatelessWidget {
  const _ContextLimitRow({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  /// 档位表。1k 起，翻倍为主，中间补几档常用的。
  static const List<int> steps = <int>[
    1024, 2048, 4096, 8192, 12288, 16384, 24576,
    32768, 49152, 65536, 98304, 131072, 163840, 200000,
  ];

  /// 32768 显示成 32k 而不是 33k：档位都是 1024 的整数倍，
  /// 按 1000 折算会得到「33k」这种看着像错的值。
  static String _fmt(int v) {
    if (v >= 1024 && v % 1024 == 0) return '${v ~/ 1024}k tokens';
    if (v >= 1000) return '${(v / 1000).round()}k tokens';
    return '$v tokens';
  }

  /// 库里可能存着不在表里的老值，取不超过它的最大档位
  int get _index {
    final exact = steps.indexOf(value);
    if (exact >= 0) return exact;
    var best = 0;
    for (var i = 0; i < steps.length; i++) {
      if (steps[i] <= value) best = i;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final index = _index;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            const Text('上下文上限', style: TextStyle(fontSize: 13)),
            Text(
              _fmt(steps[index]),
              style: TextStyle(fontSize: 12, color: scheme.primary),
            ),
          ],
        ),
        Slider(
          value: index.toDouble(),
          min: 0,
          max: (steps.length - 1).toDouble(),
          divisions: steps.length - 1,
          label: _fmt(steps[index]),
          onChanged: (v) => onChanged(steps[v.round()]),
        ),
        // 刻度提示：让人知道滑到哪儿大概是什么量级
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('1k', style: TextStyle(fontSize: 10, color: muted)),
              Text('16k', style: TextStyle(fontSize: 10, color: muted)),
              Text('64k', style: TextStyle(fontSize: 10, color: muted)),
              Text('200k', style: TextStyle(fontSize: 10, color: muted)),
            ],
          ),
        ),
      ],
    );
  }
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
