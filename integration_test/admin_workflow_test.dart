// End-to-end admin payment workflow, driven against LIVE Firebase using the
// super_admin session already persisted on this device.
//
// It exercises the exact ContributionRepository methods the admin payment
// screen's buttons invoke (validatePayment / secondValidatePayment /
// confirmContribution / rejectPayment) and reads server state back to verify
// every transition plus the server-side triggers (onContributionCreated →
// receiptNumber, onContributionConfirmed → confirmed/rejected notifications).
//
// Self-cleaning: uses a 1 FCFA sentinel against the signed-in admin's own uid,
// then deletes the test contributions/notifications and restores totals.
//
// Run:  flutter test integration_test/admin_workflow_test.dart -d <deviceId>

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cmcda_platform/core/constants/app_constants.dart';
import 'package:cmcda_platform/data/repositories/contribution_repository.dart';
import 'package:cmcda_platform/firebase_options.dart';

const _amount = 1; // sentinel FCFA
const _serverGet = GetOptions(source: Source.server);

void _log(String m) => debugPrint('E2E> $m');

Future<void> _settle() =>
    FirebaseFirestore.instance.waitForPendingWrites();

Future<Map<String, dynamic>?> _contrib(String id) async {
  final s = await FirebaseFirestore.instance
      .collection(AppConstants.contributionsCollection)
      .doc(id)
      .get(_serverGet);
  return s.data();
}

Future<int> _userTotal(String uid) async {
  final s = await FirebaseFirestore.instance
      .collection(AppConstants.usersCollection)
      .doc(uid)
      .get(_serverGet);
  return ((s.data()?['totalContributed'] as num?) ?? 0).toInt();
}

Future<int> _platformTotal() async {
  final s = await FirebaseFirestore.instance
      .collection(AppConstants.countersCollection)
      .doc('platform')
      .get(_serverGet);
  return ((s.data()?['totalContributed'] as num?) ?? 0).toInt();
}

