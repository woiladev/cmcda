import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/language_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/contribution_model.dart';

// ── Period ────────────────────────────────────────────────────

enum _AnalyticsPeriod { today, last7, last30, thisMonth, thisYear, custom }

class _DateRange {
  final DateTime start;
  final DateTime end;
  const _DateRange(this.start, this.end);
}

// ── Aggregates ────────────────────────────────────────────────

class _AnalyticsKpi {
  final int totalRevenue;
  final int txCount;
  final int activeContributors;
  const _AnalyticsKpi({
    required this.totalRevenue,
    required this.txCount,
    required this.activeContributors,
  });

  int get average => txCount == 0 ? 0 : totalRevenue ~/ txCount;
}

class _Bucket {
  final DateTime label;
  final int total;
  const _Bucket(this.label, this.total);
}

class _RegionStat {
  final String region;
  final int total;
  const _RegionStat(this.region, this.total);
}

class _ContributorRow {
  final String memberId;
  final String name;
  final String memberNumber;
  final int amount;
  final int count;
  const _ContributorRow({
    required this.memberId,
    required this.name,
    required this.memberNumber,
    required this.amount,
    required this.count,
  });
}

// ── Providers ─────────────────────────────────────────────────

final _analyticsPeriodProvider =
    StateProvider<_AnalyticsPeriod>((_) => _AnalyticsPeriod.last30);

final _analyticsCustomRangeProvider =
    StateProvider<_DateRange?>((_) => null);

final _analyticsRangeProvider = Provider<_DateRange>((ref) {
  final period = ref.watch(_analyticsPeriodProvider);
  final custom = ref.watch(_analyticsCustomRangeProvider);
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  switch (period) {
    case _AnalyticsPeriod.today:
      return _DateRange(startOfToday, now);
    case _AnalyticsPeriod.last7:
      return _DateRange(startOfToday.subtract(const Duration(days: 6)), now);
    case _AnalyticsPeriod.last30:
      return _DateRange(startOfToday.subtract(const Duration(days: 29)), now);
    case _AnalyticsPeriod.thisMonth:
      return _DateRange(DateTime(now.year, now.month, 1), now);
    case _AnalyticsPeriod.thisYear:
      return _DateRange(DateTime(now.year, 1, 1), now);
    case _AnalyticsPeriod.custom:
      return custom ?? _DateRange(startOfToday, now);
  }
});

final _confirmedContribsProvider =
    FutureProvider.autoDispose<List<ContributionModel>>((ref) async {
  final range = ref.watch(_analyticsRangeProvider);
  final snap = await FirebaseFirestore.instance
      .collection(AppConstants.contributionsCollection)
      .where('status', isEqualTo: AppConstants.statusConfirmed)
      .where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
      .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(range.end))
      .orderBy('createdAt', descending: true)
      .get();
  return snap.docs.map(ContributionModel.fromFirestore).toList();
});

final _kpiProvider = FutureProvider.autoDispose<_AnalyticsKpi>((ref) async {
  final list = await ref.watch(_confirmedContribsProvider.future);
  if (list.isEmpty) {
    return const _AnalyticsKpi(
        totalRevenue: 0, txCount: 0, activeContributors: 0);
  }
  final total = list.fold<int>(0, (s, c) => s + c.amount);
  final contributors =
      list.map((c) => c.memberId).where((id) => id.isNotEmpty).toSet();
  return _AnalyticsKpi(
    totalRevenue: total,
    txCount: list.length,
    activeContributors: contributors.length,
  );
});

// Previous equivalent period — used for KPI trend deltas.
final _prevRangeProvider = Provider.autoDispose<_DateRange>((ref) {
  final r = ref.watch(_analyticsRangeProvider);
  final span = r.end.difference(r.start);
  final prevEnd = r.start.subtract(const Duration(milliseconds: 1));
  final prevStart = prevEnd.subtract(span);
  return _DateRange(prevStart, prevEnd);
});

