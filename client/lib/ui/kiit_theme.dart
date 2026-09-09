import 'package:flutter/material.dart';

class KiitColors {
  const KiitColors._();

  static const brandPrimary = Color(0xFF149447);
  static const brandPrimaryStrong = Color(0xFF116B38);
  static const brandPrimarySoft = Color(0xFFE7F5EC);
  static const brandPrimarySubtle = Color(0xFFF3F9F5);
  static const background = Color(0xFFF5F7F5);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceElevated = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF15201A);
  static const textSecondary = Color(0xFF56635C);
  static const textMuted = Color(0xFF849089);
  static const border = Color(0xFFDCE4DF);
  static const divider = Color(0xFFE7ECE9);
  static const success = Color(0xFF15803D);
  static const warning = Color(0xFFB7791F);
  static const error = Color(0xFFB42318);
  static const info = Color(0xFF2563EB);
  static const present = Color(0xFF15803D);
  static const absent = Color(0xFFB42318);
}

class KiitSpacing {
  const KiitSpacing._();

  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
}

class KiitRadius {
  const KiitRadius._();

  static const small = 8.0;
  static const medium = 12.0;
  static const large = 18.0;
  static const hero = 22.0;
}

ThemeData buildKiitTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: KiitColors.brandPrimary,
    brightness: Brightness.light,
    primary: KiitColors.brandPrimary,
    secondary: KiitColors.brandPrimaryStrong,
    surface: KiitColors.surface,
    error: KiitColors.error,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: KiitColors.background,
    visualDensity: VisualDensity.standard,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        height: 1.08,
        fontWeight: FontWeight.w800,
        color: KiitColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        height: 1.12,
        fontWeight: FontWeight.w800,
        color: KiitColors.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        height: 1.18,
        fontWeight: FontWeight.w800,
        color: KiitColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: KiitColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: KiitColors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.42,
        color: KiitColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.4,
        color: KiitColors.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: KiitColors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: KiitColors.textSecondary,
      ),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: KiitColors.surface,
      foregroundColor: KiitColors.textPrimary,
      toolbarHeight: 68,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        color: KiitColors.textPrimary,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      height: 72,
      backgroundColor: KiitColors.surface,
      indicatorColor: KiitColors.brandPrimarySoft,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? KiitColors.brandPrimaryStrong
              : KiitColors.textSecondary,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: KiitColors.brandPrimary,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KiitRadius.medium),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: KiitColors.brandPrimaryStrong,
        minimumSize: const Size(48, 52),
        side: const BorderSide(color: KiitColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KiitRadius.medium),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    cardTheme: CardThemeData(
      color: KiitColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KiitRadius.large),
        side: const BorderSide(color: KiitColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: KiitColors.divider,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KiitColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: KiitColors.textSecondary),
      hintStyle: const TextStyle(color: KiitColors.textMuted),
      prefixIconColor: KiitColors.textSecondary,
      suffixIconColor: KiitColors.textSecondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KiitRadius.medium),
        borderSide: const BorderSide(color: KiitColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KiitRadius.medium),
        borderSide: const BorderSide(color: KiitColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KiitRadius.medium),
        borderSide:
            const BorderSide(color: KiitColors.brandPrimary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KiitRadius.medium),
        borderSide: const BorderSide(color: KiitColors.error),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: KiitColors.textPrimary,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KiitRadius.medium),
      ),
    ),
  );
}
