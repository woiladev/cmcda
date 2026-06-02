import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/repositories/contribution_repository.dart';
import '../../../data/repositories/pawapay_repository.dart';

// ── Providers ─────────────────────────────────────────────────

final _pendingPaymentsStreamProvider =
    StreamProvider.autoDispose<List<ContributionModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(AppConstants.contributionsCollection)
      .where('status', isEqualTo: AppConstants.statusPending)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => ContributionModel.fromFirestore(d)).toList());
});

final _allPaymentsStreamProvider =
    StreamProvider.autoDispose<List<ContributionModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(AppConstants.contributionsCollection)
      .orderBy('createdAt', descending: true)
      .limit(60)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => ContributionModel.fromFirestore(d)).toList());
});

final _paymentStatsProvider =
    FutureProvider.autoDispose<({int today, int month})>((ref) async {
  final repo = ContributionRepository();
  final results =
      await Future.wait([repo.getTodayTotal(), repo.getMonthTotal()]);
  return (today: results[0], month: results[1]);
});

// ── Screen ────────────────────────────────────────────────────

class AdminPaymentsScreen extends ConsumerStatefulWidget {
  const AdminPaymentsScreen({super.key});

  @override
  ConsumerState<AdminPaymentsScreen> createState() =>
      _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends ConsumerState<AdminPaymentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _repo = ContributionRepository();
  final _pawaPay = PawaPayRepository();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Validate ──────────────────────────────────────────────

