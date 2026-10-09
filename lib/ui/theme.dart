/// Massa Wallet visual identity.
///
/// Dark premium theme with Massa-inspired teal/cyan accents.
library;

import 'package:flutter/material.dart';

/// Brand colors.
abstract final class MassaColors {
  /// Primary teal.
  static const Color teal = Color(0xFF18C8C8);

  /// Deep teal for gradients.
  static const Color deepTeal = Color(0xFF0B6E6E);

  /// Background dark.
  static const Color bg = Color(0xFF0D1117);

  /// Surface dark.
  static const Color surface = Color(0xFF161B22);

  /// Card dark.
  static const Color card = Color(0xFF1C2330);

  /// Accent orange (alerts).
  static const Color orange = Color(0xFFF0883E);

  /// Success green.
  static const Color green = Color(0xFF3FB950);

  /// Error red.
  static const Color red = Color(0xFFF85149);

  /// Text primary.
  static const Color textPrimary = Color(0xFFE6EDF3);

  /// Text secondary.
  static const Color textSecondary = Color(0xFF8B949E);
}

/// App theme.
class AppTheme {
  /// Builds the dark Material 3 theme.
  static ThemeData get dark {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: MassaColors.teal,
          brightness: Brightness.dark,
        ).copyWith(
          primary: MassaColors.teal,
          secondary: MassaColors.orange,
          surface: MassaColors.surface,
          error: MassaColors.red,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: MassaColors.bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: MassaColors.bg,
        foregroundColor: MassaColors.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: const CardThemeData(
        color: MassaColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MassaColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF30363D)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF30363D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MassaColors.teal, width: 2),
        ),
        labelStyle: const TextStyle(color: MassaColors.textSecondary),
        hintStyle: const TextStyle(color: MassaColors.textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MassaColors.teal,
          foregroundColor: const Color(0xFF062A2A),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MassaColors.teal,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: MassaColors.teal),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: MassaColors.surface,
        indicatorColor: MassaColors.teal.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, color: MassaColors.textSecondary),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF21262D),
        thickness: 1,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: MassaColors.textSecondary,
        textColor: MassaColors.textPrimary,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: MassaColors.card,
        contentTextStyle: TextStyle(color: MassaColors.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: MassaColors.textPrimary,
        displayColor: MassaColors.textPrimary,
      ),
    );
  }
}
