import 'package:flutter/material.dart';

/// Semantic colors and palette helpers.
class AppColors {
  // Static status colors
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);

  // Default seed color for Material 3 dynamic color generation
  static const Color seedColor = Color(0xFF4B5563);
}

/// Material 3 Dark Theme
ThemeData buildDarkTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.seedColor,
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF171717),
        surfaceDim: const Color(0xFF121212),
        surfaceBright: const Color(0xFF353535),
        surfaceContainerLowest: const Color(0xFF101010),
        surfaceContainerLow: const Color(0xFF1F1F1F),
        surfaceContainer: const Color(0xFF242424),
        surfaceContainerHigh: const Color(0xFF2B2B2B),
        surfaceContainerHighest: const Color(0xFF353535),
        outline: const Color(0xFF5A5A5A),
        outlineVariant: const Color(0xFF393939),
        primary: const Color(0xFFF2F2F2),
        onPrimary: const Color(0xFF1A1A1A),
        primaryContainer: const Color(0xFF343434),
        onPrimaryContainer: const Color(0xFFF4F4F4),
        secondary: const Color(0xFFCACACA),
        onSecondary: const Color(0xFF262626),
        secondaryContainer: const Color(0xFF353535),
        onSecondaryContainer: const Color(0xFFF0F0F0),
        error: const Color(0xFFF87171),
        onError: const Color(0xFF450A0A),
        errorContainer: const Color(0xFF7F1D1D),
        onErrorContainer: const Color(0xFFFECACA),
      );

  return _buildTheme(colorScheme);
}

/// Material 3 Light Theme
ThemeData buildLightTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.seedColor,
        brightness: Brightness.light,
      ).copyWith(
        surface: const Color(0xFFFFFFFF),
        surfaceDim: const Color(0xFFEFEFEF),
        surfaceBright: const Color(0xFFFFFFFF),
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF5F5F5),
        surfaceContainer: const Color(0xFFF0F0F0),
        surfaceContainerHigh: const Color(0xFFEAEAEA),
        surfaceContainerHighest: const Color(0xFFE2E2E2),
        outline: const Color(0xFF9A9A9A),
        outlineVariant: const Color(0xFFE1E1E1),
        primary: const Color(0xFF202020),
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFE8E8E8),
        onPrimaryContainer: const Color(0xFF202020),
        secondary: const Color(0xFF5E5E5E),
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFE9E9E9),
        onSecondaryContainer: const Color(0xFF242424),
        error: const Color(0xFFDC2626),
        onError: Colors.white,
        errorContainer: const Color(0xFFFEE2E2),
        onErrorContainer: const Color(0xFF991B1B),
      );

  return _buildTheme(colorScheme);
}

ThemeData _buildTheme(ColorScheme colorScheme) {
  final isDark = colorScheme.brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    brightness: colorScheme.brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    fontFamily: 'Segoe UI',

    // App Bar Theme
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surfaceContainer,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Segoe UI',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant, size: 18),
    ),

    // Card Theme
    cardTheme: CardThemeData(
      color: colorScheme.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant, width: 1),
      ),
    ),

    // Dialog Theme
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: colorScheme.outlineVariant, width: 1),
      ),
      titleTextStyle: TextStyle(
        fontFamily: 'Segoe UI',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      contentTextStyle: TextStyle(
        fontFamily: 'Segoe UI',
        fontSize: 13.5,
        color: colorScheme.onSurfaceVariant,
        height: 1.5,
      ),
    ),

    // Button Themes
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        textStyle: const TextStyle(
          fontFamily: 'Segoe UI',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: const StadiumBorder(),
        elevation: 1,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        textStyle: const TextStyle(
          fontFamily: 'Segoe UI',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: BorderSide(color: colorScheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        textStyle: const TextStyle(
          fontFamily: 'Segoe UI',
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        textStyle: const TextStyle(
          fontFamily: 'Segoe UI',
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.onSurfaceVariant,
        hoverColor: colorScheme.onSurface.withValues(alpha: 0.08),
        highlightColor: colorScheme.onSurface.withValues(alpha: 0.12),
      ),
    ),

    // Chip Theme
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      disabledColor: colorScheme.surfaceContainer.withValues(alpha: 0.5),
      selectedColor: colorScheme.secondaryContainer,
      secondarySelectedColor: colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      labelStyle: TextStyle(
        fontFamily: 'Segoe UI',
        fontSize: 12,
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: 'Segoe UI',
        fontSize: 12,
        color: colorScheme.onSecondaryContainer,
      ),
      side: BorderSide(color: colorScheme.outlineVariant, width: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    // Segmented Button Theme
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(
            fontFamily: 'Segoe UI',
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ),

    // Input Decoration Theme
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark
          ? colorScheme.surfaceContainerLowest
          : colorScheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        fontSize: 13,
      ),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.error),
      ),
    ),

    // Divider Theme
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    // Tooltip Theme
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      textStyle: TextStyle(
        fontFamily: 'Segoe UI',
        color: colorScheme.onSurface,
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
      ),
      waitDuration: const Duration(milliseconds: 400),
    ),

    // Progress Indicator Theme
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearTrackColor: colorScheme.surfaceContainerHighest,
      circularTrackColor: colorScheme.surfaceContainerHighest,
      linearMinHeight: 3,
    ),
  );
}

/// Extension on BuildContext for quick, idiomatic M3 theme access.
extension ThemeContextExtension on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  TextTheme get textTheme => Theme.of(this).textTheme;
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}
