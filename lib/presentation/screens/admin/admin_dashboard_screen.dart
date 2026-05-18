import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/repositories/contribution_repository.dart';
import 'send_notification_sheet.dart';

// ── Data classes ──────────────────────────────────────────────

class _AdminStats {
  final int todayTotal;
  final int yesterdayTotal;
  final int monthTotal;
  final int activeMembers;
  final int lateMembers;
  final int newMembersToday;

  const _AdminStats({
    required this.todayTotal,
    required this.yesterdayTotal,
    required this.monthTotal,
    required this.activeMembers,
    required this.lateMembers,
    required this.newMembersToday,
  });
}

class _DayStat {
  final DateTime date;
  final int total;
  const _DayStat(this.date, this.total);
}

class _PlatformVisionStats {
  final int totalMembers;
  final int yearRevenue;

  const _PlatformVisionStats({
    required this.totalMembers,
    required this.yearRevenue,
  });
}

// ── Providers ─────────────────────────────────────────────────

final _pendingPaymentsProvider =
    StreamProvider.autoDispose<List<ContributionModel>>((ref) {
  return ContributionRepository().getPendingPayments();
});

final _recentPaymentsProvider =
    StreamProvider.autoDispose<List<ContributionModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(AppConstants.contributionsCollection)
      .orderBy('createdAt', descending: true)
      .limit(10)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => ContributionModel.fromFirestore(d)).toList());
});

final _adminStatsProvider =
    FutureProvider.autoDispose<_AdminStats>((ref) async {
  final db = FirebaseFirestore.instance;
  final col = db.collection(AppConstants.contributionsCollection);
  final usersCol = db.collection(AppConstants.usersCollection);

  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final startOfYesterday = startOfDay.subtract(const Duration(days: 1));
  final currentPeriod = AppUtils.getPeriodForDate(now);

  final tsDay = Timestamp.fromDate(startOfDay);
  final tsYest = Timestamp.fromDate(startOfYesterday);

  // All 5 queries in one parallel batch — single Firestore round trip.
  // Today/yesterday use aggregate sum to avoid downloading full documents.
  final results = await Future.wait<dynamic>([
    // [0] Today's total — aggregate sum, no document reads
    col
        .where('status', isEqualTo: AppConstants.statusConfirmed)
        .where('createdAt', isGreaterThanOrEqualTo: tsDay)
        .aggregate(sum('amount'))
        .get(),
    // [1] Yesterday's total — aggregate sum
    col
        .where('status', isEqualTo: AppConstants.statusConfirmed)
        .where('createdAt', isGreaterThanOrEqualTo: tsYest)
        .where('createdAt', isLessThan: tsDay)
        .aggregate(sum('amount'))
        .get(),
    // [2] Month docs — needed to derive paid member IDs for lateMembers
    col
        .where('period', isEqualTo: currentPeriod)
        .where('status', isEqualTo: AppConstants.statusConfirmed)
        .get(),
    // [3] Active member count
    usersCol
        .where('role', isEqualTo: AppConstants.roleMember)
        .where('status', isEqualTo: AppConstants.userStatusActive)
        .count()
        .get(),
    // [4] New members today
    usersCol
        .where('role', isEqualTo: AppConstants.roleMember)
        .where('createdAt', isGreaterThanOrEqualTo: tsDay)
        .count()
        .get(),
  ]);

  final todayTotal =
      ((results[0] as AggregateQuerySnapshot).getSum('amount') ?? 0).toInt();
  final yesterdayTotal =
      ((results[1] as AggregateQuerySnapshot).getSum('amount') ?? 0).toInt();
  final monthSnap = results[2] as QuerySnapshot;
  final activeMembers = (results[3] as AggregateQuerySnapshot).count ?? 0;
  final newMembersToday = (results[4] as AggregateQuerySnapshot).count ?? 0;

  int sumDocs(QuerySnapshot snap) => snap.docs.fold<int>(
      0, (s, d) => s + ((d.data() as Map)['amount'] as num? ?? 0).toInt());

  final monthTotal = sumDocs(monthSnap);
  final paidMemberIds = monthSnap.docs
      .map((d) => (d.data() as Map)['memberId'] as String? ?? '')
      .where((id) => id.isNotEmpty)
      .toSet();

  final lateMembers =
      (activeMembers - paidMemberIds.length).clamp(0, activeMembers);

  return _AdminStats(
    todayTotal: todayTotal,
    yesterdayTotal: yesterdayTotal,
    monthTotal: monthTotal,
    activeMembers: activeMembers,
    lateMembers: lateMembers,
    newMembersToday: newMembersToday,
  );
});

