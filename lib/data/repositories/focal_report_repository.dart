import 'package:cloud_firestore/cloud_firestore.dart';
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

  Future<void> validateReport(String id, String adminId) async {
    await _col.doc(id).update({
      'status': FocalReportModel.statusValidated,
      'validatedBy': adminId,
    });
  }

  Future<void> rejectReport(String id, String adminId, String reason) async {
    await _col.doc(id).update({
      'status': FocalReportModel.statusRejected,
      'validatedBy': adminId,
      'notes': reason,
    });
  }

  // ── Write ─────────────────────────────────────────────────

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
    final data = FocalReportModel(
      id: '',
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
    final doc = await _col.add(data.toFirestore());
    return doc.id;
  }

  Future<void> submitReport(String id) async {
    await _col.doc(id).update({'status': FocalReportModel.statusSubmitted});
  }

  Future<void> updateReport(String id, Map<String, dynamic> fields) async {
    await _col.doc(id).update(fields);
  }
}
