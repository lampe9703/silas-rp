import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../shared/glass_route.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../domain/world_entry.dart';
import '../domain/world_snippet.dart';
import 'world_snippet_library_page.dart';

/// 导入世界书的选项
class SnippetImportSelection {
  const SnippetImportSelection({
    required this.snippets,
    this.forceConstant = false,
    this.overwrite = false,
  });

  final List<WorldSnippet> snippets;

  /// 全部按常驻条目导入（词汇规范、感官规范这类本来就该常驻）
  final bool forceConstant;

  /// 卡里已有同名条目时，用片段内容覆盖
  final bool overwrite;
}

/// 世界书收藏的选择面板：搜索 + 多选 + 导入选项。
///
/// 返回 null 表示取消。
Future<SnippetImportSelection?> showWorldSnippetPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  parkKeyboard(context);
  final dao = ref.read(worldSnippetDaoProvider);
  final all = dao.list();
  if (all.isEmpty) {
    showToast(context, '世界书收藏还是空的：给条目点 ☆ 就能收藏进来');
    return null;
  }

  final selected = <String>{};
  var query = '';
  var forceConstant = false;
  var overwrite = false;

  final result = await showModalBottomSheet<SnippetImportSelection>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final muted = scheme.onSurfaceVariant;
        final visible = all.where((s) {
          if (query.trim().isEmpty) return true;
          final q = query.trim().toLowerCase();
          return s.title.toLowerCase().contains(q) ||
              s.content.toLowerCase().contains(q) ||
              s.tags.any((t) => t.toLowerCase().contains(q));
        }).toList();

        return FractionallySizedBox(
          heightFactor: 0.82,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 6),
                child: Row(
                  children: <Widget>[
                    const Text(
                      '导入世界书',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '共 ${all.length} 条',
                        style: TextStyle(fontSize: 11.5, color: muted),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        Navigator.of(context).push(
                          glassPageRoute<void>(
                            const WorldSnippetLibraryPage(),
                          ),
                        );
                      },
                      child: const Text('管理', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  onChanged: (v) => setSheetState(() => query = v),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜索标题 / 内容 / 标签',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(
                          '没有匹配的世界书',
                          style: TextStyle(fontSize: 12.5, color: muted),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final s = visible[i];
                          final checked = selected.contains(s.id);
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setSheetState(() {
                              if (checked) {
                                selected.remove(s.id);
                              } else {
                                selected.add(s.id);
                              }
                            }),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Checkbox(
                                    value: checked,
                                    onChanged: (v) => setSheetState(() {
                                      if (v == true) {
                                        selected.add(s.id);
                                      } else {
                                        selected.remove(s.id);
                                      }
                                    }),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Row(
                                          children: <Widget>[
                                            Expanded(
                                              child: Text(
                                                s.title,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              s.kind ==
                                                      WorldEntryKind.constant
                                                  ? '常驻'
                                                  : '关键词',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: s.kind ==
                                                        WorldEntryKind.constant
                                                    ? scheme.secondary
                                                    : scheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          s.content
                                              .replaceAll(RegExp(r'\s+'), ' ')
                                              .trim(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            height: 1.45,
                                            color: muted,
                                          ),
                                        ),
                                        if (s.useCount > 0)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              '用过 ${s.useCount} 次',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                color: muted,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  children: <Widget>[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        '全部作为常驻条目导入',
                        style: TextStyle(fontSize: 13),
                      ),
                      value: forceConstant,
                      onChanged: (v) =>
                          setSheetState(() => forceConstant = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        '重名时覆盖已有条目',
                        style: TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '关闭时遇到同名条目会跳过',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                      value: overwrite,
                      onChanged: (v) => setSheetState(() => overwrite = v),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () {
                                final picked = all
                                    .where((s) => selected.contains(s.id))
                                    .toList();
                                Navigator.of(sheetContext).pop(
                                  SnippetImportSelection(
                                    snippets: picked,
                                    forceConstant: forceConstant,
                                    overwrite: overwrite,
                                  ),
                                );
                              },
                        child: Text(
                          selected.isEmpty ? '请选择条目' : '导入 ${selected.length} 条',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  return result;
}
