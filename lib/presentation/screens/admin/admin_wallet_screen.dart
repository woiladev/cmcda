import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
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

// ── Screen ─────────────────────────────────────────────────────

class AdminWalletScreen extends ConsumerStatefulWidget {
  const AdminWalletScreen({super.key});

  @override
  ConsumerState<AdminWalletScreen> createState() => _AdminWalletScreenState();
}

class _AdminWalletScreenState extends ConsumerState<AdminWalletScreen> {
  bool _seeding   = false;
  bool _backfilling = false;

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
  Future<void> _initRegionalWallets(
    AppLocalizations l,
    List<WalletAccountModel> existingAccounts,
  ) async {
    if (_seeding) return;
    setState(() => _seeding = true);

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Map region → existing accountId for already-created regional wallets
    final existingByRegion = <String, String>{};
    for (final acc in existingAccounts) {
      if (acc.region != null && acc.region!.isNotEmpty) {
        existingByRegion[acc.region!] = acc.id;
      }
    }

    try {
      final paymentMap = <String, String>{};

      for (final region in AppConstants.cameroonRegions) {
        final existingId = existingByRegion[region];
        if (existingId != null) {
          paymentMap[region] = existingId;
        } else {
          final color =
              AppConstants.regionWalletColors[region] ??
              AppConstants.walletColorPalette.first;
          final id = await _walletRepo.createAccount(
            name: 'Trésorerie – $region',
            type: AppConstants.walletTypeOther,
            currency: AppConstants.defaultCurrency,
            openingBalance: 0,
            color: color,
            region: region,
            createdBy: uid,
          );
          paymentMap[region] = id;
        }
      }

      await _walletRepo.updatePaymentMap(paymentMap);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.regionalWalletsReady),
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
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: AppConstants.spaceSM),
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
          // Initialize regional wallets button
          if (_seeding)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            )
          else
            IconButton(
              onPressed: () => _initRegionalWallets(l, accounts),
              tooltip: l.initRegionalWallets,
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
        _buildRegionMappingSection(context),
        const SizedBox(height: AppConstants.spaceXL),
      ],
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

  // ── Regional mapping section ────────────────────────────────

  Widget _buildRegionMappingSection(BuildContext context) {
    final l = AppLocalizations.of(context);
    final paymentMapAsync = ref.watch(_paymentMapProvider);
    final accountsAsync  = ref.watch(_accountsProvider);

    final accounts   = accountsAsync.valueOrNull ?? [];
    final paymentMap = paymentMapAsync.valueOrNull ?? {};

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceMD,
            vertical: AppConstants.spaceXS,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppConstants.spaceMD,
            0,
            AppConstants.spaceMD,
            AppConstants.spaceMD,
          ),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppConstants.radiusSM),
            ),
            child: const Icon(Icons.public_rounded,
                color: AppColors.info, size: 18),
          ),
          title: Text(
            l.regionMapping,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            l.regionMappingHint,
            style: const TextStyle(
              color: AppColors.textGray,
              fontSize: 12,
            ),
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: AppConstants.spaceSM),
            ...AppConstants.cameroonRegions.map((region) {
              final currentAccountId = paymentMap[region];
              final regionColor = AppConstants.regionWalletColors[region];
              final accentColor = regionColor != null
                  ? Color(int.parse(
                      'FF${regionColor.replaceFirst('#', '')}',
                      radix: 16))
                  : AppColors.primary;

              return Padding(
                padding:
                    const EdgeInsets.only(bottom: AppConstants.spaceSM),
                child: Row(
                  children: [
                    // Region color dot
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spaceSM),
                    // Region name
                    Expanded(
                      child: Text(
                        region,
                        style: const TextStyle(
                          color: AppColors.textMid,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spaceSM),
                    // Account dropdown
                    DropdownButton<String?>(
                      value: accounts.any((a) => a.id == currentAccountId)
                          ? currentAccountId
                          : null,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 13,
                      ),
                      hint: const Text(
                        '— Non affecté —',
                        style: TextStyle(
                          color: AppColors.textGray,
                          fontSize: 12,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            '— Non affecté —',
                            style: TextStyle(
                              color: AppColors.textGray,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        ...accounts.map(
                          (a) => DropdownMenuItem<String?>(
                            value: a.id,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: a.accentColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  a.name,
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      onChanged: (newAccountId) async {
                        final updated = Map<String, String>.from(paymentMap);
                        if (newAccountId == null) {
                          updated.remove(region);
                        } else {
                          updated[region] = newAccountId;
                        }
                        final messenger = ScaffoldMessenger.of(context);
                        final errorMsg =
                            AppLocalizations.of(context).unknownError;
                        try {
                          await _walletRepo.updatePaymentMap(updated);
                        } catch (_) {
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(errorMsg),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
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