final _platformVisionProvider =
    FutureProvider.autoDispose<_PlatformVisionStats>((ref) async {
  final db = FirebaseFirestore.instance;
  final now = DateTime.now();
  final startOfYear = DateTime(now.year, 1, 1);

  // Use aggregate sum for year revenue — avoids downloading all contribution docs.
  final results = await Future.wait<dynamic>([
    db
        .collection(AppConstants.usersCollection)
        .count()
        .get(),
    db
        .collection(AppConstants.contributionsCollection)
        .where('status', isEqualTo: AppConstants.statusConfirmed)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfYear))
        .aggregate(sum('amount'))
        .get(),
  ]);

  final totalMembers =
      (results[0] as AggregateQuerySnapshot).count ?? 0;
  final yearRevenue =
      ((results[1] as AggregateQuerySnapshot).getSum('amount') ?? 0).toInt();

  return _PlatformVisionStats(
    totalMembers: totalMembers,
    yearRevenue: yearRevenue,
  );
});

final _chartDataProvider =
    FutureProvider.autoDispose<List<_DayStat>>((ref) async {
  final now = DateTime.now();
  final startDay = DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 13));

  final snap = await FirebaseFirestore.instance
      .collection(AppConstants.contributionsCollection)
      .where('status', isEqualTo: AppConstants.statusConfirmed)
      .where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDay))
      .get();

  final days = List.generate(
      14, (i) => _DayStat(startDay.add(Duration(days: i)), 0));

  for (final doc in snap.docs) {
    final ts = (doc.data() as Map)['createdAt'] as Timestamp?;
    if (ts == null) continue;
    final date = ts.toDate();
    final idx = date.difference(startDay).inDays;
    if (idx >= 0 && idx < 14) {
      days[idx] = _DayStat(
        days[idx].date,
        days[idx].total +
            ((doc.data() as Map)['amount'] as num? ?? 0).toInt(),
      );
    }
  }

  return days;
});

