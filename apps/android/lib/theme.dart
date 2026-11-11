import 'package:flutter/material.dart';

class TaskatyColors {
  static const navy = Color(0xFF0B1220);
  static const surface = Color(0xFF131D2E);
  static const surface2 = Color(0xFF1A273B);
  static const cyan = Color(0xFF29D4E8);
  static const amber = Color(0xFFFFB547);
  static const green = Color(0xFF4ADE80);
  static const muted = Color(0xFF91A2BA);
}

ThemeData buildTaskatyTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: TaskatyColors.cyan, brightness: Brightness.dark, surface: TaskatyColors.surface, primary: TaskatyColors.cyan, secondary: TaskatyColors.amber, error: const Color(0xFFFF7272));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: TaskatyColors.navy,
    appBarTheme: const AppBarTheme(backgroundColor: TaskatyColors.navy, surfaceTintColor: Colors.transparent, elevation: 0, centerTitle: false),
    cardTheme: CardThemeData(color: TaskatyColors.surface, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF24334A)))),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: TaskatyColors.surface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF2A3A52))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF2A3A52))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: TaskatyColors.cyan, width: 1.5)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: TaskatyColors.surface, indicatorColor: TaskatyColors.cyan.withValues(alpha: .14), labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(fontSize: 11, color: s.contains(WidgetState.selected) ? TaskatyColors.cyan : TaskatyColors.muted, fontWeight: FontWeight.w600))),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: TaskatyColors.cyan, foregroundColor: TaskatyColors.navy),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: TaskatyColors.cyan, foregroundColor: TaskatyColors.navy, minimumSize: const Size(48, 50), textStyle: const TextStyle(fontWeight: FontWeight.w700), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48), side: const BorderSide(color: Color(0xFF33445E)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
    chipTheme: ChipThemeData(backgroundColor: TaskatyColors.surface2, side: BorderSide.none, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), labelStyle: const TextStyle(color: TaskatyColors.muted)),
    textTheme: const TextTheme(headlineMedium: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.6), titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w700), titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700), bodyMedium: TextStyle(color: Color(0xFFD7E0EC), fontSize: 14), bodySmall: TextStyle(color: TaskatyColors.muted, fontSize: 12)),
  );
}
