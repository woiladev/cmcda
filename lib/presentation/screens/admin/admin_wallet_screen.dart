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
import '../../../data/repositories/wallet_repository.dart';

// ── Helpers ────────────────────────────────────────────────────

String formatFCFA(int amount) {
  return '${NumberFormat('#,###', 'fr_FR').format(amount).replaceAll(',', ' ')} FCFA';
}

String formatFCFACompact(int amount) {
  if (amount.abs() >= 1000000) {
    return '${(amount / 1000000).toStringAsFixed(1)}M FCFA';
  }
  if (amount.abs() >= 1000) {
    return '${(amount / 1000).toStringAsFixed(0)}K FCFA';
  }
  return '$amount FCFA';
}

// ── Providers ──────────────────────────────────────────────────

final _walletRepo = WalletRepository();

final _accountsProvider =
    StreamProvider.autoDispose<List<WalletAccountModel>>((ref) {
  return _walletRepo.watchAccounts(includeArchived: false);
});

final _paymentMapProvider =
    StreamProvider.autoDispose<Map<String, String>>((ref) {
  return _walletRepo.watchPaymentMap();
});

final _adminSummaryProvider =
    StreamProvider.autoDispose<Map<String, dynamic>?>((ref) {
  return _walletRepo.watchSummary();
});

final _regionTotalsProvider =
    StreamProvider.autoDispose<Map<String, int>>((ref) {
  return _walletRepo.watchRegionTotals();
});

// ── Screen ─────────────────────────────────────────────────────

class AdminWalletScreen extends ConsumerStatefulWidget {
  const AdminWalletScreen({super.key});

  @override
  ConsumerState<AdminWalletScreen> createState() => _AdminWalletScreenState();
}

class _AdminWalletScreenState extends ConsumerState<AdminWalletScreen> {
  bool _seeding   = false;
  bool _backfilling = false;
  bool _recalcRegions = false;

  // ── Helpers ────────────────────────────────────────────────

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

  void _showAccountDialog({WalletAccountModel? account}) {
    showDialog(
      context: context,
      builder: (ctx) => _WalletAccountDialog(
        account: account,
        repo: _walletRepo,
      ),
    );
  }

