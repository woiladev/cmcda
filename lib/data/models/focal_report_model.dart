import 'package:cloud_firestore/cloud_firestore.dart';

class FocalReportModel {
  final String id;
  final String focalId;
  final String focalName;
  final String location;
  final Timestamp reportDate;
  final int totalCollected;
  final int membersServed;
  final int newMembersCount;
  final String status; // draft / submitted / validated / rejected
  final String? validatedBy;
  final String? notes;
  final List<String> contributionIds;
  final Timestamp createdAt;

  // ── Status constants ──────────────────────────────────────
  static const String statusDraft = 'draft';
  static const String statusSubmitted = 'submitted';
  static const String statusValidated = 'validated';
  static const String statusRejected = 'rejected';

  const FocalReportModel({
    required this.id,
    required this.focalId,
    required this.focalName,
    required this.location,
    required this.reportDate,
    required this.totalCollected,
    required this.membersServed,
    required this.newMembersCount,
    required this.status,
    this.validatedBy,
    this.notes,
    required this.contributionIds,
    required this.createdAt,
  });

  factory FocalReportModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return FocalReportModel(
      id: doc.id,
      focalId: d['focalId'] as String? ?? '',
      focalName: d['focalName'] as String? ?? '',
      location: d['location'] as String? ?? '',
      reportDate: d['reportDate'] as Timestamp? ?? Timestamp.now(),
      totalCollected: (d['totalCollected'] as num?)?.toInt() ?? 0,
      membersServed: (d['membersServed'] as num?)?.toInt() ?? 0,
      newMembersCount: (d['newMembersCount'] as num?)?.toInt() ?? 0,
      status: d['status'] as String? ?? statusDraft,
      validatedBy: d['validatedBy'] as String?,
      notes: d['notes'] as String?,
      contributionIds: List<String>.from(d['contributionIds'] as List? ?? []),
      createdAt: d['createdAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'focalId': focalId,
      'focalName': focalName,
      'location': location,
      'reportDate': reportDate,
      'totalCollected': totalCollected,
      'membersServed': membersServed,
      'newMembersCount': newMembersCount,
      'status': status,
      if (validatedBy != null) 'validatedBy': validatedBy,
      if (notes != null) 'notes': notes,
      'contributionIds': contributionIds,
      'createdAt': createdAt,
    };
  }

  FocalReportModel copyWith({
    String? status,
    String? validatedBy,
    String? notes,
    int? totalCollected,
    int? membersServed,
    int? newMembersCount,
    List<String>? contributionIds,
  }) {
    return FocalReportModel(
      id: id,
      focalId: focalId,
      focalName: focalName,
      location: location,
      reportDate: reportDate,
      totalCollected: totalCollected ?? this.totalCollected,
      membersServed: membersServed ?? this.membersServed,
      newMembersCount: newMembersCount ?? this.newMembersCount,
      status: status ?? this.status,
      validatedBy: validatedBy ?? this.validatedBy,
      notes: notes ?? this.notes,
      contributionIds: contributionIds ?? this.contributionIds,
      createdAt: createdAt,
    );
  }

  // ── Computed ──────────────────────────────────────────────

  bool get isDraft => status == statusDraft;
  bool get isSubmitted => status == statusSubmitted;
  bool get isValidated => status == statusValidated;
  bool get isRejected => status == statusRejected;
}
