import 'package:flutter/material.dart';

class ProductColors {
  const ProductColors._();

  // Bold dark identity: ink-black canvas, neon KIIT green.
  static const brandPrimary = Color(0xFF2BD96B);
  static const brandPrimaryStrong = Color(0xFF7CF0A5);
  static const brandPrimarySoft = Color(0xFF123524);
  static const brandPrimarySubtle = Color(0xFF0E2519);
  /// Text/icon colour to place on a [brandPrimary] fill.
  static const onBrand = Color(0xFF03140A);
  static const background = Color(0xFF070B09);
  static const surface = Color(0xFF111915);
  static const surfaceElevated = Color(0xFF18221D);
  static const textPrimary = Color(0xFFF2F7F4);
  static const textSecondary = Color(0xFFA9BBB1);
  static const textMuted = Color(0xFF6E8277);
  static const border = Color(0xFF22302A);
  static const divider = Color(0xFF1A2520);
  static const success = Color(0xFF3DDC84);
  static const warning = Color(0xFFF5B84A);
  static const error = Color(0xFFFF6B6B);
  static const info = Color(0xFF6AB0FF);
  static const present = Color(0xFF3DDC84);
  static const absent = Color(0xFFFF6B6B);
}

class ProductSpacing {
  const ProductSpacing._();

  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
}

class ProductRadius {
  const ProductRadius._();

  static const small = 8.0;
  static const medium = 12.0;
  static const large = 18.0;
  static const hero = 22.0;
}

ThemeData buildProductTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: ProductColors.brandPrimary,
    brightness: Brightness.dark,
    primary: ProductColors.brandPrimary,
    secondary: ProductColors.brandPrimaryStrong,
    surface: ProductColors.surface,
    onPrimary: ProductColors.onBrand,
    onSurface: ProductColors.textPrimary,
    error: ProductColors.error,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: ProductColors.background,
    visualDensity: VisualDensity.standard,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        height: 1.08,
        fontWeight: FontWeight.w800,
        color: ProductColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        height: 1.12,
        fontWeight: FontWeight.w800,
        color: ProductColors.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        height: 1.18,
        fontWeight: FontWeight.w800,
        color: ProductColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: ProductColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: ProductColors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.42,
        color: ProductColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.4,
        color: ProductColors.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: ProductColors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: ProductColors.textSecondary,
      ),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: ProductColors.background,
      foregroundColor: ProductColors.textPrimary,
      toolbarHeight: 68,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        color: ProductColors.textPrimary,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      height: 72,
      backgroundColor: ProductColors.surface,
      indicatorColor: ProductColors.brandPrimarySoft,
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
              ? ProductColors.brandPrimaryStrong
              : ProductColors.textSecondary,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ProductColors.brandPrimary,
        foregroundColor: ProductColors.onBrand,
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ProductRadius.medium),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ProductColors.brandPrimaryStrong,
        minimumSize: const Size(48, 52),
        side: const BorderSide(color: ProductColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ProductRadius.medium),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    cardTheme: CardThemeData(
      color: ProductColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ProductRadius.large),
        side: const BorderSide(color: ProductColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: ProductColors.divider,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ProductColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: ProductColors.textSecondary),
      hintStyle: const TextStyle(color: ProductColors.textMuted),
      prefixIconColor: ProductColors.textSecondary,
      suffixIconColor: ProductColors.textSecondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ProductRadius.medium),
        borderSide: const BorderSide(color: ProductColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ProductRadius.medium),
        borderSide: const BorderSide(color: ProductColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ProductRadius.medium),
        borderSide:
            const BorderSide(color: ProductColors.brandPrimary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ProductRadius.medium),
        borderSide: const BorderSide(color: ProductColors.error),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ProductColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ProductRadius.hero)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: ProductColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: ProductColors.surfaceElevated,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: ProductColors.brandPrimary),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ProductColors.surfaceElevated,
      contentTextStyle: const TextStyle(
        color: ProductColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ProductRadius.medium),
      ),
    ),
  );
}
