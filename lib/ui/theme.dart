/// Massa Wallet visual identity — Material 3, light & dark.
///
/// Brand: Massa-inspired teal/cyan accent. Both themes build a full
/// M3 `ColorScheme.fromSeed` with modern component themes and force
/// transparent system bars (edge-to-edge) with per-theme icon brightness.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  /// Overlay style for dark surfaces (light icons).
  static const overlayDark = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    systemNavigationBarColor: Color(0x00000000),
    systemNavigationBarDividerColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  /// Overlay style for light surfaces (dark icons).
  static const overlayLight = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    systemNavigationBarColor: Color(0x00000000),
    systemNavigationBarDividerColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

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
      splashFactory: InkSparkle.splashFactory,
      scaffoldBackgroundColor: MassaColors.bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: MassaColors.bg,
        foregroundColor: MassaColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: overlayDark,
      ),
      cardTheme: const CardThemeData(
        color: MassaColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
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
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: MassaColors.teal.withValues(alpha: 0.5)),
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
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: MassaColors.surface,
        modalBackgroundColor: MassaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: MassaColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: MassaColors.card,
        side: BorderSide(color: Color(0xFF30363D)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: MassaColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MassaColors.teal,
        linearTrackColor: Color(0xFF21262D),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? MassaColors.teal
              : MassaColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? MassaColors.teal.withValues(alpha: 0.35)
              : const Color(0xFF30363D),
        ),
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: MassaColors.textPrimary,
        displayColor: MassaColors.textPrimary,
      ),
    );
  }

  /// Builds the light Material 3 theme.
  static ThemeData get light {
    const bg = Color(0xFFF6F8FA);
    const surface = Color(0xFFFFFFFF);
    const card = Color(0xFFFFFFFF);
    const border = Color(0xFFD0D7DE);
    const textPrimary = Color(0xFF1F2328);
    const textSecondary = Color(0xFF656D76);

    final scheme =
        ColorScheme.fromSeed(
          seedColor: MassaColors.teal,
          brightness: Brightness.light,
        ).copyWith(
          primary: MassaColors.deepTeal,
          secondary: MassaColors.orange,
          surface: surface,
          error: MassaColors.red,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      splashFactory: InkSparkle.splashFactory,
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: overlayLight,
      ),
      cardTheme: const CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MassaColors.deepTeal, width: 2),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MassaColors.deepTeal,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MassaColors.deepTeal,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: MassaColors.deepTeal),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: MassaColors.deepTeal.withValues(alpha: 0.5)),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: MassaColors.deepTeal.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, color: textSecondary),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      listTileTheme: const ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF24292F),
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: Color(0xFFF0F3F6),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MassaColors.deepTeal,
        linearTrackColor: Color(0xFFD0D7DE),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? MassaColors.deepTeal
              : textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? MassaColors.deepTeal.withValues(alpha: 0.35)
              : border,
        ),
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
    );
  }
}
