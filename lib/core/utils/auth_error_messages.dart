import 'package:firebase_auth/firebase_auth.dart';

import '../l10n/app_localizations.dart';

/// Maps an authentication error to a localized, user-facing message.
/// Falls back to [AppLocalizations.unknownError] for anything unrecognised,
/// so raw English Firebase strings never reach the user.
String authErrorMessage(AppLocalizations l10n, Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'wrong-password':
        return l10n.errWrongPassword;
      case 'user-not-found':
        return l10n.errUserNotFound;
      case 'email-already-in-use':
        return l10n.errEmailInUse;
      case 'weak-password':
        return l10n.errWeakPassword;
      case 'invalid-email':
        return l10n.invalidEmail;
      case 'too-many-requests':
        return l10n.errTooManyRequests;
      case 'invalid-verification-code':
        return l10n.errInvalidOtp;
      case 'user-disabled':
        return l10n.errUserDisabled;
      case 'invalid-credential':
        return l10n.errInvalidCredential;
      case 'network-request-failed':
        return l10n.networkError;
      default:
        return error.message ?? l10n.unknownError;
    }
  }
  return l10n.unknownError;
}