  Future<void> _handleValidate(
      ContributionModel c, String adminId) async {
    final l = AppLocalizations.of(context);
    // Bank transfers use single-step approval; cash keeps dual-validation.
    final isBank = c.isBankTransfer;
    final isFirst = c.validatedBy == null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final lc = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(
            isBank
                ? lc.approvePayment
                : (isFirst ? lc.firstValidation : lc.secondValidation),
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, color: AppColors.textDark),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.memberName,
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark)),
              const SizedBox(height: 4),
              Text(
                '${AppUtils.formatAmount(c.amount)} · ${_methodLabel(c.paymentMethod, l)}',
                style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textGray, fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(lc.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary),
              child: Text(lc.confirm,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final errMsg = l.unknownError;

    try {
      if (isBank) {
        await _repo.confirmContribution(c.id, adminId);
        messenger.showSnackBar(SnackBar(
          content: Text(l.paymentSuccess),
          backgroundColor: AppColors.success,
        ));
      } else if (isFirst) {
        await _repo.validatePayment(c.id, adminId);
        messenger.showSnackBar(SnackBar(
          content: Text(l.firstValidationRecorded),
          backgroundColor: AppColors.info,
        ));
      } else {
        await _repo.secondValidatePayment(c.id, adminId);
        // The "payment confirmed" push is sent server-side by the
        // onContributionConfirmed Cloud Function.
        messenger.showSnackBar(SnackBar(
          content: Text(l.paymentSuccess),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(errMsg),
        backgroundColor: AppColors.error,
      ));
    }
  }

  // ── Reject ────────────────────────────────────────────────

  Future<void> _handleReject(ContributionModel c, String adminId) async {
    final l = AppLocalizations.of(context);
    final reasonCtrl = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final lc = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(
              lc.rejectPayment,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, color: AppColors.error),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c.memberName} · ${AppUtils.formatAmount(c.amount)}',
                  style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textGray, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 3,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: lc.enterRejectReason,
                    hintStyle: GoogleFonts.plusJakartaSans(
                        color: AppColors.textGray, fontSize: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          AppConstants.radiusMD),
                      borderSide:
                          const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          AppConstants.radiusMD),
                      borderSide: const BorderSide(
                          color: AppColors.error, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(lc.cancel),
              ),
              ElevatedButton(
                onPressed: () =>
                    Navigator.pop(ctx, reasonCtrl.text),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error),
                child: Text(lc.reject,
                    style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );

    reasonCtrl.dispose();
    if (reason == null || reason.trim().isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final errMsg = l.unknownError;
    try {
      await _repo.rejectPayment(c.id, adminId, reason.trim());
      messenger.showSnackBar(SnackBar(
        content: Text(l.paymentRejected),
        backgroundColor: AppColors.warning,
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(errMsg),
        backgroundColor: AppColors.error,
      ));
    }
  }

  // ── Check mobile money status ─────────────────────────────

  Future<void> _handleCheckMoMo(ContributionModel c) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final status = await _pawaPay.checkDeposit(c.id);
      if (!mounted) return;
      if (status == AppConstants.statusConfirmed) {
        messenger.showSnackBar(SnackBar(
          content: Text(l.paymentSuccess),
          backgroundColor: AppColors.success,
        ));
      } else if (status == AppConstants.statusFailed) {
        messenger.showSnackBar(SnackBar(
          content: Text(l.paymentFailed),
          backgroundColor: AppColors.error,
        ));
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text(l.statusRefreshed),
          backgroundColor: AppColors.info,
        ));
      }
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(l.unknownError),
        backgroundColor: AppColors.error,
      ));
    }
  }

  // ── Cancel stuck mobile money deposit ─────────────────────

  Future<void> _handleCancelMoMo(
      ContributionModel c, String adminId) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final lc = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(
            lc.cancelMobilePayment,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, color: AppColors.error),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.memberName,
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark)),
              const SizedBox(height: 4),
              Text(
                '${AppUtils.formatAmount(c.amount)} · ${_methodLabel(c.paymentMethod, lc)}',
                style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textGray, fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(lc.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: Text(lc.cancelMobilePayment,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.rejectPayment(
          c.id, adminId, 'Annulé par l\'administrateur');
      messenger.showSnackBar(SnackBar(
        content: Text(l.paymentRejected),
        backgroundColor: AppColors.warning,
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(l.unknownError),
        backgroundColor: AppColors.error,
      ));
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final pendingAsync = ref.watch(_pendingPaymentsStreamProvider);
    final allAsync = ref.watch(_allPaymentsStreamProvider);
    final statsAsync = ref.watch(_paymentStatsProvider);
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final adminId = profile?.id ?? '';
    final isSuperAdmin = profile?.isSuperAdmin ?? false;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(context, l, pendingAsync),
          _buildStatsBar(l, statsAsync, pendingAsync),
          _buildTabBar(l),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _PendingTabBody(
                  paymentsAsync: pendingAsync,
                  adminId: adminId,
                  isSuperAdmin: isSuperAdmin,
                  onValidate: _handleValidate,
                  onReject: _handleReject,
                  onCheckMoMo: _handleCheckMoMo,
                  onCancelMoMo: _handleCancelMoMo,
                ),
                _AllTabBody(paymentsAsync: allAsync),
                _RejectedTabBody(paymentsAsync: allAsync),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    AppLocalizations l,
    AsyncValue<List<ContributionModel>> pendingAsync,
  ) {
    final count = pendingAsync.valueOrNull?.length ?? 0;

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
        MediaQuery.of(context).padding.top + AppConstants.spaceSM,
        AppConstants.spaceMD,
        AppConstants.spaceMD,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l.paymentsManagement,
              style: GoogleFonts.playfairDisplay(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (count > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warning,
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.hourglass_top_rounded,
                      color: Colors.white, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Stats bar ─────────────────────────────────────────────

  Widget _buildStatsBar(
    AppLocalizations l,
    AsyncValue<({int today, int month})> statsAsync,
    AsyncValue<List<ContributionModel>> pendingAsync,
  ) {
    final pending = pendingAsync.valueOrNull?.length ?? 0;
    final stats = statsAsync.valueOrNull;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMD,
          vertical: AppConstants.spaceMD),
      child: Row(
        children: [
          _StatPill(
            label: l.pendingTab,
            value: '$pending',
            color: AppColors.warning,
          ),
          const SizedBox(width: AppConstants.spaceSM),
          Expanded(
            child: _StatPill(
              label: l.todayLabel,
              value: stats != null ? _shortAmount(stats.today) : '—',
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppConstants.spaceSM),
          Expanded(
            child: _StatPill(
              label: l.thisMonth,
              value: stats != null ? _shortAmount(stats.month) : '—',
              color: AppColors.accentCyan,
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────

  Widget _buildTabBar(AppLocalizations l) {
    return Container(
      color: AppColors.surface,
      child: TabBar(
        controller: _tabs,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textGray,
        indicatorColor: AppColors.primary,
        indicatorWeight: 2.5,
        labelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13, fontWeight: FontWeight.w500),
        tabs: [
          Tab(text: l.pendingTab),
          Tab(text: l.recentTab),
          Tab(text: l.rejectedTab),
        ],
      ),
    );
  }
}

// ── Pending tab ───────────────────────────────────────────────

class _PendingTabBody extends StatelessWidget {
  final AsyncValue<List<ContributionModel>> paymentsAsync;
  final String adminId;
  final bool isSuperAdmin;
  final Future<void> Function(ContributionModel, String) onValidate;
  final Future<void> Function(ContributionModel, String) onReject;
  final Future<void> Function(ContributionModel) onCheckMoMo;
  final Future<void> Function(ContributionModel, String) onCancelMoMo;

  const _PendingTabBody({
    required this.paymentsAsync,
    required this.adminId,
    required this.isSuperAdmin,
    required this.onValidate,
    required this.onReject,
    required this.onCheckMoMo,
    required this.onCancelMoMo,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return paymentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(child: Text(l.unknownError)),
      data: (payments) {
        if (payments.isEmpty) {
          return _EmptyState(
            icon: Icons.check_circle_outline_rounded,
            message: l.noPendingPayments,
            color: AppColors.success,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppConstants.spaceMD),
          itemCount: payments.length,
          itemBuilder: (_, i) => _PendingPaymentCard(
            contribution: payments[i],
            adminId: adminId,
            isSuperAdmin: isSuperAdmin,
            onValidate: onValidate,
            onReject: onReject,
            onCheckMoMo: onCheckMoMo,
            onCancelMoMo: onCancelMoMo,
          ),
        );
      },
    );
  }
}

// ── All tab ───────────────────────────────────────────────────

class _AllTabBody extends StatelessWidget {
  final AsyncValue<List<ContributionModel>> paymentsAsync;
  const _AllTabBody({required this.paymentsAsync});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return paymentsAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(child: Text(l.unknownError)),
      data: (payments) {
        if (payments.isEmpty) {
          return _EmptyState(
            icon: Icons.receipt_long_outlined,
            message: l.noPayments,
            color: AppColors.textGray,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppConstants.spaceMD),
          itemCount: payments.length,
          itemBuilder: (_, i) =>
              _CompactPaymentCard(contribution: payments[i]),
        );
      },
    );
  }
}

// ── Rejected tab ──────────────────────────────────────────────

class _RejectedTabBody extends StatelessWidget {
  final AsyncValue<List<ContributionModel>> paymentsAsync;
  const _RejectedTabBody({required this.paymentsAsync});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return paymentsAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(child: Text(l.unknownError)),
      data: (all) {
        final rejected =
            all.where((c) => c.isFailed).toList();
        if (rejected.isEmpty) {
          return _EmptyState(
            icon: Icons.thumb_up_outlined,
            message: AppLocalizations.of(context).noRejectedPayments,
            color: AppColors.success,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppConstants.spaceMD),
          itemCount: rejected.length,
          itemBuilder: (_, i) =>
              _CompactPaymentCard(contribution: rejected[i]),
        );
      },
    );
  }
}

// ── Pending payment card (with action buttons) ────────────────

class _PendingPaymentCard extends StatelessWidget {
  final ContributionModel contribution;
  final String adminId;
  final bool isSuperAdmin;
  final Future<void> Function(ContributionModel, String) onValidate;
  final Future<void> Function(ContributionModel, String) onReject;
  final Future<void> Function(ContributionModel) onCheckMoMo;
  final Future<void> Function(ContributionModel, String) onCancelMoMo;

  const _PendingPaymentCard({
    required this.contribution,
    required this.adminId,
    required this.isSuperAdmin,
    required this.onValidate,
    required this.onReject,
    required this.onCheckMoMo,
    required this.onCancelMoMo,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = contribution;
    final isBank = c.isBankTransfer;
    final isMobileMoney = c.isMobileMoney;
    final isStep2 = c.validatedBy != null && c.secondValidatorId == null;
    final stepLabel =
        isStep2 ? l.secondValidationShort : l.firstValidationShort;
    final stepColor = isStep2 ? AppColors.info : AppColors.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.textDark.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Step badge + member row
          Padding(
            padding: const EdgeInsets.all(AppConstants.spaceMD),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InitialsAvatar(
                    name: c.memberName, color: AppColors.warning),
                const SizedBox(width: AppConstants.spaceMD),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.memberName,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Mobile money: "awaiting PIN" badge.
                          // Cash: dual-validation step badge.
                          // Bank: no badge (single-step).
                          if (isMobileMoney)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.warning
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusFull),
                                border: Border.all(
                                    color: AppColors.warning
                                        .withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                l.awaitingPin,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.warning,
                                ),
                              ),
                            )
                          else if (!isBank)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: stepColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusFull),
                                border: Border.all(
                                    color: stepColor.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                stepLabel,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: stepColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        c.memberNumber,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      if (isMobileMoney && c.payerPhone != null) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.smartphone_rounded,
                                size: 12, color: AppColors.textGray),
                            const SizedBox(width: 4),
                            Text(
                              c.payerPhone!,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: AppColors.textGray),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _MethodBadge(method: c.paymentMethod),
                          const SizedBox(
                              width: AppConstants.spaceSM),
                          Expanded(
                            child: Text(
                              _formatPeriod(c.period),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: AppColors.textGray),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppConstants.spaceSM),
                          Text(
                            AppUtils.formatAmount(c.amount),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDateTime(c.createdAt.toDate(), Localizations.localeOf(context).languageCode),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppColors.textGray),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Proof of transfer (bank transfers)
          if (c.proofUrl != null) ...[
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.all(AppConstants.spaceMD),
              child: _ProofThumbnail(url: c.proofUrl!, label: l.proofOfTransfer),
            ),
          ],
          // ── Divider
          const Divider(height: 1, color: AppColors.border),
          // ── Action buttons (super_admin only; admins are view-only)
          if (isSuperAdmin)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceMD,
                  vertical: AppConstants.spaceSM),
              child: isMobileMoney
                  // Mobile money: refresh status + cancel (no manual approval).
                  ? Row(
                      children: [
                        Expanded(
                          child: _ActionBtn(
                            label: AppLocalizations.of(context).refreshStatus,
                            icon: Icons.refresh_rounded,
                            color: AppColors.primary,
                            outlined: true,
                            onTap: () => onCheckMoMo(c),
                          ),
                        ),
                        const SizedBox(width: AppConstants.spaceSM),
                        Expanded(
                          child: _ActionBtn(
                            label: AppLocalizations.of(context)
                                .cancelMobilePayment,
                            icon: Icons.cancel_outlined,
                            color: AppColors.error,
                            outlined: true,
                            onTap: () => onCancelMoMo(c, adminId),
                          ),
                        ),
                      ],
                    )
                  // Cash / bank: dual-validation or single-step approval.
                  : Row(
                      children: [
                        Expanded(
                          child: _ActionBtn(
                            label: AppLocalizations.of(context).reject,
                            icon: Icons.close_rounded,
                            color: AppColors.error,
                            outlined: true,
                            onTap: () => onReject(c, adminId),
                          ),
                        ),
                        const SizedBox(width: AppConstants.spaceSM),
                        Expanded(
                          flex: 2,
                          child: _ActionBtn(
                            label: isBank
                                ? AppLocalizations.of(context).approvePayment
                                : (isStep2
                                    ? AppLocalizations.of(context).confirm
                                    : AppLocalizations.of(context).validate),
                            icon: Icons.check_rounded,
                            color: AppColors.success,
                            outlined: false,
                            onTap: () => onValidate(c, adminId),
                          ),
                        ),
                      ],
                    ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceMD,
                  vertical: AppConstants.spaceMD),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 14, color: AppColors.textGray),
                  const SizedBox(width: AppConstants.spaceSM),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).superAdminOnly,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: AppColors.textGray),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Compact payment card (recent / rejected) ──────────────────