/// Polls a contribution doc until [test] holds, up to [tries]×[gap].
Future<Map<String, dynamic>?> _poll(
  String id,
  bool Function(Map<String, dynamic>?) test, {
  int tries = 20,
  Duration gap = const Duration(seconds: 2),
}) async {
  Map<String, dynamic>? d;
  for (var i = 0; i < tries; i++) {
    d = await _contrib(id);
    if (test(d)) return d;
    await Future.delayed(gap);
  }
  return d;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('admin payment workflow end-to-end', (tester) async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
    }

    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    expect(user, isNotNull,
        reason:
            'No persisted session on this device. Log in as super_admin in the '
            'app first, then re-run on the SAME device/build.');
    final uid = user!.uid;
    _log('signed-in uid: $uid');

    final db = FirebaseFirestore.instance;
    final profile =
        (await db.collection(AppConstants.usersCollection).doc(uid).get(_serverGet))
            .data();
    expect(profile, isNotNull, reason: 'No users/$uid doc.');
    _log('role=${profile?['role']} status=${profile?['status']}');
    expect(profile?['role'], AppConstants.roleSuperAdmin,
        reason: 'Signed-in user must be super_admin to drive approvals.');
    expect(profile?['status'], AppConstants.userStatusActive,
        reason: 'Account must be active to create contributions.');

    final repo = ContributionRepository();
    final start = Timestamp.now();
    final created = <String>[];
    var credited = 0; // total client-side credits to reverse in cleanup

    final t0 = await _userTotal(uid);
    final p0 = await _platformTotal();
    _log('baseline totalContributed=$t0 platform=$p0');

    Future<String> create(String method) async {
      final c = await repo.createContribution(
        memberId: uid,
        memberName: 'ZZ_E2E_TEST',
        memberNumber: 'ZZ-TEST',
        amount: _amount,
        periodType: AppConstants.periodMonthly,
        paymentMethod: method,
        recordedBy: uid,
      );
      created.add(c.id);
      await _settle();
      return c.id;
    }

    try {
      // ── 1. CASH — dual validation ─────────────────────────────────
      _log('--- 1. cash dual-validation ---');
      final c1 = await create(AppConstants.paymentCash);
      var d = await _contrib(c1);
      expect(d?['status'], AppConstants.statusPending);
      expect(d?['validationRequired'], true);
      _log('cash created $c1 status=${d?['status']}');

      final r1 = await _poll(
          c1, (x) => ((x?['receiptNumber'] as String?) ?? '').isNotEmpty);
      final receipt1 = (r1?['receiptNumber'] as String?) ?? '';
      _log('receiptNumber (server) = "${receipt1.isEmpty ? '<none>' : receipt1}"');

      await repo.validatePayment(c1, uid);
      await _settle();
      d = await _contrib(c1);
      expect(d?['validatedBy'], uid);
      expect(d?['status'], AppConstants.statusPending,
          reason: 'First validation must NOT confirm.');
      _log('after first validation: validatedBy set, status=${d?['status']}');

      await repo.secondValidatePayment(c1, uid);
      credited += _amount;
      await _settle();
      d = await _contrib(c1);
      expect(d?['status'], AppConstants.statusConfirmed);
      expect(d?['secondValidatorId'], uid);
      expect(d?['confirmedAt'], isNotNull);
      _log('after second validation: status=${d?['status']} confirmedAt set');

      expect(await _userTotal(uid), t0 + _amount,
          reason: 'member total must be credited once on confirm.');
      expect(await _platformTotal(), p0 + _amount,
          reason: 'platform total must be credited once on confirm.');
      _log('totals credited +$_amount (member & platform)');

      final n1 = await _notif(db, uid, start, 'payment_confirmed');
      _log('payment_confirmed notification: ${n1 ? 'CREATED' : 'NOT seen'}');

      // ── 2. BANK — single-step approval ────────────────────────────
      _log('--- 2. bank single-step ---');
      final t1 = await _userTotal(uid);
      final p1 = await _platformTotal();
      final c2 = await create(AppConstants.paymentBankTransfer);
      d = await _contrib(c2);
      expect(d?['status'], AppConstants.statusPending);
      _log('bank created $c2 status=${d?['status']}');

      await repo.confirmContribution(c2, uid);
      credited += _amount;
      await _settle();
      d = await _contrib(c2);
      expect(d?['status'], AppConstants.statusConfirmed);
      expect(d?['validatedBy'], uid);
      expect(d?['confirmedAt'], isNotNull);
      expect(d?['secondValidatorId'], isNull,
          reason: 'bank approval is single-step, no second validator.');
      _log('after confirm: status=${d?['status']} (single-step)');

      expect(await _userTotal(uid), t1 + _amount);
      expect(await _platformTotal(), p1 + _amount);
      _log('totals credited +$_amount');

      // ── 3. REJECT ─────────────────────────────────────────────────
      _log('--- 3. reject ---');
      final t2 = await _userTotal(uid);
      final p2 = await _platformTotal();
      final c3 = await create(AppConstants.paymentCash);
      await repo.rejectPayment(c3, uid, 'E2E test reject');
      await _settle();
      d = await _contrib(c3);
      expect(d?['status'], AppConstants.statusFailed);
      expect(d?['notes'], 'E2E test reject');
      expect(d?['validatedBy'], uid);
      _log('after reject: status=${d?['status']} notes="${d?['notes']}"');

      expect(await _userTotal(uid), t2,
          reason: 'reject must NOT credit member total.');
      expect(await _platformTotal(), p2,
          reason: 'reject must NOT credit platform total.');
      _log('totals unchanged on reject (correct)');

      final n3 = await _notif(db, uid, start, 'payment_rejected');
      _log('payment_rejected notification: ${n3 ? 'CREATED' : 'NOT seen'}');

      _log('ALL ASSERTIONS PASSED');
    } finally {
      // ── Cleanup ─────────────────────────────────────────────────
      _log('--- cleanup ---');
      for (final id in created) {
        try {
          await db
              .collection(AppConstants.contributionsCollection)
              .doc(id)
              .delete();
        } catch (e) {
          _log('cleanup: could not delete contribution $id: $e');
        }
      }
      // Restore exact baselines (admin branch allows arbitrary totalContributed).
      try {
        await db
            .collection(AppConstants.usersCollection)
            .doc(uid)
            .update({'totalContributed': t0});
        await db
            .collection(AppConstants.countersCollection)
            .doc('platform')
            .set({'totalContributed': p0}, SetOptions(merge: true));
        _log('restored totals to baseline (member=$t0 platform=$p0); '
            'reversed $credited credited');
      } catch (e) {
        _log('cleanup: could not restore totals: $e');
      }
      // Delete test notifications created for this uid during the run.
      try {
        final snap = await db
            .collection(AppConstants.notificationsCollection)
            .where('userId', isEqualTo: uid)
            .get(_serverGet);
        var deleted = 0;
        for (final doc in snap.docs) {
          final c = doc.data()['createdAt'];
          final type = doc.data()['type'];
          if (c is Timestamp &&
              c.compareTo(start) >= 0 &&
              (type == 'payment_confirmed' || type == 'payment_rejected')) {
            await doc.reference.delete();
            deleted++;
          }
        }
        _log('deleted $deleted test notification(s)');
      } catch (e) {
        _log('cleanup: could not delete notifications: $e');
      }
      await _settle();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Polls notifications for [uid] for one created after [start] of [type].
Future<bool> _notif(
  FirebaseFirestore db,
  String uid,
  Timestamp start,
  String type, {
  int tries = 15,
  Duration gap = const Duration(seconds: 2),
}) async {
  for (var i = 0; i < tries; i++) {
    final snap = await db
        .collection(AppConstants.notificationsCollection)
        .where('userId', isEqualTo: uid)
        .get(_serverGet);
    final hit = snap.docs.any((doc) {
      final c = doc.data()['createdAt'];
      return doc.data()['type'] == type &&
          c is Timestamp &&
          c.compareTo(start) >= 0;
    });
    if (hit) return true;
    await Future.delayed(gap);
  }
  return false;
}
