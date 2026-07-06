import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum AppThemeMode { claro, oscuro, sepia, quiet }

// --- THEME MODE PROVIDER ---
class ThemeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() {
    final box = Hive.box('cache');
    final savedMode = box.get('theme_mode', defaultValue: AppThemeMode.claro.index);
    return AppThemeMode.values.firstWhere((e) => e.index == savedMode, orElse: () => AppThemeMode.claro);
  }

  void set(AppThemeMode mode) {
    state = mode;
    Hive.box('cache').put('theme_mode', mode.index);
  }

  void toggleDayNight() {
    if (state == AppThemeMode.claro) {
      set(AppThemeMode.oscuro);
    } else if (state == AppThemeMode.oscuro) {
      set(AppThemeMode.claro);
    } else if (state == AppThemeMode.sepia) {
      set(AppThemeMode.quiet);
    } else if (state == AppThemeMode.quiet) {
      set(AppThemeMode.sepia);
    }
  }

  void setProfileNormal() {
    if (state == AppThemeMode.sepia || state == AppThemeMode.quiet) {
      set(state == AppThemeMode.quiet ? AppThemeMode.oscuro : AppThemeMode.claro);
    } else {
      set(AppThemeMode.claro); // Si ya estaba, por defecto
    }
  }

  void setProfileLectura() {
    if (state == AppThemeMode.claro || state == AppThemeMode.oscuro) {
      set(state == AppThemeMode.oscuro ? AppThemeMode.quiet : AppThemeMode.sepia);
    } else {
      set(AppThemeMode.sepia); // Si ya estaba, por defecto
    }
  }
}
final themeProvider = NotifierProvider<ThemeNotifier, AppThemeMode>(ThemeNotifier.new);

// --- ACCENT COLOR PROVIDER ---
class AccentColorNotifier extends Notifier<Color> {
  static const defaultAccent = Color(0xFFD4AF37); // Dorado
  
  @override
  Color build() {
    final box = Hive.box('cache');
    final savedVal = box.get('accent_color', defaultValue: defaultAccent.toARGB32());
    return Color(savedVal);
  }

  void set(Color color) {
    state = color;
    Hive.box('cache').put('accent_color', color.toARGB32());
  }
}
final accentColorProvider = NotifierProvider<AccentColorNotifier, Color>(AccentColorNotifier.new);

// --- PDF NAV MODE PROVIDER ---
// true = Carousel (Horizontal), false = Scroll (Vertical)
class PdfNavModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    final box = Hive.box('cache');
    return box.get('pdf_carousel_mode', defaultValue: false);
  }

  void set(bool isCarousel) {
    state = isCarousel;
    Hive.box('cache').put('pdf_carousel_mode', isCarousel);
  }
}
final pdfNavModeProvider = NotifierProvider<PdfNavModeNotifier, bool>(PdfNavModeNotifier.new);


class AppTheme {
  static ThemeData getTheme(AppThemeMode mode, Color accentColor) {
    switch (mode) {
      case AppThemeMode.claro:
        return ThemeData(
          colorScheme: ColorScheme.light(
            primary: accentColor,
            secondary: accentColor,
            surface: Colors.white,
          ),
          scaffoldBackgroundColor: const Color(0xFFF8F9FA),
          fontFamily: 'Inter',
          appBarTheme: AppBarTheme(
            backgroundColor: const Color(0xFFF8F9FA),
            foregroundColor: accentColor,
            elevation: 0,
          ),
        );
      case AppThemeMode.oscuro:
        return ThemeData(
          colorScheme: ColorScheme.dark(
            primary: accentColor,
            secondary: accentColor,
            surface: const Color(0xFF1E1E1E),
          ),
          scaffoldBackgroundColor: Colors.black,
          fontFamily: 'Inter',
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.black,
            foregroundColor: accentColor,
            elevation: 0,
          ),
        );
      case AppThemeMode.sepia:
        return ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8B5A2B),
            brightness: Brightness.light,
            primary: const Color(0xFF8B5A2B),
            secondary: const Color(0xFF5E3A1D),
            surface: const Color(0xFFFDF5E6),
            onSurface: const Color(0xFF5B4636),
            surfaceContainerHighest: const Color(0xFFEFE6CF),
            outline: const Color(0xFFDCD0B9),
          ),
          scaffoldBackgroundColor: const Color(0xFFF4ECD8),
          fontFamily: 'Inter',
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFFDF5E6),
            foregroundColor: Color(0xFF8B5A2B),
            elevation: 0,
          ),
        );
      case AppThemeMode.quiet:
        return ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE5E5E7),
            brightness: Brightness.dark,
            primary: const Color(0xFFE5E5E7),
            secondary: const Color(0xFFFFFFFF),
            surface: const Color(0xFF4A4D51),
            onSurface: const Color(0xFFFFFFFF),
            surfaceContainerHighest: const Color(0xFF3C3F42),
            outline: const Color(0xFF515457),
          ),
          scaffoldBackgroundColor: const Color(0xFF3C3F42),
          fontFamily: 'Inter',
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF3C3F42),
            foregroundColor: Color(0xFFE5E5E7),
            elevation: 0,
          ),
        );
    }
  }
}
