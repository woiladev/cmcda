import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/notification_model.dart';
import '../constants/app_constants.dart';
import '../constants/app_routes.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const _channelId = 'cmcda_high_importance';
  static const _channelName = 'Notifications CMCDA';

  // Shared navigator key — router_service.dart uses this as its navigatorKey
  // so notification taps can navigate without a BuildContext.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Holds a cold-start message until the first frame is rendered.
  RemoteMessage? _pendingMessage;

  // ── Lifecycle ─────────────────────────────────────────────

  Future<void> initialize() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          importance: Importance.high,
        ));

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpened);

    // Cold start: store and navigate after first frame
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      _pendingMessage = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pendingMessage != null) {
          _handleMessageOpened(_pendingMessage!);
          _pendingMessage = null;
        }
      });
    }

    // Keep token fresh on refresh
    _fcm.onTokenRefresh.listen((token) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) await saveToken(uid, token);
    });

    // Save token on every auth state change
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      final token = await _getToken();
      if (token != null) await saveToken(user.uid, token);
    });
  }

  // ── Token Management ──────────────────────────────────────

  Future<String?> _getToken() async {
    if (kIsWeb) {
      if (AppConstants.webVapidKey.isEmpty) return null;
      return _fcm.getToken(vapidKey: AppConstants.webVapidKey);
    }
    return _fcm.getToken();
  }

  Future<void> saveToken(String userId, String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prev = prefs.getString('_fcm_token_$userId');
      if (prev == token) return; // unchanged — skip write to avoid triggering Cloud Functions
      await _db
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .update({'fcmTokens': FieldValue.arrayUnion([token])});
      await prefs.setString('_fcm_token_$userId', token);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'not-found') return;
      rethrow;
    }
  }

  /// Fetches this device's FCM token and stores it on [userId]'s doc. Call
  /// immediately after a user document is created (email signup / profile
  /// completion): the authStateChanges listener fires on credential creation,
  /// which is *before* that doc exists, so its save is dropped as not-found and
  /// the device would otherwise never be registered for push that session.
  Future<void> registerToken(String userId) async {
    final token = await _getToken();
    if (token != null) await saveToken(userId, token);
  }

  /// Removes this device's token from the user doc. Call before signing out so
  /// the device stops receiving pushes for the account that just logged out.
  Future<void> removeTokenOnSignOut() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final token = await _getToken();
    if (token == null) return;
    try {
      await _db
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update({
        'fcmTokens': FieldValue.arrayRemove([token]),
        'updatedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'not-found') return;
      rethrow;
    }
  }

  // ── Send Notifications ────────────────────────────────────

  Future<void> sendNotification({
    required String userId,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    await _db.collection(AppConstants.notificationsCollection).add({
      'userId': userId,
      'type': type,
      'title': title,
      'body': body,
      'read': false,
      'data': data ?? {},
      'createdAt': Timestamp.now(),
    });
  }

  // Fetches all admin/super_admin UIDs and notifies each, excluding [excludeUid].
  Future<void> _notifyAllAdmins({
    String? excludeUid,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final snap = await _db
        .collection(AppConstants.usersCollection)
        .where('role', whereIn: [
          AppConstants.roleAdmin,
          AppConstants.roleSuperAdmin,
        ])
        .get();

    await Future.wait([
      for (final doc in snap.docs)
        if (doc.id != excludeUid)
          sendNotification(
            userId: doc.id,
            type: type,
            title: title,
            body: body,
            data: data,
          ),
    ]);
  }

  // ── Read Status ───────────────────────────────────────────

  Future<void> markAsRead(String notificationId) async {
    await _db
        .collection(AppConstants.notificationsCollection)
        .doc(notificationId)
        .update({'read': true});
  }

  Future<void> markAllAsRead(String userId) async {
    final unread = await _db
        .collection(AppConstants.notificationsCollection)
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  // ── Notification Templates ────────────────────────────────
  // Payment-confirmed, payment-rejected and welcome notifications are created
  // server-side (onContributionConfirmed / onUserWelcome Cloud Functions), so
  // they are not duplicated here. Admin-facing templates stay client-side
  // because they are written by admin/focal sessions, which the security rules
  // already permit.

  /// Notifies all admins (except [creatorId]) that a payment needs validation.
  Future<void> notifyAdminPayment({
    required String creatorId,
    required String memberName,
    required String amount,
  }) async {
    await _notifyAllAdmins(
      excludeUid: creatorId,
      type: NotificationModel.typeManualPayment,
      title: 'Nouveau paiement en attente',
      body: '$memberName a soumis un paiement de $amount en attente de validation.',
      data: {'memberName': memberName, 'amount': amount},
    );
  }

  /// Notifies all admins that a focal officer submitted a report.
  Future<void> notifyFocalReport({
    required String focalName,
    required String reportId,
  }) async {
    await _notifyAllAdmins(
      type: NotificationModel.typeFocalReport,
      title: 'Rapport focal soumis',
      body: '$focalName a soumis un nouveau rapport de session.',
      data: {'focalName': focalName, 'reportId': reportId},
    );
  }

  // ── Internal Handlers ─────────────────────────────────────

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _local.show(
      message.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  void _handleMessageOpened(RemoteMessage message) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final type = message.data['type'] ?? '';
    final router = GoRouter.of(ctx);

    switch (type) {
      case NotificationModel.typeFocalReport:
        router.go(AppRoutes.adminFocalReports);
      case NotificationModel.typeManualPayment:
        router.go(AppRoutes.adminPayments);
      default:
        router.go(AppRoutes.notifications);
    }
  }
}
