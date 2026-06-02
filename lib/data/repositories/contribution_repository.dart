import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../models/contribution_model.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/app_utils.dart';

class ContributionRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _col =>
      _db.collection(AppConstants.contributionsCollection);

  // ── Create ────────────────────────────────────────────────

  /// Creates a contribution. Offline-safe: the doc id is generated locally and
  /// the write is fire-and-forget so it persists to the local cache and the
  /// caller returns immediately, syncing to the server on reconnect. The
  /// receiptNumber is left empty and assigned server-side by the
  /// onContributionCreated Cloud Function (so it works for offline-created docs
  /// too). Do NOT await the write Futures: they only complete on server ack,
  /// which never happens while offline.
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
    String? proofUrl,
  }) async {
    final effectivePeriod =
        period ?? AppUtils.getPeriodForDate(DateTime.now());
    final isCashOrBank = paymentMethod == AppConstants.paymentCash ||
        paymentMethod == AppConstants.paymentBankTransfer;
    final now = Timestamp.now();
    final ref = _col.doc(); // local id, no network round-trip

    final contribution = ContributionModel(
      id: ref.id,
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
      receiptNumber: '', // assigned server-side by onContributionCreated
      recordedBy: recordedBy,
      paidForId: paidForId,
      focalReportId: focalReportId,
      notes: notes,
      proofUrl: proofUrl,
      validationRequired: isCashOrBank,
      createdAt: now,
      confirmedAt: isCashOrBank ? null : now,
    );

    unawaited(ref.set(contribution.toFirestore()));

    // Mobile money is auto-confirmed — update the member's and platform totals.
    // Skip if memberId is empty (unregistered member recorded by focal).
    if (!isCashOrBank && memberId.isNotEmpty) {
      unawaited(_db
          .collection(AppConstants.usersCollection)
          .doc(memberId)
          .update({'totalContributed': FieldValue.increment(amount)}));
      unawaited(_db
          .collection(AppConstants.countersCollection)
          .doc('platform')
          .set({'totalContributed': FieldValue.increment(amount)},
              SetOptions(merge: true)));
    }

    return contribution;
  }

  /// Streams a single contribution doc by id — used by the payment success
  /// screen to display the receipt number once the server assigns it.
  Stream<ContributionModel?> streamContribution(String id) {
    return _col.doc(id).snapshots().map(
        (d) => d.exists ? ContributionModel.fromFirestore(d) : null);
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
    unawaited(_col.doc(contributionId).update({
      'validatedBy': validatorId,
      // If no second validation is required, confirm immediately.
      // The second-validator requirement is handled by secondValidatePayment.
    }));
  }

  /// Second validation: confirms the payment after dual-approval.
  Future<void> secondValidatePayment(
      String contributionId, String validatorId) async {
    final snap = await _col.doc(contributionId).get();
    final data = snap.data() as Map<String, dynamic>?;
    final memberId = data?['memberId'] as String?;
    final amount = (data?['amount'] as num?)?.toInt() ?? 0;

    unawaited(_col.doc(contributionId).update({
      'secondValidatorId': validatorId,
      'status': AppConstants.statusConfirmed,
      'confirmedAt': Timestamp.now(),
    }));

    if (memberId != null && amount > 0) {
      unawaited(_db
          .collection(AppConstants.usersCollection)
          .doc(memberId)
          .update({'totalContributed': FieldValue.increment(amount)}));
      unawaited(_db
          .collection(AppConstants.countersCollection)
          .doc('platform')
          .set({'totalContributed': FieldValue.increment(amount)},
              SetOptions(merge: true)));
    }
  }

  /// Single-step approval for bank transfers: confirms and credits totals in
  /// one action (no second validator). Mirrors secondValidatePayment's effect.
  Future<void> confirmContribution(
      String contributionId, String adminId) async {
    final snap = await _col.doc(contributionId).get();
    final data = snap.data() as Map<String, dynamic>?;
    final memberId = data?['memberId'] as String?;
    final amount = (data?['amount'] as num?)?.toInt() ?? 0;

    unawaited(_col.doc(contributionId).update({
      'validatedBy': adminId,
      'status': AppConstants.statusConfirmed,
      'confirmedAt': Timestamp.now(),
    }));

    if (memberId != null && memberId.isNotEmpty && amount > 0) {
      unawaited(_db
          .collection(AppConstants.usersCollection)
          .doc(memberId)
          .update({'totalContributed': FieldValue.increment(amount)}));
      unawaited(_db
          .collection(AppConstants.countersCollection)
          .doc('platform')
          .set({'totalContributed': FieldValue.increment(amount)},
              SetOptions(merge: true)));
    }
  }

  Future<void> rejectPayment(
      String contributionId, String adminId, String reason) async {
    unawaited(_col.doc(contributionId).update({
      'status': AppConstants.statusFailed,
      'validatedBy': adminId,
      'notes': reason,
    }));
  }

  // ── Proof of transfer ─────────────────────────────────────

  /// Uploads a proof-of-transfer image and returns its download URL.
  /// Uses putData (not putFile) so it works on Web as well as Android.
  Future<String> uploadProof(XFile file, String uid) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final ref = FirebaseStorage.instance.ref('receipts/$uid/$stamp.jpg');
    await ref.putData(
      await file.readAsBytes(),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return ref.getDownloadURL();
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

  /// Admin-only: recomputes the platform contribution total from ground truth.
  /// Sets counters/platform.totalContributed only.
  ///
  /// Deliberately does NOT touch counters/members.count: that counter is the
  /// matricule sequence (see AuthRepository.generateMemberNumber) and must only
  /// ever move forward. Resetting it here to the live member-doc count moved it
  /// *backward* whenever a member was promoted to staff or a doc was deleted,
  /// which made new signups re-issue matricules already in use. The displayed
  /// member total now counts user documents directly, so this no longer needs
  /// to write that counter. To repair the sequence + existing duplicates, use
  /// the repairMemberNumbers Cloud Function (Admin → Audit screen).
  ///
  /// Uses getDocs() instead of aggregate queries because Firestore blocks
  /// count()/sum() when security rules reference get() for role checks.
  Future<({int members, double total})> backfillPlatformCounters() async {
    final usersSnap =
        await _db.collection(AppConstants.usersCollection).get();
    final memberCount = usersSnap.docs.length;

    final contribSnap = await _db
        .collection(AppConstants.contributionsCollection)
        .where('status', isEqualTo: AppConstants.statusConfirmed)
        .get();
    final totalContributed = contribSnap.docs.fold<double>(
      0.0,
      (acc, doc) =>
          acc + ((doc.data()['amount'] as num?)?.toDouble() ?? 0.0),
    );

    await _db
        .collection(AppConstants.countersCollection)
        .doc('platform')
        .set({'totalContributed': totalContributed});

    return (members: memberCount, total: totalContributed);
  }
}
