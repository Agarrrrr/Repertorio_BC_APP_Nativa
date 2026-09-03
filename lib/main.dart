import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:repertorio_bc/core/notifications/push_service.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'package:repertorio_bc/app/app.dart';
import 'package:repertorio_bc/app/router.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:repertorio_bc/core/storage/app_cache.dart';
import 'package:repertorio_bc/core/providers/theme_provider.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 1. Inicializar Supabase
  await SupabaseService.init();

  // 2. Inicializar la caché. Si el disco está lleno, continúa en RAM.
  await AppCache.init();
  await initUserSettings();

  // 3. Inicializar Notificaciones Push
  PushService.onTokenRefresh = (token) async {
    await registrarFcmTokenUsuarioActual(token: token);
  };

  // Registrar el callback antes de consultar getInitialMessage() y el estado
  // de lanzamiento de las notificaciones locales. Así ningún clic se pierde
  // durante un arranque en frío.
  PushService.onNotificationTap = (payload) {
    if (!payload.startsWith('visor_')) return;
    final id = payload.replaceFirst('visor_', '').trim();
    if (id.isEmpty) return;

    final context = rootNavigatorKey.currentContext;
    if (context == null) {
      PushService.pendingPayload = 'visor_$id';
      return;
    }
    context.go('/visor/$id');
  };
  await PushService.init();

  // 4. Diseño Edge-to-Edge (Barra de estado transparente)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(
    const ProviderScope(
      child: RepertorioApp(),
    ),
  );
}
