import 'package:flutter/material.dart';

/// 四个主 Tab。顺序可在设置中调整，持久化到 app_settings.nav_order。
enum AppTab { characters, stats, editor, settings }

extension AppTabX on AppTab {
  String get label {
    switch (this) {
      case AppTab.characters:
        return '角色卡仓库';
      case AppTab.stats:
        return 'API 统计';
      case AppTab.editor:
        return '编写角色卡';
      case AppTab.settings:
        return '设置';
    }
  }

  IconData get icon {
    switch (this) {
      case AppTab.characters:
        return Icons.style_outlined;
      case AppTab.stats:
        return Icons.insights_outlined;
      case AppTab.editor:
        return Icons.edit_note_outlined;
      case AppTab.settings:
        return Icons.settings_outlined;
    }
  }

  IconData get activeIcon {
    switch (this) {
      case AppTab.characters:
        return Icons.style_rounded;
      case AppTab.stats:
        return Icons.insights_rounded;
      case AppTab.editor:
        return Icons.edit_note_rounded;
      case AppTab.settings:
        return Icons.settings_rounded;
    }
  }

  static AppTab fromId(String id) => AppTab.values.firstWhere(
        (tab) => tab.name == id,
        orElse: () => AppTab.characters,
      );
}

/// 把持久化的顺序还原成完整、无重复的 Tab 列表
List<AppTab> resolveTabOrder(List<String> stored) {
  final result = <AppTab>[];
  for (final id in stored) {
    for (final tab in AppTab.values) {
      if (tab.name == id && !result.contains(tab)) {
        result.add(tab);
        break;
      }
    }
  }
  for (final tab in AppTab.values) {
    if (!result.contains(tab)) result.add(tab);
  }
  return result;
}
