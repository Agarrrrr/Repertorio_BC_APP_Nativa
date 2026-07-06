import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:repertorio_bc/core/providers/auth_provider.dart';
import 'package:repertorio_bc/core/providers/cantos_provider.dart';
import 'package:repertorio_bc/core/providers/eventos_provider.dart';
import 'package:repertorio_bc/core/notifications/push_service.dart';
import 'package:repertorio_bc/features/auth/login_screen.dart';
import 'package:repertorio_bc/features/dashboard/dashboard_screen.dart';
import 'package:repertorio_bc/features/visor/visor_screen.dart';
import 'package:repertorio_bc/features/jukebox/jukebox_screen.dart';
import 'package:repertorio_bc/features/gestor/gestor_screen.dart';
import 'package:repertorio_bc/features/splash/splash_screen.dart';

import 'package:repertorio_bc/features/auth/register_screen.dart';
import 'package:repertorio_bc/features/auth/recover_password_screen.dart';
import 'package:repertorio_bc/features/auth/update_password_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class PendingDeepLinkNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setState(String? value) => state = value;
}
final pendingDeepLinkProvider = NotifierProvider<PendingDeepLinkNotifier, String?>(PendingDeepLinkNotifier.new);

class RouterNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = RouterNotifier();
  
  ref.listen(authUserProvider, (_, __) => notifier.notify());
  ref.listen(authLoadingProvider, (_, __) => notifier.notify());
  ref.listen(perfilProvider, (_, __) => notifier.notify());
  ref.listen(isRecoveringPasswordProvider, (_, __) => notifier.notify());

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: notifier,
    // Redireccion global basada en autenticacion
    redirect: (context, state) {
      final isLoading = ref.read(authLoadingProvider);
      
      if (isLoading) {
        return state.matchedLocation == '/splash' ? null : '/splash';
      }

      final isRecovering = ref.read(isRecoveringPasswordProvider);
      if (isRecovering && state.matchedLocation != '/update-password') {
        return '/update-password';
      }

      final authState = ref.read(authUserProvider);
      final user = authState.value;
      final isAuthRoute = state.matchedLocation == '/login' || 
                          state.matchedLocation == '/register' || 
                          state.matchedLocation == '/recover' ||
                          state.matchedLocation == '/update-password';
      final isSplashRoute = state.matchedLocation == '/splash';

      if (user == null) {
        // Si intenta acceder a una ruta protegida (ej. /visor/:id) sin sesión, guardamos su intención
        if (!isAuthRoute && !isSplashRoute && state.matchedLocation != '/') {
          Future.microtask(() => ref.read(pendingDeepLinkProvider.notifier).setState(state.uri.toString()));
        }
        return isAuthRoute ? null : '/login';
      }

      if (isAuthRoute || isSplashRoute) {
        final pending = ref.read(pendingDeepLinkProvider);
        if (pending != null) {
          Future.microtask(() => ref.read(pendingDeepLinkProvider.notifier).setState(null));
          return pending;
        }
        return '/';
      }

      // 1. Verificar si hay un payload pendiente por cold-start
      if (PushService.pendingPayload != null) {
        final p = PushService.pendingPayload!;
        PushService.pendingPayload = null; // Limpiar para no crear bucles
        if (p.startsWith('visor_')) {
          final id = p.replaceFirst('visor_', '');
          return '/visor/$id';
        }
      }

      // Proteger rutas del gestor por rol
      if (state.matchedLocation.startsWith('/gestor')) {
        final perfilState = ref.read(perfilProvider);
        final perfil = perfilState.value;
        if (perfil != null) {
          final isGestor = ['director', 'estatal', 'superadmin'].contains(perfil.rol);
          if (!isGestor) return '/'; // Rol insuficiente
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/recover',
        builder: (context, state) => const RecoverPasswordScreen(),
      ),
      GoRoute(
        path: '/update-password',
        builder: (context, state) => const UpdatePasswordScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) {
          // Deep link /?ev=ID (Pase de invitado)
          final evId = state.uri.queryParameters['ev'];
          // Deep link /?carpeta=Nombre
          final carpeta = state.uri.queryParameters['carpeta'];
          
          if (evId != null) {
            Future.microtask(() async {
              await ref.read(eventosPermanentesProvider.notifier).manejarLinkEvento(evId);
              ref.read(categoryFilterProvider.notifier).set('evento_$evId');
            });
          } else if (carpeta != null) {
            Future.microtask(() => ref.read(categoryFilterProvider.notifier).set('tema_$carpeta'));
          }
          return const DashboardScreen();
        },
      ),

      GoRoute(
        path: '/visor/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return VisorScreen(cantoId: id);
        },
      ),
      GoRoute(
        path: '/jukebox',
        builder: (context, state) => const JukeboxScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/gestor',
        builder: (context, state) => const GestorScreen(),
      ),
    ],
  );
});
