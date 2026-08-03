import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FirebaseMessaging _messaging;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;

  static const AndroidNotificationChannel _androidChannel =
  AndroidNotificationChannel(
    'splitup_high_importance',
    'SplitUP Notifications',
    description: 'Important expense, group, and settlement updates.',
    importance: Importance.max,
    playSound: true,
  );

  NotificationService({
    FirebaseMessaging? messaging,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  Future<void> initialize({
    required FutureOr<void> Function(RemoteMessage message)
    onForegroundMessage,
    required FutureOr<void> Function(RemoteMessage message)
    onNotificationOpened,
  }) async {
    await _initializeLocalNotifications();

    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint(
      'Notification permission: ${settings.authorizationStatus}',
    );

    await _saveCurrentToken();

    await _tokenRefreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedAppSubscription?.cancel();

    _tokenRefreshSubscription =
        _messaging.onTokenRefresh.listen(
              (token) async {
            try {
              await _saveToken(token);
            } catch (error) {
              debugPrint('Unable to save refreshed FCM token: $error');
            }
          },
          onError: (Object error) {
            debugPrint('FCM token refresh error: $error');
          },
        );

    _foregroundSubscription =
        FirebaseMessaging.onMessage.listen(
              (message) async {
            await showForegroundNotification(message);
            await onForegroundMessage(message);
          },
          onError: (Object error) {
            debugPrint('Foreground FCM error: $error');
          },
        );

    _openedAppSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen(
              (message) async {
            await onNotificationOpened(message);
          },
          onError: (Object error) {
            debugPrint('Notification-open error: $error');
          },
        );

    final initialMessage =
    await _messaging.getInitialMessage();

    if (initialMessage != null) {
      await onNotificationOpened(initialMessage);
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint(
          'Local notification selected. Payload: ${response.payload}',
        );
      },
    );

    final androidPlugin =
    _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      _androidChannel,
    );

    await androidPlugin?.requestNotificationsPermission();
  }

  Future<void> showForegroundNotification(
      RemoteMessage message,
      ) async {
    final notification = message.notification;

    final title = notification?.title ??
        message.data['title']?.toString() ??
        'SplitUP';

    final body = notification?.body ??
        message.data['body']?.toString() ??
        'You have a new update.';

    final notificationId =
        message.messageId?.hashCode ??
            DateTime.now().millisecondsSinceEpoch.remainder(100000);

    await _localNotifications.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'splitup_high_importance',
          'SplitUP Notifications',
          channelDescription:
          'Important expense, group, and settlement updates.',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: message.data['groupId']?.toString(),
    );
  }

  Future<String?> getToken() {
    return _messaging.getToken();
  }

  Future<void> _saveCurrentToken() async {
    final token = await _messaging.getToken();

    if (token != null && token.isNotEmpty) {
      await _saveToken(token);
    }
  }

  Future<void> _saveToken(String token) async {
    final user = _auth.currentUser;

    if (user == null) {
      return;
    }

    await _firestore.collection('users').doc(user.uid).set(
      {
        'fcmTokens': FieldValue.arrayUnion([token]),
        'notificationsEnabled': true,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> removeCurrentToken() async {
    final user = _auth.currentUser;
    final token = await _messaging.getToken();

    if (user == null || token == null) {
      return;
    }

    await _firestore.collection('users').doc(user.uid).set(
      {
        'fcmTokens': FieldValue.arrayRemove([token]),
        'notificationsEnabled': false,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await _messaging.deleteToken();
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedAppSubscription?.cancel();

    _tokenRefreshSubscription = null;
    _foregroundSubscription = null;
    _openedAppSubscription = null;
  }
}