import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../models/reminder_plan_model.dart';

class ReminderPlanRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String memberId) =>
      _db.collection(AppConstants.reminderPlansCollection).doc(memberId);

  /// Creates (or refreshes) a member's reminder plan from their frequency.
  /// Doc id = memberId. First reminder is scheduled one cadence interval out
  /// so a member isn't nudged the instant they join.
  Future<void> upsertForMember(String memberId, String frequency) async {
    final now = DateTime.now();
    final next = ReminderPlanModel.nextFrom(now, frequency);
    await _doc(memberId).set({
      'memberId': memberId,
      'frequency': frequency,
      'amount': ReminderPlanModel.amountForFrequency(frequency),
      'active': true,
      'nextReminderAt': Timestamp.fromDate(next),
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));
  }

  Stream<ReminderPlanModel?> streamPlan(String memberId) {
    return _doc(memberId).snapshots().map(
          (snap) => snap.exists ? ReminderPlanModel.fromFirestore(snap) : null,
        );
  }

  Future<void> setActive(String memberId, bool active) async {
    await _doc(memberId).update({
      'active': active,
      'updatedAt': Timestamp.now(),
    });
  }

  /// Changes cadence: recomputes the amount and re-anchors the next reminder.
  Future<void> updateFrequency(String memberId, String frequency) async {
    final now = DateTime.now();
    final next = ReminderPlanModel.nextFrom(now, frequency);
    await _doc(memberId).update({
      'frequency': frequency,
      'amount': ReminderPlanModel.amountForFrequency(frequency),
      'nextReminderAt': Timestamp.fromDate(next),
      'updatedAt': Timestamp.fromDate(now),
    });
  }
}
