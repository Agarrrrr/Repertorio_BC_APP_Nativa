import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:repertorio_bc/app/router.dart';
import 'package:repertorio_bc/core/providers/theme_provider.dart';

class RepertorioApp extends ConsumerWidget {
  const RepertorioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeProvider);
    final accentColor = ref.watch(accentColorProvider);

    ThemeMode getMaterialThemeMode() {
      if (themeMode == AppThemeMode.claro || themeMode == AppThemeMode.sepia) {
        return ThemeMode.light;
      } else {
        return ThemeMode.dark;
      }
    }

    return MaterialApp.router(
      title: 'Repertorio BC',
      debugShowCheckedModeBanner: false,
      themeMode: getMaterialThemeMode(),
      theme: themeMode == AppThemeMode.sepia 
          ? AppTheme.getTheme(AppThemeMode.sepia, accentColor)
          : AppTheme.getTheme(AppThemeMode.claro, accentColor),
      darkTheme: (themeMode == AppThemeMode.sepia || themeMode == AppThemeMode.quiet)
          ? AppTheme.getTheme(AppThemeMode.quiet, accentColor)
          : AppTheme.getTheme(AppThemeMode.oscuro, accentColor),
      builder: (context, child) {
        final data = MediaQuery.of(context);
        return MediaQuery(
          data: data.copyWith(
            textScaler: data.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.35),
          ),
          child: child!,
        );
      },
      routerConfig: router,
    );
  }
}
