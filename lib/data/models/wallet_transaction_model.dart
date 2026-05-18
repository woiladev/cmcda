import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';

class WalletTransactionModel {
  final String id;
  final String accountId;
  final String kind;        // inflow | outflow | transfer_in | transfer_out
  final int amount;         // always positive
  final String? category;
  final String? note;
  final Timestamp occurredAt;
  final String? contributionId;
  final String? transferGroupId;
  final String createdBy;
  final Timestamp createdAt;

  const WalletTransactionModel({
    required this.id,
    required this.accountId,
    required this.kind,
    required this.amount,
    this.category,
    this.note,
    required this.occurredAt,
    this.contributionId,
    this.transferGroupId,
    required this.createdBy,
    required this.createdAt,
  });

  factory WalletTransactionModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WalletTransactionModel(
      id: doc.id,
      accountId: d['account_id'] as String? ?? '',
      kind: d['kind'] as String? ?? AppConstants.txKindInflow,
      amount: (d['amount'] as num?)?.toInt() ?? 0,
      category: d['category'] as String?,
      note: d['note'] as String?,
      occurredAt: d['occurred_at'] as Timestamp? ?? Timestamp.now(),
      contributionId: d['contribution_id'] as String?,
      transferGroupId: d['transfer_group_id'] as String?,
      createdBy: d['created_by'] as String? ?? '',
      createdAt: d['created_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'account_id': accountId,
        'kind': kind,
        'amount': amount,
        'category': category,
        'note': note,
        'occurred_at': occurredAt,
        'contribution_id': contributionId,
        'transfer_group_id': transferGroupId,
        'created_by': createdBy,
        'created_at': createdAt,
      };

  WalletTransactionModel copyWith({
    String? id,
    String? accountId,
    String? kind,
    int? amount,
    String? category,
    String? note,
    Timestamp? occurredAt,
    String? contributionId,
    String? transferGroupId,
    String? createdBy,
    Timestamp? createdAt,
  }) {
    return WalletTransactionModel(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      kind: kind ?? this.kind,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      note: note ?? this.note,
      occurredAt: occurredAt ?? this.occurredAt,
      contributionId: contributionId ?? this.contributionId,
      transferGroupId: transferGroupId ?? this.transferGroupId,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ── Computed ──────────────────────────────────────────────────

  bool get isInflow =>
      kind == AppConstants.txKindInflow ||
      kind == AppConstants.txKindTransferIn;

  bool get isOutflow =>
      kind == AppConstants.txKindOutflow ||
      kind == AppConstants.txKindTransferOut;

  bool get isTransfer => transferGroupId != null;

  int get signedAmount => isInflow ? amount : -amount;
}
