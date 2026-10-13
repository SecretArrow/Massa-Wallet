/// Pine Wallet visual identity — Material 3, light & dark.
///
/// Brand: crimson-red pine accent. Both themes build a full
/// M3 `ColorScheme.fromSeed` with modern component themes and force
/// transparent system bars (edge-to-edge) with per-theme icon brightness.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Brand colors.
abstract final class PineColors {
  /// Primary brand red (dark-theme primary).
  static const Color brand = Color(0xFFE5344A);

  /// Deep brand red (light-theme primary, gradients).
  static const Color deepBrand = Color(0xFFB3122B);

  /// Highlight red (gradient start).
  static const Color brandLight = Color(0xFFFF5C6E);

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
  static const Color error = Color(0xFFF85149);

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
          seedColor: PineColors.brand,
          brightness: Brightness.dark,
        ).copyWith(
          primary: PineColors.brand,
          secondary: PineColors.orange,
          surface: PineColors.surface,
          error: PineColors.error,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      splashFactory: InkSparkle.splashFactory,
      scaffoldBackgroundColor: PineColors.bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: PineColors.bg,
        foregroundColor: PineColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: overlayDark,
      ),
      cardTheme: const CardThemeData(
        color: PineColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PineColors.surface,
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
          borderSide: const BorderSide(color: PineColors.brand, width: 2),
        ),
        labelStyle: const TextStyle(color: PineColors.textSecondary),
        hintStyle: const TextStyle(color: PineColors.textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: PineColors.brand,
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
          foregroundColor: PineColors.brand,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: PineColors.brand),
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
            BorderSide(color: PineColors.brand.withValues(alpha: 0.5)),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: PineColors.surface,
        indicatorColor: PineColors.brand.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, color: PineColors.textSecondary),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF21262D),
        thickness: 1,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: PineColors.textSecondary,
        textColor: PineColors.textPrimary,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: PineColors.card,
        contentTextStyle: TextStyle(color: PineColors.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: PineColors.surface,
        modalBackgroundColor: PineColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: PineColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: PineColors.card,
        side: BorderSide(color: Color(0xFF30363D)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: PineColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: PineColors.brand,
        linearTrackColor: Color(0xFF21262D),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? PineColors.brand
              : PineColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? PineColors.brand.withValues(alpha: 0.35)
              : const Color(0xFF30363D),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: PineColors.brand,
        thumbColor: PineColors.brand,
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: PineColors.textPrimary,
        displayColor: PineColors.textPrimary,
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
          seedColor: PineColors.deepBrand,
          brightness: Brightness.light,
        ).copyWith(
          primary: PineColors.deepBrand,
          secondary: PineColors.orange,
          surface: surface,
          error: const Color(0xFFC93C37),
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
          borderSide: const BorderSide(
            color: PineColors.deepBrand,
            width: 2,
          ),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: PineColors.deepBrand,
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
          foregroundColor: PineColors.deepBrand,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: PineColors.deepBrand),
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
            BorderSide(color: PineColors.deepBrand.withValues(alpha: 0.5)),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: PineColors.deepBrand.withValues(alpha: 0.12),
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
        color: PineColors.deepBrand,
        linearTrackColor: Color(0xFFD0D7DE),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? PineColors.deepBrand
              : textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? PineColors.deepBrand.withValues(alpha: 0.35)
              : border,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: PineColors.deepBrand,
        thumbColor: PineColors.deepBrand,
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
