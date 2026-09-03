import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:repertorio_bc/core/storage/app_cache.dart';

const userSettingsBoxName = 'settings';

Future<void> initUserSettings() async {
  try {
    if (!Hive.isBoxOpen(userSettingsBoxName)) {
      await Hive.openBox<dynamic>(userSettingsBoxName);
    }
    await migrateLegacyUserSettings();
  } catch (error) {
    debugPrint('[Settings] Se usará respaldo en memoria: $error');
  }
}

Future<void> migrateLegacyUserSettings() async {
  if (!Hive.isBoxOpen(userSettingsBoxName)) return;
  final settings = Hive.box(userSettingsBoxName);
  const preferenceKeys = [
    'theme_mode',
    OledDarkModeNotifier.storageKey,
    AccentColorNotifier.storageKey,
    'pdf_carousel_mode',
  ];

  for (final key in preferenceKeys) {
    final legacyValue = AppCache.get<dynamic>(key);
    if (!settings.containsKey(key) && legacyValue != null) {
      await settings.put(key, legacyValue);
    }
  }
}

T _readSetting<T>(String key, T defaultValue) {
  if (Hive.isBoxOpen(userSettingsBoxName)) {
    final savedSetting = Hive.box(userSettingsBoxName).get(key);
    if (savedSetting is T) return savedSetting;
  }

  // Migra instalaciones anteriores, donde las preferencias vivían en `cache`.
  final legacySetting = AppCache.get<dynamic>(key);
  if (legacySetting is T) {
    _writeSetting(key, legacySetting as Object);
    return legacySetting;
  }

  return defaultValue;
}

void _writeSetting(String key, Object value) {
  if (Hive.isBoxOpen(userSettingsBoxName)) {
    Hive.box(userSettingsBoxName).put(key, value);
  } else {
    AppCache.put(key, value);
  }
}

// `oscuroNormal` se agrega al final para no cambiar los índices ya guardados
// de claro, OLED (`oscuro`), sepia y quiet.
enum AppThemeMode { claro, oscuro, sepia, quiet, oscuroNormal }

// --- THEME MODE PROVIDER ---
class ThemeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() {
    final savedMode = _readSetting('theme_mode', AppThemeMode.claro.index);
    return AppThemeMode.values.firstWhere((e) => e.index == savedMode,
        orElse: () => AppThemeMode.claro);
  }

  void set(AppThemeMode mode) {
    state = mode;
    _writeSetting('theme_mode', mode.index);
  }

  void toggleDayNight() {
    if (state == AppThemeMode.claro) {
      set(_preferredDarkMode());
    } else if (state == AppThemeMode.oscuro ||
        state == AppThemeMode.oscuroNormal) {
      set(AppThemeMode.claro);
    } else if (state == AppThemeMode.sepia) {
      set(AppThemeMode.quiet);
    } else if (state == AppThemeMode.quiet) {
      set(AppThemeMode.sepia);
    }
  }

  void setProfileNormal() {
    if (state == AppThemeMode.sepia || state == AppThemeMode.quiet) {
      set(state == AppThemeMode.quiet
          ? _preferredDarkMode()
          : AppThemeMode.claro);
    } else {
      set(AppThemeMode.claro); // Si ya estaba, por defecto
    }
  }

  void setProfileLectura() {
    if (state == AppThemeMode.claro ||
        state == AppThemeMode.oscuro ||
        state == AppThemeMode.oscuroNormal) {
      set(state != AppThemeMode.claro
          ? AppThemeMode.quiet
          : AppThemeMode.sepia);
    } else {
      set(AppThemeMode.sepia); // Si ya estaba, por defecto
    }
  }

  AppThemeMode _preferredDarkMode() {
    final useOled = _readSetting(OledDarkModeNotifier.storageKey, true);
    return useOled ? AppThemeMode.oscuro : AppThemeMode.oscuroNormal;
  }
}

final themeProvider =
    NotifierProvider<ThemeNotifier, AppThemeMode>(ThemeNotifier.new);

