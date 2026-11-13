import 'package:flutter/material.dart';

/// Product colors shared by Taskaty's status indicators and illustrations.
class TaskatyColors {
  static const cyan = Color(0xFF087E83);
  static const amber = Color(0xFFB35C00);
  static const green = Color(0xFF28734D);
  static const navy = Color(0xFF111A29);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF0F4F6);
  static const muted = Color(0xFF596874);
}

ThemeData buildTaskatyTheme({Brightness brightness = Brightness.light}) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: TaskatyColors.cyan,
    brightness: brightness,
    surface: isDark ? const Color(0xFF111A29) : const Color(0xFFF5F7F8),
    primary: isDark ? const Color(0xFF78D5D4) : TaskatyColors.cyan,
    secondary: isDark ? const Color(0xFFFFC16D) : const Color(0xFF8C4C00),
    error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFB3261E),
  );
  final cardColor = isDark ? const Color(0xFF182437) : Colors.white;
  final outline = isDark ? const Color(0xFF2D3B50) : const Color(0xFFE0E7EA);
  final textTheme = ThemeData(brightness: brightness, useMaterial3: true)
      .textTheme
      .apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
        fontFamilyFallback: const [
          'Noto Naskh Arabic',
          'Noto Sans Arabic',
          'Arial',
        ],
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    textTheme: textTheme.copyWith(
      headlineMedium: textTheme.headlineMedium?.copyWith(
        fontSize: 27,
        height: 1.25,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.35,
      ),
      titleLarge: textTheme.titleLarge?.copyWith(
        fontSize: 19,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
      bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.55),
      bodySmall: textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
        fontSize: 12,
        height: 1.5,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      elevation: isDark ? 0 : 1,
      shadowColor: const Color(0x140A1B2B),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF121E2E) : const Color(0xFFFAFBFC),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      floatingLabelStyle: TextStyle(color: scheme.primary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cardColor,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      indicatorColor: scheme.primary.withValues(alpha: isDark ? .2 : .12),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: cardColor,
      indicatorColor: scheme.primary.withValues(alpha: isDark ? .22 : .13),
      selectedIconTheme: IconThemeData(color: scheme.primary),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 3,
      shape: const StadiumBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(48, 50),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.primary.withValues(alpha: isDark ? .22 : .14),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark
          ? const Color(0xFF29374A)
          : const Color(0xFF263642),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
  );
}

extension TaskatyThemeColors on BuildContext {
  Color get taskatyAccent => Theme.of(this).colorScheme.primary;
  Color get taskatyMuted => Theme.of(this).colorScheme.onSurfaceVariant;
  Color get taskatyWarning => Theme.of(this).brightness == Brightness.dark
      ? const Color(0xFFFFC16D)
      : TaskatyColors.amber;
  Color get taskatySuccess => Theme.of(this).brightness == Brightness.dark
      ? const Color(0xFF8DDBA6)
      : TaskatyColors.green;
  Color get taskatySurfaceAlt => Theme.of(this).brightness == Brightness.dark
      ? const Color(0xFF202D40)
      : const Color(0xFFEBF1F3);
}
