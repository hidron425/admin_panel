import 'package:flutter/material.dart';

class AdminColors {
  // Брендовый синий — как в клиенте
  static const Color primary = Color(0xFF2E7BFF);
  static const Color primaryDark = Color(0xFF1A5FCC);
  static const Color primaryLight = Color(0xFF6BA0FF);

  // Фон — белый
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF7F8FA);

  // Границы
  static const Color border = Color(0xFFE5E7EB);

  // Текст
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textDisabled = Color(0xFF9CA3AF);

  // Статусы
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);
}

ThemeData buildAdminTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AdminColors.background,
    colorScheme: const ColorScheme.light(
      primary: AdminColors.primary,
      secondary: AdminColors.primary,
      surface: AdminColors.surface,
      error: AdminColors.danger,
      onPrimary: Colors.white,
      onSurface: AdminColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AdminColors.surface,
      foregroundColor: AdminColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AdminColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: AdminColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AdminColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AdminColors.border,
      thickness: 1,
      space: 1,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AdminColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminColors.primary,
        side: const BorderSide(color: AdminColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AdminColors.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
            inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AdminColors.surfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AdminColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: AdminColors.textDisabled),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AdminColors.primary,
      unselectedLabelColor: AdminColors.textSecondary,
      indicatorColor: AdminColors.primary,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AdminColors.primary,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: AdminColors.surface,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AdminColors.textSecondary,
      textColor: AdminColors.textPrimary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AdminColors.primary;
        return AdminColors.border;
      }),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AdminColors.primary,
      linearTrackColor: AdminColors.surfaceVariant,
    ),
  );
}