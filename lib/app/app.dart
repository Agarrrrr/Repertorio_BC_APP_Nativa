import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:repertorio_bc/app/router.dart';
import 'package:repertorio_bc/core/providers/theme_provider.dart';
import 'package:repertorio_bc/core/midi/midi_engine.dart';

class RepertorioApp extends ConsumerStatefulWidget {
  const RepertorioApp({super.key});

  @override
  ConsumerState<RepertorioApp> createState() => _RepertorioAppState();
}

class _RepertorioAppState extends ConsumerState<RepertorioApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      MidiEngine().restoreAudioRoute();
    }
  }

  @override
  Widget build(BuildContext context) {
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
      darkTheme: AppTheme.getTheme(
        themeMode == AppThemeMode.quiet
            ? AppThemeMode.quiet
            : themeMode == AppThemeMode.oscuroNormal
                ? AppThemeMode.oscuroNormal
                : AppThemeMode.oscuro,
        accentColor,
      ),
      builder: (context, child) {
        final data = MediaQuery.of(context);
        return MediaQuery(
          data: data.copyWith(
            textScaler: data.textScaler
                .clamp(minScaleFactor: 1.0, maxScaleFactor: 1.35),
          ),
          child: child!,
        );
      },
      routerConfig: router,
    );
  }
}