class _CompactPaymentCard extends StatelessWidget {
  final ContributionModel contribution;
  const _CompactPaymentCard({required this.contribution});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = contribution;
    final (statusColor, statusLabel) = _statusInfo(c.status, l);

    return GestureDetector(
      onTap: () => _showDetail(context, c),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spaceSM),
        padding: const EdgeInsets.all(AppConstants.spaceMD),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusLG),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.textDark.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            _InitialsAvatar(
                name: c.memberName, color: statusColor),
            const SizedBox(width: AppConstants.spaceMD),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.memberName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        AppUtils.formatAmount(c.amount),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        c.memberNumber,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: AppConstants.spaceSM),
                      _MethodBadge(method: c.paymentMethod),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull),
                        ),
                        child: Text(
                          statusLabel,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        _formatDateTime(c.createdAt.toDate(), Localizations.localeOf(context).languageCode),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppColors.textGray),
                      ),
                      if (c.isFailed &&
                          c.notes != null &&
                          c.notes!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '· ${c.notes}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: AppColors.error,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppConstants.spaceXS),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textLight, size: 18),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, ContributionModel c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentDetailSheet(contribution: c),
    );
  }
}

// ── Payment detail sheet ──────────────────────────────────────

class _PaymentDetailSheet extends StatelessWidget {
  final ContributionModel contribution;
  const _PaymentDetailSheet({required this.contribution});

