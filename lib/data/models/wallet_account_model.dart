import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';

class WalletAccountModel {
  final String id;
  final String name;
  final String type;       // mobile_money | bank | cash | other
  final String currency;   // default XAF
  final int openingBalance;
  final int currentBalance;
  final String color;      // '#rrggbb'
  final bool archived;
  final String? region;    // one of AppConstants.cameroonRegions, null = global
  final String createdBy;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const WalletAccountModel({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    required this.openingBalance,
    required this.currentBalance,
    required this.color,
    required this.archived,
    this.region,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WalletAccountModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WalletAccountModel(
      id: doc.id,
      name: d['name'] as String? ?? '',
      type: d['type'] as String? ?? AppConstants.walletTypeCash,
      currency: d['currency'] as String? ?? AppConstants.defaultCurrency,
      openingBalance: (d['opening_balance'] as num?)?.toInt() ?? 0,
      currentBalance: (d['current_balance'] as num?)?.toInt() ?? 0,
      color: d['color'] as String? ?? '#16a34a',
      archived: d['archived'] as bool? ?? false,
      region: d['region'] as String?,
      createdBy: d['created_by'] as String? ?? '',
      createdAt: d['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: d['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'type': type,
        'currency': currency,
        'opening_balance': openingBalance,
        'current_balance': currentBalance,
        'color': color,
        'archived': archived,
        'region': region,
        'created_by': createdBy,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  WalletAccountModel copyWith({
    String? id,
    String? name,
    String? type,
    String? currency,
    int? openingBalance,
    int? currentBalance,
    String? color,
    bool? archived,
    Object? region = _sentinel,
    String? createdBy,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return WalletAccountModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      currency: currency ?? this.currency,
      openingBalance: openingBalance ?? this.openingBalance,
      currentBalance: currentBalance ?? this.currentBalance,
      color: color ?? this.color,
      archived: archived ?? this.archived,
      region: region == _sentinel ? this.region : region as String?,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ── Computed ──────────────────────────────────────────────────

  Color get accentColor {
    try {
      final hex = color.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF16a34a);
    }
  }

  bool get isMobileMoney => type == AppConstants.walletTypeMobileMoney;
  bool get isBank => type == AppConstants.walletTypeBank;
  bool get isCash => type == AppConstants.walletTypeCash;
  bool get isRegional => region != null && region!.isNotEmpty;
}

// Sentinel value to distinguish "not provided" from explicit null in copyWith
const Object _sentinel = Object();
