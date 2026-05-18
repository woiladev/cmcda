import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';

// ── Provider ──────────────────────────────────────────────────

final _walletSummaryProvider =
    StreamProvider.autoDispose<Map<String, dynamic>?>((ref) {
  return FirebaseFirestore.instance
      .collection(AppConstants.walletConfigCollection)
      .doc(AppConstants.walletSummaryDoc)
      .snapshots()
      .map((s) => s.data());
});

// ── Helpers ───────────────────────────────────────────────────

/// Formats an integer amount as "1 250 000 FCFA" (fr_FR style with NBSP).
String _formatFCFA(int amount) {
  final formatted = NumberFormat('#,###', 'fr_FR').format(amount);
  // NumberFormat fr_FR uses a regular space; replace with non-breaking space
  return '${formatted.replaceAll(',', ' ')} FCFA';
}

/// Returns a compact label for large amounts (e.g. 1 500 000 → "1,5M").
String _compactAmount(double value) {
  if (value.abs() >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value.abs() >= 1000) {
    return '${(value / 1000).toStringAsFixed(0)}K';
  }
  return value.toStringAsFixed(0);
}

/// Translates a wallet type string to a localised label.
String _walletTypeLabel(String type, AppLocalizations l) {
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

/// Parses a '#rrggbb' hex string into a Flutter [Color].
Color _hexToColor(String hex) {
  final clean = hex.replaceFirst('#', '');
  return Color(int.parse('FF$clean', radix: 16));
}

// ── Screen ────────────────────────────────────────────────────

class TransparencyScreen extends ConsumerWidget {
  const TransparencyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final summaryAsync = ref.watch(_walletSummaryProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TransparencyHeader(title: l.transparencyTitle),
            Expanded(
              child: summaryAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spaceLG),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.error,
                          size: 48,
                        ),
                        const SizedBox(height: AppConstants.spaceMD),
                        Text(
                          l.error,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: AppConstants.spaceSM),
                        Text(
                          '$e',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppColors.textGray,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppConstants.spaceLG),
                        ElevatedButton(
                          onPressed: () =>
                              ref.invalidate(_walletSummaryProvider),
                          child: Text(l.retry),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (summary) => RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async =>
                      ref.invalidate(_walletSummaryProvider),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppConstants.spaceLG),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // A. Hero balance card
                        _HeroBalanceCard(summary: summary, l: l),
                        const SizedBox(height: AppConstants.spaceLG),
                        // B. Regional leaderboard
                        _RegionalSection(summary: summary, l: l),
                        const SizedBox(height: AppConstants.spaceLG),
                        // C. Global/operational accounts (hidden when empty)
                        _AccountsSection(summary: summary, l: l),
                        // D. Monthly chart section
                        _MonthlyChartSection(summary: summary, l: l),
                        const SizedBox(height: AppConstants.spaceXL),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────

class _TransparencyHeader extends StatelessWidget {
  final String title;
  const _TransparencyHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
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
        topPad + AppConstants.spaceMD,
        AppConstants.spaceMD,
        AppConstants.spaceMD,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.playfairDisplay(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppConstants.spaceSM),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.gold,
              borderRadius:
                  BorderRadius.circular(AppConstants.radiusFull),
            ),
            child: Text(
              AppConstants.acronym,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── A. Hero Balance Card ────────────────────────────────────────

class _HeroBalanceCard extends StatelessWidget {
  final Map<String, dynamic>? summary;
  final AppLocalizations l;
  const _HeroBalanceCard({required this.summary, required this.l});

  @override
  Widget build(BuildContext context) {
    final totalBalance = (summary?['total_balance'] as num?)?.toInt() ?? 0;
    final updatedAt = summary?['updated_at'] as Timestamp?;
    final dateStr = updatedAt != null
        ? DateFormat('d MMM yyyy, HH:mm', 'fr_FR').format(updatedAt.toDate())
        : '—';

    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceLG),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Row(
            children: [
              const Icon(Icons.account_balance_rounded,
                  size: 13, color: AppColors.gold),
              const SizedBox(width: 5),
              Text(
                'TRÉSORERIE OFFICIELLE CMCDA',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceSM),
          // Amount
          Text(
            _formatFCFA(totalBalance),
            style: GoogleFonts.playfairDisplay(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: AppConstants.spaceSM),
          // Updated at
          Row(
            children: [
              Icon(
                Icons.update_rounded,
                size: 13,
                color: Colors.white.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 5),
              Text(
                '${l.walletLastUpdate} : $dateStr',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── B. Regional Leaderboard ─────────────────────────────────────

class _RegionalSection extends StatelessWidget {
  final Map<String, dynamic>? summary;
  final AppLocalizations l;
  const _RegionalSection({required this.summary, required this.l});

  @override
  Widget build(BuildContext context) {
    final rawAccounts = summary?['accounts'] as List<dynamic>? ?? [];

    final regionTotals = <String, int>{};
    final regionColors = <String, String>{};
    for (final raw in rawAccounts) {
      final acc = raw as Map<String, dynamic>;
      final region = acc['region'] as String?;
      if (region == null || region.isEmpty) continue;
      final balance = (acc['balance'] as num?)?.toInt() ?? 0;
      regionTotals[region] = (regionTotals[region] ?? 0) + balance;
      regionColors[region] = acc['color'] as String? ?? '#16a34a';
    }

    if (regionTotals.isEmpty) return const SizedBox.shrink();

    // Sort by balance descending — highest contributing region first
    final sorted = regionTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final grandTotal = regionTotals.values.fold(0, (s, v) => s + v);
    final maxBalance = sorted.first.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _SectionHeader(label: l.byRegion)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.15),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.emoji_events_rounded,
                      size: 12, color: AppColors.gold),
                  const SizedBox(width: 4),
                  Text(
                    'Classement',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.gold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceMD),
        ...List.generate(sorted.length, (i) {
          final entry = sorted[i];
          final accentColor =
              _hexToColor(regionColors[entry.key] ?? '#16a34a');
          final pct = grandTotal > 0 ? entry.value / grandTotal : 0.0;
          final progress = maxBalance > 0 ? entry.value / maxBalance : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppConstants.spaceSM),
            child: _LeaderboardRow(
              rank: i + 1,
              region: entry.key,
              balance: entry.value,
              pct: pct,
              progress: progress,
              accentColor: accentColor,
            ),
          );
        }),
      ],
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final String region;
  final int balance;
  final double pct;
  final double progress;
  final Color accentColor;

  const _LeaderboardRow({
    required this.rank,
    required this.region,
    required this.balance,
    required this.pct,
    required this.progress,
    required this.accentColor,
  });

  static const _gold   = Color(0xFFFFD700);
  static const _silver = Color(0xFF9E9E9E);
  static const _bronze = Color(0xFFCD7F32);

  Color get _medalColor =>
      rank == 1 ? _gold : rank == 2 ? _silver : rank == 3 ? _bronze : AppColors.textGray;

  @override
  Widget build(BuildContext context) {
    final isTop3 = rank <= 3;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMD,
        AppConstants.spaceSM,
        AppConstants.spaceMD,
        AppConstants.spaceSM,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        border: Border.all(
          color: isTop3 ? accentColor.withValues(alpha: 0.35) : AppColors.border,
          width: isTop3 ? 1.5 : 1,
        ),
        boxShadow: rank == 1
            ? [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Rank badge
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _medalColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isTop3
                      ? Icon(Icons.emoji_events_rounded,
                          size: 14, color: _medalColor)
                      : Text(
                          '$rank',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _medalColor,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: AppConstants.spaceSM),
              // Region name + share label
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      region,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      '${(pct * 100).toStringAsFixed(1)} % du total',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        color: AppColors.textGray,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatFCFA(balance),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: balance > 0 ? AppColors.success : AppColors.textGray,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ── C. Accounts Section ─────────────────────────────────────────

class _AccountsSection extends StatelessWidget {
  final Map<String, dynamic>? summary;
  final AppLocalizations l;
  const _AccountsSection({required this.summary, required this.l});

  @override
  Widget build(BuildContext context) {
    final rawAccounts = summary?['accounts'] as List<dynamic>? ?? [];
    // Only show global/operational accounts — regional ones are in the leaderboard
    final global = rawAccounts.where((raw) {
      final acc = raw as Map<String, dynamic>;
      final region = acc['region'] as String?;
      return region == null || region.isEmpty;
    }).toList();

    if (global.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(label: l.walletAccounts),
        const SizedBox(height: AppConstants.spaceMD),
        ...global.map((raw) {
          final acc = raw as Map<String, dynamic>;
          final colorStr = acc['color'] as String? ?? '#1A6B3C';
          final balance = (acc['balance'] as num?)?.toInt() ?? 0;
          final accentColor = _hexToColor(colorStr);
          return Padding(
            padding: const EdgeInsets.only(bottom: AppConstants.spaceSM),
            child: _AccountCard(
              name: acc['name'] as String? ?? '—',
              type: acc['type'] as String? ?? '',
              balance: balance,
              accentColor: accentColor,
              l: l,
            ),
          );
        }),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  final String name;
  final String type;
  final int balance;
  final Color accentColor;
  final AppLocalizations l;

  const _AccountCard({
    required this.name,
    required this.type,
    required this.balance,
    required this.accentColor,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        border: Border.all(color: AppColors.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 4px accent left border
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppConstants.radiusMD),
                  bottomLeft: Radius.circular(AppConstants.radiusMD),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceMD,
                  vertical: AppConstants.spaceMD,
                ),
                child: Row(
                  children: [
                    // Name + type
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _walletTypeLabel(type, l),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: AppColors.textGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Balance
                    Text(
                      _formatFCFA(balance),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: balance > 0
                            ? AppColors.success
                            : AppColors.textGray,
                      ),
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

// ── C. Monthly Chart Section ────────────────────────────────────

class _MonthlyChartSection extends StatelessWidget {
  final Map<String, dynamic>? summary;
  final AppLocalizations l;
  const _MonthlyChartSection({required this.summary, required this.l});

  @override
  Widget build(BuildContext context) {
    final rawMonthly = summary?['monthly'] as List<dynamic>? ?? [];
    // Use last 12 months max
    final months = rawMonthly.length > 12
        ? rawMonthly.sublist(rawMonthly.length - 12)
        : rawMonthly;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(label: l.monthlyChart),
        const SizedBox(height: AppConstants.spaceMD),
        Container(
          padding: const EdgeInsets.all(AppConstants.spaceMD),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusLG),
            border: Border.all(color: AppColors.border),
          ),
          child: months.isEmpty
              ? SizedBox(
                  height: 120,
                  child: Center(
                    child: Text(
                      l.noData,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: AppColors.textGray,
                      ),
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Legend
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _LegendDot(
                            color: AppColors.success, label: l.inflowLabel),
                        const SizedBox(width: AppConstants.spaceMD),
                        _LegendDot(
                            color: AppColors.error, label: l.outflowLabel),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spaceMD),
                    // Chart
                    SizedBox(
                      height: 220,
                      child: _BarChart(months: months),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<dynamic> months;
  const _BarChart({required this.months});

  @override
  Widget build(BuildContext context) {
    // Compute the max value for Y-axis scaling
    double maxVal = 1;
    for (final raw in months) {
      final m = raw as Map<String, dynamic>;
      final inflow = (m['inflow'] as num?)?.toDouble() ?? 0;
      final outflow = (m['outflow'] as num?)?.toDouble() ?? 0;
      if (inflow > maxVal) maxVal = inflow;
      if (outflow > maxVal) maxVal = outflow;
    }

    final barGroups = <BarChartGroupData>[];
    for (var i = 0; i < months.length; i++) {
      final m = months[i] as Map<String, dynamic>;
      final inflow = (m['inflow'] as num?)?.toDouble() ?? 0;
      final outflow = (m['outflow'] as num?)?.toDouble() ?? 0;
      barGroups.add(
        BarChartGroupData(
          x: i,
          barsSpace: 3,
          barRods: [
            BarChartRodData(
              toY: inflow,
              width: 6,
              color: AppColors.success,
              borderRadius: BorderRadius.circular(3),
            ),
            BarChartRodData(
              toY: outflow,
              width: 6,
              color: AppColors.error,
              borderRadius: BorderRadius.circular(3),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        maxY: maxVal * 1.2,
        minY: 0,
        barGroups: barGroups,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => const FlLine(
            color: AppColors.border,
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    _compactAmount(value),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      color: AppColors.textGray,
                    ),
                    textAlign: TextAlign.right,
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= months.length) {
                  return const SizedBox.shrink();
                }
                final monthStr =
                    (months[idx] as Map<String, dynamic>)['month']
                        as String? ??
                        '';
                // Show last 3 chars of 'YYYY-MM' which gives the zero-padded
                // month number; instead parse and abbreviate properly.
                final label = _monthAbbrev(monthStr);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      color: AppColors.textGray,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.primaryDark,
            tooltipRoundedRadius: AppConstants.radiusSM,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final amount = rod.toY.toInt();
              return BarTooltipItem(
                _compactAmount(rod.toY),
                GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: amount == 0
                      ? Colors.white.withValues(alpha: 0.5)
                      : Colors.white,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Abbreviates a 'YYYY-MM' string to a 3-letter French month abbreviation.
  String _monthAbbrev(String yearMonth) {
    if (yearMonth.length < 7) return yearMonth;
    final month = int.tryParse(yearMonth.substring(5, 7));
    if (month == null || month < 1 || month > 12) return yearMonth;
    const abbrevs = [
      'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Jun',
      'Jul', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc',
    ];
    return abbrevs[month - 1];
  }
}

// ── Shared sub-widgets ──────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textGray,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: AppColors.textGray,
          ),
        ),
      ],
    );
  }
}
