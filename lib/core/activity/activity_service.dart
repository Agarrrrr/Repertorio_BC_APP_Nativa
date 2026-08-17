import 'package:flutter/foundation.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';

class ActivityService {
  ActivityService._();

  static DateTime? _lastRegistration;

  static String get platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'web',
    };
  }

  static Future<void> register({bool force = false}) async {
    if (SupabaseService.client.auth.currentUser == null) return;
    final now = DateTime.now();
    if (!force &&
        _lastRegistration != null &&
        now.difference(_lastRegistration!) < const Duration(minutes: 5)) {
      return;
    }
    _lastRegistration = now;
    try {
      await SupabaseService.client.rpc(
        'registrar_actividad_app',
        params: {'p_plataforma': platform},
      );
    } catch (error) {
      // No debe bloquear el inicio si el dispositivo está sin conexión o si el
      // backend todavía no recibió la migración.
      debugPrint('[Actividad] No se pudo registrar: $error');
    }
  }
}