final _prevKpiProvider = FutureProvider.autoDispose<_AnalyticsKpi>((ref) async {
  final range = ref.watch(_prevRangeProvider);
  final snap = await FirebaseFirestore.instance
      .collection(AppConstants.contributionsCollection)
      .where('status', isEqualTo: AppConstants.statusConfirmed)
      .where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
      .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(range.end))
      .get();
  if (snap.docs.isEmpty) {
    return const _AnalyticsKpi(
        totalRevenue: 0, txCount: 0, activeContributors: 0);
  }
  final list = snap.docs.map(ContributionModel.fromFirestore).toList();
  final total = list.fold<int>(0, (s, c) => s + c.amount);
  final contributors =
      list.map((c) => c.memberId).where((id) => id.isNotEmpty).toSet();
  return _AnalyticsKpi(
    totalRevenue: total,
    txCount: list.length,
    activeContributors: contributors.length,
  );
});

final _revenueSeriesProvider =
    FutureProvider.autoDispose<List<_Bucket>>((ref) async {
  final list = await ref.watch(_confirmedContribsProvider.future);
  final range = ref.watch(_analyticsRangeProvider);
  final spanDays = range.end.difference(range.start).inDays + 1;
  // Day buckets for ≤ 31 days, otherwise week buckets.
  final useWeek = spanDays > 31;
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final bucketSize = useWeek ? 7 : 1;
  final bucketCount = (spanDays / bucketSize).ceil().clamp(1, 60);
  final totals = List<int>.filled(bucketCount, 0);
  for (final c in list) {
    final d = c.createdAt.toDate();
    final idx = d.difference(start).inDays ~/ bucketSize;
    if (idx >= 0 && idx < bucketCount) {
      totals[idx] += c.amount;
    }
  }
  return [
    for (var i = 0; i < bucketCount; i++)
      _Bucket(start.add(Duration(days: i * bucketSize)), totals[i]),
  ];
});

final _methodSplitProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final list = await ref.watch(_confirmedContribsProvider.future);
  final out = <String, int>{
    AppConstants.paymentMtnMomo: 0,
    AppConstants.paymentOrangeMoney: 0,
    AppConstants.paymentCash: 0,
    AppConstants.paymentBankTransfer: 0,
  };
  for (final c in list) {
    out[c.paymentMethod] = (out[c.paymentMethod] ?? 0) + c.amount;
  }
  return out;
});

final _regionSplitProvider =
    FutureProvider.autoDispose<List<_RegionStat>>((ref) async {
  final list = await ref.watch(_confirmedContribsProvider.future);
  if (list.isEmpty) return [];
  final memberIds = list
      .map((c) => c.memberId)
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();
  // Firestore whereIn caps at 30 ids per query — batch.
  final regionByMember = <String, String>{};
  for (var i = 0; i < memberIds.length; i += 30) {
    final slice = memberIds.sublist(i, math.min(i + 30, memberIds.length));
    final snap = await FirebaseFirestore.instance
        .collection(AppConstants.usersCollection)
        .where(FieldPath.documentId, whereIn: slice)
        .get();
    for (final d in snap.docs) {
      regionByMember[d.id] = (d.data()['region'] as String? ?? '').trim();
    }
  }
  final totals = <String, int>{};
  for (final c in list) {
    final r = regionByMember[c.memberId];
    if (r == null || r.isEmpty) continue;
    totals[r] = (totals[r] ?? 0) + c.amount;
  }
  final entries = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries.take(5).map((e) => _RegionStat(e.key, e.value)).toList();
});

