import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Custom palette, exposed as a ThemeExtension so every screen can read
/// `Theme.of(context).extension<AppColors>()!` (or the `context.colors`
/// shortcut below) instead of hardcoding colors. This is what makes
/// Light/Dark actually swap everywhere instead of just the MaterialApp
/// chrome.
class AppColors extends ThemeExtension<AppColors> {
  final Color bg;
  final Color card;
  final Color cardAlt;
  final Color accent;
  final Color accentDim;
  final Color textPrimary;
  final Color textSecondary;

  const AppColors({
    required this.bg,
    required this.card,
    required this.cardAlt,
    required this.accent,
    required this.accentDim,
    required this.textPrimary,
    required this.textSecondary,
  });

  // Your existing dark palette, unchanged.
  static const dark = AppColors(
    bg: Color(0xFF141414),
    card: Color.fromARGB(255, 31, 31, 31),
    cardAlt: Color(0xFF262626),
    accent: Color.fromARGB(255, 77, 240, 255),
    accentDim: Color.fromARGB(255, 32, 40, 68),
    textPrimary: Colors.white,
    textSecondary: Color(0xFF9C9C9C),
  );

  // New light palette, same teal/cyan accent for brand continuity.
  static const light = AppColors(
    bg: Color(0xFFF5F7F8),
    card: Colors.white,
    cardAlt: Color(0xFFEDEFF1),
    accent: Color.fromARGB(255, 0, 172, 193),
    accentDim: Color(0xFFDFF6F9),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF6B6B6B),
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? card,
    Color? cardAlt,
    Color? accent,
    Color? accentDim,
    Color? textPrimary,
    Color? textSecondary,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      card: card ?? this.card,
      cardAlt: cardAlt ?? this.cardAlt,
      accent: accent ?? this.accent,
      accentDim: accentDim ?? this.accentDim,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardAlt: Color.lerp(cardAlt, other.cardAlt, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDim: Color.lerp(accentDim, other.accentDim, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
    );
  }
}

/// Shortcut so call sites read `context.colors.bg` instead of the longer
/// `Theme.of(context).extension<AppColors>()!.bg`.
extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

class AppTheme {
  static ThemeData _base(Brightness brightness, AppColors colors) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.bg,
      primaryColor: colors.accent,
      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light())
          .copyWith(
        primary: colors.accent,
        surface: colors.card,
        onSurface: colors.textPrimary,
        secondary: colors.accent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.bg,
        elevation: 0,
        foregroundColor: colors.textPrimary,
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: Typography.englishLike2021.apply(
        bodyColor: colors.textPrimary,
        displayColor: colors.textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: colors.card,
        hintStyle: TextStyle(color: colors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.bg,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textSecondary,
          side: BorderSide(color: colors.textSecondary),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.card,
        selectedItemColor: colors.accent,
        unselectedItemColor: colors.textSecondary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.accent : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? colors.accent.withValues(alpha: 0.4) : null,
        ),
      ),
      cardColor: colors.card,
      dividerColor: colors.cardAlt,
      extensions: [colors],
    );
  }

  static ThemeData get light => _base(Brightness.light, AppColors.light);
  static ThemeData get dark => _base(Brightness.dark, AppColors.dark);
}

/// Holds the current ThemeMode and persists the user's choice to disk
/// with shared_preferences so it survives an app restart.
class ThemeProvider extends ChangeNotifier {
  static const _prefsKey = 'theme_mode';

  ThemeMode _themeMode = ThemeMode.dark; // sensible default matching your current app
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  /// Call this once at startup (see main.dart) before runApp so the
  /// correct theme is used on first frame instead of flashing the default.
  Future<void> loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == 'light') {
      _themeMode = ThemeMode.light;
    } else if (saved == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setDarkMode(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, isDark ? 'dark' : 'light');
  }
}