import 'package:flutter/material.dart';

class KiitColors {
  const KiitColors._();

  static const brandPrimary = Color(0xFF159A53);
  static const brandPrimaryStrong = Color(0xFF0B6F3A);
  static const brandPrimarySoft = Color(0xFFE8F7EF);
  static const brandPrimarySubtle = Color(0xFFF3FBF6);
  static const background = Color(0xFFF7FAF8);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceElevated = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF17211D);
  static const textSecondary = Color(0xFF52615A);
  static const textMuted = Color(0xFF7A8781);
  static const border = Color(0xFFDDE7E1);
  static const divider = Color(0xFFE8EFEA);
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
  static const large = 16.0;
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
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 36,
        height: 1.05,
        fontWeight: FontWeight.w800,
        color: KiitColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        height: 1.15,
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
        height: 1.45,
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
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: KiitColors.textPrimary,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: KiitColors.surface,
      indicatorColor: KiitColors.brandPrimarySoft,
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
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KiitRadius.medium),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: KiitColors.brandPrimaryStrong,
        minimumSize: const Size(48, 48),
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
  );
}
