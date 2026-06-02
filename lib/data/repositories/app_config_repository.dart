import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bank_details_model.dart';
import '../../core/constants/app_constants.dart';

class AppConfigRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference get _bankDoc => _db
      .collection(AppConstants.appConfigCollection)
      .doc(AppConstants.bankDetailsDoc);

  Stream<BankDetailsModel> streamBankDetails() {
    return _bankDoc.snapshots().map(
          (d) => d.exists
              ? BankDetailsModel.fromFirestore(d)
              : BankDetailsModel.defaults(),
        );
  }

  Future<void> updateBankDetails({
    required String bankName,
    required String accountNumber,
    required String accountName,
    required String instructions,
    required String updatedBy,
  }) async {
    await _bankDoc.set({
      'bankName': bankName,
      'accountNumber': accountNumber,
      'accountName': accountName,
      'instructions': instructions,
      'updatedAt': Timestamp.now(),
      'updatedBy': updatedBy,
    }, SetOptions(merge: true));
  }
}

final bankDetailsProvider = StreamProvider<BankDetailsModel>((ref) {
  return AppConfigRepository().streamBankDetails();
});
