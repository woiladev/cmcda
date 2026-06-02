
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/wallet_account_model.dart';
import '../../../data/models/wallet_transaction_model.dart';
import '../../../data/repositories/wallet_repository.dart';
import 'admin_wallet_screen.dart' show formatFCFA, formatFCFACompact;

// ── Filter state ───────────────────────────────────────────────

class _TxFilter {
  final DateTime? from;
  final DateTime? to;
  final String? kind; // null = all
  final String? category;
  final String search;

  const _TxFilter({
    this.from,
    this.to,
    this.kind,
    this.category,
    this.search = '',
  });

  _TxFilter copyWith({
    DateTime? from,
    DateTime? to,
    bool clearFrom = false,
    bool clearTo = false,
    String? kind,
    bool clearKind = false,
    String? category,
    bool clearCategory = false,
    String? search,
  }) {
    return _TxFilter(
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      kind: clearKind ? null : (kind ?? this.kind),
      category: clearCategory ? null : (category ?? this.category),
      search: search ?? this.search,
    );
  }
}

// ── Providers ──────────────────────────────────────────────────

final _walletRepoAccount = WalletRepository();

final _accountDetailProvider =
    StreamProvider.autoDispose.family<WalletAccountModel?, String>(
        (ref, accountId) {
  return FirebaseFirestore.instance
      .collection(AppConstants.walletAccountsCollection)
      .doc(accountId)
      .snapshots()
      .map((s) => s.exists ? WalletAccountModel.fromFirestore(s) : null);
});

final _allAccountsProvider =
    StreamProvider.autoDispose<List<WalletAccountModel>>((ref) {
  return _walletRepoAccount.watchAccounts(includeArchived: false);
});

final _txFilterProvider =
    StateProvider.autoDispose<_TxFilter>((ref) => const _TxFilter());

// ── Screen ─────────────────────────────────────────────────────

class AdminWalletAccountScreen extends ConsumerStatefulWidget {
  final String accountId;

  const AdminWalletAccountScreen({
    super.key,
    required this.accountId,
  });

  @override
  ConsumerState<AdminWalletAccountScreen> createState() =>
      _AdminWalletAccountScreenState();
}

