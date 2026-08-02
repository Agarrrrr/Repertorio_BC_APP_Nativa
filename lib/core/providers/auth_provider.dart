import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:flutter/foundation.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:repertorio_bc/core/notifications/push_service.dart';
import 'package:repertorio_bc/core/activity/activity_service.dart';
import 'package:repertorio_bc/models/perfil.dart';
import 'package:hive/hive.dart';
import 'dart:convert';

// 1. Estado para saber si esta cargando
class AuthLoadingNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void setState(bool value) => state = value;
}

final authLoadingProvider =
    NotifierProvider<AuthLoadingNotifier, bool>(AuthLoadingNotifier.new);

// Provider extra para manejar el estado de recuperación de contraseña
class IsRecoveringPasswordNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void setState(bool value) => state = value;
}

final isRecoveringPasswordProvider =
    NotifierProvider<IsRecoveringPasswordNotifier, bool>(
        IsRecoveringPasswordNotifier.new);

// 2. Provider para el usuario de Supabase Auth
final authUserProvider = StreamProvider<supabase.User?>((ref) {
  return SupabaseService.client.auth.onAuthStateChange.map((state) {
    if (state.event == supabase.AuthChangeEvent.passwordRecovery) {
      // Usamos microtask para no romper el build del provider
      Future.microtask(
          () => ref.read(isRecoveringPasswordProvider.notifier).setState(true));
    }
    return state.session?.user;
  });
});

// 3. Provider para el Perfil (base de datos)
final perfilProvider = FutureProvider<Perfil?>((ref) async {
  final user = ref.watch(authUserProvider).value;
  if (user == null) {
    Future.microtask(
        () => ref.read(authLoadingProvider.notifier).setState(false));
    return null;
  }

  // Registrar actividad y FCM Token inmediatamente al detectar sesión activa,
  // de forma independiente al éxito de la consulta del perfil en red.
  ActivityService.register();
  registrarFcmToken(user.id);

  try {
    final box = Hive.box('cache');
    // Buscar el perfil por id de usuario
    final data = await SupabaseService.client
        .from('perfiles')
        .select()
        .eq('id', user.id)
        .maybeSingle()
        .timeout(const Duration(milliseconds: 1500)); // Fast-fail offline

    Future.microtask(
        () => ref.read(authLoadingProvider.notifier).setState(false));

    if (data == null) return null;

    // Guardar perfil en cache offline
    box.put('perfil_json', jsonEncode(data));

    return Perfil.fromJson(data);
  } catch (e) {
    Future.microtask(
        () => ref.read(authLoadingProvider.notifier).setState(false));
    // Caemos de gracia a Hive si estamos offline
    final box = Hive.box('cache');
    final cachedProfile = box.get('perfil_json');
    if (cachedProfile != null) {
      return Perfil.fromJson(jsonDecode(cachedProfile));
    }
    return null;
  }
});

void registrarFcmToken(String userId) async {
  final token = await PushService.getToken();
  debugPrint('[FCM] Token obtenido: $token');
  if (token != null) {
    try {
      // Detectar la plataforma real para que el backend envíe con el servicio correcto.
      final plataforma = Platform.isIOS ? 'ios_fcm' : 'android_fcm';
      final result =
          await SupabaseService.client.from('suscripciones_push').upsert({
        'usuario_id': userId,
        'endpoint': token,
        'plataforma': plataforma,
        'suscripcion': {}
      }, onConflict: 'endpoint');
      await SupabaseService.client
          .from('perfiles')
          .update({'notificaciones_activas': true}).eq('id', userId);
      debugPrint('[FCM] Token guardado en Supabase ($plataforma): $result');
    } catch (e) {
      debugPrint('[FCM] ERROR guardando token: $e');
    }
  } else {
    try {
      await SupabaseService.client
          .from('suscripciones_push')
          .delete()
          .eq('usuario_id', userId);
      await SupabaseService.client
          .from('perfiles')
          .update({'notificaciones_activas': false}).eq('id', userId);
    } catch (error) {
      debugPrint('[FCM] Error limpiando el estado inactivo: $error');
    }
    debugPrint('[FCM] Token nulo, no se guardó nada');
  }
}

// Controller para login/logout
class AuthController {
  static Future<void> login(String email, String password) async {
    await SupabaseService.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> loginWithGoogle() async {
    await SupabaseService.client.auth.signInWithOAuth(
      supabase.OAuthProvider.google,
      redirectTo: 'repertorioestatal://login-callback/',
    );
  }

  static Future<void> logout() async {
    await SupabaseService.client.auth.signOut();
  }

  /// Elimina permanentemente al usuario autenticado y todos los datos que
  /// dependan de auth.users mediante las reglas ON DELETE de la base de datos.
  ///
  /// La función RPC es SECURITY DEFINER y solo puede borrar auth.uid(), por lo
  /// que el cliente nunca recibe credenciales administrativas.
  static Future<void> deleteAccount() async {
    if (SupabaseService.client.auth.currentUser == null) {
      throw const supabase.AuthException(
        'La sesión expiró. Inicia sesión de nuevo para eliminar tu cuenta.',
      );
    }

    await SupabaseService.client.rpc('eliminar_mi_cuenta');

    // El usuario ya no existe en el servidor. Limpiamos la sesión persistida y
    // los datos personales almacenados en el dispositivo.
    try {
      await SupabaseService.client.auth.signOut(
        scope: supabase.SignOutScope.local,
      );
    } catch (_) {
      // La revocación remota puede responder "usuario inexistente"; el borrado
      // ya se completó, así que la limpieza local debe continuar.
    }

    final cache = Hive.box('cache');
    await Future.wait([
      cache.delete('perfil_json'),
      cache.delete('avisos_json'),
      cache.delete('eventos_permanentes'),
    ]);

    if (Hive.isBoxOpen('favoritos_box')) {
      await Hive.box('favoritos_box').clear();
    }
  }
}
