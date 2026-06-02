import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';

/// CMCDA bank account shown to members making a bank transfer.
/// Stored in app_config/bank_details, editable by super admins.
/// Falls back to the hardcoded constants before the doc is first saved.
class BankDetailsModel {
  final String bankName;
  final String accountNumber;
  final String accountName;
  final String instructions; // optional free text shown to members
  final Timestamp? updatedAt;
  final String? updatedBy;

  const BankDetailsModel({
    required this.bankName,
    required this.accountNumber,
    required this.accountName,
    required this.instructions,
    this.updatedAt,
    this.updatedBy,
  });

  factory BankDetailsModel.defaults() => const BankDetailsModel(
        bankName: AppConstants.bankName,
        accountNumber: AppConstants.bankAccount,
        accountName: AppConstants.orgName,
        instructions: '',
      );

  factory BankDetailsModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>?;
    if (d == null) return BankDetailsModel.defaults();
    return BankDetailsModel(
      bankName: d['bankName'] as String? ?? AppConstants.bankName,
      accountNumber: d['accountNumber'] as String? ?? AppConstants.bankAccount,
      accountName: d['accountName'] as String? ?? AppConstants.orgName,
      instructions: d['instructions'] as String? ?? '',
      updatedAt: d['updatedAt'] as Timestamp?,
      updatedBy: d['updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'bankName': bankName,
        'accountNumber': accountNumber,
        'accountName': accountName,
        'instructions': instructions,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (updatedBy != null) 'updatedBy': updatedBy,
      };
}
