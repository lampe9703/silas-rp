import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_providers.dart';
import '../../../../core/theme/glass_theme.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../domain/session_tag.dart';

/// 给一批会话打标签。
///
/// 标签是「库」而不是自由文本：同一个标签在多条会话间复用，
/// 才能按标签找回来。新建标签时直接写进库，下次就能选。
///
/// 返回要**添加**的标签 id 列表；null 表示取消。
Future<List<String>?> showSessionTagPicker(
  BuildContext context, {
  required int sessionCount,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SessionTagPickerSheet(sessionCount: sessionCount),
  );
}

class _SessionTagPickerSheet extends ConsumerStatefulWidget {
  const _SessionTagPickerSheet({required this.sessionCount});

  final int sessionCount;

  @override
  ConsumerState<_SessionTagPickerSheet> createState() =>
      _SessionTagPickerSheetState();
}

class _SessionTagPickerSheetState
    extends ConsumerState<_SessionTagPickerSheet> {
  final TextEditingController _input = TextEditingController();
  final Set<String> _selected = <String>{};
  List<SessionTag> _tags = const <SessionTag>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _tags = ref.read(sessionTagDaoProvider).all();
    });
  }

  void _create() {
    final name = _input.text.trim();
    if (name.isEmpty) return;
    final tag = ref.read(sessionTagDaoProvider).ensure(name);
    _input.clear();
    _reload();
    setState(() => _selected.add(tag.id));
  }

  Future<void> _delete(SessionTag tag) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除标签',
      message: '「${tag.name}」会从标签库里移除，已贴了这个标签的会话也会一起失去它。',
      confirmText: '删除',
      danger: true,
    );
    if (ok != true) return;
    ref.read(sessionTagDaoProvider).deleteTag(tag.id);
    setState(() => _selected.remove(tag.id));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final faint = GlassPalette.inkFaintOf(brightness);
    final ink = GlassPalette.inkOf(brightness);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: Text(
              '给 ${widget.sessionCount} 个会话打标签',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
              '标签会在多条会话间复用，之后可以按标签找回来',
              style: TextStyle(fontSize: 12, height: 1.5, color: faint),
            ),
          ),
          if (_tags.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Text(
                '还没有标签，先在下面建一个',
                style: TextStyle(fontSize: 13, height: 1.5, color: faint),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _tags.length,
                itemBuilder: (context, index) {
                  final tag = _tags[index];
                  final checked = _selected.contains(tag.id);
                  return ListTile(
                    contentPadding: const EdgeInsets.only(left: 8, right: 8),
                    minVerticalPadding: 10,
                    leading: Checkbox(
                      value: checked,
                      onChanged: (_) => setState(() {
                        if (checked) {
                          _selected.remove(tag.id);
                        } else {
                          _selected.add(tag.id);
                        }
                      }),
                    ),
                    title: Text(
                      tag.name,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        tag.useCount == 0
                            ? '未使用'
                            : '已贴在 ${tag.useCount} 个会话',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: faint,
                        ),
                      ),
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 19,
                        color: faint,
                      ),
                      onPressed: () => _delete(tag),
                    ),
                    onTap: () => setState(() {
                      if (checked) {
                        _selected.remove(tag.id);
                      } else {
                        _selected.add(tag.id);
                      }
                    }),
                  );
                },
              ),
            ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              '新建标签',
              style: TextStyle(fontSize: 12.5, color: faint),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _input,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '如 主线 / 存档 / 试验',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _create(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.tonal(
                  onPressed: _create,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(76, 48),
                  ),
                  child: const Text('添加'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_selected.toList()),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: scheme.primary,
              ),
              child: Text(
                _selected.isEmpty
                    ? '选择或新建标签'
                    : '添加 ${_selected.length} 个标签',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
