import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/theme/glass_theme.dart';
import '../../../shared/glass_route.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../data/character_dao.dart';
import '../domain/character_card.dart';
import '../../chat/presentation/chat_page.dart';

/// 独立的角色卡搜索页（入口在角色卡仓库右下角的圆形按钮）
class CharacterSearchPage extends ConsumerStatefulWidget {
  const CharacterSearchPage({super.key});

  @override
  ConsumerState<CharacterSearchPage> createState() =>
      _CharacterSearchPageState();
}

class _CharacterSearchPageState extends ConsumerState<CharacterSearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<CharacterCard> _results = const <CharacterCard>[];
  String _query = '';
  bool _loaded = false;

  /// 返回拦截去重：收键盘的短暂延迟期间连按返回不会重入
  bool _popping = false;

  @override
  void initState() {
    super.initState();
    // 先给一个「全部」列表，空查询时也有内容可看
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _run('');
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 160), () => _run(value));
  }

  void _run(String value) {
    final q = value.trim();
    final results = ref.read(characterRepositoryProvider).list(
          query: q,
          sort: q.isEmpty ? CardSort.lastChat : CardSort.updated,
          limit: 60,
        );
    if (!mounted) return;
    setState(() {
      _query = q;
      _results = results;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return PopScope(
      // 拦截返回：搜索框常持焦点，键盘下沉状态下直接返回主页
      // 会把输入法重新唤出（与聊天页同根因）。先收 IME 再离开。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _popping) return;
        _popping = true;
        final navigator = Navigator.of(context);
        try {
          FocusManager.instance.primaryFocus?.unfocus();
          await SystemChannels.textInput.invokeMethod('TextInput.hide');
          await Future<void>.delayed(const Duration(milliseconds: 60));
        } finally {
          _popping = false;
        }
        if (mounted) navigator.pop();
      },
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _run,
            style: TextStyle(
              fontSize: 15,
              color: GlassPalette.inkOf(brightness),
            ),
            decoration: InputDecoration(
              hintText: '搜索角色卡名称、描述或标签',
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: GlassPalette.inkFaintOf(brightness),
              ),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _controller.clear();
                        _run('');
                      },
                    ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
      ),
      body: !_loaded
          ? const SizedBox.shrink()
          : _results.isEmpty
              ? EmptyState(
                  icon: _query.isEmpty
                      ? Icons.style_outlined
                      : Icons.search_off_rounded,
                  title: _query.isEmpty ? '还没有角色卡' : '没有找到「$_query」',
                  description: _query.isEmpty
                      ? '回到角色卡仓库，导入或编写一张吧。'
                      : '换个关键词试试，搜索会同时匹配名称、描述和标签。',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: _results.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 4),
                        child: Text(
                          _query.isEmpty
                              ? '全部角色卡 · ${_results.length}'
                              : '找到 ${_results.length} 张',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 0.6,
                            color: GlassPalette.inkFaintOf(brightness),
                          ),
                        ),
                      );
                    }
                    final card = _results[index - 1];
                    return _ResultTile(card: card);
                  },
                ),
      ),
    );
  }
}

class _ResultTile extends ConsumerWidget {
  const _ResultTile({required this.card});

  final CharacterCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final avatar = ref.watch(avatarStorageProvider).file(card.avatarPath);

    return GlassSurface(
      radius: 18,
      blur: 14,
      alpha: brightness == Brightness.dark ? 0.55 : 0.56,
      lift: 0.6,
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.of(context).push(
        glassPageRoute<void>(ChatPage(cardId: card.id)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CharacterAvatar(file: avatar, name: card.name, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: GlassPalette.inkOf(brightness),
                  ),
                ),
                if (card.previewText.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    card.previewText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: GlassPalette.inkSoftOf(brightness),
                    ),
                  ),
                ],
                if (card.tags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: <Widget>[
                      for (final tag in card.tags.take(4))
                        GlassChip(label: tag, dense: true),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