final _topContributorsProvider =
    FutureProvider.autoDispose<List<_ContributorRow>>((ref) async {
  final list = await ref.watch(_confirmedContribsProvider.future);
  if (list.isEmpty) return [];
  final totals = <String, int>{};
  final counts = <String, int>{};
  final names = <String, String>{};
  final numbers = <String, String>{};
  for (final c in list) {
    if (c.memberId.isEmpty) continue;
    totals[c.memberId] = (totals[c.memberId] ?? 0) + c.amount;
    counts[c.memberId] = (counts[c.memberId] ?? 0) + 1;
    names[c.memberId] = c.memberName;
    numbers[c.memberId] = c.memberNumber;
  }
  final ordered = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top = ordered.take(10).toList();

  // Some contributions carry a blank denormalized memberName — resolve the
  // authoritative name from the user doc for those. Firestore whereIn caps
  // at 30 ids per query, so batch.
  final missing = [
    for (final e in top)
      if ((names[e.key] ?? '').trim().isEmpty) e.key,
  ];
  for (var i = 0; i < missing.length; i += 30) {
    final slice = missing.sublist(i, math.min(i + 30, missing.length));
    final snap = await FirebaseFirestore.instance
        .collection(AppConstants.usersCollection)
        .where(FieldPath.documentId, whereIn: slice)
        .get();
    for (final d in snap.docs) {
      final data = d.data();
      final full =
          '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
      if (full.isNotEmpty) names[d.id] = full;
    }
  }

  return top.map((e) {
    final resolved = (names[e.key] ?? '').trim();
    final number = numbers[e.key] ?? '';
    return _ContributorRow(
      memberId: e.key,
      name: resolved.isNotEmpty
          ? resolved
          : (number.isNotEmpty ? number : e.key),
      memberNumber: number,
      amount: e.value,
      count: counts[e.key] ?? 0,
    );
  }).toList();
});

// ── Screen ────────────────────────────────────────────────────

class AdminAnalyticsScreen extends ConsumerWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            SliverToBoxAdapter(child: _Header()),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppConstants.spaceLG),
            ),
            const SliverToBoxAdapter(child: _PeriodSelector()),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppConstants.spaceLG),
            ),
            const SliverToBoxAdapter(child: _KpiGrid()),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppConstants.spaceLG),
            ),
            const SliverToBoxAdapter(child: _RevenueLineCard()),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppConstants.spaceLG),
            ),
            const SliverToBoxAdapter(child: _MethodBarCard()),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppConstants.spaceLG),
            ),
            const SliverToBoxAdapter(child: _RegionBarCard()),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppConstants.spaceLG),
            ),
            const SliverToBoxAdapter(child: _TopContributorsCard()),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppConstants.spaceLG),
            ),
            const SliverToBoxAdapter(child: _ExportButtons()),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppConstants.spaceXL),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
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
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: AppConstants.spaceSM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.analyticsTitle,
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l.analyticsSubtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
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

// ── Period selector ───────────────────────────────────────────

class _PeriodSelector extends ConsumerWidget {
  const _PeriodSelector();

