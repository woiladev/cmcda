import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../models/user_model.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/notification_service.dart';
import 'reminder_plan_repository.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final ReminderPlanRepository _reminderPlans = ReminderPlanRepository();

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

    await _reminderPlans.upsertForMember(uid, preferredFrequency);

    // Register the FCM token now the doc exists — the authStateChanges save
    // fired before createUserWithEmailAndPassword's doc was written.
    await NotificationService.instance.registerToken(uid);

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

    // New Google user — return null so CompleteProfileScreen collects region
    // and generates the correct region-prefixed member number.
    return null;
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

    // New Apple user — return null so CompleteProfileScreen collects region
    // and generates the correct region-prefixed member number.
    return null;
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

    // New phone user — return null so CompleteProfileScreen collects region
    // and generates the correct region-prefixed member number.
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  //  COMMON
  // ═══════════════════════════════════════════════════════════

  Future<void> signOut() async {
    await NotificationService.instance.removeTokenOnSignOut();
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

  /// Assigns [role] to [uid] via the super-admin-gated Cloud Function, which
  /// updates the Firestore doc, the auth custom claim, and the audit log.
  /// Must be called by a super_admin; throws [FirebaseFunctionsException] otherwise.
  Future<void> setUserRole(String uid, String role) async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('setUserRole');
    await callable.call<dynamic>({'uid': uid, 'role': role});
  }

  /// Repairs the matricule namespace via the super-admin-gated Cloud Function:
  /// reassigns empty/duplicate member numbers and reseeds the sequence counter
  /// so future signups never collide. Returns how many docs were scanned and
  /// repaired, plus the new counter high-water mark.
  /// Must be called by a super_admin; throws [FirebaseFunctionsException] otherwise.
  Future<({int scanned, int repaired, int counter})>
      repairMemberNumbers() async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('repairMemberNumbers');
    final result = await callable.call<dynamic>();
    final data = Map<String, dynamic>.from(result.data as Map);
    return (
      scanned: (data['scanned'] as num?)?.toInt() ?? 0,
      repaired: (data['repaired'] as num?)?.toInt() ?? 0,
      counter: (data['counter'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> updateFcmToken(String userId, String token) async {
    await _db.collection(AppConstants.usersCollection).doc(userId).update({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> updateLanguage(String userId, String languageCode) async {
    await updateProfile(userId, {'language': languageCode});
  }

  // ── Complete Profile (social / phone sign-up) ────────────

  /// Called from CompleteProfileScreen after Google, Apple, or phone OTP
  /// auth for new users. Generates the member number using the correct
  /// region prefix and writes the full Firestore user document.
  Future<UserModel> completeProfile({
    required String uid,
    required String firstName,
    required String lastName,
    required String phone,
    required String region,
    required String department,
    String? city,
    String? quarter,
    String? email,
    String? avatarUrl,
    String preferredPayment = AppConstants.paymentMtnMomo,
    String preferredFrequency = AppConstants.periodMonthly,
    String language = AppConstants.defaultLocale,
  }) async {
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
      avatarUrl: avatarUrl,
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

    await _reminderPlans.upsertForMember(uid, preferredFrequency);

    // Register the FCM token now the doc exists — for Google/Apple/Phone
    // sign-ups the authStateChanges save fired before this doc was written.
    await NotificationService.instance.registerToken(uid);

    return user;
  }

  // ── Register member by focal officer ─────────────────────

  /// Creates a Firestore user doc for a member registered on the spot during
  /// a focal session. The member has no Firebase Auth account yet — the doc
  /// is created with a Firestore-auto ID. Matricule is generated atomically
  /// using the same counter as self-signups, so numbering stays consistent
  /// across all entry paths.
  Future<UserModel> registerMemberByFocal({
    required String firstName,
    required String lastName,
    required String phone,
    required String region,
    required String department,
    String? city,
    String? quarter,
    required String focalId,
  }) async {
    final docRef = _db.collection(AppConstants.usersCollection).doc();
    final memberNumber = await generateMemberNumber(region);
    final now = Timestamp.now();

    final user = UserModel(
      id: docRef.id,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      region: region,
      department: department,
      city: city,
      quarter: quarter,
      role: AppConstants.roleMember,
      memberNumber: memberNumber,
      status: AppConstants.userStatusActive,
      preferredPayment: AppConstants.paymentCash,
      preferredFrequency: AppConstants.periodMonthly,
      language: AppConstants.defaultLocale,
      createdAt: now,
      updatedAt: now,
    );

    await docRef.set({
      ...user.toFirestore(),
      'registeredByFocalId': focalId,
    });

    await _reminderPlans.upsertForMember(docRef.id, AppConstants.periodMonthly);

    return user;
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
