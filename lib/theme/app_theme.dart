import 'package:flutter/material.dart';

/// A restrained, mobile-first Material 3 dark theme.
///
/// Palette is deliberately small: one user-selectable accent (see Settings)
/// plus two fixed semantic colours (amber = break, red = end/stop). Everything
/// else is derived greyscale. The timer uses the platform monospace family —
/// no bundled/network font needed.
class AppColors {
  AppColors._();

  /// Default accent (mint). The live accent is `context.accent`.
  static const Color defaultAccent = Color(0xFF3DDC97);

  static const Color breakAmber = Color(0xFFFFB020); // take break / on break
  static const Color stopRed = Color(0xFFFF5A5F); // end session / delete

  static const Color background = Color(0xFF121417);
  static const Color surface = Color(0xFF1B1E24);
  static const Color surfaceHigh = Color(0xFF242832);

  /// Accent choices offered in Settings (name -> colour).
  static const List<AccentOption> accents = [
    AccentOption('Mint', Color(0xFF3DDC97)),
    AccentOption('Sky', Color(0xFF4FC3F7)),
    AccentOption('Violet', Color(0xFFB388FF)),
    AccentOption('Coral', Color(0xFFFF8A65)),
    AccentOption('Rose', Color(0xFFF06292)),
    AccentOption('Lime', Color(0xFFC6FF00)),
  ];
}

class AccentOption {
  final String name;
  final Color color;
  const AccentOption(this.name, this.color);
}

/// Font choices — Android system families, so they work fully offline and
/// add nothing to the APK. `null` = platform default (Roboto).
class AppFonts {
  AppFonts._();

  static const List<FontOption> options = [
    FontOption('Default', null),
    FontOption('Serif', 'serif'),
    FontOption('Condensed', 'sans-serif-condensed'),
    FontOption('Monospace', 'monospace'),
  ];
}

class FontOption {
  final String name;
  final String? family;
  const FontOption(this.name, this.family);
}

/// Convenient access to the live accent colour from any widget.
extension AccentX on BuildContext {
  Color get accent => Theme.of(this).colorScheme.primary;
}

class AppTheme {
  AppTheme._();

  static const String monoFont = 'monospace';

  /// Builds the dark theme for the given user settings.
  static ThemeData build({
    Color accent = AppColors.defaultAccent,
    String? fontFamily,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accent,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: fontFamily,
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
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Kept for call sites that want the default look (e.g. before settings load).
  static ThemeData get dark => build();
}
