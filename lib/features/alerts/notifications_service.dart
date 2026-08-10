import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/firestore/firestore_paths.dart';

/// Registers this device for price-alert push notifications and shows
/// them while the app is in the foreground (FCM only auto-displays a
/// system notification when the app is backgrounded/killed — a
/// foreground `onMessage` has to be shown manually, which is what
/// flutter_local_notifications is for here).
///
/// See functions/src/alerts/checkPriceAlerts.ts for the sender side, and
/// android/app/src/main/AndroidManifest.xml's
/// `com.google.firebase.messaging.default_notification_channel_id` for
/// why both sides have to agree on the `'price_alerts'` channel id.
class NotificationsService {
  NotificationsService({
    required FirebaseMessaging messaging,
    required FlutterLocalNotificationsPlugin localNotifications,
    required FirebaseFirestore firestore,
  })  : _messaging = messaging,
        _localNotifications = localNotifications,
        _paths = FirestorePaths(firestore);

  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final FirestorePaths _paths;

  static const _channel = AndroidNotificationChannel(
    'price_alerts',
    'Price Alerts',
    description: 'Notifications when a coin crosses your target price.',
    importance: Importance.high,
  );

  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
  }

  /// Requests notification permission and, if granted, registers this
  /// device's FCM token under the signed-in user — call once per app
  /// session after sign-in (see alerts_providers.dart's
  /// notificationsBootstrapProvider). A denial is silent: alerts still
  /// work in-app (the Price Alerts screen shows triggered history
  /// either way), this only affects whether a push actually reaches the
  /// device.
  Future<void> requestPermissionAndRegister(String uid) async {
    await _ensureInitialized();

    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[NotificationsService] permission denied, skipping token registration');
      return;
    }

    final token = await _messaging.getToken();
    if (token != null) await _registerToken(uid, token);

    _messaging.onTokenRefresh.listen((newToken) => _registerToken(uid, newToken));
  }

  Future<void> _registerToken(String uid, String token) {
    return _paths.fcmTokenDoc(uid, token).set({
      'updated_at': FieldValue.serverTimestamp(),
      'platform': defaultTargetPlatform.name,
    });
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
