import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/glass_theme.dart';
import 'features/home/home_shell.dart';

/// 原生通道：设置状态栏/导航栏图标明暗。
///
/// 为什么不用 Flutter 自带的 SystemUiOverlayStyle：Flutter 3.24 走的是旧的
/// View.setSystemUiVisibility，而 Android 15+ 强制 edge-to-edge 后会忽略其中的
/// LIGHT_STATUS_BAR 标志（导航栏标志碰巧还认），表现就是亮色模式下状态栏图标
/// 仍是白色、看不清。原生侧用 WindowInsetsController 设置，新旧系统都可靠。
const MethodChannel _systemUiChannel = MethodChannel('app/system_ui');

class AiRoleplayApp extends ConsumerStatefulWidget {
  const AiRoleplayApp({super.key});

  @override
  ConsumerState<AiRoleplayApp> createState() => _AiRoleplayAppState();
}

class _AiRoleplayAppState extends ConsumerState<AiRoleplayApp> {
  /// 上次同步给系统的「图标是否用浅色」，避免每帧重复打通道
  bool? _syncedLightIcons;

  /// light = true：暗色底，图标用浅色；false：亮色底，图标用深色。
  void _syncSystemBarIcons(bool light) {
    if (_syncedLightIcons == light) return;
    _syncedLightIcons = light;
    // 放到帧后执行：确保晚于 Flutter 引擎的首次默认设置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _systemUiChannel.invokeMethod<void>(
        'setSystemBarIcons',
        <String, dynamic>{'light': light},
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final themeMode = settings.themeMode;
    // 用户自定义的主题色 / 点缀色（十六进制）；非法或为空时回落默认马卡龙蓝粉
    final accent = AppTheme.parseHexColor(settings.themeAccent);
    final spot = AppTheme.parseHexColor(settings.themeSpot);

    return MaterialApp(
      title: 'Silas RP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accent: accent, spot: spot),
      darkTheme: AppTheme.dark(accent: accent, spot: spot),
      themeMode: switch (themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      locale: const Locale('zh', 'CN'),
      supportedLocales: const <Locale>[
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // 全局环境光背景：所有页面透明化后叠在这层之上，玻璃面板才有东西可模糊
      builder: (context, child) {
        // 状态栏 / 导航栏图标明暗必须跟随 App 内实际主题：
        // 亮色底配白色图标会看不清（反之亦然）。App 内主题可手动切换，
        // 所以不能靠 Android 的 values-night（那只跟随系统）。
        final bool isDark = switch (themeMode) {
          'light' => false,
          'dark' => true,
          _ => MediaQuery.of(context).platformBrightness == Brightness.dark,
        };
        _syncSystemBarIcons(isDark);
        return AmbientBackdrop(
          accent: accent,
          spot: spot,
          // 兜底：没有显式 TextStyle 的 Text 也走内置简中字形
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: kCjkFamily),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const HomeShell(),
    );
  }
}
