import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:repertorio_bc/core/notifications/push_service.dart';
import 'package:repertorio_bc/app/app.dart';
import 'package:repertorio_bc/app/router.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  
  // 1. Inicializar Supabase
  await SupabaseService.init();
  
  // 2. Inicializar Hive (offline cache)
  await Hive.initFlutter();
  await Hive.openBox('cache');

  // 3. Inicializar Notificaciones Push
  await PushService.init();
  PushService.onNotificationTap = (payload) {
    if (payload.startsWith('visor_')) {
      final id = payload.replaceFirst('visor_', '');
      final context = rootNavigatorKey.currentContext;
      if (context != null) {
        // GoRouter push
        context.push('/visor/$id');
      }
    }
  };
  
  // 4. Diseño Edge-to-Edge (Barra de estado transparente)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  FlutterNativeSplash.remove();

  runApp(
    const ProviderScope(
      child: RepertorioApp(),
    ),
  );
}
