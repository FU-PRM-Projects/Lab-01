import 'package:flutter/material.dart';

/// Semantic colors and palette helpers.
class AppColors {
  // Static status colors
  static const Color danger = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  // Default seed color for Material 3 dynamic color generation
  static const Color seedColor = Color(0xFF2563EB);

  // Backward compatibility colors (mapped to dark palette)
  static const Color darkBg = Color(0xFF131316);
  static const Color sidebarBg = Color(0xFF1A1A1E);
  static const Color cardBg = Color(0xFF222227);
  static const Color composerBg = Color(0xFF26262C);
  static const Color border = Color(0xFF32323A);
  static const Color borderSubtle = Color(0xFF2A2A32);
  static const Color hover = Color(0xFF2E2E36);
  static const Color selected = Color(0xFF383844);

  static const Color textPrimary = Color(0xFFEDEDF2);
  static const Color textSecondary = Color(0xFFA1A1AC);
  static const Color textMuted = Color(0xFF71717E);

  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color accentBlueHover = Color(0xFF2563EB);
  static const Color citationChip = Color(0xFF1E293B);
  static const Color citationChipBorder = Color(0xFF334155);
  static const Color citationChipText = Color(0xFF60A5FA);
}

/// Material 3 Dark Theme
ThemeData buildDarkTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.seedColor,
    brightness: Brightness.dark,
  ).copyWith(
    surface: const Color(0xFF131316),
    surfaceDim: const Color(0xFF101013),
    surfaceBright: const Color(0xFF35353C),
    surfaceContainerLowest: const Color(0xFF0D0D10),
    surfaceContainerLow: const Color(0xFF1A1A1E),
    surfaceContainer: const Color(0xFF222227),
    surfaceContainerHigh: const Color(0xFF2A2A31),
    surfaceContainerHighest: const Color(0xFF33333C),
    outline: const Color(0xFF52525E),
    outlineVariant: const Color(0xFF33333C),
    primary: const Color(0xFF60A5FA),
    onPrimary: const Color(0xFF002F6C),
    primaryContainer: const Color(0xFF1E3A8A),
    onPrimaryContainer: const Color(0xFFDBEAFE),
    secondary: const Color(0xFF93C5FD),
    onSecondary: const Color(0xFF0C2D64),
    secondaryContainer: const Color(0xFF25334E),
    onSecondaryContainer: const Color(0xFFBFDBFE),
    error: const Color(0xFFF87171),
    onError: const Color(0xFF450A0A),
    errorContainer: const Color(0xFF7F1D1D),
    onErrorContainer: const Color(0xFFFECACA),
  );

  return _buildTheme(colorScheme);
}

/// Material 3 Light Theme
ThemeData buildLightTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.seedColor,
    brightness: Brightness.light,
  ).copyWith(
    surface: const Color(0xFFF8FAFC),
    surfaceDim: const Color(0xFFEDEFEF),
    surfaceBright: Colors.white,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFF1F5F9),
    surfaceContainer: const Color(0xFFE2E8F0),
    surfaceContainerHigh: const Color(0xFFCBD5E1),
    surfaceContainerHighest: const Color(0xFF94A3B8),
    outline: const Color(0xFF94A3B8),
    outlineVariant: const Color(0xFFE2E8F0),
    primary: const Color(0xFF2563EB),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFDBEAFE),
    onPrimaryContainer: const Color(0xFF1E3A8A),
    secondary: const Color(0xFF3B82F6),
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFEFF6FF),
    onSecondaryContainer: const Color(0xFF1D4ED8),
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
      iconTheme: IconThemeData(
        color: colorScheme.onSurfaceVariant,
        size: 18,
      ),
    ),

    // Card Theme
    cardTheme: CardThemeData(
      color: colorScheme.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant,
          width: 1,
        ),
      ),
    ),

    // Dialog Theme
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(
          color: colorScheme.outlineVariant,
          width: 1,
        ),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
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
      labelStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: 13,
      ),
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
