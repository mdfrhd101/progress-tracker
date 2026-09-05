import 'package:flutter/material.dart';

/// A restrained, mobile-first Material 3 dark theme.
///
/// Palette is deliberately small: one brand accent (focus mint) plus two
/// semantic colours (amber = break, red = end/stop). Everything else is
/// derived greyscale from the M3 scheme. The timer uses the platform
/// monospace family ('monospace' on Android) — no bundled/network font needed.
class AppColors {
  AppColors._();

  static const Color focus = Color(0xFF3DDC97); // start / active / resume
  static const Color breakAmber = Color(0xFFFFB020); // take break / on break
  static const Color stopRed = Color(0xFFFF5A5F); // end session / delete

  static const Color background = Color(0xFF121417);
  static const Color surface = Color(0xFF1B1E24);
  static const Color surfaceHigh = Color(0xFF242832);
}

class AppTheme {
  AppTheme._();

  static const String monoFont = 'monospace';

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.focus,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.focus,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide.none,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