// --- DARK DISPLAY STYLE PROVIDER ---
class OledDarkModeNotifier extends Notifier<bool> {
  static const storageKey = 'dark_oled_enabled';

  @override
  bool build() {
    return _readSetting(storageKey, true);
  }

  void set(bool enabled) {
    state = enabled;
    _writeSetting(storageKey, enabled);

    final currentTheme = ref.read(themeProvider);
    if (currentTheme == AppThemeMode.oscuro ||
        currentTheme == AppThemeMode.oscuroNormal) {
      ref.read(themeProvider.notifier).set(
            enabled ? AppThemeMode.oscuro : AppThemeMode.oscuroNormal,
          );
    }
  }
}

final oledDarkModeProvider =
    NotifierProvider<OledDarkModeNotifier, bool>(OledDarkModeNotifier.new);

// --- ACCENT COLOR PROVIDER ---
class AccentColorNotifier extends Notifier<Color> {
  static const storageKey = 'accent_color';
  static const defaultAccent = Color(0xFFF6D96B); // Dorado del tema oscuro

  @override
  Color build() {
    final savedVal = _readSetting(storageKey, defaultAccent.toARGB32());
    return Color(savedVal);
  }

  void set(Color color) {
    state = color;
    _writeSetting(storageKey, color.toARGB32());
  }
}

final accentColorProvider =
    NotifierProvider<AccentColorNotifier, Color>(AccentColorNotifier.new);

// --- PDF NAV MODE PROVIDER ---
// true = Carousel (Horizontal), false = Scroll (Vertical)
class PdfNavModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    return _readSetting('pdf_carousel_mode', false);
  }

  void set(bool isCarousel) {
    state = isCarousel;
    _writeSetting('pdf_carousel_mode', isCarousel);
  }
}

final pdfNavModeProvider =
    NotifierProvider<PdfNavModeNotifier, bool>(PdfNavModeNotifier.new);

class AppTheme {
  static Color adaptAccent(AppThemeMode mode, Color baseColor) {
    // El dorado base ya fue diseñado específicamente para oscuro normal.
    if (mode == AppThemeMode.oscuroNormal &&
        baseColor == AccentColorNotifier.defaultAccent) {
      return baseColor;
    }

    final hsv = HSVColor.fromColor(baseColor);
    late final double saturation;
    late final double value;

    switch (mode) {
      case AppThemeMode.claro:
        saturation = (hsv.saturation * 1.05).clamp(0.0, 0.82);
        value = hsv.value.clamp(0.50, 0.72);
        break;
      case AppThemeMode.oscuro:
        saturation = (hsv.saturation * 0.95).clamp(0.0, 0.86);
        value = hsv.value.clamp(0.78, 1.0);
        break;
      case AppThemeMode.oscuroNormal:
        saturation = (hsv.saturation * 0.82).clamp(0.0, 0.72);
        value = hsv.value.clamp(0.78, 0.94);
        break;
      case AppThemeMode.sepia:
        saturation = (hsv.saturation * 0.65).clamp(0.0, 0.55);
        value = hsv.value.clamp(0.48, 0.68);
        break;
      case AppThemeMode.quiet:
        saturation = (hsv.saturation * 0.70).clamp(0.0, 0.62);
        value = hsv.value.clamp(0.76, 0.90);
        break;
    }

    return hsv.withSaturation(saturation).withValue(value).toColor();
  }

  static Color _onAccent(Color accent) =>
      ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
          ? Colors.white
          : const Color(0xFF11161C);

