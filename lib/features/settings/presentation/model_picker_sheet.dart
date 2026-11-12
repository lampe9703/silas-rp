import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../domain/settings_models.dart';

/// 通用模型选择面板：带搜索的模型名列表，点一行返回该模型名。
class ModelPickerSheet extends StatefulWidget {
  const ModelPickerSheet({super.key, required this.models});

  final List<String> models;

  @override
  State<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<ModelPickerSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keyword = _search.text.trim().toLowerCase();
    final list = widget.models
        .where((m) => keyword.isEmpty || m.toLowerCase().contains(keyword))
        .toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.62,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '选择模型（${widget.models.length} 个）',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索模型名，如 claude / gpt / gemini',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      '没有匹配的模型',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final id = list[i];
                      return ListTile(
                        dense: true,
                        title: Text(id, style: const TextStyle(fontSize: 13.5)),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                        ),
                        onTap: () => Navigator.of(context).pop(id),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 从已保存的 API 配置里挑一个模型名。
///
/// 两级：先给「已保存的模型」（零网络，直接读配置里填过的那个 model），
/// 需要更全的列表再按配置去拉 `GET /models`。
/// 返回 null 表示用户放弃。
Future<String?> pickModelFromConfigs(
  BuildContext context,
  WidgetRef ref,
) async {
  final configs = ref.read(settingsRepositoryProvider).apiConfigs();
  if (configs.isEmpty) {
    showToast(context, '还没有 API 配置：先在「设置 → API 配置」里添加一个');
    return null;
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ModelSourceSheet(configs: configs),
  );
}

class _ModelSourceSheet extends ConsumerStatefulWidget {
  const _ModelSourceSheet({required this.configs});

  final List<ApiConfig> configs;

  @override
  ConsumerState<_ModelSourceSheet> createState() => _ModelSourceSheetState();
}

class _ModelSourceSheetState extends ConsumerState<_ModelSourceSheet> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _pulling = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 已保存的模型：按模型名去重，记第一个来源配置
  List<({String model, String source})> get _saved {
    final seen = <String>{};
    final out = <({String model, String source})>[];
    for (final config in widget.configs) {
      final model = config.model.trim();
      if (model.isEmpty || !seen.add(model)) continue;
      out.add((model: model, source: config.name));
    }
    return out;
  }

  Future<void> _pull(ApiConfig config) async {
    if (_pulling.contains(config.id)) return;
    setState(() => _pulling.add(config.id));
    try {
      final repo = ref.read(settingsRepositoryProvider);
      final key = await repo.apiKey(config);
      final models = await ref
          .read(openAiClientProvider)
          .fetchModels(config, key);
      if (!mounted) return;
      if (models.isEmpty) {
        showToast(context, '「${config.name}」没有返回模型列表');
        return;
      }
      final picked = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ModelPickerSheet(models: models),
      );
      if (picked != null && mounted) Navigator.of(context).pop(picked);
    } catch (e) {
      if (mounted) showToast(context, '拉取失败：$e');
    } finally {
      if (mounted) setState(() => _pulling.remove(config.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keyword = _search.text.trim().toLowerCase();
    final saved = _saved
        .where((e) =>
            keyword.isEmpty || e.model.toLowerCase().contains(keyword))
        .toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.66,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              '选择模型',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              '先用已保存的模型，需要更全的列表就从服务商拉取',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索模型名',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: saved.isEmpty
                ? Center(
                    child: Text(
                      '没有已保存的模型，用下面按钮拉取',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: saved.length,
                    itemBuilder: (context, i) {
                      final item = saved[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          item.model,
                          style: const TextStyle(fontSize: 13.5),
                        ),
                        subtitle: Text(
                          '来自 ${item.source}',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                        ),
                        onTap: () => Navigator.of(context).pop(item.model),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Text(
              '从服务商拉取完整列表',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.configs.map((config) {
                final pulling = _pulling.contains(config.id);
                return ActionChip(
                  avatar: pulling
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined, size: 15),
                  label: Text(
                    config.name,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: pulling ? null : () => _pull(config),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
