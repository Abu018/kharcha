import 'package:flutter/material.dart';

/// Palette: near-black screens, lime call-to-action, pastel accents.
abstract final class AppColors {
  static const background = Color(0xFF0E0E11);
  static const surface = Color(0xFF1A1A1F);
  static const surfaceHigh = Color(0xFF24242B);
  static const outline = Color(0xFF34343D);
  static const card = Color(0xFFF4F3F7);
  static const ink = Color(0xFF111114);
  static const muted = Color(0xFF9A9AA6);

  static const lime = Color(0xFFD7F36B);
  static const lavender = Color(0xFFC9B8FF);
  static const pink = Color(0xFFF6B5DD);
  static const blue = Color(0xFF7C8CFF);
  static const peach = Color(0xFFFFC59A);
  static const mint = Color(0xFF9BE7C4);
  static const error = Color(0xFFFF7A7A);

  /// Accent per category, used for chips and the spending breakdown.
  static Color category(String category) => switch (category.toLowerCase()) {
    'food' => peach,
    'groceries' => lime,
    'transport' => blue,
    'shopping' => pink,
    'bills' => lavender,
    'entertainment' => mint,
    'health' => const Color(0xFFFF9EA8),
    'transfers' => const Color(0xFF8FD3FF),
    'income' => mint,
    'other' => const Color(0xFFE2E2E8),
    _ => const Color(0xFFD9D9E0),
  };
}

abstract final class AppTheme {
  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.lime,
      onPrimary: AppColors.ink,
      primaryContainer: AppColors.lime,
      onPrimaryContainer: AppColors.ink,
      secondary: AppColors.lavender,
      onSecondary: AppColors.ink,
      secondaryContainer: AppColors.surfaceHigh,
      onSecondaryContainer: Colors.white,
      tertiary: AppColors.pink,
      onTertiary: AppColors.ink,
      error: AppColors.error,
      onError: AppColors.ink,
      surface: AppColors.background,
      onSurface: Colors.white,
      onSurfaceVariant: AppColors.muted,
      surfaceContainerLowest: AppColors.background,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surfaceHigh,
      surfaceContainerHighest: AppColors.surfaceHigh,
      outline: AppColors.outline,
      outlineVariant: AppColors.outline,
      inverseSurface: AppColors.card,
      onInverseSurface: AppColors.ink,
    );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final text = base.textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.lime,
          foregroundColor: AppColors.ink,
          disabledBackgroundColor: AppColors.lime.withValues(alpha: 0.4),
          disabledForegroundColor: AppColors.ink.withValues(alpha: 0.6),
          minimumSize: const Size.fromHeight(56),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: Colors.white,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.lime,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: StadiumBorder(),
        extendedTextStyle: TextStyle(fontWeight: FontWeight.w700),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        labelStyle: const TextStyle(color: AppColors.muted),
        floatingLabelStyle: const TextStyle(color: AppColors.lime),
        prefixIconColor: AppColors.muted,
        suffixIconColor: AppColors.muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.lime, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.outline),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.lime
                : AppColors.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.ink
                : Colors.white,
          ),
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.surfaceHigh),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.lavender,
        contentTextStyle: const TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.lime,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.outline),
    );
  }
}