  @override
  Widget build(BuildContext context) {
    final c = contribution;
    final l = AppLocalizations.of(context);
    final (statusColor, statusLabel) = _statusInfo(c.status, l);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppConstants.radiusXL)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: AppConstants.spaceMD),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(
                    AppConstants.spaceLG,
                    0,
                    AppConstants.spaceLG,
                    AppConstants.spaceXL),
                children: [
                  // ── Header
                  Row(
                    children: [
                      _InitialsAvatar(
                          name: c.memberName,
                          color: statusColor,
                          size: 52),
                      const SizedBox(width: AppConstants.spaceMD),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.memberName,
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              c.memberNumber,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull),
                          border: Border.all(
                              color: statusColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          statusLabel,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // ── Amount hero
                  Container(
                    padding: const EdgeInsets.all(AppConstants.spaceLG),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusLG),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.amount,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: AppColors.textGray),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppUtils.formatAmount(c.amount),
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.end,
                          children: [
                            Text(
                              _methodLabel(c.paymentMethod, l),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textDark),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatPeriod(c.period),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: AppColors.textGray),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // ── Detail rows
                  _DetailRow(
                    icon: Icons.receipt_outlined,
                    label: l.receiptNo,
                    value: c.receiptNumber.isNotEmpty
                        ? c.receiptNumber
                        : '—',
                  ),
                  _DetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: l.submissionDate,
                    value: _formatDateTime(c.createdAt.toDate(), Localizations.localeOf(context).languageCode),
                  ),
                  if (c.confirmedAt != null)
                    _DetailRow(
                      icon: Icons.check_circle_outline_rounded,
                      label: l.confirmedOn,
                      value: _formatDateTime(c.confirmedAt!.toDate(),
                          Localizations.localeOf(context).languageCode),
                      valueColor: AppColors.success,
                    ),
                  if (c.isFailed &&
                      c.notes != null &&
                      c.notes!.isNotEmpty)
                    _DetailRow(
                      icon: Icons.info_outline_rounded,
                      label: l.rejectReason,
                      value: c.notes!,
                      valueColor: AppColors.error,
                    ),

                  // ── Proof of transfer
                  if (c.proofUrl != null) ...[
                    const SizedBox(height: AppConstants.spaceSM),
                    _ProofThumbnail(
                        url: c.proofUrl!, label: l.proofOfTransfer),
                    const SizedBox(height: AppConstants.spaceSM),
                  ],

                  // ── Validation trace
                  if (c.validationRequired) ...[
                    const SizedBox(height: AppConstants.spaceMD),
                    const Divider(color: AppColors.border),
                    const SizedBox(height: AppConstants.spaceMD),
                    Text(
                      l.validationTrace,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textGray,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: AppConstants.spaceMD),
                    _ValidationStep(
                      step: 1,
                      label: l.firstValidation,
                      done: c.validatedBy != null,
                      uid: c.validatedBy,
                    ),
                    const SizedBox(height: AppConstants.spaceSM),
                    _ValidationStep(
                      step: 2,
                      label: l.secondValidation,
                      done: c.secondValidatorId != null,
                      uid: c.secondValidatorId,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers widgets ───────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMD,
          vertical: AppConstants.spaceSM),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius:
            BorderRadius.circular(AppConstants.radiusMD),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String name;
  final Color color;
  final double size;

  const _InitialsAvatar({
    required this.name,
    required this.color,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(' ');
    final initials =
        parts.map((p) => p.isNotEmpty ? p[0].toUpperCase() : '').take(2).join();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.plusJakartaSans(
          fontSize: size * 0.3,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _MethodBadge extends StatelessWidget {
  final String method;
  const _MethodBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (color, label) = _methodInfo(method, l);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius:
            BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool outlined;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.outlined,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(
              color: color, width: outlined ? 1.5 : 0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: outlined ? color : Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: outlined ? color : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceMD),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: AppConstants.spaceSM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textGray,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: valueColor ?? AppColors.textDark,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ValidationStep extends StatelessWidget {
  final int step;
  final String label;
  final bool done;
  final String? uid;

  const _ValidationStep({
    required this.step,
    required this.label,
    required this.done,
    this.uid,
  });

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.success : AppColors.textGray;

    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: done
                ? AppColors.success.withValues(alpha: 0.12)
                : AppColors.border.withValues(alpha: 0.4),
            shape: BoxShape.circle,
            border: Border.all(
                color: done ? AppColors.success : AppColors.border),
          ),
          alignment: Alignment.center,
          child: done
              ? const Icon(Icons.check_rounded,
                  size: 14, color: AppColors.success)
              : Text(
                  '$step',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textGray),
                ),
        ),
        const SizedBox(width: AppConstants.spaceSM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              if (done && uid != null)
                Text(
                  'UID: ${uid!.substring(0, 8)}…',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10, color: AppColors.textGray),
                ),
            ],
          ),
        ),
        if (done)
          const Icon(Icons.check_circle_rounded,
              size: 16, color: AppColors.success),
      ],
    );
  }
}

