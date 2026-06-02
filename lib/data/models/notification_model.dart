import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final bool read;
  final Map<String, dynamic> data;
  final Timestamp createdAt;

  // ── Type Constants ────────────────────────────────────────
  static const String typePaymentConfirmed = 'payment_confirmed';
  static const String typePaymentRejected = 'payment_rejected';
  static const String typePaymentReminder = 'payment_reminder';
  static const String typeWelcome = 'welcome';
  static const String typeMilestone = 'milestone';
  static const String typeAdminAlert = 'admin_alert';
  static const String typeFocalReport = 'focal_report';
  static const String typeManualPayment = 'manual_payment';
  static const String typeRoleChange = 'role_change';

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.data,
    required this.createdAt,
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      type: d['type'] as String? ?? typeAdminAlert,
      title: d['title'] as String? ?? '',
      body: d['body'] as String? ?? '',
      read: d['read'] as bool? ?? false,
      data: Map<String, dynamic>.from(d['data'] as Map? ?? {}),
      createdAt: d['createdAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'type': type,
      'title': title,
      'body': body,
      'read': read,
      'data': data,
      'createdAt': createdAt,
    };
  }

  NotificationModel copyWith({bool? read}) {
    return NotificationModel(
      id: id,
      userId: userId,
      type: type,
      title: title,
      body: body,
      read: read ?? this.read,
      data: data,
      createdAt: createdAt,
    );
  }
}
