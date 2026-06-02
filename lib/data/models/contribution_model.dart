import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';

class ContributionModel {
  final String id;
  final String memberId;
  final String memberName;
  final String memberNumber;
  final int amount;
  final String period;      // ISO year-month: "2026-05"
  final String periodType;  // daily / monthly / annual / custom
  final String paymentMethod;
  final String status;
  final String receiptNumber;
  final String recordedBy;    // UID of who recorded
  final String? validatedBy;  // UID of first validator
  final String? secondValidatorId;
  final String? paidForId;    // member ID if paying on behalf of another
  final String? focalReportId;
  final String? notes;
  final String? proofUrl; // proof-of-transfer image (bank transfers)
  final String? depositId; // pawaPay deposit id (mobile money via gateway)
  final String? pawaPayStatus; // last raw pawaPay status (ACCEPTED/COMPLETED/…)
  final String? pawaPayProvider; // MTN_MOMO_CMR / ORANGE_CMR
  final String? payerPhone; // MSISDN used for the deposit
  final bool validationRequired; // cash/bank always require validation
  final Timestamp createdAt;
  final Timestamp? confirmedAt;

  const ContributionModel({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.memberNumber,
    required this.amount,
    required this.period,
    required this.periodType,
    required this.paymentMethod,
    required this.status,
    required this.receiptNumber,
    required this.recordedBy,
    this.validatedBy,
    this.secondValidatorId,
    this.paidForId,
    this.focalReportId,
    this.notes,
    this.proofUrl,
    this.depositId,
    this.pawaPayStatus,
    this.pawaPayProvider,
    this.payerPhone,
    required this.validationRequired,
    required this.createdAt,
    this.confirmedAt,
  });

  factory ContributionModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ContributionModel(
      id: doc.id,
      memberId: d['memberId'] as String? ?? '',
      memberName: d['memberName'] as String? ?? '',
      memberNumber: d['memberNumber'] as String? ?? '',
      amount: (d['amount'] as num?)?.toInt() ?? 0,
      period: d['period'] as String? ?? '',
      periodType: d['periodType'] as String? ?? AppConstants.periodMonthly,
      paymentMethod: d['paymentMethod'] as String? ?? AppConstants.paymentMtnMomo,
      status: d['status'] as String? ?? AppConstants.statusPending,
      receiptNumber: d['receiptNumber'] as String? ?? '',
      recordedBy: d['recordedBy'] as String? ?? '',
      validatedBy: d['validatedBy'] as String?,
      secondValidatorId: d['secondValidatorId'] as String?,
      paidForId: d['paidForId'] as String?,
      focalReportId: d['focalReportId'] as String?,
      notes: d['notes'] as String?,
      proofUrl: d['proofUrl'] as String?,
      depositId: d['depositId'] as String?,
      pawaPayStatus: d['pawaPayStatus'] as String?,
      pawaPayProvider: d['pawaPayProvider'] as String?,
      payerPhone: d['payerPhone'] as String?,
      validationRequired: d['validationRequired'] as bool? ?? false,
      createdAt: d['createdAt'] as Timestamp? ?? Timestamp.now(),
      confirmedAt: d['confirmedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'memberId': memberId,
      'memberName': memberName,
      'memberNumber': memberNumber,
      'amount': amount,
      'period': period,
      'periodType': periodType,
      'paymentMethod': paymentMethod,
      'status': status,
      'receiptNumber': receiptNumber,
      'recordedBy': recordedBy,
      if (validatedBy != null) 'validatedBy': validatedBy,
      if (secondValidatorId != null) 'secondValidatorId': secondValidatorId,
      if (paidForId != null) 'paidForId': paidForId,
      if (focalReportId != null) 'focalReportId': focalReportId,
      if (notes != null) 'notes': notes,
      if (proofUrl != null) 'proofUrl': proofUrl,
      if (depositId != null) 'depositId': depositId,
      if (pawaPayStatus != null) 'pawaPayStatus': pawaPayStatus,
      if (pawaPayProvider != null) 'pawaPayProvider': pawaPayProvider,
      if (payerPhone != null) 'payerPhone': payerPhone,
      'validationRequired': validationRequired,
      'createdAt': createdAt,
      if (confirmedAt != null) 'confirmedAt': confirmedAt,
    };
  }

  ContributionModel copyWith({
    String? status,
    String? validatedBy,
    String? secondValidatorId,
    String? focalReportId,
    String? notes,
    String? proofUrl,
    Timestamp? confirmedAt,
  }) {
    return ContributionModel(
      id: id,
      memberId: memberId,
      memberName: memberName,
      memberNumber: memberNumber,
      amount: amount,
      period: period,
      periodType: periodType,
      paymentMethod: paymentMethod,
      status: status ?? this.status,
      receiptNumber: receiptNumber,
      recordedBy: recordedBy,
      validatedBy: validatedBy ?? this.validatedBy,
      secondValidatorId: secondValidatorId ?? this.secondValidatorId,
      paidForId: paidForId,
      focalReportId: focalReportId ?? this.focalReportId,
      notes: notes ?? this.notes,
      proofUrl: proofUrl ?? this.proofUrl,
      depositId: depositId,
      pawaPayStatus: pawaPayStatus,
      pawaPayProvider: pawaPayProvider,
      payerPhone: payerPhone,
      validationRequired: validationRequired,
      createdAt: createdAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
    );
  }

  // ── Computed ──────────────────────────────────────────────

  bool get isConfirmed => status == AppConstants.statusConfirmed;
  bool get isPending => status == AppConstants.statusPending;
  bool get isFailed => status == AppConstants.statusFailed;
  bool get isCash => paymentMethod == AppConstants.paymentCash;
  bool get isBankTransfer => paymentMethod == AppConstants.paymentBankTransfer;
  bool get isMobileMoney =>
      paymentMethod == AppConstants.paymentMtnMomo ||
      paymentMethod == AppConstants.paymentOrangeMoney;
  bool get isManual => isCash || isBankTransfer;
  bool get needsSecondValidation => validatedBy != null && secondValidatorId == null && validationRequired;
}
