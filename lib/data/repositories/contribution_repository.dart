import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/contribution_model.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/app_utils.dart';

class ContributionRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _col =>
      _db.collection(AppConstants.contributionsCollection);

  // ── Create ────────────────────────────────────────────────

  Future<ContributionModel> createContribution({
    required String memberId,
    required String memberName,
    required String memberNumber,
    required int amount,
    required String periodType,
    required String paymentMethod,
    required String recordedBy,
    String? period,
    String? paidForId,
    String? focalReportId,
    String? notes,
  }) async {
    final receiptNumber = await generateReceiptNumber();
    final effectivePeriod =
        period ?? AppUtils.getPeriodForDate(DateTime.now());
    final isCashOrBank = paymentMethod == AppConstants.paymentCash ||
        paymentMethod == AppConstants.paymentBankTransfer;
    final now = Timestamp.now();

    final contribution = ContributionModel(
      id: '',
      memberId: memberId,
      memberName: memberName,
      memberNumber: memberNumber,
      amount: amount,
      period: effectivePeriod,
      periodType: periodType,
      paymentMethod: paymentMethod,
      status: isCashOrBank
          ? AppConstants.statusPending
          : AppConstants.statusConfirmed,
      receiptNumber: receiptNumber,
      recordedBy: recordedBy,
      paidForId: paidForId,
      focalReportId: focalReportId,
      notes: notes,
      validationRequired: isCashOrBank,
      createdAt: now,
      confirmedAt: isCashOrBank ? null : now,
    );

    final doc = await _col.add(contribution.toFirestore());

    // Mobile money is auto-confirmed — update the member's and platform totals.
    // Skip if memberId is empty (unregistered member recorded by focal).
    if (!isCashOrBank && memberId.isNotEmpty) {
      await _db
          .collection(AppConstants.usersCollection)
          .doc(memberId)
          .update({'totalContributed': FieldValue.increment(amount)});
      await _db
          .collection(AppConstants.countersCollection)
          .doc('platform')
          .set({'totalContributed': FieldValue.increment(amount)}, SetOptions(merge: true));
    }

    return ContributionModel.fromFirestore(await doc.get());
  }

  // ── Read ──────────────────────────────────────────────────

  Stream<List<ContributionModel>> getMemberContributions(String memberId) {
    return _col
        .where('memberId', isEqualTo: memberId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => ContributionModel.fromFirestore(d)).toList());
  }

  Future<int> getTotalContributed(String memberId) async {
    final snap = await _col
        .where('memberId', isEqualTo: memberId)
        .where('status', isEqualTo: AppConstants.statusConfirmed)
        .get();
    return snap.docs.fold<int>(
      0,
      (acc, doc) =>
          acc + ((doc.data() as Map)['amount'] as num? ?? 0).toInt(),
    );
  }

  Stream<List<ContributionModel>> getPendingPayments() {
    return _col
        .where('status', isEqualTo: AppConstants.statusPending)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => ContributionModel.fromFirestore(d)).toList());
  }

  // ── Validation (dual-validation flow) ────────────────────

  /// First validation: records the validator and marks the status as 'pending'
  /// until a second validator confirms (for cash/bank transfers).
  Future<void> validatePayment(
      String contributionId, String validatorId) async {
    await _col.doc(contributionId).update({
      'validatedBy': validatorId,
      // If no second validation is required, confirm immediately.
      // The second-validator requirement is handled by secondValidatePayment.
    });
  }

  /// Second validation: confirms the payment after dual-approval.
  Future<void> secondValidatePayment(
      String contributionId, String validatorId) async {
    final snap = await _col.doc(contributionId).get();
    final data = snap.data() as Map<String, dynamic>?;
    final memberId = data?['memberId'] as String?;
    final amount = (data?['amount'] as num?)?.toInt() ?? 0;

    await _col.doc(contributionId).update({
      'secondValidatorId': validatorId,
      'status': AppConstants.statusConfirmed,
      'confirmedAt': Timestamp.now(),
    });

    if (memberId != null && amount > 0) {
      await _db
          .collection(AppConstants.usersCollection)
          .doc(memberId)
          .update({'totalContributed': FieldValue.increment(amount)});
      await _db
          .collection(AppConstants.countersCollection)
          .doc('platform')
          .set({'totalContributed': FieldValue.increment(amount)}, SetOptions(merge: true));
    }
  }

  Future<void> rejectPayment(
      String contributionId, String adminId, String reason) async {
    await _col.doc(contributionId).update({
      'status': AppConstants.statusFailed,
      'validatedBy': adminId,
      'notes': reason,
    });
  }

  // ── Aggregates ────────────────────────────────────────────

  Future<int> getTodayTotal() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final snap = await _col
        .where('status', isEqualTo: AppConstants.statusConfirmed)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('createdAt', isLessThan: Timestamp.fromDate(endOfDay))
        .get();

    return snap.docs.fold<int>(
      0,
      (acc, doc) =>
          acc + ((doc.data() as Map)['amount'] as num? ?? 0).toInt(),
    );
  }

  Future<int> getMonthTotal() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startOfNextMonth = DateTime(now.year, now.month + 1, 1);

    final snap = await _col
        .where('status', isEqualTo: AppConstants.statusConfirmed)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('createdAt',
            isLessThan: Timestamp.fromDate(startOfNextMonth))
        .get();

    return snap.docs.fold<int>(
      0,
      (acc, doc) =>
          acc + ((doc.data() as Map)['amount'] as num? ?? 0).toInt(),
    );
  }

  // ── Platform Total ────────────────────────────────────────

  Stream<double> streamPlatformTotal() {
    return _db
        .collection(AppConstants.countersCollection)
        .doc('platform')
        .snapshots()
        .map((s) => (s.data()?['totalContributed'] as num?)?.toDouble() ?? 0.0);
  }

  Stream<int> streamMemberCount() {
    return _db
        .collection(AppConstants.countersCollection)
        .doc('members')
        .snapshots()
        .map((s) => (s.data()?['count'] as num?)?.toInt() ?? 0);
  }

  /// Admin-only: recomputes the platform counters from Firestore ground truth.
  /// Sets counters/members.count and counters/platform.totalContributed.
  Future<({int members, double total})> backfillPlatformCounters() async {
    final userCountSnap = await _db
        .collection(AppConstants.usersCollection)
        .count()
        .get();
    final memberCount = userCountSnap.count ?? 0;

    final contribSnap = await _db
        .collection(AppConstants.contributionsCollection)
        .where('status', isEqualTo: AppConstants.statusConfirmed)
        .aggregate(sum('amount'))
        .get();
    final totalContributed = contribSnap.getSum('amount') ?? 0.0;

    await _db
        .collection(AppConstants.countersCollection)
        .doc('members')
        .set({'count': memberCount});
    await _db
        .collection(AppConstants.countersCollection)
        .doc('platform')
        .set({'totalContributed': totalContributed});

    return (members: memberCount, total: totalContributed);
  }

  // ── Receipt Number ────────────────────────────────────────

  /// Atomically increments the receipt counter.
  /// Format: RCP-000001
  Future<String> generateReceiptNumber() async {
    final counterRef = _db
        .collection(AppConstants.countersCollection)
        .doc('receipts');

    int newCount = 0;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(counterRef);
      newCount = ((snap.data()?['count'] as num?)?.toInt() ?? 0) + 1;
      tx.set(counterRef, {'count': newCount}, SetOptions(merge: true));
    });

    return '${AppConstants.receiptPrefix}${newCount.toString().padLeft(6, '0')}';
  }
}
