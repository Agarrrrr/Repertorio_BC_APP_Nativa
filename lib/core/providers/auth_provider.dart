import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

final _pushFailureReports = <String>{};

Future<void> _reportPushRegistrationFailure(
  String userId,
  String reason,
) async {
  // TestFlight no expone debugPrint al usuario. Guardamos un único diagnóstico
  // por motivo para saber si falla APNs, FCM o el upsert de Supabase.
  final key = '$userId:$reason';
  if (!_pushFailureReports.add(key)) return;
  try {
    await SupabaseService.client.from('errores_app').insert({
      'usuario_id': userId,
      'mensaje': '[PUSH_REGISTRATION] $reason',
      'user_agent': Platform.operatingSystem,
    });
  } catch (error) {
    debugPrint('[FCM] No se pudo guardar diagnóstico push: $error');
  }
}

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
    debugPrint(
      '[FCM] Token aun no disponible; se reintentara mas adelante. '
      '${PushService.lastTokenError ?? ''}',
    );
    await _reportPushRegistrationFailure(
      userId,
      PushService.lastTokenError ?? 'No se obtuvo token FCM.',
    );
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
    await _reportPushRegistrationFailure(
      userId,
      'No se pudo guardar la suscripción: $error',
    );
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
  // Este es el cliente OAuth web configurado en el proveedor Google de
  // Supabase. No es un secreto. Se pasa de forma explicita porque el proyecto
  // Firebase usado por FCM es distinto y su google-services.json no contiene
  // clientes OAuth.
  static const _googleServerClientId =
      '882216089330-shvij662ok8e0h1kd6o7k86id49fdf10.apps.googleusercontent.com';
  static const _googleScopes = <String>['openid', 'email', 'profile'];
  static final _googleSignIn = GoogleSignIn.instance;
  static Future<void>? _googleInitialization;

  static Future<void> login(String email, String password) async {
    await SupabaseService.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> loginWithGoogle() async {
    // En web el SDK nativo no permite authenticate() desde un boton propio.
    // Conservamos ahi el flujo OAuth del navegador.
    if (kIsWeb || !Platform.isAndroid) {
      await SupabaseService.client.auth.signInWithOAuth(
        supabase.OAuthProvider.google,
        redirectTo: 'repertorioestatal://login-callback/',
      );
      return;
    }

    try {
      _googleInitialization ??= _googleSignIn.initialize(
        serverClientId: _googleServerClientId,
      );
      await _googleInitialization;

      final googleUser = await _googleSignIn.authenticate(
        scopeHint: _googleScopes,
      );
      final idToken = googleUser.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const GoogleLoginException(
          'Google no entrego un token de identidad. Intenta de nuevo.',
        );
      }

      // Supabase requiere tambien el access token de Google. En la API 7.x
      // se obtiene por separado del token de identidad.
      final authorization = await googleUser.authorizationClient
              .authorizationForScopes(_googleScopes) ??
          await googleUser.authorizationClient.authorizeScopes(_googleScopes);

      await SupabaseService.client.auth.signInWithIdToken(
        provider: supabase.OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization.accessToken,
      );
    } on GoogleSignInException catch (error) {
      throw GoogleLoginException.fromGoogle(error);
    }
  }

  static String googleLoginErrorMessage(Object error) {
    if (error is GoogleLoginException) return error.message;
    if (error is supabase.AuthException) {
      return 'Google valido la cuenta, pero no se pudo crear la sesion. '
          'Comprueba tu conexion e intenta de nuevo.';
    }
    if (error is SocketException) {
      return 'No hay conexion a Internet. Revisa tu red e intenta de nuevo.';
    }
    return 'No se pudo iniciar sesion con Google. Intenta de nuevo.';
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
    if (!kIsWeb && Platform.isAndroid && _googleInitialization != null) {
      try {
        await _googleInitialization;
        await _googleSignIn.signOut();
      } catch (error) {
        debugPrint(
            '[Auth] No se pudo cerrar la sesion local de Google: $error');
      }
    }
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

class GoogleLoginException implements Exception {
  const GoogleLoginException(this.message);

  factory GoogleLoginException.fromGoogle(GoogleSignInException error) {
    switch (error.code) {
      case GoogleSignInExceptionCode.canceled:
        return const GoogleLoginException(
          'Se cancelo el acceso con Google. Si aparece despues de elegir una '
          'cuenta, falta autorizar la firma de esta version de la app.',
        );
      case GoogleSignInExceptionCode.interrupted:
        return const GoogleLoginException(
          'El acceso con Google fue interrumpido. Intenta de nuevo.',
        );
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return const GoogleLoginException(
          'Google no reconoce esta version de la app. Debe registrarse su '
          'paquete y certificado SHA en Google Cloud.',
        );
      case GoogleSignInExceptionCode.uiUnavailable:
        return const GoogleLoginException(
          'Google no pudo mostrar el selector de cuentas. Vuelve a abrir la '
          'app e intenta de nuevo.',
        );
      case GoogleSignInExceptionCode.userMismatch:
        return const GoogleLoginException(
          'La cuenta seleccionada no coincide con la sesion de Google activa.',
        );
      case GoogleSignInExceptionCode.unknownError:
        return const GoogleLoginException(
          'Google no pudo completar el acceso. Comprueba Google Play Services '
          'y tu conexion, luego intenta de nuevo.',
        );
    }
  }

  final String message;

  @override
  String toString() => message;
}
