import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:flutter/foundation.dart';
import 'package:repertorio_bc/core/supabase/supabase_service.dart';
import 'package:repertorio_bc/core/notifications/push_service.dart';
import 'package:repertorio_bc/core/activity/activity_service.dart';
import 'package:repertorio_bc/core/storage/app_cache.dart';
import 'package:repertorio_bc/models/perfil.dart';
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
  final profileCacheKey = AppCache.userKey('perfil_json', user.id);

  try {
    // Buscar el perfil por id de usuario
    final data = await SupabaseService.client
        .from('perfiles')
        .select()
        .eq('id', user.id)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));

    Future.microtask(
        () => ref.read(authLoadingProvider.notifier).setState(false));

    if (data == null) return null;

    // Guardar perfil en cache offline
    await AppCache.put(profileCacheKey, jsonEncode(data));
    await AppCache.delete('perfil_json');

    return Perfil.fromJson(data);
  } catch (e) {
    Future.microtask(
        () => ref.read(authLoadingProvider.notifier).setState(false));
    var cachedProfile = AppCache.get<String>(profileCacheKey);
    final legacyProfile = AppCache.get<String>('perfil_json');
    if (cachedProfile == null && legacyProfile != null) {
      try {
        final legacyJson = jsonDecode(legacyProfile) as Map<String, dynamic>;
        if (legacyJson['id']?.toString() == user.id) {
          cachedProfile = legacyProfile;
          await AppCache.put(profileCacheKey, legacyProfile);
          await AppCache.delete('perfil_json');
        }
      } catch (_) {
        // Una entrada heredada corrupta no debe bloquear el inicio.
      }
    }
    if (cachedProfile != null) {
      return Perfil.fromJson(jsonDecode(cachedProfile));
    }
    return null;
  }
});

Future<bool> registrarFcmToken(String userId, {String? token}) async {
  final resolvedToken = token ?? await PushService.getToken();
  if (resolvedToken == null || resolvedToken.isEmpty) {
    // Un token puede tardar en estar disponible o fallar por falta de red.
    // Nunca se deben borrar suscripciones validas por un fallo temporal.
    debugPrint('[FCM] Token aun no disponible; se reintentara mas adelante.');
    return false;
  }

  try {
    final plataforma = Platform.isIOS ? 'ios_fcm' : 'android_fcm';
    await SupabaseService.client.from('suscripciones_push').upsert({
      'usuario_id': userId,
      'endpoint': resolvedToken,
      'plataforma': plataforma,
      'suscripcion': {}
    }, onConflict: 'endpoint');
    await SupabaseService.client
        .from('perfiles')
        .update({'notificaciones_activas': true}).eq('id', userId);
    debugPrint('[FCM] Dispositivo registrado correctamente ($plataforma).');
    return true;
  } catch (error) {
    debugPrint('[FCM] Error registrando el dispositivo: $error');
    return false;
  }
}

Future<bool> registrarFcmTokenUsuarioActual({String? token}) async {
  final user = SupabaseService.client.auth.currentUser;
  if (user == null) return false;
  return registrarFcmToken(user.id, token: token);
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
    final user = SupabaseService.client.auth.currentUser;
    if (user != null) {
      try {
        final token = await PushService.getToken();
        if (token?.isNotEmpty == true) {
          await SupabaseService.client
              .from('suscripciones_push')
              .delete()
              .eq('usuario_id', user.id)
              .eq('endpoint', token!)
              .timeout(const Duration(seconds: 4));
        }
      } catch (error) {
        debugPrint(
            '[Auth] No se pudo retirar el token al cerrar sesión: $error');
      }
      await AppCache.clearUser(user.id);
      await AppCache.deletePrefix('cantos_json_${user.id}_');
      await AppCache.delete('perfil_json');
      await AppCache.delete('avisos_json');
      await AppCache.delete('eventos_permanentes');
    }
    await SupabaseService.client.auth.signOut();
  }

  /// Elimina permanentemente al usuario autenticado y todos los datos que
  /// dependan de auth.users mediante las reglas ON DELETE de la base de datos.
  ///
  /// La función RPC es SECURITY DEFINER y solo puede borrar auth.uid(), por lo
  /// que el cliente nunca recibe credenciales administrativas.
  static Future<void> deleteAccount() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
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

    await AppCache.clearUser(user.id);
    await AppCache.deletePrefix('cantos_json_${user.id}_');
    await AppCache.delete('perfil_json');
    await AppCache.delete('avisos_json');
    await AppCache.delete('eventos_permanentes');
  }
}