class _ProofThumbnail extends StatelessWidget {
  final String url;
  final String label;
  const _ProofThumbnail({required this.url, required this.label});

  void _open(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _ProofViewer(url: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.image_outlined,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: AppConstants.spaceSM),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textGray,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceSM),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            child: Image.network(
              url,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) => progress == null
                  ? child
                  : Container(
                      height: 160,
                      color: AppColors.bg,
                      child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
              errorBuilder: (ctx, _, __) => Container(
                height: 160,
                color: AppColors.bg,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined,
                    color: AppColors.textGray),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofViewer extends StatelessWidget {
  final String url;
  const _ProofViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (ctx, _, __) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                      size: 48),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: color.withValues(alpha: 0.4)),
          const SizedBox(height: AppConstants.spaceMD),
          Text(
            message,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }
}

// ── Pure helpers ──────────────────────────────────────────────

String _formatPeriod(String period) {
  try {
    final parts = period.split('-');
    if (parts.length == 2) {
      final date =
          DateTime(int.parse(parts[0]), int.parse(parts[1]));
      final s = DateFormat('MMMM yyyy', 'fr_FR').format(date);
      return s[0].toUpperCase() + s.substring(1);
    }
  } catch (_) {}
  return period;
}

String _formatDateTime(DateTime dt, String localeCode) {
  return DateFormat('d MMM yyyy · HH:mm', localeCode).format(dt);
}