  /// Creates one wallet account per Cameroon region (idempotent) and
  /// updates the payment map to route each region to its account.
  /// Idempotently creates the 4 payment-method wallets and sets
  /// payment_method_map = { method → accountId }. Re-running reuses any wallet
  /// already mapped. Obsolete region-tagged wallets are archived so the tab
  /// shows only the 4 method wallets.
  Future<void> _initMethodWallets(
    AppLocalizations l,
    List<WalletAccountModel> existingAccounts,
  ) async {
    if (_seeding) return;
    setState(() => _seeding = true);

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final currentMap = ref.read(_paymentMapProvider).valueOrNull ?? {};
    final existingById = {for (final a in existingAccounts) a.id: a};

    // method → (name, type, color)
    final defs = <String, (String, String, String)>{
      AppConstants.paymentMtnMomo:
          ('MTN Mobile Money', AppConstants.walletTypeMobileMoney, '#f59e0b'),
      AppConstants.paymentOrangeMoney:
          ('Orange Money', AppConstants.walletTypeMobileMoney, '#ea580c'),
      AppConstants.paymentCash:
          ('Espèces', AppConstants.walletTypeCash, '#16a34a'),
      AppConstants.paymentBankTransfer:
          ('Virement bancaire', AppConstants.walletTypeBank, '#0ea5e9'),
    };

    try {
      final paymentMap = <String, String>{};

      for (final entry in defs.entries) {
        final method = entry.key;
        final existingId = currentMap[method];
        if (existingId != null && existingById.containsKey(existingId)) {
          paymentMap[method] = existingId;
        } else {
          final id = await _walletRepo.createAccount(
            name: entry.value.$1,
            type: entry.value.$2,
            currency: AppConstants.defaultCurrency,
            openingBalance: 0,
            color: entry.value.$3,
            createdBy: uid,
          );
          paymentMap[method] = id;
        }
      }

      await _walletRepo.updatePaymentMap(paymentMap);

      // Archive obsolete region-tagged wallets (we now route by method).
      for (final acc in existingAccounts) {
        if (acc.region != null && acc.region!.isNotEmpty && !acc.archived) {
          await _walletRepo.archiveAccount(acc.id);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.walletsReady),
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
      if (mounted) setState(() => _seeding = false);
    }
  }

  /// Calls the Cloud Function to create wallet transactions for all
  /// contributions that were confirmed before the trigger was deployed.
  Future<void> _backfillContributions(AppLocalizations l) async {
    if (_backfilling) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        ),
        title: Text(
          l.backfillContributions,
          style: GoogleFonts.playfairDisplay(
            color: AppColors.textDark,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          l.backfillContributionsHint,
          style: const TextStyle(color: AppColors.textMid, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _backfilling = true);

    try {
      final result = await _walletRepo.backfillContributions();
      final created = result['created'] as int? ?? 0;
      final skipped = result['skipped'] as int? ?? 0;
      final failed  = result['failed']  as int? ?? 0;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.backfillDone(created, skipped, failed),
            ),
            backgroundColor:
                failed > 0 ? AppColors.warning : AppColors.success,
            duration: const Duration(seconds: 5),
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
      if (mounted) setState(() => _backfilling = false);
    }
  }

  /// Recomputes per-region contribution totals (super-admin only).
  Future<void> _recalcRegionTotals(AppLocalizations l) async {
    if (_recalcRegions) return;
    setState(() => _recalcRegions = true);
    try {
      await _walletRepo.backfillRegionTotals();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.regionTotalsUpdated),
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
      if (mounted) setState(() => _recalcRegions = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final l = AppLocalizations.of(context);
    final accountsAsync = ref.watch(_accountsProvider);
    final accounts = accountsAsync.valueOrNull ?? [];
    final isSuperAdmin =
        ref.watch(currentUserProfileProvider).valueOrNull?.isSuperAdmin ??
            false;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceMD,
        MediaQuery.of(context).padding.top + AppConstants.spaceMD,
        AppConstants.spaceMD,
        AppConstants.spaceMD,
      ),
      child: Row(
        children: [
          // Shown only when pushed (e.g. deep-linked); as a nav tab there's
          // nothing to pop.
          if (context.canPop()) ...[
            IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: AppConstants.spaceSM),
          ],
          Expanded(
            child: Text(
              l.adminWalletTitle,
              style: GoogleFonts.playfairDisplay(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Maintenance / edit actions — super_admin only (view-only for admins)
          if (isSuperAdmin) ...[
          // Initialize the 4 payment-method wallets
          if (_seeding)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            )
          else
            IconButton(
              onPressed: () => _initMethodWallets(l, accounts),
              tooltip: l.initWallets,
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusSM),
                ),
                child: const Icon(Icons.public_rounded,
                    color: Colors.white, size: 20),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          const SizedBox(width: AppConstants.spaceSM),
          // Backfill existing confirmed contributions
          if (_backfilling)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            )
          else
            IconButton(
              onPressed: () => _backfillContributions(l),
              tooltip: l.backfillContributions,
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusSM),
                ),
                child: const Icon(Icons.sync_rounded,
                    color: Colors.white, size: 20),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          const SizedBox(width: AppConstants.spaceSM),
          IconButton(
            onPressed: () => _showAccountDialog(),
            tooltip: l.addWalletAccount,
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusSM),
              ),
              child: const Icon(Icons.add_rounded,
                  color: Colors.white, size: 20),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          ],
        ],
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────