// ── Screen ────────────────────────────────────────────────────

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  final _contribRepo = ContributionRepository();
  // ── Helpers ───────────────────────────────────────────────

  String _trend(int today, int yesterday) {
    if (yesterday == 0) return today > 0 ? '↑ +100%' : '—';
    final pct = ((today - yesterday) / yesterday * 100).round();
    return pct >= 0 ? '↑ +$pct%' : '↓ ${pct.abs()}%';
  }

  Color _trendColor(int today, int yesterday) {
    if (yesterday == 0) {
      return today > 0 ? AppColors.success : AppColors.textGray;
    }
    return today >= yesterday ? AppColors.success : AppColors.error;
  }

  String _paymentMethodShort(String method) {
    switch (method) {
      case AppConstants.paymentMtnMomo:
        return 'MTN MoMo';
      case AppConstants.paymentOrangeMoney:
        return 'Orange Money';
      case AppConstants.paymentCash:
        return 'Espèces';
      default:
        return 'Virement';
    }
  }

  // ── Validation action ─────────────────────────────────────

  Future<void> _handleValidate(
      ContributionModel c, String adminId) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.validatePayment),
        content: Text(
            '${c.memberName}\n${AppUtils.formatAmount(c.amount)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      if (c.validatedBy == null) {
        await _contribRepo.validatePayment(c.id, adminId);
      } else if (c.secondValidatorId == null) {
        await _contribRepo.secondValidatePayment(c.id, adminId);
        if (c.memberId.isNotEmpty) {
          NotificationService.instance.notifyPaymentConfirmed(
            userId: c.memberId,
            amount: AppUtils.formatAmount(c.amount),
            receiptNumber: c.receiptNumber,
          ).ignore();
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.paymentSuccess),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.unknownError),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context)),
            SliverToBoxAdapter(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dateStr = DateFormat('EEEE d MMMM yyyy', 'fr_FR')
        .format(DateTime.now())
        .replaceFirstMapped(
            RegExp(r'^.'), (m) => m.group(0)!.toUpperCase());
    final pendingAsync = ref.watch(_pendingPaymentsProvider);
    final pendingCount =
        pendingAsync.valueOrNull?.length ?? 0;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(AppConstants.radiusXL),
          bottomRight: Radius.circular(AppConstants.radiusXL),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceMD,
        MediaQuery.of(context).padding.top + AppConstants.spaceMD,
        AppConstants.spaceMD,
        AppConstants.spaceLG,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.adminDashboardTitle,
                      style: GoogleFonts.playfairDisplay(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull),
                ),
                child: Text(
                  l10n.adminBadge,
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spaceSM),
              IconButton(
                onPressed: () {
                  ref.read(viewingAsMemberProvider.notifier).state = true;
                  context.go(AppRoutes.dashboard);
                },
                tooltip: 'Vue Membre',
                icon: const Icon(Icons.switch_account_outlined,
                    color: Colors.white, size: 22),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: AppConstants.spaceSM),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: () =>
                        context.push(AppRoutes.notifications),
                    icon: const Icon(
                      Icons.notifications_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  if (pendingCount > 0)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceLG),
          _buildPlatformVision(context, pendingCount),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────

  Widget _buildBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppConstants.spaceLG),
        _buildQuickActions(context),
        const SizedBox(height: AppConstants.spaceLG),
        _buildKpiCards(context),
        const SizedBox(height: AppConstants.spaceLG),
        _buildChartCard(context),
        const SizedBox(height: AppConstants.spaceLG),
        _buildRecentPayments(context),
        const SizedBox(height: AppConstants.spaceXL),
      ],
    );
  }

  // ── Platform Vision ───────────────────────────────────────

  Widget _buildPlatformVision(BuildContext context, int pendingCount) {
    final l10n = AppLocalizations.of(context);
    final visionAsync = ref.watch(_platformVisionProvider);

    Widget glass({required Widget child}) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppConstants.spaceLG),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppConstants.radiusLG),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: child,
        );

    Widget pendingStrip() {
      if (pendingCount <= 0) return const SizedBox.shrink();
      return Column(
        children: [
          const SizedBox(height: AppConstants.spaceMD),
          Divider(
              color: Colors.white.withValues(alpha: 0.12), height: 1),
          const SizedBox(height: AppConstants.spaceMD),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push(AppRoutes.adminPayments),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.22),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMD),
                  ),
                  child: const Icon(Icons.pending_actions_rounded,
                      color: AppColors.warning, size: 20),
                ),
                const SizedBox(width: AppConstants.spaceMD),
                Expanded(
                  child: Text(
                    '$pendingCount ${l10n.pendingValidation}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Row(
                    children: [
                      Text(
                        l10n.viewAll,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return visionAsync.when(
      loading: () => glass(
        child: const SizedBox(
          height: 200,
          child: Center(
            child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (stats) {
        final memberProgress =
            (stats.totalMembers / AppConstants.targetMembers).clamp(0.0, 1.0);
        final revenueProgress =
            (stats.yearRevenue / AppConstants.targetAnnualRevenue)
                .clamp(0.0, 1.0);
        final memberPct = (memberProgress * 100).toStringAsFixed(1);
        final revenuePct = (revenueProgress * 100).toStringAsFixed(2);

        return glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.18),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMD),
                    ),
                    child: const Icon(Icons.stars_rounded,
                        color: AppColors.gold, size: 22),
                  ),
                  const SizedBox(width: AppConstants.spaceMD),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.platformVision,
                          style: GoogleFonts.playfairDisplay(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.platformVisionSub,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceLG),

              // Members bar
              _VisionProgressBar(
                label: l10n.membersGoal,
                icon: Icons.group_outlined,
                progress: memberProgress,
                currentLabel: _formatLargeNumber(stats.totalMembers),
                targetLabel:
                    '${l10n.targetLabel} ${_formatLargeNumber(AppConstants.targetMembers)}',
                percentLabel: '$memberPct%',
                barColor: Colors.white,
                glowColor: Colors.white,
              ),
              const SizedBox(height: AppConstants.spaceLG),
              Divider(
                  color: Colors.white.withValues(alpha: 0.12), height: 1),
              const SizedBox(height: AppConstants.spaceLG),

              // Revenue bar
              _VisionProgressBar(
                label: l10n.annualRevenueGoal,
                icon: Icons.account_balance_wallet_outlined,
                progress: revenueProgress,
                currentLabel: _formatBigAmount(stats.yearRevenue),
                targetLabel:
                    '${l10n.targetLabel} ${_formatBigAmount(AppConstants.targetAnnualRevenue)}',
                percentLabel: '$revenuePct%',
                barColor: AppColors.gold,
                glowColor: AppColors.gold,
              ),

              // Pending validation — merged into the same container
              pendingStrip(),
            ],
          ),
        );
      },
    );
  }

  String _formatLargeNumber(int n) {
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
    }
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(0)}K';
    }
    return NumberFormat('#,###', 'fr_FR').format(n);
  }

  String _formatBigAmount(int n) {
    if (n >= 1000000000) {
      final v = n / 1000000000;
      return '${v.toStringAsFixed(v == v.truncateToDouble() ? 0 : 1)} Mrd FCFA';
    }
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(1)} M FCFA';
    }
    return '${NumberFormat('#,###', 'fr_FR').format(n)} FCFA';
  }

  // ── KPI Cards ─────────────────────────────────────────────

  Widget _buildKpiCards(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final statsAsync = ref.watch(_adminStatsProvider);
    final pendingAsync = ref.watch(_pendingPaymentsProvider);
    final pendingCount =
        pendingAsync.valueOrNull?.length ?? 0;

    return statsAsync.when(
      loading: () => _buildKpiShimmer(),
      error: (_, __) => const SizedBox.shrink(),
      data: (stats) {
        final trendStr = _trend(stats.todayTotal, stats.yesterdayTotal);
        final trendCol = _trendColor(
            stats.todayTotal, stats.yesterdayTotal);

        return SizedBox(
          height: 130,
          child: ListView(
            padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceMD),
            scrollDirection: Axis.horizontal,
            children: [
              _KpiCard(
                emoji: '💰',
                value: AppUtils.formatAmount(stats.todayTotal)
                    .replaceAll(' FCFA', ''),
                suffix: 'FCFA',
                label: l10n.todayCollection,
                trend: trendStr,
                trendColor: trendCol,
              ),
              const SizedBox(width: AppConstants.spaceSM),
              _KpiCard(
                emoji: '👥',
                value: stats.activeMembers.toString(),
                label: l10n.activeMembers,
                trend: '+${stats.newMembersToday} ${l10n.newMembersToday}',
                trendColor: AppColors.success,
              ),
              const SizedBox(width: AppConstants.spaceSM),
              _KpiCard(
                emoji: '📅',
                value: _shortAmount(stats.monthTotal),
                label: l10n.thisMonth,
              ),
              const SizedBox(width: AppConstants.spaceSM),
              _KpiCard(
                emoji: '⚠️',
                value: stats.lateMembers.toString(),
                label: l10n.lateMembers,
                trend: pendingCount > 0
                    ? '$pendingCount ${l10n.pendingValidation}'
                    : null,
                trendColor: AppColors.error,
              ),
              const SizedBox(width: AppConstants.spaceSM),
              _KpiCard(
                emoji: '🆕',
                value: stats.newMembersToday.toString(),
                label: l10n.newMembersToday,
              ),
            ],
          ),
        );
      },
    );
  }

  String _shortAmount(int amount) {
    if (amount >= 1000000) {
      final m = (amount / 1000000).toStringAsFixed(1);
      return '${m}M';
    }
    if (amount >= 1000) {
      final k = (amount / 1000).toStringAsFixed(0);
      return '${k}K';
    }
    return amount.toString();
  }

  Widget _buildKpiShimmer() {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceMD),
        scrollDirection: Axis.horizontal,
        itemCount: 5,
        separatorBuilder: (_, __) =>
            const SizedBox(width: AppConstants.spaceSM),
        itemBuilder: (_, __) => Container(
          width: 156,
          decoration: BoxDecoration(
            color: AppColors.border.withValues(alpha: 0.4),
            borderRadius:
                BorderRadius.circular(AppConstants.radiusLG),
          ),
        ),
      ),
    );
  }

  // ── Chart Card ────────────────────────────────────────────

  Widget _buildChartCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final periodStr = DateFormat('MMMM yyyy', 'fr_FR')
        .format(DateTime.now())
        .replaceFirstMapped(
            RegExp(r'^.'), (m) => m.group(0)!.toUpperCase());

    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMD),
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.chartTitle,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull),
                ),
                child: Text(
                  periodStr,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceMD),
          ref.watch(_chartDataProvider).when(
            loading: () => const SizedBox(
              height: 140,
              child: Center(
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              ),
            ),
            error: (_, __) => const SizedBox(height: 140),
            data: (days) => _buildBarChart(days),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<_DayStat> days) {
    if (days.isEmpty) return const SizedBox(height: 140);

    final maxTotal =
        days.map((d) => d.total).reduce(math.max).toDouble();
    const maxBarH = 100.0;

    return Column(
      children: [
        SizedBox(
          height: maxBarH + 20,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: days.asMap().entries.map((e) {
              final i = e.key;
              final day = e.value;
              final isToday = i == 13;
              final isPeak = maxTotal > 0 &&
                  day.total == maxTotal.toInt() &&
                  day.total > 0;
              final barH = maxTotal > 0
                  ? (day.total / maxTotal) * maxBarH
                  : 0.0;
              final barColor = isPeak
                  ? AppColors.gold
                  : isToday
                      ? AppColors.primaryLight
                      : AppColors.primary;

              return Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        height: barH.clamp(2.0, maxBarH),
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(2),
                            topRight: Radius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        day.date.day.toString(),
                        style: TextStyle(
                          fontSize: 9,
                          color: isToday
                              ? AppColors.primary
                              : AppColors.textGray,
                          fontWeight: isToday
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        const Row(
          children: [
            _ChartLegendDot(color: AppColors.primary,
                label: 'Jours normaux'),
            SizedBox(width: 12),
            _ChartLegendDot(color: AppColors.primaryLight,
                label: "Aujourd'hui"),
            SizedBox(width: 12),
            _ChartLegendDot(
                color: AppColors.gold, label: 'Record'),
          ],
        ),
      ],
    );
  }

  // ── Recent Payments ───────────────────────────────────────

  Widget _buildRecentPayments(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(currentUserProfileProvider);
    final adminId = profileAsync.valueOrNull?.id ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceMD),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.recentPayments,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextButton(
                onPressed: () =>
                    context.push(AppRoutes.adminPayments),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  l10n.viewAll,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spaceSM),
        ref.watch(_recentPaymentsProvider).when(
          loading: () => _buildPaymentsShimmer(),
          error: (_, __) => const SizedBox.shrink(),
          data: (payments) {
            if (payments.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceMD),
                child: Text(
                  l10n.noPaymentYet,
                  style: const TextStyle(
                      color: AppColors.textGray, fontSize: 14),
                ),
              );
            }
            return Column(
              children: payments
                  .map((p) => _RecentPaymentItem(
                        contribution: p,
                        paymentMethodLabel:
                            _paymentMethodShort(p.paymentMethod),
                        onValidate: adminId.isNotEmpty
                            ? () => _handleValidate(p, adminId)
                            : null,
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPaymentsShimmer() {
    return Column(
      children: List.generate(
        4,
        (_) => Container(
          height: 68,
          margin: const EdgeInsets.fromLTRB(
              AppConstants.spaceMD, 0,
              AppConstants.spaceMD, AppConstants.spaceSM),
          decoration: BoxDecoration(
            color: AppColors.border.withValues(alpha: 0.4),
            borderRadius:
                BorderRadius.circular(AppConstants.radiusMD),
          ),
        ),
      ),
    );
  }

  // ── Quick Actions ─────────────────────────────────────────

  Widget _buildQuickActions(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final actions = [
      (Icons.add_circle_outline_rounded, l10n.manualPayment,
          AppColors.primary, () => context.push(AppRoutes.adminManualPayment)),
      (Icons.group_outlined, l10n.manageMembers,
          AppColors.info, () => context.push(AppRoutes.adminMembers)),
      (Icons.file_upload_outlined, l10n.generateReport,
          AppColors.gold, () => context.push(AppRoutes.adminAnalytics)),
      (Icons.notifications_outlined, l10n.sendNotificationAction,
          AppColors.warning, () => showSendNotificationSheet(context)),
      (Icons.account_balance_wallet_rounded, l10n.adminWalletTitle,
          const Color(0xFF0f766e), () => context.push(AppRoutes.adminWallet)),
      (Icons.assignment_outlined, l10n.focalReportsTitle,
          const Color(0xFF26A8F3), () => context.push(AppRoutes.adminFocalReports)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceMD),
          child: Text(
            l10n.quickActionsTitle,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spaceSM),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceMD),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: AppConstants.spaceSM,
            mainAxisSpacing: AppConstants.spaceSM,
            childAspectRatio: 2.2,
            children: actions
                .map((a) => _QuickActionCard(
                      icon: a.$1,
                      label: a.$2,
                      color: a.$3,
                      onTap: a.$4,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }


}

// ── Private widgets ───────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String emoji;
  final String value;
  final String? suffix;
  final String label;
  final String? trend;
  final Color? trendColor;

  const _KpiCard({
    required this.emoji,
    required this.value,
    this.suffix,
    required this.label,
    this.trend,
    this.trendColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 156,
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: const Border(
          left: BorderSide(color: AppColors.primary, width: 3),
          top: BorderSide(color: AppColors.border),
          right: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.textDark.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: GoogleFonts.playfairDisplay(
                        color: AppColors.textDark,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (suffix != null) ...[
                    const SizedBox(width: 3),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        suffix!,
                        style: const TextStyle(
                          color: AppColors.textGray,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textGray,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (trend != null) ...[
                const SizedBox(height: 4),
                Text(
                  trend!,
                  style: TextStyle(
                    color: trendColor ?? AppColors.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentPaymentItem extends StatelessWidget {
  final ContributionModel contribution;
  final String paymentMethodLabel;
  final VoidCallback? onValidate;

  const _RecentPaymentItem({
    required this.contribution,
    required this.paymentMethodLabel,
    this.onValidate,
  });

  @override
  Widget build(BuildContext context) {
    final c = contribution;
    final isPending = c.status == AppConstants.statusPending;
    final initials = c.memberName.isNotEmpty
        ? c.memberName
            .split(' ')
            .take(2)
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
            .join()
        : '?';

    return Container(
      margin: const EdgeInsets.fromLTRB(AppConstants.spaceMD, 0,
          AppConstants.spaceMD, AppConstants.spaceSM),
      padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMD, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(AppConstants.radiusMD),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isPending
                  ? AppColors.warning.withValues(alpha: 0.15)
                  : AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: isPending
                      ? AppColors.warning
                      : AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spaceSM),

          // Middle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.memberName,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${c.memberNumber} · $paymentMethodLabel',
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppConstants.spaceSM),

          // Right: amount + time + action
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                AppUtils.formatAmount(c.amount),
                style: GoogleFonts.playfairDisplay(
                  color: AppColors.gold,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                AppUtils.timeAgo(c.createdAt.toDate()),
                style: const TextStyle(
                    color: AppColors.textGray, fontSize: 10),
              ),
              if (isPending && onValidate != null) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: onValidate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull),
                    ),
                    child: const Text(
                      'Valider',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius:
              BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(
              color: color.withValues(alpha: 0.25), width: 1),
        ),
        child: Row(
          children: [
            const SizedBox(width: AppConstants.spaceMD),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusSM),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: AppConstants.spaceSM),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartLegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _ChartLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGray,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _VisionProgressBar extends StatelessWidget {
  final String label;
  final IconData icon;
  final double progress;
  final String currentLabel;
  final String targetLabel;
  final String percentLabel;
  final Color barColor;
  final Color glowColor;

  const _VisionProgressBar({
    required this.label,
    required this.icon,
    required this.progress,
    required this.currentLabel,
    required this.targetLabel,
    required this.percentLabel,
    required this.barColor,
    required this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: barColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                border: Border.all(color: barColor.withValues(alpha: 0.5)),
              ),
              child: Text(
                percentLabel,
                style: TextStyle(
                  color: barColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                currentLabel,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                targetLabel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          child: Stack(
            children: [
              Container(
                height: 10,
                width: double.infinity,
                color: Colors.white.withValues(alpha: 0.1),
              ),
              FractionallySizedBox(
                widthFactor: math.max(progress, 0.004),
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        barColor.withValues(alpha: 0.7),
                        barColor,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withValues(alpha: 0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
