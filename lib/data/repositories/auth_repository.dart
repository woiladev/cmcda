import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../models/user_model.dart';
import '../../core/constants/app_constants.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // ── Auth State ────────────────────────────────────────────

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // ═══════════════════════════════════════════════════════════
  //  EMAIL / PASSWORD
  // ═══════════════════════════════════════════════════════════

  Future<UserModel> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
    required String region,
    required String department,
    String? city,
    String? quarter,
    String preferredPayment = AppConstants.paymentMtnMomo,
    String preferredFrequency = AppConstants.periodMonthly,
    String language = AppConstants.defaultLocale,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = credential.user!.uid;
    final memberNumber = await generateMemberNumber(region);
    final now = Timestamp.now();

    final user = UserModel(
      id: uid,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      email: email,
      region: region,
      department: department,
      city: city,
      quarter: quarter,
      role: AppConstants.roleMember,
      memberNumber: memberNumber,
      status: AppConstants.userStatusActive,
      preferredPayment: preferredPayment,
      preferredFrequency: preferredFrequency,
      language: language,
      createdAt: now,
      updatedAt: now,
    );

    await _db
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .set(user.toFirestore());

    return user;
  }

  Future<UserModel?> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (credential.user == null) return null;
    return getUserById(credential.user!.uid);
  }

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // ═══════════════════════════════════════════════════════════
  //  GOOGLE SIGN-IN
  // ═══════════════════════════════════════════════════════════

  /// Returns the existing [UserModel] if the Google account already has a
  /// Firestore profile, otherwise creates a new member profile.
  /// Returns null if the user cancels the Google picker.
  Future<UserModel?> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // user cancelled

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final firebaseUser = userCredential.user!;

    // Return existing profile if already registered
    final existing = await getUserById(firebaseUser.uid);
    if (existing != null) return existing;

    // First-time Google login — create a minimal profile.
    // The signup screen will collect region/department on next step.
    // Region unknown at this point → Cmr- prefix; number stays after region is filled.
    final memberNumber = await generateMemberNumber('');
    final now = Timestamp.now();
    final nameParts = (firebaseUser.displayName ?? '').trim().split(' ');

    final newUser = UserModel(
      id: firebaseUser.uid,
      firstName: nameParts.isNotEmpty ? nameParts.first : '',
      lastName: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '',
      phone: firebaseUser.phoneNumber ?? '',
      email: firebaseUser.email,
      region: '',
      department: '',
      role: AppConstants.roleMember,
      memberNumber: memberNumber,
      status: AppConstants.userStatusActive,
      avatarUrl: firebaseUser.photoURL,
      preferredPayment: AppConstants.paymentMtnMomo,
      preferredFrequency: AppConstants.periodMonthly,
      language: AppConstants.defaultLocale,
      createdAt: now,
      updatedAt: now,
    );

    await _db
        .collection(AppConstants.usersCollection)
        .doc(firebaseUser.uid)
        .set(newUser.toFirestore());

    return newUser;
  }

  Future<void> signOutGoogle() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // ═══════════════════════════════════════════════════════════
  //  APPLE SIGN-IN
  // ═══════════════════════════════════════════════════════════

  /// Signs in (or up) via Apple ID.
  /// Requires Apple Sign-In to be enabled in Firebase Console and
  /// [AppConstants.appleServiceId] to be filled in (Android/Web only).
  Future<UserModel?> signInWithApple() async {
    if (AppConstants.appleServiceId.isEmpty) {
      throw Exception(
        'Apple Sign-In n\'est pas encore configuré. '
        'Veuillez configurer le Service ID Apple dans AppConstants.',
      );
    }

    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
      webAuthenticationOptions: WebAuthenticationOptions(
        clientId: AppConstants.appleServiceId,
        redirectUri: Uri.parse(AppConstants.appleRedirectUri),
      ),
    );

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );

    final userCredential = await _auth.signInWithCredential(oauthCredential);
    final firebaseUser = userCredential.user!;

    final existing = await getUserById(firebaseUser.uid);
    if (existing != null) return existing;

    // Region unknown at Apple sign-in → Cmr- prefix; number stays after region is filled.
    final memberNumber = await generateMemberNumber('');
    final now = Timestamp.now();

    final newUser = UserModel(
      id: firebaseUser.uid,
      firstName: appleCredential.givenName ?? '',
      lastName: appleCredential.familyName ?? '',
      phone: '',
      email: appleCredential.email ?? firebaseUser.email,
      region: '',
      department: '',
      role: AppConstants.roleMember,
      memberNumber: memberNumber,
      status: AppConstants.userStatusActive,
      preferredPayment: AppConstants.paymentMtnMomo,
      preferredFrequency: AppConstants.periodMonthly,
      language: AppConstants.defaultLocale,
      createdAt: now,
      updatedAt: now,
    );

    await _db
        .collection(AppConstants.usersCollection)
        .doc(firebaseUser.uid)
        .set(newUser.toFirestore());

    return newUser;
  }

  // ── Apple Sign-In helpers ─────────────────────────────────

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
        length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ═══════════════════════════════════════════════════════════
  //  PHONE AUTH  (2-step: send OTP → verify OTP)
  // ═══════════════════════════════════════════════════════════

  /// Step 1 — sends an SMS OTP to [phoneNumber] (E.164 format, e.g. +237699000000).
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(FirebaseAuthException error) onFailed,
    void Function(PhoneAuthCredential credential)? onAutoVerified,
    int? resendToken,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      forceResendingToken: resendToken,
      verificationCompleted: (credential) {
        // Android auto-retrieval / instant verification
        if (onAutoVerified != null) onAutoVerified(credential);
      },
      verificationFailed: onFailed,
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (_) {},
      timeout: const Duration(seconds: 60),
    );
  }

  /// Step 2 — verifies the OTP and signs in.
  /// Creates a new member profile if this is the first login.
  Future<UserModel?> verifyOTP({
    required String verificationId,
    required String smsCode,
    String firstName = '',
    String lastName = '',
    String region = '',
    String department = '',
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final firebaseUser = userCredential.user!;

    // Return existing profile if already registered
    final existing = await getUserById(firebaseUser.uid);
    if (existing != null) return existing;

    // New user — create minimal member profile
    final memberNumber = await generateMemberNumber(region);
    final now = Timestamp.now();

    final newUser = UserModel(
      id: firebaseUser.uid,
      firstName: firstName,
      lastName: lastName,
      phone: firebaseUser.phoneNumber ?? '',
      email: firebaseUser.email,
      region: region,
      department: department,
      role: AppConstants.roleMember,
      memberNumber: memberNumber,
      status: AppConstants.userStatusActive,
      preferredPayment: AppConstants.paymentMtnMomo,
      preferredFrequency: AppConstants.periodMonthly,
      language: AppConstants.defaultLocale,
      createdAt: now,
      updatedAt: now,
    );

    await _db
        .collection(AppConstants.usersCollection)
        .doc(firebaseUser.uid)
        .set(newUser.toFirestore());

    return newUser;
  }

  // ═══════════════════════════════════════════════════════════
  //  COMMON
  // ═══════════════════════════════════════════════════════════

  Future<void> signOut() async {
    if (await _googleSignIn.isSignedIn()) await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<UserModel?> getUserById(String uid) async {
    final doc = await _db
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  Stream<UserModel?> userStream(String uid) {
    return _db
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? UserModel.fromFirestore(doc) : null);
  }

  Future<void> updateProfile(String userId, Map<String, dynamic> fields) async {
    await _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .update({...fields, 'updatedAt': Timestamp.now()});
  }

  Future<void> updateFcmToken(String userId, String token) async {
    await updateProfile(userId, {'fcmToken': token});
  }

  Future<void> updateLanguage(String userId, String languageCode) async {
    await updateProfile(userId, {'language': languageCode});
  }

  // ── Member Number ────────────────────────────────────────

  /// Atomically increments the global member counter and returns the member number.
  /// Format: Yde-000011 — region prefix + global platform position.
  /// Counter doc: counters/members (single global counter).
  Future<String> generateMemberNumber(String region) async {
    final prefix = AppConstants.regionMemberPrefixes[region]
        ?? AppConstants.memberPrefixFallback;
    final counterRef = _db
        .collection(AppConstants.countersCollection)
        .doc('members');

    int newCount = 0;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(counterRef);
      newCount = ((snap.data()?['count'] as num?)?.toInt() ?? 0) + 1;
      tx.set(counterRef, {'count': newCount}, SetOptions(merge: true));
    });

    return '$prefix-${newCount.toString().padLeft(6, '0')}';
  }
}
