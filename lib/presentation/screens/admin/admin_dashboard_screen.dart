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
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/repositories/contribution_repository.dart';
import '../../widgets/common/app_animations.dart';
import '../../widgets/common/app_shimmer.dart';
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

class _FocalRanking {
  final String focalId;
  final String name;
  final int amount;
  final int count;

  const _FocalRanking({
    required this.focalId,
    required this.name,
    required this.amount,
    required this.count,
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

// Total members = live count of every user document, mirroring the members
// page (_allUsersProvider) exactly so the two screens always agree. Uses a
// document snapshot stream (not an aggregate count()), which the Firestore
// role-check rules don't block — see backfillPlatformCounters() for why
// aggregate queries are avoided. The platform total still reads its counter.
final _memberCountProvider = StreamProvider.autoDispose<int>((ref) {
  return FirebaseFirestore.instance
      .collection(AppConstants.usersCollection)
      .orderBy('createdAt', descending: true)
      .limit(500)
      .snapshots()
      .map((s) => s.docs.length);
});

final _platformTotalProvider = StreamProvider.autoDispose<double>((ref) {
  return ContributionRepository().streamPlatformTotal();
});

final _focalLeaderboardProvider =
    FutureProvider.autoDispose<List<_FocalRanking>>((ref) async {
  final db = FirebaseFirestore.instance;
  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1);

  // Pull this month's confirmed contributions and group client-side.
  // We need per-focal totals, which Firestore can't aggregate directly.
  final snap = await db
      .collection(AppConstants.contributionsCollection)
      .where('status', isEqualTo: AppConstants.statusConfirmed)
      .where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
      .get();

  final totals = <String, int>{};
  final counts = <String, int>{};
  for (final doc in snap.docs) {
    final data = doc.data();
    final focalId = (data['recordedBy'] as String?)?.trim() ?? '';
    if (focalId.isEmpty) continue;
    totals[focalId] =
        (totals[focalId] ?? 0) + ((data['amount'] as num?)?.toInt() ?? 0);
    counts[focalId] = (counts[focalId] ?? 0) + 1;
  }

  final topIds = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top = topIds.take(3).toList();
  if (top.isEmpty) return [];

  // Resolve focal names — but only the ones we actually need.
  final userDocs = await Future.wait(top.map((e) =>
      db.collection(AppConstants.usersCollection).doc(e.key).get()));

  return [
    for (var i = 0; i < top.length; i++)
      _FocalRanking(
        focalId: top[i].key,
        name: () {
          final d = userDocs[i].data();
          if (d == null) return top[i].key;
          final first = (d['firstName'] as String?) ?? '';
          final last = (d['lastName'] as String?) ?? '';
          final full = '$first $last'.trim();
          return full.isEmpty ? top[i].key : full;
        }(),
        amount: top[i].value,
        count: counts[top[i].key] ?? 0,
      ),
  ];
});

final _methodDistributionProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final db = FirebaseFirestore.instance;
  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1);
  final col = db.collection(AppConstants.contributionsCollection);

  Future<int> sumFor(String method) async {
    final agg = await col
        .where('status', isEqualTo: AppConstants.statusConfirmed)
        .where('paymentMethod', isEqualTo: method)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .aggregate(sum('amount'))
        .get();
    return (agg.getSum('amount') ?? 0).toInt();
  }

  final methods = [
    AppConstants.paymentMtnMomo,
    AppConstants.paymentOrangeMoney,
    AppConstants.paymentCash,
    AppConstants.paymentBankTransfer,
  ];
  final results = await Future.wait(methods.map(sumFor));
  return {for (var i = 0; i < methods.length; i++) methods[i]: results[i]};
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