class _AdminWalletAccountScreenState
    extends ConsumerState<AdminWalletAccountScreen> {
  static const int _pageSize = 20;

  final List<WalletTransactionModel> _transactions = [];
  bool _loadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDoc;

  final _searchCtrl = TextEditingController();
  List<String> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadTransactions(reset: true);
    _loadCategories();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────

  Future<void> _loadCategories() async {
    try {
      final cats = await _walletRepoAccount.getCategories();
      if (mounted) setState(() => _categories = cats);
    } catch (_) {}
  }

  Future<void> _loadTransactions({bool reset = false}) async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);

    if (reset) {
      _transactions.clear();
      _lastDoc = null;
      _hasMore = true;
    }

    final filter = ref.read(_txFilterProvider);

    try {
      // Build a one-shot query for pagination
      Query query = FirebaseFirestore.instance
          .collection(AppConstants.walletTransactionsCollection)
          .where('account_id', isEqualTo: widget.accountId)
          .orderBy('occurred_at', descending: true);

      if (filter.from != null) {
        query = query.where('occurred_at',
            isGreaterThanOrEqualTo:
                Timestamp.fromDate(filter.from!));
      }
      if (filter.to != null) {
        final end = DateTime(
            filter.to!.year, filter.to!.month, filter.to!.day, 23, 59, 59);
        query = query.where('occurred_at',
            isLessThanOrEqualTo: Timestamp.fromDate(end));
      }
      if (filter.kind != null) {
        query = query.where('kind', isEqualTo: filter.kind);
      }
      if (filter.category != null && filter.category!.isNotEmpty) {
        query =
            query.where('category', isEqualTo: filter.category);
      }

      if (_lastDoc != null) {
        query = query.startAfterDocument(_lastDoc!);
      }
      query = query.limit(_pageSize);

      final snap = await query.get();
      final newTxs = snap.docs
          .map((d) => WalletTransactionModel.fromFirestore(d))
          .toList();

      // Client-side text search
      final searchLower = filter.search.toLowerCase().trim();
      final filtered = searchLower.isEmpty
          ? newTxs
          : newTxs.where((t) {
              return (t.category?.toLowerCase().contains(searchLower) ??
                      false) ||
                  (t.note?.toLowerCase().contains(searchLower) ?? false);
            }).toList();

      if (mounted) {
        setState(() {
          _transactions.addAll(filtered);
          _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : _lastDoc;
          _hasMore = snap.docs.length == _pageSize;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ── Kind helpers ───────────────────────────────────────────

  String _kindLabel(String kind, AppLocalizations l) {
    switch (kind) {
      case AppConstants.txKindInflow:
        return l.txKindInflow;
      case AppConstants.txKindOutflow:
        return l.txKindOutflow;
      case AppConstants.txKindTransferIn:
        return l.txKindTransferIn;
      case AppConstants.txKindTransferOut:
        return l.txKindTransferOut;
      default:
        return kind;
    }
  }

  IconData _kindIcon(String kind) {
    switch (kind) {
      case AppConstants.txKindInflow:
        return Icons.arrow_downward_rounded;
      case AppConstants.txKindOutflow:
        return Icons.arrow_upward_rounded;
      case AppConstants.txKindTransferIn:
        return Icons.swap_horiz_rounded;
      case AppConstants.txKindTransferOut:
        return Icons.swap_horiz_rounded;
      default:
        return Icons.circle_outlined;
    }
  }

  Color _kindColor(String kind) {
    switch (kind) {
      case AppConstants.txKindInflow:
        return AppColors.success;
      case AppConstants.txKindOutflow:
        return AppColors.error;
      case AppConstants.txKindTransferIn:
        return AppColors.info;
      case AppConstants.txKindTransferOut:
        return AppColors.info;
      default:
        return AppColors.textGray;
    }
  }

  // ── Actions ────────────────────────────────────────────────

  void _showTransactionDialog({WalletTransactionModel? tx}) {
    final account = ref.read(_accountDetailProvider(widget.accountId)).valueOrNull;
    if (account == null) return;
    showDialog(
      context: context,
      builder: (ctx) => _WalletTransactionDialog(
        transaction: tx,
        accountId: widget.accountId,
        repo: _walletRepoAccount,
      ),
    ).then((_) => _loadTransactions(reset: true));
  }

  void _showTransferDialog(WalletAccountModel fromAccount) {
    showDialog(
      context: context,
      builder: (ctx) => _TransferDialog(
        fromAccount: fromAccount,
        repo: _walletRepoAccount,
      ),
    ).then((_) => _loadTransactions(reset: true));
  }

  void _showDeleteDialog(WalletTransactionModel tx) {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        ),
        title: Text(
          l.deleteMovementConfirm,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          l.deleteMovementBody,
          style: const TextStyle(
              color: AppColors.textGray, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await _walletRepoAccount.deleteTransaction(tx.id);
                if (mounted) {
                  _loadTransactions(reset: true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l.movementDeleted),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l.unknownError),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(80, 40),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceMD),
            ),
            child: Text(l.deleteMovement),
          ),
        ],
      ),
    );
  }

  void _showArchiveDialog(WalletAccountModel account) {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        ),
        title: Text(
          l.archiveAccountConfirm,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          l.archiveAccountBody,
          style: const TextStyle(
              color: AppColors.textGray, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await _walletRepoAccount.archiveAccount(account.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l.accountArchived),
                      backgroundColor: AppColors.success,
                    ),
                  );
                  context.pop();
                }
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l.unknownError),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              minimumSize: const Size(80, 40),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceMD),
            ),
            child: Text(
              l.archiveAccount,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accountAsync =
        ref.watch(_accountDetailProvider(widget.accountId));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: accountAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (_, __) => Center(
            child: Text(
              AppLocalizations.of(context).unknownError,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
          data: (account) {
            if (account == null) {
              return Center(
                child: Text(
                  AppLocalizations.of(context).error,
                  style: const TextStyle(color: AppColors.textGray),
                ),
              );
            }
            return _buildContent(context, account);
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WalletAccountModel account) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        _buildColoredHeader(context, account, l),
        _buildFilterBar(context, l),
        Expanded(
          child: RefreshIndicator(
            color: account.accentColor,
            onRefresh: () => _loadTransactions(reset: true),
            child: _buildTransactionList(context, l),
          ),
        ),
      ],
    );
  }

  // ── Colored header ─────────────────────────────────────────

  Widget _buildColoredHeader(
      BuildContext context, WalletAccountModel account, AppLocalizations l) {
    final isSuperAdmin =
        ref.watch(currentUserProfileProvider).valueOrNull?.isSuperAdmin ??
            false;
    final baseColor = account.accentColor;
    // Darken for gradient end
    final darkColor = Color.fromARGB(
      255,
      (baseColor.r * 255 * 0.6).round(),
      (baseColor.g * 255 * 0.6).round(),
      (baseColor.b * 255 * 0.6).round(),
    );

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [baseColor, darkColor],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceMD,
        MediaQuery.of(context).padding.top + AppConstants.spaceSM,
        AppConstants.spaceMD,
        AppConstants.spaceMD,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button row
          Row(
            children: [
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const Spacer(),
              if (isSuperAdmin)
                IconButton(
                  onPressed: () => _showArchiveDialog(account),
                  tooltip: l.archiveAccount,
                  icon: const Icon(Icons.archive_outlined,
                      color: Colors.white, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceSM),

          // Account name
          Text(
            account.name,
            style: GoogleFonts.playfairDisplay(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                _typeLabel(account.type, l),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
              if (account.region != null && account.region!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.public_rounded,
                          color: Colors.white, size: 11),
                      const SizedBox(width: 3),
                      Text(
                        account.region!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppConstants.spaceMD),

          // Balance
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatFCFA(account.currentBalance),
                style: GoogleFonts.playfairDisplay(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppConstants.spaceSM),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  account.currency,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceLG),

          // Action buttons row — super_admin only (view-only for admins)
          if (isSuperAdmin)
            Row(
              children: [
                _HeaderActionButton(
                  icon: Icons.add_circle_outline_rounded,
                  label: l.addMovement,
                  onTap: () => _showTransactionDialog(),
                ),
                const SizedBox(width: AppConstants.spaceSM),
                _HeaderActionButton(
                  icon: Icons.swap_horiz_rounded,
                  label: l.transferTitle,
                  onTap: () {
                    final acc = ref
                        .read(_accountDetailProvider(widget.accountId))
                        .valueOrNull;
                    if (acc != null) _showTransferDialog(acc);
                  },
                ),
                const SizedBox(width: AppConstants.spaceSM),
                _HeaderActionButton(
                  icon: Icons.archive_outlined,
                  label: l.archiveAccount,
                  onTap: () {
                    final acc = ref
                        .read(_accountDetailProvider(widget.accountId))
                        .valueOrNull;
                    if (acc != null) _showArchiveDialog(acc);
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _typeLabel(String type, AppLocalizations l) {
    switch (type) {
      case AppConstants.walletTypeMobileMoney:
        return l.walletTypeMobileMoney;
      case AppConstants.walletTypeBank:
        return l.walletTypeBank;
      case AppConstants.walletTypeCash:
        return l.walletTypeCash;
      default:
        return l.walletTypeOther;
    }
  }

  // ── Filter bar ─────────────────────────────────────────────

  Widget _buildFilterBar(BuildContext context, AppLocalizations l) {
    final filter = ref.watch(_txFilterProvider);

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMD,
        vertical: AppConstants.spaceSM,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Date range
            _FilterChip(
              label: filter.from != null || filter.to != null
                  ? '${filter.from != null ? DateFormat('dd/MM', 'fr_FR').format(filter.from!) : '…'}  →  ${filter.to != null ? DateFormat('dd/MM', 'fr_FR').format(filter.to!) : '…'}'
                  : '${l.filterDateFrom} – ${l.filterDateTo}',
              isActive: filter.from != null || filter.to != null,
              icon: Icons.date_range_outlined,
              onTap: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  initialDateRange: filter.from != null && filter.to != null
                      ? DateTimeRange(start: filter.from!, end: filter.to!)
                      : null,
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: Theme.of(ctx)
                          .colorScheme
                          .copyWith(primary: AppColors.primary),
                    ),
                    child: child!,
                  ),
                );
                if (range != null) {
                  ref.read(_txFilterProvider.notifier).state = filter
                      .copyWith(from: range.start, to: range.end);
                  _loadTransactions(reset: true);
                }
              },
              onClear: filter.from != null || filter.to != null
                  ? () {
                      ref.read(_txFilterProvider.notifier).state =
                          filter.copyWith(
                              clearFrom: true, clearTo: true);
                      _loadTransactions(reset: true);
                    }
                  : null,
            ),
            const SizedBox(width: AppConstants.spaceSM),

            // Kind chips
            _FilterChip(
              label: l.inflowLabel,
              isActive: filter.kind == AppConstants.txKindInflow,
              onTap: () {
                final newKind =
                    filter.kind == AppConstants.txKindInflow
                        ? null
                        : AppConstants.txKindInflow;
                ref.read(_txFilterProvider.notifier).state = filter
                    .copyWith(
                        kind: newKind,
                        clearKind: newKind == null);
                _loadTransactions(reset: true);
              },
            ),
            const SizedBox(width: AppConstants.spaceSM),
            _FilterChip(
              label: l.outflowLabel,
              isActive: filter.kind == AppConstants.txKindOutflow,
              onTap: () {
                final newKind =
                    filter.kind == AppConstants.txKindOutflow
                        ? null
                        : AppConstants.txKindOutflow;
                ref.read(_txFilterProvider.notifier).state = filter
                    .copyWith(
                        kind: newKind,
                        clearKind: newKind == null);
                _loadTransactions(reset: true);
              },
            ),
            const SizedBox(width: AppConstants.spaceSM),
            _FilterChip(
              label: l.transferTitle,
              isActive: filter.kind == AppConstants.txKindTransferIn,
              onTap: () {
                // Transfer filter: show transfer_in kind
                final newKind =
                    filter.kind == AppConstants.txKindTransferIn
                        ? null
                        : AppConstants.txKindTransferIn;
                ref.read(_txFilterProvider.notifier).state = filter
                    .copyWith(
                        kind: newKind,
                        clearKind: newKind == null);
                _loadTransactions(reset: true);
              },
            ),
            const SizedBox(width: AppConstants.spaceSM),

            // Category dropdown
            if (_categories.isNotEmpty) ...[
              _FilterDropdown(
                label: l.movementCategory,
                value: filter.category,
                items: _categories,
                onChanged: (cat) {
                  ref.read(_txFilterProvider.notifier).state =
                      filter.copyWith(
                          category: cat,
                          clearCategory: cat == null);
                  _loadTransactions(reset: true);
                },
              ),
              const SizedBox(width: AppConstants.spaceSM),
            ],

            // Search
            SizedBox(
              width: 160,
              height: 36,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) {
                  ref.read(_txFilterProvider.notifier).state =
                      filter.copyWith(search: v);
                  // Trigger re-filter (client-side on next load)
                  _loadTransactions(reset: true);
                },
                decoration: InputDecoration(
                  hintText: l.search,
                  hintStyle: const TextStyle(fontSize: 12),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 16, color: AppColors.textGray),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull),
                    borderSide:
                        const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull),
                    borderSide:
                        const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull),
                    borderSide: const BorderSide(
                        color: AppColors.primary, width: 1.5),
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Transaction list ───────────────────────────────────────

  Widget _buildTransactionList(
      BuildContext context, AppLocalizations l) {
    if (_transactions.isEmpty && !_loadingMore) {
      return ListView(
        children: [
          const SizedBox(height: AppConstants.spaceXL),
          Center(
            child: Column(
              children: [
                const Icon(Icons.receipt_long_outlined,
                    size: 48, color: AppColors.border),
                const SizedBox(height: AppConstants.spaceSM),
                Text(
                  l.walletNoTransactions,
                  style: const TextStyle(
                      color: AppColors.textGray, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMD,
        vertical: AppConstants.spaceMD,
      ),
      itemCount: _transactions.length +
          (_hasMore ? 1 : 0) +
          (_loadingMore && _transactions.isEmpty ? 3 : 0),
      itemBuilder: (ctx, i) {
        // Shimmer placeholders while first load
        if (_transactions.isEmpty && _loadingMore) {
          return _buildTxShimmer();
        }

        if (i < _transactions.length) {
          return _buildTransactionItem(
              context, _transactions[i], l);
        }

        // Load more button / spinner
        return Padding(
          padding: const EdgeInsets.symmetric(
              vertical: AppConstants.spaceSM),
          child: _loadingMore
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                )
              : Center(
                  child: OutlinedButton(
                    onPressed: () => _loadTransactions(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spaceLG,
                          vertical: AppConstants.spaceSM),
                      side: const BorderSide(
                          color: AppColors.primary),
                    ),
                    child: Text(l.loadMore),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildTransactionItem(BuildContext context,
      WalletTransactionModel tx, AppLocalizations l) {
    final isSuperAdmin =
        ref.watch(currentUserProfileProvider).valueOrNull?.isSuperAdmin ??
            false;
    final kindColor = _kindColor(tx.kind);
    final signed = tx.signedAmount;
    final amountColor = signed >= 0 ? AppColors.success : AppColors.error;
    final amountPrefix = signed >= 0 ? '+' : '';
    final dateStr = DateFormat('dd MMM', 'fr_FR').format(tx.occurredAt.toDate());

    return GestureDetector(
      onLongPress:
          isSuperAdmin ? () => _showTxOptions(context, tx, l) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spaceSM),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMD,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Kind icon circle
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kindColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(_kindIcon(tx.kind), color: kindColor, size: 18),
            ),
            const SizedBox(width: AppConstants.spaceSM),

            // Center: date, category, note
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        dateStr,
                        style: const TextStyle(
                          color: AppColors.textGray,
                          fontSize: 11,
                        ),
                      ),
                      if (tx.category != null &&
                          tx.category!.isNotEmpty) ...[
                        const SizedBox(width: AppConstants.spaceXS),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusFull),
                          ),
                          child: Text(
                            tx.category!,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tx.note?.isNotEmpty == true
                        ? tx.note!
                        : _kindLabel(tx.kind, l),
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppConstants.spaceSM),

            // Amount + edit icon
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$amountPrefix${formatFCFACompact(signed.abs())}',
                  style: GoogleFonts.playfairDisplay(
                    color: amountColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                if (isSuperAdmin)
                GestureDetector(
                  onTap: () => _showTxOptions(context, tx, l),
                  child: const Icon(Icons.more_vert_rounded,
                      size: 16, color: AppColors.textGray),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTxOptions(BuildContext context, WalletTransactionModel tx,
      AppLocalizations l) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXL)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppConstants.spaceSM),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
            const SizedBox(height: AppConstants.spaceSM),
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  color: AppColors.primary),
              title: Text(l.editMovement),
              onTap: () {
                Navigator.of(ctx).pop();
                _showTransactionDialog(tx: tx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error),
              title: Text(l.deleteMovement,
                  style: const TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.of(ctx).pop();
                _showDeleteDialog(tx);
              },
            ),
            const SizedBox(height: AppConstants.spaceSM),
          ],
        ),
      ),
    );
  }

  Widget _buildTxShimmer() {
    return Container(
      height: 68,
      margin: const EdgeInsets.only(bottom: AppConstants.spaceSM),
      decoration: BoxDecoration(
        color: AppColors.border.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      ),
    );
  }
}

// ── HeaderActionButton ─────────────────────────────────────────

class _HeaderActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppConstants.radiusSM),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── FilterChip ─────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final IconData? icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _FilterChip({
    required this.label,
    required this.isActive,
    this.icon,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.bg,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon!,
                  size: 13,
                  color: isActive
                      ? AppColors.primary
                      : AppColors.textGray),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color:
                    isActive ? AppColors.primary : AppColors.textGray,
                fontSize: 12,
                fontWeight:
                    isActive ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close_rounded,
                    size: 13, color: AppColors.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── FilterDropdown ─────────────────────────────────────────────

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: value != null
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.bg,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        border: Border.all(
          color: value != null ? AppColors.primary : AppColors.border,
          width: value != null ? 1.5 : 1,
        ),
      ),
      child: DropdownButton<String?>(
        value: value,
        isDense: true,
        underline: const SizedBox.shrink(),
        hint: Text(label,
            style: const TextStyle(
                color: AppColors.textGray, fontSize: 12)),
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        dropdownColor: AppColors.surface,
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textGray, fontSize: 12)),
          ),
          ...items.map(
            (cat) => DropdownMenuItem<String?>(
              value: cat,
              child: Text(cat,
                  style: const TextStyle(
                      color: AppColors.textDark, fontSize: 12)),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

// ── WalletTransactionDialog ────────────────────────────────────

class _WalletTransactionDialog extends ConsumerStatefulWidget {
  final WalletTransactionModel? transaction;
  final String accountId;
  final WalletRepository repo;

  const _WalletTransactionDialog({
    required this.transaction,
    required this.accountId,
    required this.repo,
  });

  @override
  ConsumerState<_WalletTransactionDialog> createState() =>
      _WalletTransactionDialogState();
}

class _WalletTransactionDialogState
    extends ConsumerState<_WalletTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String _kind = AppConstants.txKindInflow;
  DateTime _date = DateTime.now();
  bool _saving = false;
  List<String> _categorySuggestions = [];

  @override
  void initState() {
    super.initState();
    final tx = widget.transaction;
    if (tx != null) {
      _amountCtrl.text = tx.amount.toString();
      _categoryCtrl.text = tx.category ?? '';
      _noteCtrl.text = tx.note ?? '';
      _kind = tx.kind;
      _date = tx.occurredAt.toDate();
    }
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    try {
      final cats = await widget.repo.getCategories();
      if (mounted) setState(() => _categorySuggestions = cats);
    } catch (_) {}
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _categoryCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(AppLocalizations l) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final amount =
        int.tryParse(_amountCtrl.text.trim()) ?? 0;
    try {
      if (widget.transaction == null) {
        await widget.repo.createTransaction(
          accountId: widget.accountId,
          kind: _kind,
          amount: amount,
          category: _categoryCtrl.text.trim().isNotEmpty
              ? _categoryCtrl.text.trim()
              : null,
          note: _noteCtrl.text.trim().isNotEmpty
              ? _noteCtrl.text.trim()
              : null,
          occurredAt: Timestamp.fromDate(_date),
          createdBy: uid,
        );
      } else {
        await widget.repo.updateTransaction(
          widget.transaction!.id,
          category: _categoryCtrl.text.trim().isNotEmpty
              ? _categoryCtrl.text.trim()
              : null,
          note: _noteCtrl.text.trim().isNotEmpty
              ? _noteCtrl.text.trim()
              : null,
          occurredAt: Timestamp.fromDate(_date),
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.movementSaved),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.unknownError),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isCreate = widget.transaction == null;
    final dateStr =
        DateFormat('dd MMM yyyy', 'fr_FR').format(_date);

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
      ),
      title: Text(
        isCreate ? l.addMovement : l.editMovement,
        style: GoogleFonts.playfairDisplay(
          color: AppColors.textDark,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Kind selector (create only — cannot change kind on edit)
                if (isCreate) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _KindToggle(
                          label: l.inflowLabel,
                          icon: Icons.arrow_downward_rounded,
                          color: AppColors.success,
                          isSelected:
                              _kind == AppConstants.txKindInflow,
                          onTap: () => setState(
                              () => _kind = AppConstants.txKindInflow),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spaceSM),
                      Expanded(
                        child: _KindToggle(
                          label: l.outflowLabel,
                          icon: Icons.arrow_upward_rounded,
                          color: AppColors.error,
                          isSelected:
                              _kind == AppConstants.txKindOutflow,
                          onTap: () => setState(
                              () => _kind = AppConstants.txKindOutflow),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spaceMD),
                ],

                // Amount
                TextFormField(
                  controller: _amountCtrl,
                  readOnly: !isCreate,
                  decoration: InputDecoration(
                    labelText: l.movementAmount,
                    suffixText: 'FCFA',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return l.required;
                    final n = int.tryParse(v.trim());
                    if (n == null || n <= 0) return l.required;
                    return null;
                  },
                ),
                const SizedBox(height: AppConstants.spaceMD),

                // Date picker
                InkWell(
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMD),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now()
                          .add(const Duration(days: 1)),
                      builder: (ctx, child) => Theme(
                        data: Theme.of(ctx).copyWith(
                          colorScheme: Theme.of(ctx)
                              .colorScheme
                              .copyWith(primary: AppColors.primary),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setState(() => _date = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: l.movementDate,
                      suffixIcon: const Icon(Icons.calendar_today_outlined,
                          size: 18),
                    ),
                    child: Text(
                      dateStr,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spaceMD),

                // Category with autocomplete
                Autocomplete<String>(
                  initialValue: TextEditingValue(
                      text: _categoryCtrl.text),
                  optionsBuilder: (v) {
                    if (v.text.isEmpty) return const [];
                    return _categorySuggestions.where((c) => c
                        .toLowerCase()
                        .contains(v.text.toLowerCase()));
                  },
                  onSelected: (s) => _categoryCtrl.text = s,
                  fieldViewBuilder: (ctx, ctrl, fn, onSubmit) {
                    // Sync category controller
                    ctrl.text = _categoryCtrl.text;
                    ctrl.addListener(() {
                      _categoryCtrl.text = ctrl.text;
                    });
                    return TextFormField(
                      controller: ctrl,
                      focusNode: fn,
                      decoration: InputDecoration(
                        labelText: l.movementCategory,
                      ),
                      onEditingComplete: onSubmit,
                    );
                  },
                ),
                const SizedBox(height: AppConstants.spaceMD),

                // Note
                TextFormField(
                  controller: _noteCtrl,
                  decoration: InputDecoration(
                    labelText: l.movementNote,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        ElevatedButton(
          onPressed: _saving ? null : () => _save(l),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(80, 40),
            padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceMD),
          ),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Text(l.save),
        ),
      ],
    );
  }
}

// ── KindToggle ─────────────────────────────────────────────────

class _KindToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _KindToggle({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
            vertical: AppConstants.spaceSM),
        decoration: BoxDecoration(
          color:
              isSelected ? color.withValues(alpha: 0.12) : AppColors.bg,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? color : AppColors.textGray,
                size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color:
                    isSelected ? color : AppColors.textGray,
                fontSize: 13,
                fontWeight: isSelected
                    ? FontWeight.w700
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── TransferDialog ─────────────────────────────────────────────

class _TransferDialog extends ConsumerStatefulWidget {
  final WalletAccountModel fromAccount;
  final WalletRepository repo;

  const _TransferDialog({
    required this.fromAccount,
    required this.repo,
  });

  @override
  ConsumerState<_TransferDialog> createState() =>
      _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<_TransferDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  WalletAccountModel? _toAccount;
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _execute(AppLocalizations l) async {
    if (!_formKey.currentState!.validate()) return;
    if (_toAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.required),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (_toAccount!.id == widget.fromAccount.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.sameAccountError),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final amount =
        int.tryParse(_amountCtrl.text.trim()) ?? 0;
    final note = _noteCtrl.text.trim().isNotEmpty
        ? _noteCtrl.text.trim()
        : null;

    // Generate a shared transferGroupId
    final transferGroupId = FirebaseFirestore.instance
        .collection('_')
        .doc()
        .id;

    try {
      final now = Timestamp.now();

      // Create transfer_out on source account
      await widget.repo.createTransaction(
        accountId: widget.fromAccount.id,
        kind: AppConstants.txKindTransferOut,
        amount: amount,
        note: note,
        occurredAt: now,
        transferGroupId: transferGroupId,
        createdBy: uid,
      );

      // Create transfer_in on destination account
      await widget.repo.createTransaction(
        accountId: _toAccount!.id,
        kind: AppConstants.txKindTransferIn,
        amount: amount,
        note: note,
        occurredAt: now,
        transferGroupId: transferGroupId,
        createdBy: uid,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.transferExecuted),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.unknownError),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final allAccountsAsync = ref.watch(_allAccountsProvider);
    final otherAccounts = allAccountsAsync.valueOrNull
            ?.where((a) => a.id != widget.fromAccount.id)
            .toList() ??
        [];

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
      ),
      title: Text(
        l.transferTitle,
        style: GoogleFonts.playfairDisplay(
          color: AppColors.textDark,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // From (readonly)
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: l.transferFrom,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: widget.fromAccount.accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.fromAccount.name,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppConstants.spaceMD),

                // To
                DropdownButtonFormField<WalletAccountModel>(
                  initialValue: _toAccount,
                  decoration: InputDecoration(
                    labelText: l.transferTo,
                  ),
                  items: otherAccounts
                      .map(
                        (a) => DropdownMenuItem(
                          value: a,
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: a.accentColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(a.name),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _toAccount = v),
                  validator: (v) =>
                      v == null ? l.required : null,
                ),
                const SizedBox(height: AppConstants.spaceMD),

                // Amount
                TextFormField(
                  controller: _amountCtrl,
                  decoration: InputDecoration(
                    labelText: l.movementAmount,
                    suffixText: 'FCFA',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return l.required;
                    }
                    final n = int.tryParse(v.trim());
                    if (n == null || n <= 0) return l.required;
                    return null;
                  },
                ),
                const SizedBox(height: AppConstants.spaceMD),

                // Note
                TextFormField(
                  controller: _noteCtrl,
                  decoration: InputDecoration(
                    labelText: l.transferNote,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        ElevatedButton(
          onPressed: _saving ? null : () => _execute(l),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(80, 40),
            padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceMD),
          ),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Text(l.confirm),
        ),
      ],
    );
  }
}