  String _label(_AnalyticsPeriod p, AppLocalizations l) {
    switch (p) {
      case _AnalyticsPeriod.today:
        return l.periodToday;
      case _AnalyticsPeriod.last7:
        return l.periodLast7d;
      case _AnalyticsPeriod.last30:
        return l.periodLast30d;
      case _AnalyticsPeriod.thisMonth:
        return l.periodThisMonth;
      case _AnalyticsPeriod.thisYear:
        return l.periodThisYear;
      case _AnalyticsPeriod.custom:
        return l.periodCustom;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final selected = ref.watch(_analyticsPeriodProvider);
    final localeCode = ref.watch(currentLocaleProvider).languageCode;

    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMD),
        scrollDirection: Axis.horizontal,
        itemCount: _AnalyticsPeriod.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = _AnalyticsPeriod.values[i];
          final isSel = p == selected;
          return GestureDetector(
            onTap: () async {
              if (p == _AnalyticsPeriod.custom) {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  helpText: l.selectDateRange,
                  locale: Locale(localeCode),
                );
                if (picked != null) {
                  ref.read(_analyticsCustomRangeProvider.notifier).state =
                      _DateRange(picked.start, picked.end);
                  ref.read(_analyticsPeriodProvider.notifier).state =
                      _AnalyticsPeriod.custom;
                }
              } else {
                ref.read(_analyticsPeriodProvider.notifier).state = p;
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSel ? AppColors.primary : AppColors.surface,
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusFull),
                border: Border.all(
                  color: isSel ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Text(
                _label(p, l),
                style: TextStyle(
                  color: isSel ? Colors.white : AppColors.textDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── KPI Grid ──────────────────────────────────────────────────

class _KpiSpec {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final double? delta;
  const _KpiSpec(this.label, this.value, this.icon, this.color, this.delta);
}

class _KpiGrid extends ConsumerWidget {
  const _KpiGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final kpiAsync = ref.watch(_kpiProvider);
    final prev = ref.watch(_prevKpiProvider).valueOrNull;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppConstants.spaceMD),
      child: kpiAsync.when(
        loading: () => _kpiSkeleton(),
        error: (_, __) => _kpiRow(
            l,
            const _AnalyticsKpi(
                totalRevenue: 0, txCount: 0, activeContributors: 0),
            null),
        data: (k) => _kpiRow(l, k, prev),
      ),
    );
  }

  static const _gridDelegate =
      SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    crossAxisSpacing: AppConstants.spaceSM,
    mainAxisSpacing: AppConstants.spaceSM,
    mainAxisExtent: 120,
  );

  Widget _kpiSkeleton() {
    return GridView(
      gridDelegate: _gridDelegate,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(
        4,
        (_) => Container(
          decoration: BoxDecoration(
            color: AppColors.border.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          ),
        ),
      ),
    );
  }

  double? _delta(int cur, int? prev) {
    if (prev == null || prev == 0) return null;
    return (cur - prev) / prev;
  }

  Widget _kpiRow(AppLocalizations l, _AnalyticsKpi k, _AnalyticsKpi? p) {
    final cards = [
      _KpiSpec(l.kpiTotalRevenue, AppUtils.formatAmount(k.totalRevenue),
          Icons.payments_rounded, AppColors.primary,
          _delta(k.totalRevenue, p?.totalRevenue)),
      _KpiSpec(l.kpiTxCount, k.txCount.toString(),
          Icons.receipt_long_rounded, AppColors.info,
          _delta(k.txCount, p?.txCount)),
      _KpiSpec(l.kpiAvgPayment, AppUtils.formatAmount(k.average),
          Icons.bar_chart_rounded, AppColors.gold,
          _delta(k.average, p?.average)),
      _KpiSpec(l.kpiActiveContributors, k.activeContributors.toString(),
          Icons.groups_rounded, AppColors.success,
          _delta(k.activeContributors, p?.activeContributors)),
    ];
    return GridView(
      gridDelegate: _gridDelegate,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cards.map((c) => _KpiCard(spec: c)).toList(),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final _KpiSpec spec;
  const _KpiCard({required this.spec});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLG),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: spec.color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spaceMD),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: spec.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSM),
                ),
                child: Icon(spec.icon, size: 18, color: spec.color),
              ),
              const Spacer(),
              if (spec.delta != null) _DeltaChip(delta: spec.delta!),
            ],
          ),
          const SizedBox(height: AppConstants.spaceSM),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              spec.value,
              maxLines: 1,
              style: GoogleFonts.playfairDisplay(
                color: AppColors.textDark,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            spec.label,
            style: const TextStyle(color: AppColors.textGray, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final double delta;
  const _DeltaChip({required this.delta});

  @override
  Widget build(BuildContext context) {
    final up = delta >= 0;
    final color = up ? AppColors.success : AppColors.error;
    final pct = delta.abs() * 100;
    final txt = pct >= 1000 ? '999%+' : '${pct.toStringAsFixed(0)}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            txt,
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

// ── Card shell ────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:
          const EdgeInsets.symmetric(horizontal: AppConstants.spaceMD),
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
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: AppConstants.spaceMD),
          child,
        ],
      ),
    );
  }
}

// ── Line chart ────────────────────────────────────────────────

class _RevenueLineCard extends ConsumerWidget {
  const _RevenueLineCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final localeCode = ref.watch(currentLocaleProvider).languageCode;
    final async = ref.watch(_revenueSeriesProvider);

