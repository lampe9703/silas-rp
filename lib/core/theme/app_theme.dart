import 'package:flutter/material.dart';

import 'fonts.dart';
import 'glass_theme.dart';

export 'fonts.dart';

/// 主题里每一处显式 TextStyle 都必须带上字体族。
///
/// 原因：`ThemeData(fontFamily:)` 只作用于 textTheme 本身，而
/// buttonTheme / snackBarTheme / popupMenuTheme / chipTheme 这类
/// 「子主题里的 textStyle」是**整段替换**的——没写 fontFamily 就等于
/// 显式声明「用系统默认字体」，中文会掉回 Noto Sans CJK。
/// 之前导航栏标签、Toast、排序菜单、按钮文字看着还是旧字体，就是这个原因。
class AppTheme {
  static const Color seed = GlassPalette.sky;

  /// 解析十六进制颜色：支持 #RGB / #RRGGBB / RRGGBB；非法输入返回 null。
  /// 供设置页的主题色 / 点缀色使用。
  static Color? parseHexColor(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 3) {
      s = s.split('').map((c) => c + c).join();
    }
    if (s.length != 6) return null;
    final v = int.tryParse(s, radix: 16);
    if (v == null || v < 0) return null;
    return Color(0xFF000000 | v);
  }

  static ThemeData light({Color? accent, Color? spot}) =>
      _build(Brightness.light, accent, spot);
  static ThemeData dark({Color? accent, Color? spot}) =>
      _build(Brightness.dark, accent, spot);

  /// HSL 明度平移：自定义主题色时派生深浅变体
  static Color _shiftLightness(Color c, double delta) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + delta).clamp(0.0, 1.0))
        .toColor();
  }

  static ThemeData _build(
    Brightness brightness,
    Color? accentOverride,
    Color? spotOverride,
  ) {
    final isDark = brightness == Brightness.dark;

    // 主题色三个明度档：默认时用原马卡龙色（零色偏），自定义时用 HSL 派生
    final accentSoft = accentOverride == null
        ? GlassPalette.skySoft
        : _shiftLightness(accentOverride, isDark ? 0.08 : 0.14);
    final accentMain = accentOverride ?? GlassPalette.sky;
    final accentDeep = accentOverride == null
        ? GlassPalette.skyDeep
        : _shiftLightness(accentOverride, -0.10);
    final spotMain =
        spotOverride ?? (isDark ? GlassPalette.roseSoft : GlassPalette.rose);

    final scheme = ColorScheme.fromSeed(
      seedColor: accentMain,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? accentSoft : accentDeep,
      onPrimary: Colors.white,
      secondary: spotMain,
      tertiary: GlassPalette.mint,
      surface: isDark ? const Color(0xFF1A2431) : Colors.white,
      onSurface: GlassPalette.inkOf(brightness),
      onSurfaceVariant: GlassPalette.inkSoftOf(brightness),
      outline: GlassPalette.hairline(brightness),
      outlineVariant: GlassPalette.hairline(brightness),
      error: const Color(0xFFD9636B),
      surfaceContainerHighest: isDark
          ? Colors.white.withOpacity(0.10)
          : Colors.white.withOpacity(0.72),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: kCjkFamily,
    );
    final textTheme = base.textTheme
        .apply(
          bodyColor: GlassPalette.inkOf(brightness),
          displayColor: GlassPalette.inkOf(brightness),
        )
        // 整份 TextTheme 再压一遍字体族：ThemeData(fontFamily:) 在某些
        // Typography 组合下会漏掉个别档位（display*/headline*），这里兜底。
        .apply(fontFamily: kCjkFamily);

    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: GlassPalette.inkOf(brightness),
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          fontFamily: kCjkFamily,
          color: GlassPalette.inkOf(brightness),
        ),
      ),
      // 现有页面里的 Card 统一成「磨砂片」：半透明 + 细描边 + 柔投影
      cardTheme: CardTheme(
        elevation: 0,
        color: isDark
            ? const Color(0xFF1A2431).withOpacity(0.72)
            : Colors.white.withOpacity(0.66),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.10)
                : Colors.white.withOpacity(0.66),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withOpacity(0.07)
            : Colors.white.withOpacity(0.62),
        hintStyle: TextStyle(
          fontSize: 14,
          fontFamily: kCjkFamily,
          color: GlassPalette.inkFaintOf(brightness),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: GlassPalette.glassBorder(brightness)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.10)
                : Colors.white.withOpacity(0.70),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? accentSoft : accentMain,
            width: 1.4,
          ),
        ),
        isDense: true,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: GlassPalette.hairline(brightness)),
        backgroundColor: isDark
            ? Colors.white.withOpacity(0.07)
            : Colors.white.withOpacity(0.62),
        labelStyle: TextStyle(
          fontSize: 12,
          fontFamily: kCjkFamily,
          color: GlassPalette.inkSoftOf(brightness),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        shape: const StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF22303F).withOpacity(0.96)
            : const Color(0xFF40566F).withOpacity(0.94),
        contentTextStyle: const TextStyle(
          fontSize: 13,
          fontFamily: kCjkFamily,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: isDark
            ? const Color(0xFF1A2431)
            : Colors.white.withOpacity(0.96),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark
            ? const Color(0xFF18212D).withOpacity(0.98)
            : Colors.white.withOpacity(0.96),
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: isDark
            ? const Color(0xFF18212D).withOpacity(0.98)
            : Colors.white.withOpacity(0.96),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        dragHandleColor: GlassPalette.inkFaintOf(brightness).withOpacity(0.4),
      ),
      dividerTheme: DividerThemeData(
        color: GlassPalette.hairline(brightness).withOpacity(0.9),
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        iconColor: GlassPalette.inkSoftOf(brightness),
        textColor: GlassPalette.inkOf(brightness),
        titleTextStyle: TextStyle(
          fontSize: 14,
          fontFamily: kCjkFamily,
          color: GlassPalette.inkOf(brightness),
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 11.5,
          fontFamily: kCjkFamily,
          color: GlassPalette.inkSoftOf(brightness),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: isDark ? accentSoft : accentMain,
        inactiveTrackColor: (isDark ? accentSoft : accentMain)
            .withOpacity(0.18),
        thumbColor: Colors.white,
        overlayColor: accentMain.withOpacity(0.12),
        trackHeight: 4,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : (isDark ? Colors.white70 : Colors.white),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (isDark ? accentMain : accentDeep)
              : GlassPalette.inkFaintOf(brightness).withOpacity(0.35),
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isDark ? accentMain : accentDeep,
        foregroundColor: Colors.white,
        elevation: 4,
        highlightElevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? accentMain : accentDeep,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontFamily: kCjkFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? accentSoft : accentDeep,
          textStyle: const TextStyle(fontSize: 13.5, fontFamily: kCjkFamily),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? accentSoft : accentDeep,
          side: BorderSide(color: GlassPalette.hairline(brightness)),
          minimumSize: const Size(0, 46),
          textStyle: const TextStyle(fontSize: 14, fontFamily: kCjkFamily),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark
            ? const Color(0xFF1E2836).withOpacity(0.98)
            : Colors.white.withOpacity(0.96),
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: TextStyle(
          fontSize: 13.5,
          fontFamily: kCjkFamily,
          color: GlassPalette.inkOf(brightness),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: TextStyle(
          fontSize: 12,
          height: 1.35,
          fontFamily: kCjkFamily,
          color: isDark ? GlassPalette.inkOf(Brightness.dark) : Colors.white,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF22303F).withOpacity(0.96)
              : const Color(0xFF40566F).withOpacity(0.94),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }
}
