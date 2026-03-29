import 'package:flutter/material.dart';

/// MeshCore PT app theme — matches the official meshcore.pt website.
/// Palette: near-black background, orange primary accent, dark cards.
class AppTheme {
  // ---- Brand colours (from meshcore.pt) ----
  static const primary = Color(0xFFFF6B00); // orange accent
  static const primaryVariant = Color(0xFFFF8C38); // lighter orange
  static const background = Color(0xFF111111); // near-black page bg
  static const surface = Color(0xFF1C1C1C); // card / appbar surface
  static const surfaceVariant = Color(0xFF252525); // slightly lighter surface
  static const onPrimary = Colors.white;
  static const onBackground = Color(0xFFF0F0F0); // near-white text
  static const onSurface = Color(0xFFE0E0E0);
  static const divider = Color(0xFF2E2E2E);
  static const navBar = Color(0xFF141414); // bottom / side nav

  static ThemeData get dark {
    const cs = ColorScheme(
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: Color(0xFF3A1A00),
      onPrimaryContainer: primaryVariant,
      secondary: Color(0xFF14B8A6),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFF0D3330),
      onSecondaryContainer: Color(0xFF5EEAD4),
      tertiary: Color(0xFFFFB347),
      onTertiary: Colors.black,
      tertiaryContainer: Color(0xFF3D2800),
      onTertiaryContainer: Color(0xFFFFB347),
      error: Color(0xFFFF5252),
      onError: Colors.white,
      errorContainer: Color(0xFF4A0000),
      onErrorContainer: Color(0xFFFF8A80),
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surfaceVariant,
      onSurfaceVariant: Color(0xFFAAAAAA),
      outline: Color(0xFF444444),
      outlineVariant: divider,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFFE8E8E8),
      onInverseSurface: Color(0xFF1C1C1C),
      inversePrimary: Color(0xFFB84500),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: background,

      // AppBar: dark with orange icon/title
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: onBackground,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: primary),
      ),

      // Cards: dark with subtle border, no elevation glow
      cardTheme: const CardThemeData(
        color: surfaceVariant,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          side: BorderSide(color: divider, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // Bottom navigation bar: very dark bg, orange indicator
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navBar,
        indicatorColor: primary.withAlpha(40),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary);
          }
          return const IconThemeData(color: Color(0xFF888888));
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: primary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            );
          }
          return const TextStyle(color: Color(0xFF888888), fontSize: 12);
        }),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),

      // Dividers
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),

      // List tiles
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      // Text inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: Color(0xFF666666)),
      ),

      // FAB
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 2,
      ),

      // Elevated buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // Text buttons
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),

      // Chips
      chipTheme: const ChipThemeData(
        backgroundColor: surfaceVariant,
        selectedColor: Color(0xFF3A1A00),
        labelStyle: TextStyle(color: onSurface),
        secondaryLabelStyle: TextStyle(
          color: primaryVariant,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: onSurface),
        secondarySelectedColor: Color(0xFF3A1A00),
        checkmarkColor: primary,
        side: BorderSide(color: divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),

      // Bottom sheets
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),

      // Popup menus
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: divider),
        ),
      ),

      // Dialogs
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: divider),
        ),
      ),

      // Switches / checkboxes
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected)
                  ? primary
                  : const Color(0xFF666666),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected)
                  ? primary.withAlpha(80)
                  : const Color(0xFF333333),
        ),
      ),

      // Progress indicators
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: divider,
      ),

      // Snackbars
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceVariant,
        contentTextStyle: const TextStyle(color: onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData get light => dark; // Force dark only — matches website
}
