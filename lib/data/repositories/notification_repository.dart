import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';
import '../../core/constants/app_constants.dart';

class NotificationRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _col =>
      _db.collection(AppConstants.notificationsCollection);

  Stream<List<NotificationModel>> streamNotifications(String userId) {
    return _col
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => NotificationModel.fromFirestore(doc)).toList());
  }

  Future<void> markAsRead(String notificationId) async {
    await _col.doc(notificationId).update({'read': true});
  }

  Future<void> markAllAsRead(String userId) async {
    final unread = await _col
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }
}
