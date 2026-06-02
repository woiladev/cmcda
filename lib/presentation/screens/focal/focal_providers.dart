import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/models/focal_report_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/focal_report_repository.dart';
import '../../../data/repositories/notification_repository.dart';

/// All reports for a given focal officer, ordered by createdAt desc.
final focalReportsProvider =
    StreamProvider.autoDispose.family<List<FocalReportModel>, String>(
  (ref, focalId) => FocalReportRepository().streamMyReports(focalId),
);

/// Members registered by a given focal officer.
final focalMembersProvider =
    StreamProvider.autoDispose.family<List<UserModel>, String>(
  (ref, focalId) => FirebaseFirestore.instance
      .collection(AppConstants.usersCollection)
      .where('registeredByFocalId', isEqualTo: focalId)
      .snapshots()
      .map((snap) {
    final list = snap.docs
        .map((doc) => UserModel.fromFirestore(doc))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }),
);

/// Total confirmed contributions recorded by a focal officer this calendar month.
final focalMonthCollectedProvider =
    StreamProvider.autoDispose.family<int, String>(
  (ref, focalId) => FirebaseFirestore.instance
      .collection(AppConstants.contributionsCollection)
      .where('recordedBy', isEqualTo: focalId)
      .snapshots()
      .map((snap) {
    final now = DateTime.now();
    return snap.docs
        .where((doc) {
          final data = doc.data();
          if (data['status'] != AppConstants.statusConfirmed) return false;
          final ts = data['createdAt'];
          if (ts == null) return false;
          final d = (ts as dynamic).toDate() as DateTime;
          return d.year == now.year && d.month == now.month;
        })
        .fold<int>(
            0, (acc, doc) => acc + ((doc.data()['amount'] as num?)?.toInt() ?? 0));
  }),
);

/// Today's confirmed contributions recorded by a focal officer.
/// Returns (amountToday, countToday).
final focalTodayContribProvider =
    StreamProvider.autoDispose.family<(int, int), String>(
  (ref, focalId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final tsStart = Timestamp.fromDate(startOfDay);
    return FirebaseFirestore.instance
        .collection(AppConstants.contributionsCollection)
        .where('recordedBy', isEqualTo: focalId)
        .where('createdAt', isGreaterThanOrEqualTo: tsStart)
        .snapshots()
        .map((snap) {
      final confirmed = snap.docs.where(
          (d) => d.data()['status'] == AppConstants.statusConfirmed);
      final amount = confirmed.fold<int>(
          0,
          (s, d) =>
              s + ((d.data()['amount'] as num?)?.toInt() ?? 0));
      return (amount, snap.size);
    });
  },
);

/// New members registered today by a focal officer.
final focalTodayMembersProvider =
    StreamProvider.autoDispose.family<int, String>(
  (ref, focalId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final tsStart = Timestamp.fromDate(startOfDay);
    return FirebaseFirestore.instance
        .collection(AppConstants.usersCollection)
        .where('registeredByFocalId', isEqualTo: focalId)
        .where('createdAt', isGreaterThanOrEqualTo: tsStart)
        .snapshots()
        .map((snap) => snap.size);
  },
);

/// All contributions recorded by a focal officer, newest first.
/// Sorted client-side to avoid requiring a composite index and to keep
/// reads serving from cache when offline.
final focalRecentPaymentsProvider =
    StreamProvider.autoDispose.family<List<ContributionModel>, String>(
  (ref, focalId) => FirebaseFirestore.instance
      .collection(AppConstants.contributionsCollection)
      .where('recordedBy', isEqualTo: focalId)
      .snapshots()
      .map((snap) {
    final list = snap.docs
        .map((doc) => ContributionModel.fromFirestore(doc))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }),
);

/// Count of unread notifications for a given user.
final focalUnreadCountProvider =
    StreamProvider.autoDispose.family<int, String>(
  (ref, userId) => NotificationRepository()
      .streamNotifications(userId)
      .map((list) => list.where((n) => !n.read).length),
);
