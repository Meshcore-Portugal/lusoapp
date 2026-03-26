import 'package:flutter/material.dart';

/// MeshCore PT app theme — dark theme with green accent (radio/mesh aesthetic).
class AppTheme {
  static const _seedColor = Color(0xFF2E7D32); // forest green
  static const _meshGreen = Color(0xFF4CAF50);
  static const _meshDark = Color(0xFF1B5E20);

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E1E1E),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _meshGreen,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: _meshGreen.withAlpha(50),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _meshDark.withAlpha(100),
      ),
    );
  }

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _meshGreen,
        foregroundColor: Colors.white,
      ),
    );
  }
}
