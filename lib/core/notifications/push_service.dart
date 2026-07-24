import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

class PushService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  static void Function(String)? onNotificationTap;
  static String? pendingPayload;
  static String? lastNotifiedCantoId;

  static Future<void> init() async {
    // 1. Inicializar Firebase (requiere GoogleService-Info.plist en iOS y google-services.json en Android)
    try {
      await Firebase.initializeApp();
      debugPrint('Firebase inicializado correctamente');
    } catch (e) {
      debugPrint('Firebase init falló (probablemente falta configuración iOS): $e');
      debugPrint('Push notifications deshabilitadas. Registra una app iOS en Firebase Console.');
      return; // Salir sin configurar notificaciones push
    }

    // 2. Configurar manejador en segundo plano
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 3. Configurar notificaciones locales para cuando la app esté en primer plano
    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(android: androidInit, iOS: darwinInit, macOS: darwinInit);
    await _localNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null && details.payload!.isNotEmpty) {
          onNotificationTap?.call(details.payload!);
        }
      },
    );

    // 4. Chequear si la app se abrió desde una notificación (Cold Start)
    final launchDetails = await _localNotificationsPlugin.getNotificationAppLaunchDetails();
    if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
      if (launchDetails.notificationResponse?.payload != null) {
        pendingPayload = launchDetails.notificationResponse!.payload;
      }
    }

    // 5. Escuchar cambios de token y refrescarlo en Supabase cuando cambie
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      debugPrint('[FCM] Token refrescado: $token');
    });

    // 6. Configurar opciones de presentación para iOS (alert, badge, sound)
    if (Platform.isIOS) {
      await _firebaseMessaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    // 7. Escuchar notificaciones en primer plano
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Recibida notificación en primer plano: ${message.notification?.title}');
      
      final notification = message.notification;
      final cantoId = message.data['canto_id'];
      
      if (notification != null) {
        _localNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'repertorio_bc_channel', // id
              'Avisos y Actualizaciones', // title
              channelDescription: 'Notificaciones sobre setlists y actualizaciones',
              importance: Importance.max,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          payload: cantoId != null && cantoId.toString().isNotEmpty ? 'visor_$cantoId' : null,
        );
      }
    });


    // 8. Escuchar clics en notificaciones cuando la app está en segundo plano (pero no cerrada)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('FCM: Notificación cliqueada en segundo plano: ${message.data}');
      _handleMessageClick(message);
    });

    // 9. Chequear si la app se abrió desde una notificación cerrada (Cold Start de FCM)
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('FCM: App abierta desde notificación con cold start: ${initialMessage.data}');
      _handleMessageClick(initialMessage);
    }
  }

  static void _handleMessageClick(RemoteMessage message) {
    final cantoId = message.data['canto_id'];
    if (cantoId != null && cantoId.toString().isNotEmpty) {
      final payload = 'visor_$cantoId';
      if (onNotificationTap != null) {
        onNotificationTap!(payload);
      } else {
        pendingPayload = payload;
      }
    }
  }

  static Future<String?> getToken() async {
    try {
      if (Platform.isIOS) {
        // En iOS, se requiere asegurar que APNs Token esté recibido antes de pedir el FCM Token.
        String? apnsToken = await _firebaseMessaging.getAPNSToken();
        if (apnsToken == null) {
          debugPrint('[PushService] Esperando APNs Token en iOS...');
          for (int i = 0; i < 6; i++) {
            await Future.delayed(const Duration(milliseconds: 500));
            apnsToken = await _firebaseMessaging.getAPNSToken();
            if (apnsToken != null) break;
          }
        }
        debugPrint('[PushService] APNs Token obtenido: $apnsToken');
      }
      final token = await _firebaseMessaging.getToken();
      return token;
    } catch (e) {
      debugPrint('[PushService] Error obteniendo FCM token: $e');
      return null;
    }
  }

  static Future<void> requestPermission() async {
    if (Platform.isIOS || Platform.isAndroid) {
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('[PushService] Estado de permiso: ${settings.authorizationStatus}');
    }
  }

}
