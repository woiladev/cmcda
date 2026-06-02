import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';

class UserModel {
  final String id;
  final String firstName;
  final String lastName;
  final String phone;
  final String? email;
  final String region;
  final String department;
  final String role;
  final String memberNumber;
  final String status;
  final String? avatarUrl;
  final String? city;
  final String? quarter;
  final String? focalZone;
  final List<String> fcmTokens;
  final String preferredPayment;
  final String preferredFrequency;
  final String language;
  final int totalContributed;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const UserModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    this.email,
    required this.region,
    required this.department,
    required this.role,
    required this.memberNumber,
    required this.status,
    this.city,
    this.quarter,
    this.avatarUrl,
    this.focalZone,
    this.fcmTokens = const [],
    required this.preferredPayment,
    required this.preferredFrequency,
    required this.language,
    this.totalContributed = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      firstName: d['firstName'] as String? ?? '',
      lastName: d['lastName'] as String? ?? '',
      phone: d['phone'] as String? ?? '',
      email: d['email'] as String?,
      region: d['region'] as String? ?? '',
      department: d['department'] as String? ?? '',
      role: d['role'] as String? ?? AppConstants.roleMember,
      memberNumber: d['memberNumber'] as String? ?? '',
      status: d['status'] as String? ?? AppConstants.userStatusActive,
      avatarUrl: d['avatarUrl'] as String?,
      city: d['city'] as String?,
      quarter: d['quarter'] as String?,
      focalZone: d['focalZone'] as String?,
      fcmTokens: _parseTokens(d),
      preferredPayment: d['preferredPayment'] as String? ?? AppConstants.paymentMtnMomo,
      preferredFrequency: d['preferredFrequency'] as String? ?? AppConstants.periodMonthly,
      language: d['language'] as String? ?? AppConstants.defaultLocale,
      totalContributed: (d['totalContributed'] as num?)?.toInt() ?? 0,
      createdAt: d['createdAt'] as Timestamp? ?? Timestamp.now(),
      updatedAt: d['updatedAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  // Reads the multi-device token array, falling back to the legacy single
  // `fcmToken` string for user docs written before the array migration.
  static List<String> _parseTokens(Map<String, dynamic> d) {
    final raw = d['fcmTokens'];
    if (raw is List) {
      return raw.whereType<String>().where((t) => t.isNotEmpty).toList();
    }
    final legacy = d['fcmToken'] as String?;
    return (legacy != null && legacy.isNotEmpty) ? [legacy] : const [];
  }

  Map<String, dynamic> toFirestore() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'phone': phone,
      if (email != null) 'email': email,
      'region': region,
      'department': department,
      'role': role,
      'memberNumber': memberNumber,
      'status': status,
      if (city != null) 'city': city,
      if (quarter != null) 'quarter': quarter,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (focalZone != null) 'focalZone': focalZone,
      'fcmTokens': fcmTokens,
      'preferredPayment': preferredPayment,
      'preferredFrequency': preferredFrequency,
      'language': language,
      'totalContributed': totalContributed,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  UserModel copyWith({
    String? firstName,
    String? lastName,
    String? phone,
    String? email,
    String? region,
    String? department,
    String? role,
    String? memberNumber,
    String? status,
    String? city,
    String? quarter,
    String? avatarUrl,
    String? focalZone,
    List<String>? fcmTokens,
    String? preferredPayment,
    String? preferredFrequency,
    String? language,
    int? totalContributed,
    Timestamp? updatedAt,
  }) {
    return UserModel(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      region: region ?? this.region,
      department: department ?? this.department,
      role: role ?? this.role,
      memberNumber: memberNumber ?? this.memberNumber,
      status: status ?? this.status,
      city: city ?? this.city,
      quarter: quarter ?? this.quarter,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      focalZone: focalZone ?? this.focalZone,
      fcmTokens: fcmTokens ?? this.fcmTokens,
      preferredPayment: preferredPayment ?? this.preferredPayment,
      preferredFrequency: preferredFrequency ?? this.preferredFrequency,
      language: language ?? this.language,
      totalContributed: totalContributed ?? this.totalContributed,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ── Computed ──────────────────────────────────────────────

  String get fullName => '$firstName $lastName';

  String get initials {
    final f = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    final l = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    return '$f$l';
  }

  bool get isActive => status == AppConstants.userStatusActive;
  bool get isMember => role == AppConstants.roleMember;
  bool get isFocal => role == AppConstants.roleFocal;
  bool get isAdmin => role == AppConstants.roleAdmin;
  bool get isSuperAdmin => role == AppConstants.roleSuperAdmin;
  bool get hasAdminAccess => isAdmin || isSuperAdmin;
  bool get isSuperContributor => totalContributed >= AppConstants.amountAnnual;
}
