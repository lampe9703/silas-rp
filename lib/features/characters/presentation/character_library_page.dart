import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../shared/glass_route.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../chat/presentation/chat_page.dart';
import '../../editor/presentation/card_editor_page.dart';
import '../data/card_import_service.dart';
import '../data/character_dao.dart';
import '../data/character_repository.dart';
import 'card_generation_sheet.dart';
import '../domain/character_card.dart';
import 'controllers/character_list_controller.dart';

class CharacterLibraryPage extends ConsumerStatefulWidget {
  const CharacterLibraryPage({super.key});

  @override
  ConsumerState<CharacterLibraryPage> createState() =>
      _CharacterLibraryPageState();
}

class _CharacterLibraryPageState extends ConsumerState<CharacterLibraryPage> {
  final _scrollController = ScrollController();
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(characterListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(characterListProvider);
    final settings = ref.watch(appSettingsProvider);
    final tags = ref.watch(characterTagsProvider);
    final isGrid = settings.libraryViewMode == 'grid';

    return Scaffold(
      appBar: AppBar(
        title: const Text('角色卡仓库'),
        actions: [
          IconButton(
            tooltip: isGrid ? '切换列表' : '切换网格',
            onPressed: () => ref
                .read(appSettingsProvider.notifier)
                .setLibraryViewMode(isGrid ? 'list' : 'grid'),
            icon: Icon(isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded),
          ),
          PopupMenuButton<CardSort>(
            tooltip: '排序',
            icon: const Icon(Icons.sort_rounded),
            initialValue: state.sort,
            onSelected: (sort) =>
                ref.read(characterListProvider.notifier).setSort(sort),
            itemBuilder: (context) => const [
              PopupMenuItem(value: CardSort.updated, child: Text('最近编辑')),
              PopupMenuItem(value: CardSort.lastChat, child: Text('最近聊天')),
              PopupMenuItem(value: CardSort.name, child: Text('名称')),
            ],
          ),
          IconButton(
            tooltip: '导入角色卡',
            onPressed: _importing ? null : _chooseImport,
            icon: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (tags.isNotEmpty)
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: tags.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final entry = tags[index];
                  final selected = state.tags.contains(entry.tag);
                  return FilterChip(
                    label: Text('${entry.tag} ${entry.count}'),
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) => ref
                        .read(characterListProvider.notifier)
                        .toggleTag(entry.tag),
                  );
                },
              ),
            ),
          const SizedBox(height: 4),
          Expanded(child: _buildBody(state, isGrid)),
        ],
      ),
    );
  }

  Widget _buildBody(CharacterListState state, bool isGrid) {
    if (state.items.isEmpty) {
      return EmptyState(
        icon: state.isFiltering ? Icons.search_off_rounded : Icons.style_outlined,
        title: state.isFiltering ? '没有匹配的角色卡' : '还没有角色卡',
        description: state.isFiltering
            ? '换个关键词或清除标签筛选试试'
            : '支持导入 SillyTavern 的 PNG 角色卡与 JSON 文件，也可以自己编写一张。',
        action: state.tags.isEmpty
            ? FilledButton.icon(
                onPressed: _chooseImport,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('导入角色卡'),
              )
            : TextButton(
                onPressed: () =>
                    ref.read(characterListProvider.notifier).clearTags(),
                child: const Text('清除筛选'),
              ),
      );
    }

    if (isGrid) {
      return GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 150),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.74,
        ),
        itemCount: state.items.length,
        itemBuilder: (context, index) => _GridTile(card: state.items[index]),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 150),
      itemCount: state.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _ListTile(card: state.items[index]),
    );
  }

  /// 先选来源：普通模式（酒馆通用卡）还是高级模式（幻梦卡）
  Future<void> _chooseImport() async {
    final flavor = await showModalBottomSheet<CardImportFlavor>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.style_outlined),
              title: const Text('普通模式导入'),
              subtitle: const Text('酒馆通用卡：Character Card V1 / V2 / V3'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(CardImportFlavor.tavern),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: const Text('高级模式导入'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(CardImportFlavor.huanmeng),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (flavor == null || !mounted) return;
    await _import(flavor);
  }

  Future<void> _import(CardImportFlavor flavor) async {
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['png', 'json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final repo = ref.read(characterRepositoryProvider);
      var imported = 0;
      var failed = 0;
      final failures = <String>[];

      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) {
          failed++;
          failures.add(file.name);
          continue;
        }
        final name = file.name.toLowerCase();
        if (name.endsWith('.json')) {
          final outcome = await repo.importJsonPayload(
            utf8.decode(bytes, allowMalformed: true),
            fileName: file.name,
            flavor: flavor,
          );
          imported += outcome.imported;
          failed += outcome.failed;
          failures.addAll(outcome.failures);
        } else {
          final outcome = await repo.importFile(
            bytes,
            fileName: file.name,
            flavor: flavor,
          );
          imported += outcome.imported;
          failed += outcome.failed;
          failures.addAll(outcome.failures);
        }
      }

      ref.read(characterListProvider.notifier).refresh();
      if (!mounted) return;
      final mode = flavor == CardImportFlavor.tavern ? '酒馆卡' : '幻梦卡';
      final message = failed == 0
          ? '成功按$mode导入 $imported 张角色卡'
          : '按$mode导入：成功 $imported 张，失败 $failed 张（${failures.take(2).join('、')}）';
      showToast(context, message);
    } catch (e) {
      if (mounted) showToast(context, '导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}

class _GridTile extends ConsumerWidget {
  const _GridTile({required this.card});

  final CharacterCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final avatar = ref.watch(avatarStorageProvider).file(card.avatarPath);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openChat(context),
      onLongPress: () => _showActions(context, ref),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: scheme.primary.withOpacity(0.12),
                    child: avatar == null
                        ? Center(
                            child: Text(
                              card.name.isEmpty
                                  ? '?'
                                  : card.name.substring(0, 1).toUpperCase(),
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                            ),
                          )
                        : Image.file(
                            avatar,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                  ),
                  if (card.isFavorite)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(Icons.favorite_rounded,
                          size: 16, color: Colors.white),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    card.previewText.isEmpty ? '暂无简介' : card.previewText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (card.tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: card.tags
                          .take(2)
                          .map((t) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  t,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: scheme.primary,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openChat(BuildContext context) {
    Navigator.of(context).push(
      glassPageRoute<void>(ChatPage(cardId: card.id)),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    showCharacterActions(context, ref, card);
  }
}

class _ListTile extends ConsumerWidget {
  const _ListTile({required this.card});

  final CharacterCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final avatar = ref.watch(avatarStorageProvider).file(card.avatarPath);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          glassPageRoute<void>(ChatPage(cardId: card.id)),
        ),
        onLongPress: () => showCharacterActions(context, ref, card),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CharacterAvatar(file: avatar, name: card.name, size: 58),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            card.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (card.isFavorite)
                          Icon(Icons.favorite_rounded,
                              size: 14, color: scheme.primary),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card.previewText.isEmpty ? '暂无简介' : card.previewText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (card.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: card.tags
                            .take(4)
                            .map((t) => Text(
                                  '#$t',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.primary,
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 长按操作面板：编辑 / 复制 / 导出 / 收藏 / 删除
Future<void> showCharacterActions(
  BuildContext context,
  WidgetRef ref,
  CharacterCard card,
) async {
  final repo = ref.read(characterRepositoryProvider);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('卡面信息'),
              subtitle: const Text('名称 / 简介 / 标签'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showCardMetaSheet(context, ref, card);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑角色卡'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context)
                    .push(glassPageRoute<void>(CardEditorPage(cardId: card.id)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('生成参数'),
              subtitle: const Text(
                '温度 / 上下文上限，仅对这张卡生效',
                style: TextStyle(fontSize: 11.5),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showCardGenerationSheet(context, ref, card);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('复制一份'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await repo.duplicate(card.id);
                ref.read(characterListProvider.notifier).refresh();
                if (context.mounted) showToast(context, '已复制');
              },
            ),
            ListTile(
              leading: Icon(
                card.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              title: Text(card.isFavorite ? '取消收藏' : '加入收藏'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await repo.toggleFavorite(card);
                ref.read(characterListProvider.notifier).refresh();
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('导出'),
              subtitle: const Text('JSON（通用）/ PNG（内嵌元数据）'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showExportSheet(context, repo, card);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final confirmed = await showConfirmDialog(
                  context,
                  title: '删除角色卡',
                  message: '「${card.name}」及其全部会话记录都会被删除，且无法恢复。',
                  confirmText: '删除',
                  danger: true,
                );
                if (!confirmed) return;
                await repo.delete(card);
                ref.read(characterListProvider.notifier).refresh();
                if (context.mounted) showToast(context, '已删除');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> _showExportSheet(
  BuildContext context,
  CharacterRepository repo,
  CharacterCard card,
) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.data_object_rounded),
            title: const Text('导出 JSON'),
            subtitle: const Text('Character Card V2 结构'),
            onTap: () => Navigator.of(sheetContext).pop('json'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('导出 PNG'),
            subtitle: const Text('把数据写进头像图片，可直接拖进 SillyTavern'),
            onTap: () => Navigator.of(sheetContext).pop('png'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null) return;

  try {
    String? path;
    if (choice == 'json') {
      path = await repo.exportJson(card);
    } else {
      path = await repo.exportPng(card);
      if (path == null) {
        if (context.mounted) showToast(context, '这张角色卡没有 PNG 头像，无法导出为 PNG');
        return;
      }
    }
    await shareExportedFile(path);
    if (context.mounted) showToast(context, '已导出到：$path');
  } catch (e) {
    if (context.mounted) showToast(context, '导出失败：$e');
  }
}

/// 卡面信息：名称 / 简介 / 标签（写卡页不再负责这些元数据）
Future<void> showCardMetaSheet(
  BuildContext context,
  WidgetRef ref,
  CharacterCard card,
) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CardMetaSheet(card: card, ref: ref),
  );
  if (saved == true && context.mounted) {
    ref.read(characterListProvider.notifier).refresh();
    showToast(context, '已更新卡面信息');
  }
}

class _CardMetaSheet extends StatefulWidget {
  const _CardMetaSheet({required this.card, required this.ref});

  final CharacterCard card;
  final WidgetRef ref;

  @override
  State<_CardMetaSheet> createState() => _CardMetaSheetState();
}

class _CardMetaSheetState extends State<_CardMetaSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.card.name);
  late final TextEditingController _summary =
      TextEditingController(text: widget.card.summary);
  final TextEditingController _tagInput = TextEditingController();
  late final List<String> _tags = <String>[...widget.card.tags];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _summary.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showToast(context, '名称不能为空');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.ref.read(characterRepositoryProvider).save(
            widget.card.copyWith(
              name: name,
              summary: _summary.text.trim(),
              tags: List<String>.from(_tags),
            ),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, '保存失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        0,
        18,
        18 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text(
                '卡面信息',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            TextField(
              controller: _name,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '角色名字',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _summary,
              maxLines: 3,
              minLines: 2,
              style: const TextStyle(fontSize: 14, height: 1.5),
              decoration: const InputDecoration(
                labelText: '简介',
                hintText: '一两句话的卡片简介，只显示在卡库列表里',
              ),
            ),
            const SizedBox(height: 14),
            const Text('标签', style: TextStyle(fontSize: 12.5)),
            const SizedBox(height: 8),
            if (_tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final tag in _tags)
                      Chip(
                        label: Text(tag),
                        onDeleted: () => setState(() => _tags.remove(tag)),
                        deleteIcon: const Icon(Icons.close_rounded, size: 14),
                      ),
                  ],
                ),
              ),
            TextField(
              controller: _tagInput,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 14),
              onSubmitted: (value) {
                final tag = value.trim();
                if (tag.isEmpty) return;
                if (!_tags.contains(tag)) setState(() => _tags.add(tag));
                _tagInput.clear();
              },
              decoration: const InputDecoration(
                hintText: '输入标签后回车添加，例如：奇幻、恋爱',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

