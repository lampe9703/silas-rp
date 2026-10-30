import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../domain/settings_models.dart';

class PricingPage extends ConsumerStatefulWidget {
  const PricingPage({super.key});

  @override
  ConsumerState<PricingPage> createState() => _PricingPageState();
}

class _PricingPageState extends ConsumerState<PricingPage> {
  List<ModelPricing> _items = const <ModelPricing>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _items = ref.read(settingsRepositoryProvider).pricings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('模型单价')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('添加单价'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '单价用于把 token 换算成金额。模型名支持通配符，例如 gpt-4o* 会匹配 gpt-4o-mini、gpt-4o-2024-08-06。'
              '匹配顺序为「精确 → 通配」。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_items.isEmpty)
            const EmptyState(
              icon: Icons.payments_outlined,
              title: '还没有配置单价',
              description: '不配置也可以正常对话，只是费用会显示为 0。',
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < _items.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      title: Text(
                        _items[i].modelPattern,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        '输入 ${formatUnitPrice(_items[i].inputPer1M, currency: _items[i].currency)}'
                        ' / 输出 ${formatUnitPrice(_items[i].outputPer1M, currency: _items[i].currency)}'
                        ' 每 1M tokens',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        onPressed: () async {
                          final ok = await showConfirmDialog(
                            context,
                            title: '删除单价',
                            message: '删除后该模型的历史费用仍保留，但新调用不再计入费用。',
                            confirmText: '删除',
                            danger: true,
                          );
                          if (!ok) return;
                          ref
                              .read(settingsRepositoryProvider)
                              .deletePricing(_items[i].id);
                          _reload();
                        },
                      ),
                      onTap: () => _showEditDialog(_items[i]),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(ModelPricing? existing) async {
    // 打开编辑对话框前释放输入焦点（本页从统计页/设置页都能进，
    // 来源页可能有带焦点的输入框，关闭对话框时避免唤出输入法）
    parkKeyboard(context);
    final patternController =
        TextEditingController(text: existing?.modelPattern ?? '');
    final inputController = TextEditingController(
      text: existing == null ? '' : (existing.inputPer1M / 1000000).toString(),
    );
    final outputController = TextEditingController(
      text: existing == null ? '' : (existing.outputPer1M / 1000000).toString(),
    );
    var currency = existing?.currency ?? 'USD';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? '添加单价' : '编辑单价',
            style: const TextStyle(fontSize: 16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: patternController,
                  decoration: const InputDecoration(
                    labelText: '模型匹配',
                    hintText: 'gpt-4o*',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: inputController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '输入单价 / 1M tokens',
                    hintText: '2.5',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: outputController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '输出单价 / 1M tokens',
                    hintText: '10',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('货币', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: currency,
                      items: const [
                        DropdownMenuItem(value: 'USD', child: Text('USD (\$)')),
                        DropdownMenuItem(value: 'CNY', child: Text('CNY (¥)')),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => currency = v ?? 'USD'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final pattern = patternController.text.trim();
    if (pattern.isEmpty) return;
    final input = double.tryParse(inputController.text.trim()) ?? 0;
    final output = double.tryParse(outputController.text.trim()) ?? 0;

    ref.read(settingsRepositoryProvider).savePricing(
          pattern: pattern,
          inputPer1M: (input * 1000000).round(),
          outputPer1M: (output * 1000000).round(),
          currency: currency,
        );
    _reload();
  }
}
