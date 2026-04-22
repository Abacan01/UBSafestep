import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotificationsService {
  PushNotificationsService({
    required String parentGuardianId,
    required Future<void> Function(String token) onToken,
    required void Function(Map<String, dynamic> data) onNotificationTap,
  })  : _parentGuardianId = parentGuardianId,
        _onToken = onToken,
        _onNotificationTap = onNotificationTap {
    // Set static instance for global access
    _instance = this;
  }

  // Static instance for global access
  static PushNotificationsService? _instance;
  static PushNotificationsService? get instance => _instance;

  final String _parentGuardianId;
  final Future<void> Function(String token) _onToken;
  final void Function(Map<String, dynamic> data) _onNotificationTap;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifs = FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'ub_safestep_alerts',
    'UBSafeStep Alerts',
    description: 'Notifications for safezones, predefined zones, and emergency alerts',
    importance: Importance.max,
  );

  Future<void> init() async {
    // Permissions (iOS + Android 13)
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    // Local notifications init (for foreground display)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifs.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        // We can't easily pass full data here without storing it; use a fixed route.
        _onNotificationTap({'route': 'alerts'});
      },
    );

    // Create Android channel
    final androidPlugin = _localNotifs.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);

    // Token registration
    final token = await _messaging.getToken();
    if (token != null) {
      if (kDebugMode) print('🔔 [FCM] Token for $_parentGuardianId: $token');
      await _onToken(token);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      if (kDebugMode) print('🔔 [FCM] Token refreshed for $_parentGuardianId: $t');
      await _onToken(t);
    });

    // App opened from terminated
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _onNotificationTap(initialMessage.data);
    }

    // App opened from background
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      _onNotificationTap(msg.data);
    });

    // Foreground message -> show local notification
    FirebaseMessaging.onMessage.listen((msg) async {
      final title = msg.notification?.title ?? 'UBSafeStep';
      final body = msg.notification?.body ?? (msg.data['message']?.toString() ?? 'New alert');

      final androidDetails = AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      final details = NotificationDetails(android: androidDetails);

      await _localNotifs.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
      );
    });
  }

  /// Get the current FCM token
  Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  /// Show safezone entry/exit notification directly in notification tray
  /// This ensures notifications appear even if Cloud Functions aren't deployed
  Future<void> showSafezoneNotification({
    required String title,
    required String body,
    bool isEntry = true,
  }) async {
    try {
      if (kDebugMode) {
        print('📱 [LOCAL NOTIFICATION] Showing safezone notification');
        print('   Title: $title');
        print('   Body: $body');
        print('   Type: ${isEntry ? "ENTRY" : "EXIT"}');
      }

      final androidDetails = AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        color: isEntry ? const Color(0xFF4CAF50) : const Color(0xFFFF9800), // Green for entry, Orange for exit
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
        showWhen: true,
        when: DateTime.now().millisecondsSinceEpoch,
      );
      final details = NotificationDetails(android: androidDetails);

      // Use unique ID based on timestamp to ensure each notification shows
      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      await _localNotifs.show(
        notificationId,
        title,
        body,
        details,
      );

      if (kDebugMode) {
        print('✅ [LOCAL NOTIFICATION] Notification displayed successfully (ID: $notificationId)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [LOCAL NOTIFICATION] Error showing notification: $e');
      }
    }
  }

  /// Static helper method to show safezone notification from anywhere
  static Future<void> showSafezoneNotificationStatic({
    required String title,
    required String body,
    bool isEntry = true,
  }) async {
    if (_instance != null) {
      await _instance!.showSafezoneNotification(
        title: title,
        body: body,
        isEntry: isEntry,
      );
    } else {
      if (kDebugMode) {
        print('⚠️ [LOCAL NOTIFICATION] PushNotificationsService instance not initialized yet');
      }
    }
  }
}