  String _paymentMethodShort(String method, AppLocalizations l) {
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
        // The "payment confirmed" push is sent server-side by the
        // onContributionConfirmed Cloud Function.
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
    final pendingAsync = ref.watch(_pendingPaymentsProvider);
    final pendingList = pendingAsync.valueOrNull ?? const [];
    final pendingCount = pendingList.length;
    final awaiting1st = pendingList
        .where((c) => (c.validatedBy ?? '').isEmpty)
        .length;
    final awaiting2nd = pendingCount - awaiting1st;
    final adminInitials =
        ref.watch(currentUserProfileProvider).valueOrNull?.initials ?? '?';

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
              GestureDetector(
                onTap: () => context.go(AppRoutes.adminSettings),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    adminInitials,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ),
              const Spacer(),
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
                tooltip: l10n.viewAsMember,
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
          _buildPlatformVision(context, pendingCount, awaiting1st, awaiting2nd),
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
        _buildMethodDistribution(context),
        const SizedBox(height: AppConstants.spaceLG),
        _buildFocalLeaderboard(context),
        const SizedBox(height: AppConstants.spaceLG),
        _buildRecentPayments(context),
        const SizedBox(height: AppConstants.spaceXL),
      ],
    );
  }

  // ── Focal leaderboard ─────────────────────────────────────

  Widget _buildFocalLeaderboard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(_focalLeaderboardProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMD),
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.topFocalOfficers,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    context.push(AppRoutes.adminFocalReports),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  l10n.viewAll,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceMD),
          async.when(
            loading: () => const SizedBox(
              height: 60,
              child: Center(
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (rankings) {
              if (rankings.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    l10n.noFocalActivity,
                    style: const TextStyle(
                        color: AppColors.textGray, fontSize: 13),
                  ),
                );
              }
              return Column(
                children: rankings
                    .asMap()
                    .entries
                    .map((e) => _LeaderboardRow(
                          rank: e.key + 1,
                          ranking: e.value,
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Payment-method distribution ───────────────────────────

  Widget _buildMethodDistribution(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(_methodDistributionProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMD),
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.paymentMethodDistribution,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: AppConstants.spaceMD),
          async.when(
            loading: () => const SizedBox(
              height: 40,
              child: Center(
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (totals) {
              final total = totals.values.fold<int>(0, (s, v) => s + v);
              if (total == 0) {
                return Text(
                  l10n.noPaymentsThisMonth,
                  style: const TextStyle(
                      color: AppColors.textGray, fontSize: 13),
                );
              }
              return _MethodBar(totals: totals, total: total);
            },
          ),
        ],
      ),
    );
  }

  // ── Platform Vision ───────────────────────────────────────

  Widget _buildPlatformVision(BuildContext context, int pendingCount,
      int awaiting1st, int awaiting2nd) {
    final l10n = AppLocalizations.of(context);
    final membersAsync = ref.watch(_memberCountProvider);
    final totalAsync = ref.watch(_platformTotalProvider);

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$pendingCount ${l10n.pendingValidation}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$awaiting1st · ${l10n.awaitingFirstValidator} · '
                        '$awaiting2nd · ${l10n.awaitingSecondValidator}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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

    final memberValue = membersAsync.when(
      loading: () => '…',
      error: (_, __) => '—',
      data: (n) => _formatLargeNumber(n),
    );
    final totalValue = totalAsync.when(
      loading: () => '…',
      error: (_, __) => '—',
      data: (t) => _formatBigAmount(t.toInt()),
    );

    Widget statTile({
      required IconData icon,
      required String label,
      required String value,
      required Color accent,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                color: accent,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
    }

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
                  borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                ),
                child: const Icon(Icons.stars_rounded,
                    color: AppColors.gold, size: 22),
              ),
              const SizedBox(width: AppConstants.spaceMD),
              Expanded(
                child: Text(
                  l10n.platformVision,
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceLG),

          // Real community totals — two tiles fed by the counters/ docs.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: statTile(
                    icon: Icons.group_outlined,
                    label: l10n.totalMembers,
                    value: memberValue,
                    accent: Colors.white,
                  ),
                ),
                const SizedBox(width: AppConstants.spaceMD),
                Container(
                  width: 1,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
                const SizedBox(width: AppConstants.spaceMD),
                Expanded(
                  child: statTile(
                    icon: Icons.account_balance_wallet_outlined,
                    label: l10n.totalContributed,
                    value: totalValue,
                    accent: AppColors.gold,
                  ),
                ),
              ],
            ),
          ),

          // Pending validation — merged into the same container
          pendingStrip(),
        ],
      ),
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
                value: _shortAmount(stats.todayTotal),
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
      child: AppShimmer(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceMD),
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 5,
          separatorBuilder: (_, __) =>
              const SizedBox(width: AppConstants.spaceSM),
          itemBuilder: (_, __) => Container(
            width: 156,
            decoration: BoxDecoration(
              color: AppColors.border.withValues(alpha: 0.55),
              borderRadius:
                  BorderRadius.circular(AppConstants.radiusLG),
            ),
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
            data: (days) => _buildBarChart(days, l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<_DayStat> days, AppLocalizations l10n) {
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
        Row(
          children: [
            _ChartLegendDot(
                color: AppColors.primary, label: l10n.chartLegendNormal),
            const SizedBox(width: 12),
            _ChartLegendDot(
                color: AppColors.primaryLight, label: l10n.chartLegendToday),
            const SizedBox(width: 12),
            _ChartLegendDot(
                color: AppColors.gold, label: l10n.chartLegendRecord),
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
    final isSuperAdmin = profileAsync.valueOrNull?.isSuperAdmin ?? false;

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
              children: [
                for (int i = 0; i < payments.length; i++)
                  FadeSlideIn(
                    delay: Duration(milliseconds: i * 60),
                    child: _RecentPaymentItem(
                      contribution: payments[i],
                      paymentMethodLabel:
                          _paymentMethodShort(payments[i].paymentMethod, l10n),
                      validateLabel: l10n.validate,
                      onValidate: (isSuperAdmin && adminId.isNotEmpty)
                          ? () => _handleValidate(payments[i], adminId)
                          : null,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildPaymentsShimmer() {
    return AppShimmer(
      child: Column(
        children: List.generate(
          4,
          (_) => Container(
            height: 68,
            margin: const EdgeInsets.fromLTRB(
                AppConstants.spaceMD, 0,
                AppConstants.spaceMD, AppConstants.spaceSM),
            decoration: BoxDecoration(
              color: AppColors.border.withValues(alpha: 0.55),
              borderRadius:
                  BorderRadius.circular(AppConstants.radiusMD),
            ),
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
      (Icons.event_rounded, l10n.manageEvents,
          AppColors.primaryLight, () => context.push(AppRoutes.adminEvents)),
      (Icons.settings_outlined, l10n.settings,
          AppColors.textGray, () => context.push(AppRoutes.adminSettings)),
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
  final String label;
  final String? trend;
  final Color? trendColor;

  const _KpiCard({
    required this.emoji,
    required this.value,
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
              Text(
                value,
                style: GoogleFonts.playfairDisplay(
                  color: AppColors.textDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
  final String validateLabel;
  final VoidCallback? onValidate;

  const _RecentPaymentItem({
    required this.contribution,
    required this.paymentMethodLabel,
    required this.validateLabel,
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
                    child: Text(
                      validateLabel,
                      style: const TextStyle(
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(width: AppConstants.spaceSM),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.radiusSM),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: AppConstants.spaceSM),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppConstants.spaceSM),
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

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final _FocalRanking ranking;
  const _LeaderboardRow({required this.rank, required this.ranking});

  @override
  Widget build(BuildContext context) {
    final medalColor = switch (rank) {
      1 => AppColors.gold,
      2 => AppColors.textGray,
      _ => AppColors.warning,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: medalColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$rank',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: medalColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ranking.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  '${ranking.count}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textGray),
                ),
              ],
            ),
          ),
          Text(
            AppUtils.formatAmount(ranking.amount),
            style: GoogleFonts.playfairDisplay(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodBar extends StatelessWidget {
  final Map<String, int> totals;
  final int total;
  const _MethodBar({required this.totals, required this.total});

  Color _colorFor(String method) {
    switch (method) {
      case AppConstants.paymentMtnMomo:
        return AppColors.gold;
      case AppConstants.paymentOrangeMoney:
        return AppColors.warning;
      case AppConstants.paymentCash:
        return AppColors.success;
      default:
        return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entries = totals.entries.where((e) => e.value > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          child: SizedBox(
            height: 10,
            child: Row(
              children: entries.map((e) {
                return Expanded(
                  flex: e.value,
                  child: Container(color: _colorFor(e.key)),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spaceMD),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: entries.map((e) {
            final pct = ((e.value / total) * 100).toStringAsFixed(0);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _colorFor(e.key),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${l.paymentMethodName(e.key)} · $pct%',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textGray),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}
