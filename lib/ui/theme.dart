import 'package:flutter/material.dart';

/// MeshCore PT app theme — matches the official meshcore.pt website.
///
/// The brand palette is fixed (near-black background, orange accent) but the
/// user can override:
///   * the seed/accent colour via [build] `accent` parameter
///   * the brightness via [build] `brightness` parameter
///
/// The static [AppTheme.primary] colour is the immutable brand orange and is
/// referenced directly by a few brand splashes (logo background, repeater
/// badge, etc.). User customisation only affects the Material `colorScheme`.
class AppTheme {
  // ---- Brand colours (from meshcore.pt) ----
  static const primary = Color(0xFFFF6B00); // orange accent (brand)
  static const primaryVariant = Color(0xFFFF8C38); // lighter orange

  // Dark surfaces
  static const _darkBackground = Color(0xFF111111);
  static const _darkSurface = Color(0xFF1C1C1C);
  static const _darkSurfaceVariant = Color(0xFF252525);
  static const _darkOnSurface = Color(0xFFE0E0E0);
  static const _darkOnBackground = Color(0xFFF0F0F0);
  static const _darkDivider = Color(0xFF2E2E2E);
  static const _darkNavBar = Color(0xFF141414);

  // Backwards-compatible aliases (used by a few hard-coded widgets).
  static const background = _darkBackground;
  static const surface = _darkSurface;
  static const surfaceVariant = _darkSurfaceVariant;
  static const onPrimary = Colors.white;
  static const onBackground = _darkOnBackground;
  static const onSurface = _darkOnSurface;
  static const divider = _darkDivider;
  static const navBar = _darkNavBar;

  /// Default dark theme (brand orange accent).
  static ThemeData get dark => build(brightness: Brightness.dark);

  /// Default light theme (brand orange accent).
  static ThemeData get light => build(brightness: Brightness.light);

  /// Build a [ThemeData] with the given [brightness] and optional [accent]
  /// colour. When [accent] is null, the brand orange is used.
  static ThemeData build({
    required Brightness brightness,
    Color? accent,
  }) {
    final acc = accent ?? primary;
    return brightness == Brightness.dark
        ? _buildDark(acc)
        : _buildLight(acc);
  }

  // ---------------------------------------------------------------------
  // Dark theme
  // ---------------------------------------------------------------------
  static ThemeData _buildDark(Color acc) {
    final cs = ColorScheme(
      brightness: Brightness.dark,
      primary: acc,
      onPrimary: Colors.white,
      primaryContainer: Color.alphaBlend(acc.withAlpha(40), _darkSurface),
      onPrimaryContainer: acc,
      secondary: const Color(0xFF14B8A6),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFF0D3330),
      onSecondaryContainer: const Color(0xFF5EEAD4),
      tertiary: const Color(0xFFFFB347),
      onTertiary: Colors.black,
      tertiaryContainer: const Color(0xFF3D2800),
      onTertiaryContainer: const Color(0xFFFFB347),
      error: const Color(0xFFFF5252),
      onError: Colors.white,
      errorContainer: const Color(0xFF4A0000),
      onErrorContainer: const Color(0xFFFF8A80),
      surface: _darkSurface,
      onSurface: _darkOnSurface,
      surfaceContainerHighest: _darkSurfaceVariant,
      onSurfaceVariant: const Color(0xFFAAAAAA),
      outline: const Color(0xFF444444),
      outlineVariant: _darkDivider,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: const Color(0xFFE8E8E8),
      onInverseSurface: const Color(0xFF1C1C1C),
      inversePrimary: Color.alphaBlend(acc.withAlpha(140), Colors.black),
    );
    return _commonTheme(cs, _darkBackground, _darkNavBar, _darkDivider, acc);
  }

  // ---------------------------------------------------------------------
  // Light theme — bright surfaces, accent drives primary.
  // ---------------------------------------------------------------------
  static ThemeData _buildLight(Color acc) {
    const lightBackground = Color(0xFFFAFAFA);
    const lightSurface = Color(0xFFFFFFFF);
    const lightSurfaceVariant = Color(0xFFF1F1F1);
    const lightOnSurface = Color(0xFF1C1C1C);
    const lightDivider = Color(0xFFE0E0E0);
    const lightNavBar = Color(0xFFFFFFFF);

    final cs = ColorScheme(
      brightness: Brightness.light,
      primary: acc,
      onPrimary: Colors.white,
      primaryContainer: Color.alphaBlend(acc.withAlpha(40), Colors.white),
      onPrimaryContainer: Color.alphaBlend(acc.withAlpha(220), Colors.black),
      secondary: const Color(0xFF0F766E),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFCCFBF1),
      onSecondaryContainer: const Color(0xFF042F2E),
      tertiary: const Color(0xFFB45309),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFFEF3C7),
      onTertiaryContainer: const Color(0xFF451A03),
      error: const Color(0xFFD32F2F),
      onError: Colors.white,
      errorContainer: const Color(0xFFFFEBEE),
      onErrorContainer: const Color(0xFF7F1D1D),
      surface: lightSurface,
      onSurface: lightOnSurface,
      surfaceContainerHighest: lightSurfaceVariant,
      onSurfaceVariant: const Color(0xFF555555),
      outline: const Color(0xFFBDBDBD),
      outlineVariant: lightDivider,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: const Color(0xFF1C1C1C),
      onInverseSurface: const Color(0xFFE8E8E8),
      inversePrimary: Color.alphaBlend(acc.withAlpha(140), Colors.white),
    );
    return _commonTheme(cs, lightBackground, lightNavBar, lightDivider, acc);
  }

  // ---------------------------------------------------------------------
  // Shared component themes — derived from the colour scheme so a single
  // body works for both brightnesses.
  // ---------------------------------------------------------------------
  static ThemeData _commonTheme(
    ColorScheme cs,
    Color scaffoldBg,
    Color navBg,
    Color dividerColor,
    Color acc,
  ) {
    final isDark = cs.brightness == Brightness.dark;
    final mutedIcon = isDark ? const Color(0xFF888888) : const Color(0xFF777777);
    final hintColor = isDark ? const Color(0xFF666666) : const Color(0xFF999999);
    final switchOff = isDark ? const Color(0xFF666666) : const Color(0xFFBDBDBD);
    final switchTrackOff =
        isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0);

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: scaffoldBg,

      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: cs.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: acc),
      ),

      cardTheme: CardThemeData(
        color: cs.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          side: BorderSide(color: dividerColor, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navBg,
        indicatorColor: acc.withAlpha(40),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: acc);
          }
          return IconThemeData(color: mutedIcon);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: acc,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            );
          }
          return TextStyle(color: mutedIcon, fontSize: 12);
        }),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),

      dividerTheme: DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: acc, width: 1.5),
        ),
        hintStyle: TextStyle(color: hintColor),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: acc,
        foregroundColor: Colors.white,
        elevation: 2,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: acc,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: acc),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: cs.surfaceContainerHighest,
        selectedColor: cs.primaryContainer,
        labelStyle: TextStyle(color: cs.onSurface),
        secondaryLabelStyle: TextStyle(
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: cs.onSurface),
        secondarySelectedColor: cs.primaryContainer,
        checkmarkColor: acc,
        side: BorderSide(color: dividerColor),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: dividerColor),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: dividerColor),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? acc : switchOff,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? acc.withAlpha(80)
              : switchTrackOff,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: acc,
        linearTrackColor: dividerColor,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: cs.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: cs.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
