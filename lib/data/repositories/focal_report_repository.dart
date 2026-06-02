import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/focal_report_model.dart';
import '../../core/constants/app_constants.dart';

class FocalReportRepository {
  final _col = FirebaseFirestore.instance
      .collection(AppConstants.focalReportsCollection);

  // ── Read ──────────────────────────────────────────────────

  Stream<List<FocalReportModel>> streamMyReports(String focalId) {
    return _col
        .where('focalId', isEqualTo: focalId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => FocalReportModel.fromFirestore(d)).toList());
  }

  Stream<List<FocalReportModel>> streamAllReports() {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => FocalReportModel.fromFirestore(d)).toList());
  }

  /// Accepts a focal report via the super-admin-gated Cloud Function, which
  /// confirms all of its still-pending cash contributions (crediting the
  /// wallets via the onContributionConfirmed trigger). Returns
  /// `{ confirmed: int, total: int }`.
  Future<({int confirmed, int total})> validateReport(String id) async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('validateFocalReport');
    final res = await callable.call<dynamic>({'reportId': id});
    final data = Map<String, dynamic>.from(res.data as Map);
    return (
      confirmed: (data['confirmed'] as num?)?.toInt() ?? 0,
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// Rejects a focal report via the super-admin-gated Cloud Function, which
  /// also fails the report's still-pending contributions.
  Future<void> rejectReport(String id, String reason) async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('rejectFocalReport');
    await callable.call<dynamic>({'reportId': id, 'reason': reason});
  }

  // ── Write ─────────────────────────────────────────────────

  /// Offline-safe: the doc id is generated locally and the write is
  /// fire-and-forget, so a focal officer can finalize a field session with no
  /// connection. The report (and its linked contributions) sync on reconnect.
  Future<String> createReport({
    required String focalId,
    required String focalName,
    required String location,
    required DateTime reportDate,
    required int totalCollected,
    required int membersServed,
    required int newMembersCount,
    String? notes,
  }) async {
    final now = Timestamp.now();
    final ref = _col.doc(); // local id, no network round-trip
    final data = FocalReportModel(
      id: ref.id,
      focalId: focalId,
      focalName: focalName,
      location: location,
      reportDate: Timestamp.fromDate(reportDate),
      totalCollected: totalCollected,
      membersServed: membersServed,
      newMembersCount: newMembersCount,
      status: FocalReportModel.statusDraft,
      contributionIds: [],
      createdAt: now,
      notes: notes?.isNotEmpty == true ? notes : null,
    );
    unawaited(ref.set(data.toFirestore()));
    return ref.id;
  }

  Future<void> submitReport(String id) async {
    unawaited(
        _col.doc(id).update({'status': FocalReportModel.statusSubmitted}));
  }

  Future<void> updateReport(String id, Map<String, dynamic> fields) async {
    unawaited(_col.doc(id).update(fields));
  }
}