String _methodLabel(String method, AppLocalizations l) {
  switch (method) {
    case AppConstants.paymentMtnMomo:
      return 'MTN MoMo';
    case AppConstants.paymentOrangeMoney:
      return 'Orange Money';
    case AppConstants.paymentCash:
      return l.cash;
    default:
      return l.bankTransfer;
  }
}

(Color, String) _methodInfo(String method, AppLocalizations l) {
  switch (method) {
    case AppConstants.paymentMtnMomo:
      return (const Color(0xFFFFCC00), 'MTN');
    case AppConstants.paymentOrangeMoney:
      return (Colors.deepOrange, 'Orange');
    case AppConstants.paymentCash:
      return (AppColors.success, l.cash);
    default:
      return (AppColors.info, l.bankTransfer);
  }
}

(Color, String) _statusInfo(String status, AppLocalizations l) {
  switch (status) {
    case AppConstants.statusConfirmed:
      return (AppColors.success, l.confirmed);
    case AppConstants.statusFailed:
      return (AppColors.error, l.rejectedStatus);
    default:
      return (AppColors.warning, l.pending);
  }
}

String _shortAmount(int fcfa) {
  if (fcfa >= 1000000) {
    return '${(fcfa / 1000000).toStringAsFixed(1)}M';
  }
  if (fcfa >= 1000) {
    return '${(fcfa / 1000).toStringAsFixed(0)}K';
  }
  return '$fcfa';
}