    return _SectionCard(
      title: l.revenueOverTime,
      child: async.when(
        loading: () => const SizedBox(
          height: 180,
          child: Center(
            child: CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2),
          ),
        ),
        error: (_, __) => SizedBox(
          height: 180,
          child: Center(
            child: Text(l.noChartData,
                style: const TextStyle(color: AppColors.textGray)),
          ),
        ),
        data: (buckets) {
          if (buckets.isEmpty || buckets.every((b) => b.total == 0)) {
            return SizedBox(
              height: 180,
              child: Center(
                child: Text(l.noChartData,
                    style: const TextStyle(color: AppColors.textGray)),
              ),
            );
          }
          final spots = [
            for (var i = 0; i < buckets.length; i++)
              FlSpot(i.toDouble(), buckets[i].total.toDouble()),
          ];
          final maxY = buckets
              .map((b) => b.total)
              .reduce(math.max)
              .toDouble();
          return SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY == 0 ? 1 : maxY * 1.2,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY == 0 ? 1 : maxY / 4,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: AppColors.border,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        return Text(
                          _shortAmount(value.toInt()),
                          style: const TextStyle(
                              color: AppColors.textGray, fontSize: 9),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: math.max(1, buckets.length / 6).toDouble(),
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= buckets.length) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          DateFormat('dd/MM', localeCode)
                              .format(buckets[i].label),
                          style: const TextStyle(
                              color: AppColors.textGray, fontSize: 9),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _shortAmount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
  return n.toString();
}

// ── Method bar ────────────────────────────────────────────────

class _MethodBarCard extends ConsumerWidget {
  const _MethodBarCard();

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
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(_methodSplitProvider);
    return _SectionCard(
      title: l.paymentMethodBreakdown,
      child: async.when(
        loading: () => const SizedBox(
          height: 80,
          child: Center(
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2)),
        ),
        error: (_, __) => Text(l.noChartData,
            style: const TextStyle(color: AppColors.textGray)),
        data: (totals) {
          final entries = totals.entries.toList();
          final maxV = entries.map((e) => e.value).fold<int>(0, math.max);
          if (maxV == 0) {
            return Text(l.noChartData,
                style: const TextStyle(color: AppColors.textGray));
          }
          final nonZero = entries.where((e) => e.value > 0).toList();
          final grandTotal = nonZero.fold<int>(0, (s, e) => s + e.value);
          return Column(
            children: [
              SizedBox(
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 44,
                        sections: [
                          for (final e in nonZero)
                            PieChartSectionData(
                              value: e.value.toDouble(),
                              color: _colorFor(e.key),
                              radius: 16,
                              showTitle: false,
                            ),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _shortAmount(grandTotal),
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        Text(
                          l.kpiTotalRevenue,
                          style: const TextStyle(
                              fontSize: 9, color: AppColors.textGray),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spaceMD),
              ...entries.map((e) {
              final pct = (e.value / maxV).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l.paymentMethodName(e.key),
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          AppUtils.formatAmount(e.value),
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull),
                      child: Stack(
                        children: [
                          Container(
                            height: 8,
                            width: double.infinity,
                            color: AppColors.border,
                          ),
                          FractionallySizedBox(
                            widthFactor: math.max(pct, 0.01),
                            child: Container(
                              height: 8,
                              color: _colorFor(e.key),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            ],
          );
        },
      ),
    );
  }
}

// ── Region bar ────────────────────────────────────────────────

class _RegionBarCard extends ConsumerWidget {
  const _RegionBarCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(_regionSplitProvider);
    return _SectionCard(
      title: l.regionalRevenue,
      child: async.when(
        loading: () => const SizedBox(
          height: 80,
          child: Center(
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2)),
        ),
        error: (_, __) => Text(l.noChartData,
            style: const TextStyle(color: AppColors.textGray)),
        data: (regions) {
          if (regions.isEmpty) {
            return Text(l.noChartData,
                style: const TextStyle(color: AppColors.textGray));
          }
          final maxV = regions.map((r) => r.total).reduce(math.max);
          return Column(
            children: regions.map((r) {
              final pct = (r.total / maxV).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(r.region,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textDark,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Text(
                          AppUtils.formatAmount(r.total),
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull),
                      child: Stack(
                        children: [
                          Container(
                            height: 8,
                            width: double.infinity,
                            color: AppColors.border,
                          ),
                          FractionallySizedBox(
                            widthFactor: math.max(pct, 0.01),
                            child: Container(
                              height: 8,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// ── Top contributors ──────────────────────────────────────────

class _TopContributorsCard extends ConsumerWidget {
  const _TopContributorsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(_topContributorsProvider);
    return _SectionCard(
      title: l.topContributorsTitle,
      child: async.when(
        loading: () => const SizedBox(
          height: 80,
          child: Center(
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2)),
        ),
        error: (_, __) => Text(l.noChartData,
            style: const TextStyle(color: AppColors.textGray)),
        data: (rows) {
          if (rows.isEmpty) {
            return Text(l.noChartData,
                style: const TextStyle(color: AppColors.textGray));
          }
          return Column(
            children: rows.asMap().entries.map((e) {
              final rank = e.key + 1;
              final r = e.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$rank',
                          style: GoogleFonts.playfairDisplay(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spaceMD),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.name,
                              style: const TextStyle(
                                  color: AppColors.textDark,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          Text(
                            '${r.memberNumber} · ${r.count}',
                            style: const TextStyle(
                                color: AppColors.textGray, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      AppUtils.formatAmount(r.amount),
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.gold,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// ── Export buttons ────────────────────────────────────────────

class _ExportButtons extends ConsumerWidget {
  const _ExportButtons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    Future<void> showErr(String msg) async {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );
    }

    Future<void> showOk(String msg) async {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.success),
      );
    }

    Future<void> exportCsv() async {
      try {
        final list = await ref.read(_confirmedContribsProvider.future);
        final rows = <List<dynamic>>[
          [
            'date',
            'receipt',
            'memberNumber',
            'memberName',
            'amount',
            'paymentMethod',
            'period',
            'status',
          ],
          for (final c in list)
            [
              c.createdAt.toDate().toIso8601String(),
              c.receiptNumber,
              c.memberNumber,
              c.memberName,
              c.amount,
              c.paymentMethod,
              c.period,
              c.status,
            ],
        ];
        final csv = const ListToCsvConverter().convert(rows);
        final dir = await getTemporaryDirectory();
        final stamp = DateTime.now().millisecondsSinceEpoch;
        final file = File('${dir.path}/cmcda_analytics_$stamp.csv');
        await file.writeAsString(csv);
        await Share.shareXFiles([XFile(file.path)],
            text: 'CMCDA — Analytics');
        await showOk(l.exportSuccess);
      } catch (_) {
        await showErr(l.exportError);
      }
    }

    Future<void> exportPdf() async {
      try {
        final list = await ref.read(_confirmedContribsProvider.future);
        final kpi = await ref.read(_kpiProvider.future);
        final methods = await ref.read(_methodSplitProvider.future);
        final regions = await ref.read(_regionSplitProvider.future);
        final range = ref.read(_analyticsRangeProvider);
        final df = DateFormat('dd/MM/yyyy');
        final doc = pw.Document();
        doc.addPage(
          pw.MultiPage(
            pageFormat: pw.PdfPageFormat.a4,
            build: (_) => [
              pw.Text('CMCDA — ${l.analyticsTitle}',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('${df.format(range.start)} — ${df.format(range.end)}',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 16),
              pw.Text(l.kpiTotalRevenue,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(AppUtils.formatAmount(kpi.totalRevenue)),
              pw.SizedBox(height: 8),
              pw.Text(l.kpiTxCount,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(kpi.txCount.toString()),
              pw.SizedBox(height: 8),
              pw.Text(l.kpiActiveContributors,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(kpi.activeContributors.toString()),
              pw.SizedBox(height: 16),
              pw.Text(l.paymentMethodBreakdown,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.TableHelper.fromTextArray(
                headers: ['Method', 'Amount'],
                data: methods.entries
                    .map((e) =>
                        [e.key, AppUtils.formatAmount(e.value)])
                    .toList(),
              ),
              pw.SizedBox(height: 16),
              pw.Text(l.regionalRevenue,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.TableHelper.fromTextArray(
                headers: ['Region', 'Amount'],
                data: regions
                    .map((r) =>
                        [r.region, AppUtils.formatAmount(r.total)])
                    .toList(),
              ),
              pw.SizedBox(height: 16),
              pw.Text('${l.kpiTxCount}: ${list.length}',
                  style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        );
        await Printing.layoutPdf(onLayout: (_) async => doc.save());
        await showOk(l.exportSuccess);
      } catch (_) {
        await showErr(l.exportError);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMD),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: exportCsv,
              icon: const Icon(Icons.table_rows_rounded, size: 18),
              label: Text(l.exportCsv),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: AppColors.primary),
                foregroundColor: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spaceSM),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: exportPdf,
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: Text(l.exportPdf),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
