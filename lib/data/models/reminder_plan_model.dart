import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';

class ReminderPlanModel {
  final String memberId; // = doc id
  final String frequency; // daily / monthly / annual
  final int amount; // cadence amount in FCFA
  final bool active;
  final Timestamp nextReminderAt;
  final Timestamp? lastReminderAt;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const ReminderPlanModel({
    required this.memberId,
    required this.frequency,
    required this.amount,
    required this.active,
    required this.nextReminderAt,
    this.lastReminderAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReminderPlanModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ReminderPlanModel(
      memberId: doc.id,
      frequency: d['frequency'] as String? ?? AppConstants.periodMonthly,
      amount: (d['amount'] as num?)?.toInt() ??
          amountForFrequency(d['frequency'] as String? ?? AppConstants.periodMonthly),
      active: d['active'] as bool? ?? true,
      nextReminderAt: d['nextReminderAt'] as Timestamp? ?? Timestamp.now(),
      lastReminderAt: d['lastReminderAt'] as Timestamp?,
      createdAt: d['createdAt'] as Timestamp? ?? Timestamp.now(),
      updatedAt: d['updatedAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'memberId': memberId,
      'frequency': frequency,
      'amount': amount,
      'active': active,
      'nextReminderAt': nextReminderAt,
      if (lastReminderAt != null) 'lastReminderAt': lastReminderAt,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  ReminderPlanModel copyWith({
    String? frequency,
    int? amount,
    bool? active,
    Timestamp? nextReminderAt,
    Timestamp? lastReminderAt,
    Timestamp? updatedAt,
  }) {
    return ReminderPlanModel(
      memberId: memberId,
      frequency: frequency ?? this.frequency,
      amount: amount ?? this.amount,
      active: active ?? this.active,
      nextReminderAt: nextReminderAt ?? this.nextReminderAt,
      lastReminderAt: lastReminderAt ?? this.lastReminderAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ── Cadence helpers (mirror the Cloud Function logic) ──────

  /// FCFA amount expected per reminder cadence.
  static int amountForFrequency(String frequency) {
    switch (frequency) {
      case AppConstants.periodDaily:
        return AppConstants.amountDaily;
      case AppConstants.periodAnnual:
        return AppConstants.amountAnnual;
      case AppConstants.periodMonthly:
      default:
        return AppConstants.amountMonthly;
    }
  }

  /// Next reminder time after [from] for the given cadence:
  /// daily → +1 day, monthly → +1 month, annual → +1 year.
  static DateTime nextFrom(DateTime from, String frequency) {
    switch (frequency) {
      case AppConstants.periodDaily:
        return from.add(const Duration(days: 1));
      case AppConstants.periodAnnual:
        return DateTime(from.year + 1, from.month, from.day,
            from.hour, from.minute, from.second);
      case AppConstants.periodMonthly:
      default:
        return DateTime(from.year, from.month + 1, from.day,
            from.hour, from.minute, from.second);
    }
  }
}
