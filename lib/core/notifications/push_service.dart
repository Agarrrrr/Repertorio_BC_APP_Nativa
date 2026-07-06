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
    // 1. Inicializar Firebase
    await Firebase.initializeApp();

    // 2. Configurar manejador en segundo plano
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 3. Configurar notificaciones locales para cuando la app esté en primer plano
    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotificationsPlugin.initialize(
      settings: initSettings,
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

    // El permiso se solicitará más adelante cuando la UI esté lista

    // 5. Escuchar notificaciones en primer plano
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Recibida notificación en primer plano: ${message.notification?.title}');
      
      final notification = message.notification;
      final cantoId = message.data['canto_id'];
      
      if (notification != null) {
        _localNotificationsPlugin.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'repertorio_bc_channel', // id
              'Avisos y Actualizaciones', // title
              channelDescription: 'Notificaciones sobre setlists y actualizaciones',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
          payload: cantoId != null && cantoId.toString().isNotEmpty ? 'visor_$cantoId' : null,
        );
      }
    });

    // 6. Escuchar clics en notificaciones cuando la app está en segundo plano (pero no cerrada)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('FCM: Notificación cliqueada en segundo plano: ${message.data}');
      _handleMessageClick(message);
    });

    // 7. Chequear si la app se abrió desde una notificación cerrada (Cold Start de FCM)
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
      final token = await _firebaseMessaging.getToken();
      return token;
    } catch (e) {
      debugPrint('Error obteniendo FCM token: $e');
      return null;
    }
  }

  static Future<void> requestPermission() async {
    if (Platform.isIOS || Platform.isAndroid) {
      await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

}
