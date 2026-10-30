import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../home/app_tab.dart';

class NavOrderPage extends ConsumerStatefulWidget {
  const NavOrderPage({super.key});

  @override
  ConsumerState<NavOrderPage> createState() => _NavOrderPageState();
}

class _NavOrderPageState extends ConsumerState<NavOrderPage> {
  late List<AppTab> _order;

  @override
  void initState() {
    super.initState();
    _order = resolveTabOrder(ref.read(appSettingsProvider).navOrder);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('调整 Tab 顺序')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text(
              '长按右侧手柄拖动排序，结果会立即生效并保存。',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _order.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _order.removeAt(oldIndex);
                  _order.insert(newIndex, item);
                });
                ref.read(appSettingsProvider.notifier).setNavOrder(
                      _order.map((t) => t.name).toList(),
                    );
              },
              itemBuilder: (context, index) {
                final tab = _order[index];
                return Card(
                  key: ValueKey(tab.name),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: scheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(tab.icon, size: 19, color: scheme.primary),
                    ),
                    title: Text(
                      tab.label,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      '位置 ${index + 1}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    trailing: ReorderableDragStartListener(
                      index: index,
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
