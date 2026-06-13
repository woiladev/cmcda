import 'package:cloud_functions/cloud_functions.dart';

/// Thin wrapper over the direct MTN MoMo Collection Cloud Functions. The MTN
/// API credentials are secret and never reach the client, so every call goes
/// through a callable. Mirrors [PawaPayRepository] so the mobile-money payment
/// sheets can branch on the selected provider: MTN deposits go DIRECT through
/// MTN's Collection API (here), while Orange keeps using pawaPay.
///
/// Deposits are async (push-USSD PIN prompt): [initiateDeposit] creates the
/// contribution (pending) and prompts the payer; the contribution flips to
/// confirmed/failed via the server-side `momoWebhook` (MTN's one-shot callback
/// to api.cmcda.org), with [checkDeposit] polling and the scheduled reconciler
/// as fallbacks. Polling stays the reliable path since MTN never retries the
/// callback — keep calling [checkDeposit] while the payment sheet is open.
class MtnMomoRepository {
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// Initiates an MTN deposit. Returns the created contribution id and the MTN
  /// referenceId. Throws [FirebaseFunctionsException] if MTN rejects the
  /// request (the stable failure token is in `e.details['failureCode']`).
  Future<({String contributionId, String referenceId, String status})>
      initiateDeposit({
    required int amount,
    required String periodType,
    required String phoneNumber,
    String? memberId,
  }) async {
    final result =
        await _functions.httpsCallable('initiateMtnMomoDeposit').call<dynamic>({
      'amount': amount,
      'periodType': periodType,
      'phoneNumber': phoneNumber,
      if (memberId != null) 'memberId': memberId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return (
      contributionId: data['contributionId'] as String? ?? '',
      referenceId: data['referenceId'] as String? ?? '',
      status: data['status'] as String? ?? 'PENDING',
    );
  }

  /// Poll: reconciles the live MTN requesttopay status into the contribution.
  /// Returns the resulting contribution status (pending/confirmed/failed).
  Future<String> checkDeposit(String contributionId) async {
    final result =
        await _functions.httpsCallable('checkMtnMomoDeposit').call<dynamic>({
      'contributionId': contributionId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['status'] as String? ?? 'pending';
  }
}