  Widget _buildBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.spaceMD),
      children: [
        _buildTotalBalanceCard(context),
        const SizedBox(height: AppConstants.spaceMD),
        _buildAccountsSection(context),
        const SizedBox(height: AppConstants.spaceMD),
        _buildRegionalSection(context),
        const SizedBox(height: AppConstants.spaceXL),
      ],
    );
  }

  Widget _buildRegionalSection(BuildContext context) {
    final l = AppLocalizations.of(context);
    final totals = ref.watch(_regionTotalsProvider).valueOrNull ?? {};
    final isSuperAdmin =
        ref.watch(currentUserProfileProvider).valueOrNull?.isSuperAdmin ??
            false;

    final sorted = totals.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final grandTotal = sorted.fold<int>(0, (s, e) => s + e.value);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMD),
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.byRegion.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textGray,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (isSuperAdmin)
                _recalcRegions
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        onPressed: () => _recalcRegionTotals(l),
                        tooltip: l.recalcRegionTotals,
                        icon: const Icon(Icons.refresh_rounded,
                            size: 18, color: AppColors.textGray),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceSM),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: AppConstants.spaceMD),
              child: Text(
                l.noData,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: AppColors.textGray),
              ),
            )
          else
            ...sorted.map((e) {
              final pct = grandTotal > 0 ? e.value / grandTotal : 0.0;
              final color = () {
                final hex = AppConstants.regionWalletColors[e.key];
                if (hex == null) return AppColors.primary;
                return Color(
                    int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
              }();
              return Padding(
                padding:
                    const EdgeInsets.only(bottom: AppConstants.spaceSM),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: AppConstants.spaceSM),
                    Expanded(
                      child: Text(
                        e.key,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    Text(
                      '${(pct * 100).toStringAsFixed(0)}%',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: AppColors.textGray,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spaceSM),
                    Text(
                      formatFCFA(e.value),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTotalBalanceCard(BuildContext context) {
    final l = AppLocalizations.of(context);
    final summaryAsync = ref.watch(_adminSummaryProvider);
    final accountsAsync = ref.watch(_accountsProvider);

    final totalBalance =
        (summaryAsync.valueOrNull?['total_balance'] as num?)?.toInt() ?? 0;
    final accountCount = (accountsAsync.valueOrNull ?? []).length;
    final isLoading = summaryAsync.isLoading;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppConstants.spaceMD,
        AppConstants.spaceSM,
        AppConstants.spaceMD,
        0,
      ),
      padding: const EdgeInsets.all(AppConstants.spaceLG),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, Color(0xFF0D3A1E)],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SOLDE TOTAL DE LA TRÉSORERIE',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: AppConstants.spaceSM),
          isLoading
              ? const SizedBox(
                  height: 38,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    ),
                  ),
                )
              : Text(
                  formatFCFA(totalBalance),
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
          const SizedBox(height: AppConstants.spaceSM),
          Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded,
                  size: 13, color: Colors.white.withValues(alpha: 0.45)),
              const SizedBox(width: 5),
              Text(
                '$accountCount ${l.walletAccounts.toLowerCase()}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
              const Spacer(),
              // Regional breakdown chip
              if (!isLoading) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.public_rounded,
                          size: 11,
                          color: Colors.white.withValues(alpha: 0.75)),
                      const SizedBox(width: 4),
                      Text(
                        '${(accountsAsync.valueOrNull ?? []).where((a) => a.isRegional).length} ${l.byRegion.toLowerCase()}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Accounts section ───────────────────────────────────────

  Widget _buildAccountsSection(BuildContext context) {
    final l = AppLocalizations.of(context);
    final accountsAsync = ref.watch(_accountsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppConstants.spaceMD, 0,
              AppConstants.spaceMD, AppConstants.spaceSM),
          child: Text(
            l.walletAccounts,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        accountsAsync.when(
          loading: () => _buildAccountsShimmer(),
          error: (e, _) => _buildErrorCard(l.unknownError),
          data: (accounts) {
            if (accounts.isEmpty) {
              return _buildEmptyState(
                icon: Icons.account_balance_wallet_outlined,
                label: l.walletNoAccounts,
              );
            }
            return Column(
              children: accounts
                  .map((a) => _buildAccountCard(context, a, l))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAccountCard(
      BuildContext context, WalletAccountModel account, AppLocalizations l) {
    final balanceColor =
        account.currentBalance >= 0 ? AppColors.success : AppColors.error;
    return GestureDetector(
      onTap: () => context.push('/admin/treasury/${account.id}'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(AppConstants.spaceMD, 0,
            AppConstants.spaceMD, AppConstants.spaceSM),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.textDark.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Colored left accent bar
            Container(
              width: 4,
              height: 72,
              decoration: BoxDecoration(
                color: account.accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppConstants.radiusLG),
                  bottomLeft: Radius.circular(AppConstants.radiusLG),
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spaceMD),
            // Colored dot
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: account.accentColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppConstants.spaceSM),
            // Name + type + optional region badge
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: AppConstants.spaceMD),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          _typeLabel(account.type, l),
                          style: const TextStyle(
                            color: AppColors.textGray,
                            fontSize: 12,
                          ),
                        ),
                        if (account.isRegional) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: account.accentColor
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusFull),
                            ),
                            child: Text(
                              account.region!,
                              style: TextStyle(
                                color: account.accentColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spaceSM),
            // Balance + edit
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppConstants.spaceMD),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatFCFA(account.currentBalance),
                    style: GoogleFonts.playfairDisplay(
                      color: balanceColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () =>
                            _showAccountDialog(account: account),
                        child: const Icon(Icons.edit_outlined,
                            size: 16, color: AppColors.textGray),
                      ),
                      const SizedBox(width: AppConstants.spaceSM),
                      const Icon(Icons.chevron_right_rounded,
                          size: 20, color: AppColors.textGray),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountsShimmer() {
    return Column(
      children: List.generate(
        3,
        (_) => Container(
          height: 72,
          margin: const EdgeInsets.fromLTRB(AppConstants.spaceMD, 0,
              AppConstants.spaceMD, AppConstants.spaceSM),
          decoration: BoxDecoration(
            color: AppColors.border.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          ),
        ),
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────

  Widget _buildEmptyState(
      {required IconData icon, required String label}) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppConstants.spaceXL,
          horizontal: AppConstants.spaceMD),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 48, color: AppColors.border),
            const SizedBox(height: AppConstants.spaceSM),
            Text(
              label,
              style: const TextStyle(
                  color: AppColors.textGray, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMD),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spaceMD),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(
              color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 18),
            const SizedBox(width: AppConstants.spaceSM),
            Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: AppColors.error, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── WalletAccountDialog ────────────────────────────────────────

class _WalletAccountDialog extends ConsumerStatefulWidget {
  final WalletAccountModel? account;
  final WalletRepository repo;

  const _WalletAccountDialog({
    required this.account,
    required this.repo,
  });

  @override
  ConsumerState<_WalletAccountDialog> createState() =>
      _WalletAccountDialogState();
}

class _WalletAccountDialogState
    extends ConsumerState<_WalletAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController();
  final _openingBalanceCtrl = TextEditingController();

  String _selectedType = AppConstants.walletTypeMobileMoney;
  String _selectedColor = AppConstants.walletColorPalette.first;
  String? _selectedRegion; // null = global account
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    if (a != null) {
      _nameCtrl.text = a.name;
      _currencyCtrl.text = a.currency;
      _selectedType = a.type;
      _selectedRegion = a.region;
      final hex =
          '#${a.accentColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      _selectedColor = AppConstants.walletColorPalette.contains(hex)
          ? hex
          : AppConstants.walletColorPalette.first;
    } else {
      _currencyCtrl.text = AppConstants.defaultCurrency;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _currencyCtrl.dispose();
    _openingBalanceCtrl.dispose();
    super.dispose();
  }

  Color _hexToColor(String hex) {
    final clean = hex.replaceAll('#', '');
    return Color(int.parse('FF$clean', radix: 16));
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

  Future<void> _save(AppLocalizations l) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      if (widget.account == null) {
        final opening =
            int.tryParse(_openingBalanceCtrl.text.trim()) ?? 0;
        await widget.repo.createAccount(
          name: _nameCtrl.text.trim(),
          type: _selectedType,
          currency: _currencyCtrl.text.trim().toUpperCase(),
          openingBalance: opening,
          color: _selectedColor,
          region: _selectedRegion,
          createdBy: uid,
        );
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.walletAccountCreated),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        await widget.repo.updateAccount(
          widget.account!.id,
          name: _nameCtrl.text.trim(),
          type: _selectedType,
          currency: _currencyCtrl.text.trim().toUpperCase(),
          color: _selectedColor,
          region: _selectedRegion,
        );
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.walletAccountUpdated),
              backgroundColor: AppColors.success,
            ),
          );
        }
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
    final isCreate = widget.account == null;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
      ),
      title: Text(
        isCreate ? l.addWalletAccount : l.editWalletAccount,
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(labelText: l.walletAccountName),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? l.required : null,
                ),
                const SizedBox(height: AppConstants.spaceMD),

                // Region (optional)
                DropdownButtonFormField<String?>(
                  initialValue: _selectedRegion,
                  decoration: InputDecoration(labelText: l.walletRegion),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l.walletGlobal),
                    ),
                    ...AppConstants.cameroonRegions.map(
                      (r) => DropdownMenuItem<String?>(
                        value: r,
                        child: Text(r),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedRegion = v),
                ),
                const SizedBox(height: AppConstants.spaceMD),

                // Type
                DropdownButtonFormField<String>(
                  initialValue: _selectedType,
                  decoration: InputDecoration(labelText: l.walletAccountType),
                  items: AppConstants.walletAccountTypes
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(_typeLabel(t, l)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedType = v);
                  },
                ),
                const SizedBox(height: AppConstants.spaceMD),

                // Currency
                TextFormField(
                  controller: _currencyCtrl,
                  decoration:
                      InputDecoration(labelText: l.walletAccountCurrency),
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 5,
                  buildCounter: (_, {required int currentLength,
                          required bool isFocused,
                          required int? maxLength}) =>
                      null,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? l.required : null,
                ),
                const SizedBox(height: AppConstants.spaceMD),

                // Opening balance (create only)
                if (isCreate) ...[
                  TextFormField(
                    controller: _openingBalanceCtrl,
                    decoration: InputDecoration(
                      labelText: l.walletOpeningBalance,
                      hintText: '0',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: AppConstants.spaceMD),
                ],

                // Color picker
                Text(
                  l.walletColor,
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: AppConstants.spaceSM),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: AppConstants.walletColorPalette.map((hex) {
                    final isSelected = _selectedColor == hex;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedColor = hex),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(
                            right: AppConstants.spaceSM),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _hexToColor(hex),
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(
                                  color: AppColors.textDark, width: 2.5)
                              : null,
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: _hexToColor(hex)
                                        .withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check_rounded,
                                color: Colors.white, size: 20)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(l.save),
        ),
      ],
    );
  }
}
