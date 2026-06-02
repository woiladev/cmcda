import 'package:cloud_functions/cloud_functions.dart';

/// Thin wrapper over the pawaPay Cloud Functions. The pawaPay API token is
/// secret and never reaches the client, so every call goes through a callable.
/// Mobile-money deposits are async: [initiateDeposit] creates the contribution
/// (pending) and pushes a PIN prompt to the payer's phone; the contribution
/// flips to confirmed/failed via the pawaPayWebhook callback or [checkDeposit].
class PawaPayRepository {
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// Initiates a deposit. Returns the created contribution id and depositId.
  /// Throws [FirebaseFunctionsException] if pawaPay rejects the request.
  Future<({String contributionId, String depositId, String status})>
      initiateDeposit({
    required int amount,
    required String periodType,
    required String phoneNumber,
    required String provider,
    String? memberId,
  }) async {
    final result =
        await _functions.httpsCallable('initiatePawaPayDeposit').call<dynamic>({
      'amount': amount,
      'periodType': periodType,
      'phoneNumber': phoneNumber,
      'provider': provider,
      if (memberId != null) 'memberId': memberId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return (
      contributionId: data['contributionId'] as String? ?? '',
      depositId: data['depositId'] as String? ?? '',
      status: data['status'] as String? ?? 'ACCEPTED',
    );
  }

  /// Poll fallback: reconciles the live pawaPay status into the contribution.
  /// Returns the resulting contribution status (pending/confirmed/failed).
  Future<String> checkDeposit(String contributionId) async {
    final result =
        await _functions.httpsCallable('checkPawaPayDeposit').call<dynamic>({
      'contributionId': contributionId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['status'] as String? ?? 'pending';
  }

  /// Predicts the mobile-money provider for a phone number. Returns the pawaPay
  /// provider code (e.g. MTN_MOMO_CMR) or an empty string if unknown.
  Future<String> predictProvider(String phoneNumber) async {
    final result =
        await _functions.httpsCallable('predictPawaPayProvider').call<dynamic>({
      'phoneNumber': phoneNumber,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['provider'] as String? ?? '';
  }
}