  static ThemeData getTheme(AppThemeMode mode, Color accentColor) {
    final effectiveAccent = adaptAccent(mode, accentColor);

    switch (mode) {
      case AppThemeMode.claro:
        return ThemeData(
          colorScheme: ColorScheme.light(
            primary: effectiveAccent,
            onPrimary: _onAccent(effectiveAccent),
            secondary: effectiveAccent,
            surface: Colors.white,
          ),
          scaffoldBackgroundColor: const Color(0xFFF8F9FA),
          fontFamily: 'Inter',
          appBarTheme: AppBarTheme(
            backgroundColor: const Color(0xFFF8F9FA),
            foregroundColor: effectiveAccent,
            elevation: 0,
          ),
        );
      case AppThemeMode.oscuro:
        return ThemeData(
          colorScheme: ColorScheme.dark(
            primary: effectiveAccent,
            onPrimary: _onAccent(effectiveAccent),
            secondary: effectiveAccent,
            surface: const Color(0xFF1E1E1E),
          ),
          scaffoldBackgroundColor: Colors.black,
          fontFamily: 'Inter',
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.black,
            foregroundColor: effectiveAccent,
            elevation: 0,
          ),
        );
      case AppThemeMode.oscuroNormal:
        const appBackground = Color(0xFF11161C);
        const foreground = Color(0xFFF1F5F9);
        const surface = Color(0xFF1B2430);
        const secondarySurface = Color(0xFF16202A);
        const border = Color(0xFF314052);
        const softAccent = Color(0xFF2F3A4A);
        const softText = Color(0xFFC3CFDB);
        const inputBackground = Color(0xFF222D3A);
        const inputBorder = Color(0xFF3B4A5D);
        final strongAccent =
            effectiveAccent == AccentColorNotifier.defaultAccent
                ? const Color(0xFFFFE48F)
                : Color.lerp(effectiveAccent, Colors.white, 0.24)!;

        final scheme = ColorScheme.fromSeed(
          seedColor: effectiveAccent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: effectiveAccent,
          onPrimary: _onAccent(effectiveAccent),
          secondary: strongAccent,
          onSecondary: appBackground,
          surface: surface,
          onSurface: foreground,
          surfaceContainer: inputBackground,
          surfaceContainerHighest: secondarySurface,
          onSurfaceVariant: softText,
          outline: border,
          outlineVariant: inputBorder,
          shadow: effectiveAccent.withValues(alpha: 0.30),
        );

        return ThemeData(
          brightness: Brightness.dark,
          colorScheme: scheme,
          scaffoldBackgroundColor: appBackground,
          cardColor: surface,
          dividerColor: border,
          canvasColor: secondarySurface,
          shadowColor: effectiveAccent.withValues(alpha: 0.30),
          fontFamily: 'Inter',
          appBarTheme: AppBarTheme(
            backgroundColor: const Color(0xF21B2430),
            foregroundColor: effectiveAccent,
            elevation: 0,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: surface),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: inputBackground,
            hintStyle: const TextStyle(color: softText),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: inputBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: effectiveAccent,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? effectiveAccent
                  : softText,
            ),
            trackColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? softAccent
                  : secondarySurface,
            ),
          ),
        );
      case AppThemeMode.sepia:
        return ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: effectiveAccent,
            brightness: Brightness.light,
            primary: effectiveAccent,
            onPrimary: _onAccent(effectiveAccent),
            secondary: effectiveAccent,
            surface: const Color(0xFFFDF5E6),
            onSurface: const Color(0xFF5B4636),
            surfaceContainerHighest: const Color(0xFFEFE6CF),
            outline: const Color(0xFFDCD0B9),
          ),
          scaffoldBackgroundColor: const Color(0xFFF4ECD8),
          fontFamily: 'Inter',
          appBarTheme: AppBarTheme(
            backgroundColor: const Color(0xFFFDF5E6),
            foregroundColor: effectiveAccent,
            elevation: 0,
          ),
        );
      case AppThemeMode.quiet:
        return ThemeData(
          colorScheme: ColorScheme.dark(
            primary: effectiveAccent,
            onPrimary: _onAccent(effectiveAccent),
            secondary: effectiveAccent,
            surface: const Color(0xFF4A4D51),
            onSurface: const Color(0xFFFFFFFF),
            surfaceContainerHighest: const Color(0xFF3C3F42),
            outline: const Color(0xFF515457),
          ),
          scaffoldBackgroundColor: const Color(0xFF3C3F42),
          fontFamily: 'Inter',
          appBarTheme: AppBarTheme(
            backgroundColor: const Color(0xFF3C3F42),
            foregroundColor: effectiveAccent,
            elevation: 0,
          ),
        );
    }
  }
}
