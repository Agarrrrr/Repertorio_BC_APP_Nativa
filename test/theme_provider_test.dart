import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repertorio_bc/core/providers/theme_provider.dart';
import 'package:repertorio_bc/core/storage/app_cache.dart';

void main() {
  setUp(AppCache.useMemoryOnlyForTests);

  test('oscuroNormal conserva los índices históricos', () {
    expect(AppThemeMode.claro.index, 0);
    expect(AppThemeMode.oscuro.index, 1);
    expect(AppThemeMode.sepia.index, 2);
    expect(AppThemeMode.quiet.index, 3);
    expect(AppThemeMode.oscuroNormal.index, 4);
  });

  test('el oscuro normal usa la paleta solicitada', () {
    final theme = AppTheme.getTheme(
      AppThemeMode.oscuroNormal,
      AccentColorNotifier.defaultAccent,
    );
    expect(theme.scaffoldBackgroundColor, const Color(0xFF11161C));
    expect(theme.colorScheme.surface, const Color(0xFF1B2430));
    expect(theme.colorScheme.surfaceContainerHighest, const Color(0xFF16202A));
    expect(theme.colorScheme.outline, const Color(0xFF314052));
    expect(theme.colorScheme.onSurface, const Color(0xFFF1F5F9));
    expect(theme.colorScheme.primary, const Color(0xFFF6D96B));
    expect(theme.colorScheme.secondary, const Color(0xFFFFE48F));
  });

  test('adaptar el acento conserva el tono y no modifica el valor guardado',
      () {
    const base = Color(0xFF8B5A2B);
    final container = ProviderContainer(
      overrides: [accentColorProvider.overrideWith(() => _BrownAccent())],
    );
    addTearDown(container.dispose);

    final adapted = AppTheme.adaptAccent(
      AppThemeMode.oscuroNormal,
      container.read(accentColorProvider),
    );
    final baseHue = HSVColor.fromColor(base).hue;
    final adaptedHue = HSVColor.fromColor(adapted).hue;

    expect((baseHue - adaptedHue).abs(), lessThan(1));
    expect(container.read(accentColorProvider), base);
  });

  test('OLED sigue habilitado por defecto', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(oledDarkModeProvider), isTrue);
  });
}

class _BrownAccent extends AccentColorNotifier {
  @override
  Color build() => const Color(0xFF8B5A2B);
}
