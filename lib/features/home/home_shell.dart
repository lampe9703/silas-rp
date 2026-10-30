import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/theme/glass_theme.dart';
import '../../shared/glass_route.dart';
import '../characters/presentation/character_library_page.dart';
import '../characters/presentation/character_search_page.dart';
import '../editor/presentation/card_editor_page.dart';
import '../settings/presentation/settings_page.dart';
import '../stats/presentation/stats_page.dart';
import 'app_tab.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with SingleTickerProviderStateMixin {
  AppTab _current = AppTab.characters;

  /// 切换目标：连续快速点击时以最后一次为准
  AppTab _target = AppTab.characters;
  Timer? _swapTimer;

  /// Tab 内容的 fade-through：旧内容淡出 → 环境光 → 新内容淡入。
  /// IndexedStack 全程保活，只动透明度，页面状态（滚动位置/输入草稿）不丢。
  late final AnimationController _contentFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 210),
    reverseDuration: const Duration(milliseconds: 90),
    value: 1,
  );

  /// 按枚举顺序固定，保证调整导航顺序时页面状态不丢失
  late final List<Widget> _pages = const <Widget>[
    CharacterLibraryPage(),
    StatsPage(),
    CardEditorPage(embedded: true),
    SettingsPage(),
  ];

  @override
  void dispose() {
    _swapTimer?.cancel();
    _contentFade.dispose();
    super.dispose();
  }

  void _openSearch() {
    Navigator.of(context).push(
      glassPageRoute<void>(const CharacterSearchPage()),
    );
  }

  void _selectTab(AppTab tab) {
    if (tab == _current) return;
    if (_swapTimer != null && tab == _target) return;
    _target = tab;
    _swapTimer?.cancel();
    _contentFade.reverse();
    // 中点换页：淡出完成时才切 IndexedStack，视觉上是干净的 fade-through
    _swapTimer = Timer(const Duration(milliseconds: 90), () {
      _swapTimer = null;
      if (!mounted) return;
      setState(() => _current = _target);
      _contentFade.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final order = resolveTabOrder(ref.watch(appSettingsProvider).navOrder);
    final index = AppTab.values.indexOf(_current);
    // 搜索是角色卡仓库的入口，别的 tab 不显示，避免误导
    final showSearch = _current == AppTab.characters;

    return Scaffold(
      extendBody: true,
      // 关键：键盘弹出时**不要**把整个 body（含底部导航）顶到输入法上方。
      // 各 Tab 页面自己的 Scaffold 会正确处理键盘 insets，让内容滚到
      // 输入法上方；导航胶囊留在屏幕底部（被键盘盖住）——「仅出现输入法」。
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: <Widget>[
          FadeTransition(
            opacity: CurvedAnimation(
              parent: _contentFade,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
            child: IndexedStack(index: index, children: _pages),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 搜索入口：右下角悬浮胶囊（参考旧版「编写角色卡」框的位置），
                  // 处于导航胶囊上方；离开角色卡仓库时滑落淡出，回来时上浮淡入
                  IgnorePointer(
                    ignoring: !showSearch,
                    child: AnimatedSlide(
                      offset: showSearch
                          ? Offset.zero
                          : const Offset(0, 0.6),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: showSearch ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding:
                                const EdgeInsets.only(right: 4, bottom: 12),
                            child: GlassPillButton(
                              icon: Icons.search_rounded,
                              label: '搜索',
                              width: GlassPillButton.sharedWidth,
                              tooltip: '搜索角色卡',
                              onTap: _openSearch,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  GlassNavBar(
                    currentIndex: order.indexOf(_current),
                    onSelected: (i) => _selectTab(order[i]),
                    items: <GlassNavItem>[
                      for (final tab in order)
                        GlassNavItem(
                          label: tab.label,
                          icon: tab.icon,
                          activeIcon: tab.activeIcon,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
