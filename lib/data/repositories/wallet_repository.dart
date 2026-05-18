import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/wallet_account_model.dart';
import '../models/wallet_transaction_model.dart';
import '../../core/constants/app_constants.dart';

class WalletRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _accounts =>
      _db.collection(AppConstants.walletAccountsCollection);

  CollectionReference get _transactions =>
      _db.collection(AppConstants.walletTransactionsCollection);

  DocumentReference get _summary => _db
      .collection(AppConstants.walletConfigCollection)
      .doc(AppConstants.walletSummaryDoc);

  DocumentReference get _paymentMap => _db
      .collection(AppConstants.walletConfigCollection)
      .doc(AppConstants.walletPaymentMapDoc);

  // ── Accounts ──────────────────────────────────────────────────

  Stream<List<WalletAccountModel>> watchAccounts({
    bool includeArchived = false,
    String? region,
  }) {
    Query q = _accounts.orderBy('created_at', descending: false);
    if (!includeArchived) q = q.where('archived', isEqualTo: false);
    if (region != null) q = q.where('region', isEqualTo: region);
    return q
        .snapshots()
        .map((s) => s.docs.map(WalletAccountModel.fromFirestore).toList());
  }

  /// Creates a new account and returns the generated document ID.
  Future<String> createAccount({
    required String name,
    required String type,
    required String currency,
    required int openingBalance,
    required String color,
    String? region,
    required String createdBy,
  }) async {
    final now = Timestamp.now();
    final ref = await _accounts.add({
      'name': name,
      'type': type,
      'currency': currency,
      'opening_balance': openingBalance,
      'current_balance': openingBalance,
      'color': color,
      'archived': false,
      'region': region,
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    });
    return ref.id;
  }

  Future<void> updateAccount(
    String id, {
    String? name,
    String? type,
    String? currency,
    String? color,
    Object? region = _sentinel,
  }) async {
    final updates = <String, dynamic>{'updated_at': Timestamp.now()};
    if (name != null) updates['name'] = name;
    if (type != null) updates['type'] = type;
    if (currency != null) updates['currency'] = currency;
    if (color != null) updates['color'] = color;
    if (region != _sentinel) updates['region'] = region as String?;
    await _accounts.doc(id).update(updates);
  }

  Future<void> archiveAccount(String id) async {
    await _accounts.doc(id).update({
      'archived': true,
      'updated_at': Timestamp.now(),
    });
  }

  // ── Transactions ──────────────────────────────────────────────

  /// Streams transactions for [accountId], ordered by [occurredAt] descending.
  ///
  /// Firestore query is restricted to account_id + occurredAt range only to
  /// avoid composite indexes. [kind], [category], and [search] filters are
  /// applied in-memory after fetching.
  Stream<List<WalletTransactionModel>> watchTransactions(
    String accountId, {
    DateTime? from,
    DateTime? to,
    String? kind,
    String? category,
    String? search,
    DocumentSnapshot? startAfter,
    int limit = 20,
  }) {
    Query q = _transactions
        .where('account_id', isEqualTo: accountId)
        .orderBy('occurred_at', descending: true);

    if (from != null) {
      q = q.where('occurred_at',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from));
    }
    if (to != null) {
      q = q.where('occurred_at',
          isLessThanOrEqualTo: Timestamp.fromDate(to));
    }
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    q = q.limit(limit);

    return q.snapshots().map((s) {
      var items =
          s.docs.map(WalletTransactionModel.fromFirestore).toList();

      if (kind != null && kind.isNotEmpty) {
        items = items.where((t) => t.kind == kind).toList();
      }
      if (category != null && category.isNotEmpty) {
        items = items
            .where((t) =>
                (t.category ?? '')
                    .toLowerCase()
                    .contains(category.toLowerCase()))
            .toList();
      }
      if (search != null && search.isNotEmpty) {
        final q2 = search.toLowerCase();
        items = items
            .where((t) =>
                (t.category ?? '').toLowerCase().contains(q2) ||
                (t.note ?? '').toLowerCase().contains(q2))
            .toList();
      }
      return items;
    });
  }

  Future<void> createTransaction({
    required String accountId,
    required String kind,
    required int amount,
    String? category,
    String? note,
    required Timestamp occurredAt,
    String? contributionId,
    String? transferGroupId,
    required String createdBy,
  }) async {
    final now = Timestamp.now();
    await _transactions.add({
      'account_id': accountId,
      'kind': kind,
      'amount': amount,
      'category': category,
      'note': note,
      'occurred_at': occurredAt,
      'contribution_id': contributionId,
      'transfer_group_id': transferGroupId,
      'created_by': createdBy,
      'created_at': now,
    });
  }

  Future<void> updateTransaction(
    String id, {
    String? category,
    String? note,
    Timestamp? occurredAt,
  }) async {
    final updates = <String, dynamic>{};
    if (category != null) updates['category'] = category;
    if (note != null) updates['note'] = note;
    if (occurredAt != null) updates['occurred_at'] = occurredAt;
    if (updates.isEmpty) return;
    await _transactions.doc(id).update(updates);
  }

  Future<void> deleteTransaction(String id) async {
    await _transactions.doc(id).delete();
  }

  // ── Summary & Payment Map ─────────────────────────────────────

  Stream<Map<String, dynamic>?> watchSummary() {
    return _summary
        .snapshots()
        .map((s) => s.data() as Map<String, dynamic>?);
  }

  /// Streams the regional payment map: { regionName → accountId }
  Stream<Map<String, String>> watchPaymentMap() {
    return _paymentMap.snapshots().map((s) {
      final d = s.data() as Map<String, dynamic>? ?? {};
      return d.map((k, v) => MapEntry(k, v.toString()));
    });
  }

  /// Overwrites the payment map with [map] (region → accountId).
  Future<void> updatePaymentMap(Map<String, String> map) async {
    await _paymentMap.set(map, SetOptions(merge: false));
  }

  /// Calls the backfillConfirmedContributions Cloud Function.
  /// Returns { created, skipped, failed, total }.
  Future<Map<String, dynamic>> backfillContributions() async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('backfillConfirmedContributions');
    final result = await callable.call<Map<String, dynamic>>();
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Fetches all transactions and returns a sorted list of distinct
  /// non-empty category strings.
  Future<List<String>> getCategories() async {
    final snap = await _transactions.get();
    final cats = snap.docs
        .map((d) => (d.data() as Map<String, dynamic>)['category'] as String? ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    cats.sort();
    return cats;
  }
}

const Object _sentinel = Object();
