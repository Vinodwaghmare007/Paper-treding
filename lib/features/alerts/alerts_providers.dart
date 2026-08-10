import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/alert_repository.dart';
import '../../domain/entities/price_alert.dart';
import '../auth/auth_providers.dart';
import 'notifications_service.dart';

final alertRepositoryProvider = Provider<AlertRepository>((ref) {
  return AlertRepository(ref.watch(firebaseFirestoreProvider));
});

final notificationsServiceProvider = Provider<NotificationsService>((ref) {
  return NotificationsService(
    messaging: FirebaseMessaging.instance,
    localNotifications: FlutterLocalNotificationsPlugin(),
    firestore: ref.watch(firebaseFirestoreProvider),
  );
});

/// Watched once from HomeShell to trigger permission request + FCM token
/// registration as a side effect after sign-in — its AsyncValue is never
/// otherwise read, this is purely for the side effect.
final notificationsBootstrapProvider = FutureProvider<void>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return;
  await ref.watch(notificationsServiceProvider).requestPermissionAndRegister(uid);
});

/// Requires a signed-in user — only meant to be watched beneath AuthGate,
/// same contract as the other `_uidOrThrow` helpers in this app.
String _uidOrThrow(Ref ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    throw StateError('alertsProvider read outside of AuthGate');
  }
  return uid;
}

final alertsProvider = StreamProvider<List<PriceAlert>>((ref) {
  final uid = _uidOrThrow(ref);
  return ref.watch(alertRepositoryProvider).watchAlerts(uid);
});
