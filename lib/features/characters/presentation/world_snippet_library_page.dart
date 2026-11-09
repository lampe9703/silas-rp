import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../domain/world_entry.dart';
import '../domain/world_snippet.dart';

/// 世界书收藏：跨角色卡复用的通用条目。
///
/// 这里是**全局**的，不属于任何一张卡；导入到卡里是复制快照，
/// 所以导出角色卡时不会带走这里的片段，需要单独导出成 JSON。
class WorldSnippetLibraryPage extends ConsumerStatefulWidget {
  const WorldSnippetLibraryPage({super.key});

  @override
  ConsumerState<WorldSnippetLibraryPage> createState() =>
      _WorldSnippetLibraryPageState();
}

class _WorldSnippetLibraryPageState
    extends ConsumerState<WorldSnippetLibraryPage> {
  String _query = '';

  List<WorldSnippet> get _items =>
      ref.read(worldSnippetDaoProvider).list(query: _query);

  Future<void> _delete(WorldSnippet snippet) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除',
      message: '「${snippet.title}」会从世界书收藏里移除。已经导入到角色卡里的条目不受影响。',
      confirmText: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    ref.read(worldSnippetDaoProvider).delete(snippet.id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final items = _items;

    return Scaffold(
      appBar: AppBar(title: const Text('世界书收藏')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索标题 / 内容 / 标签',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
            child: Text(
              '这里的世界书是全局的，导入到卡里是复制一份；导出角色卡不会带走它们。'
              '备份与恢复在「设置 → 数据管理」。',
              style: TextStyle(fontSize: 11, height: 1.5, color: muted),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _query.trim().isEmpty
                            ? '还没有收藏的世界书。\n\n在角色卡编辑页展开某个世界书条目，\n点右上角的 ☆ 就能收藏到这里。'
                            : '没有匹配的世界书',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.8,
                          color: muted,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _snippetTile(items[i], scheme),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _snippetTile(WorldSnippet snippet, ColorScheme scheme) {
    final muted = scheme.onSurfaceVariant;
    final isConstant = snippet.kind == WorldEntryKind.constant;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withOpacity(0.06)
            : Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        snippet.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      isConstant ? '常驻' : '关键词',
                      style: TextStyle(
                        fontSize: 10,
                        color: isConstant ? scheme.secondary : scheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  snippet.content.replaceAll(RegExp(r'\s+'), ' ').trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, height: 1.45, color: muted),
                ),
                const SizedBox(height: 3),
                Text(
                  <String>[
                    if (snippet.tags.isNotEmpty) snippet.tags.join(' · '),
                    if (snippet.useCount > 0) '用过 ${snippet.useCount} 次',
                  ].join('  |  '),
                  style: TextStyle(fontSize: 10.5, color: muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => _delete(snippet),
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }
}
