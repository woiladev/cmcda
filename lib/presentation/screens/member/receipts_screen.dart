import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../widgets/common/payment_method_icon.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/repositories/contribution_repository.dart';

// ── Provider ──────────────────────────────────────────────────

final _contributionRepo = ContributionRepository();

final _receiptsProvider =
    StreamProvider.autoDispose.family<List<ContributionModel>, String>(
  (ref, uid) => _contributionRepo.getMemberContributions(uid),
);

// ── Screen ────────────────────────────────────────────────────

class ReceiptsScreen extends ConsumerStatefulWidget {
  const ReceiptsScreen({super.key});

  @override
  ConsumerState<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends ConsumerState<ReceiptsScreen> {
  String? _selectedYear;
  String _statusFilter = 'all'; // all | confirmed | pending

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final profileAsync = ref.watch(currentUserProfileProvider);

    return profileAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => Scaffold(body: Center(child: Text(l.unknownError))),
      data: (user) {
        if (user == null) return Scaffold(body: Center(child: Text(l.unknownError)));
        final receiptsAsync = ref.watch(_receiptsProvider(user.id));
        return _buildScaffold(context, l, receiptsAsync);
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    AppLocalizations l,
    AsyncValue<List<ContributionModel>> receiptsAsync,
  ) {
    final all = receiptsAsync.valueOrNull ?? [];

    // Collect distinct years
    final years = all
        .map((c) => c.createdAt.toDate().year.toString())
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (_selectedYear == null && years.isNotEmpty) {
      _selectedYear = years.first;
    }

    // Apply filters
    final filtered = all.where((c) {
      final yearMatch = _selectedYear == null ||
          c.createdAt.toDate().year.toString() == _selectedYear;
      final statusMatch = _statusFilter == 'all' ||
          (_statusFilter == 'confirmed' && c.isConfirmed) ||
          (_statusFilter == 'pending' && c.isPending);
      return yearMatch && statusMatch;
    }).toList();

    final confirmedTotal = filtered
        .where((c) => c.isConfirmed)
        .fold<int>(0, (s, c) => s + c.amount);
    final pendingCount = filtered.where((c) => c.isPending).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          // ── Header ────────────────────────────────────────
          SliverToBoxAdapter(child: _buildHeader(context, l, confirmedTotal, pendingCount)),

          // ── Year chips ────────────────────────────────────
          if (years.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildYearChips(years),
            ),

          // ── Status filter ─────────────────────────────────
          SliverToBoxAdapter(
            child: _buildStatusFilter(l),
          ),

          // ── List ──────────────────────────────────────────
          receiptsAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(AppConstants.spaceXL),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (_, __) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spaceXL),
                child: Center(child: Text(l.unknownError)),
              ),
            ),
            data: (_) {
              if (filtered.isEmpty) {
                return SliverToBoxAdapter(child: _EmptyReceipts(l: l));
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spaceLG,
                  0,
                  AppConstants.spaceLG,
                  AppConstants.spaceXL,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => Padding(
                      padding: const EdgeInsets.only(bottom: AppConstants.spaceSM),
                      child: _ReceiptCard(
                        contribution: filtered[i],
                        onTap: () => _openDetail(context, l, filtered[i]),
                      ),
                    ),
                    childCount: filtered.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    AppLocalizations l,
    int confirmedTotal,
    int pendingCount,
  ) {
    final statusBarH = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        statusBarH + AppConstants.spaceMD,
        AppConstants.spaceLG,
        AppConstants.spaceLG,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back + title row
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 16),
                ),
              ),
              const SizedBox(width: AppConstants.spaceMD),
              Text(
                l.myReceipts,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceLG),
          // Summary card
          Container(
            padding: const EdgeInsets.all(AppConstants.spaceLG),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppConstants.radiusLG),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeaderStat(
                    label: l.totalContributed,
                    value: AppUtils.formatAmount(confirmedTotal)
                        .replaceAll(' FCFA', ''),
                    suffix: 'FCFA',
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: Colors.white.withValues(alpha: 0.2),
                  margin: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMD),
                ),
                Expanded(
                  child: _HeaderStat(
                    label: l.paymentPending,
                    value: pendingCount.toString().padLeft(2, '0'),
                    valueColor: pendingCount > 0 ? AppColors.gold : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Year chips ────────────────────────────────────────────

  Widget _buildYearChips(List<String> years) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        AppConstants.spaceLG,
        AppConstants.spaceLG,
        0,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final year in years) ...[
              _FilterChip(
                label: year,
                selected: _selectedYear == year,
                onTap: () => setState(() => _selectedYear = year),
                selectedColor: AppColors.primary,
              ),
              const SizedBox(width: AppConstants.spaceSM),
            ],
          ],
        ),
      ),
    );
  }

  // ── Status filter ─────────────────────────────────────────

  Widget _buildStatusFilter(AppLocalizations l) {
    final filters = [
      ('all', l.allFilter),
      ('confirmed', l.confirmed),
      ('pending', l.pending),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        AppConstants.spaceSM,
        AppConstants.spaceLG,
        AppConstants.spaceMD,
      ),
      child: Row(
        children: [
          for (final (key, label) in filters) ...[
            _FilterChip(
              label: label,
              selected: _statusFilter == key,
              onTap: () => setState(() => _statusFilter = key),
              selectedColor: key == 'confirmed'
                  ? AppColors.success
                  : key == 'pending'
                      ? AppColors.warning
                      : AppColors.primary,
            ),
            const SizedBox(width: AppConstants.spaceSM),
          ],
        ],
      ),
    );
  }

  // ── Detail sheet ──────────────────────────────────────────

  void _openDetail(
      BuildContext context, AppLocalizations l, ContributionModel c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReceiptDetailSheet(contribution: c, l: l),
    );
  }
}

// ── Receipt card ──────────────────────────────────────────────

class _ReceiptCard extends StatelessWidget {
  final ContributionModel contribution;
  final VoidCallback onTap;

  const _ReceiptCard({required this.contribution, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = contribution;
    final isConfirmed = c.isConfirmed;
    final statusColor = isConfirmed ? AppColors.success : AppColors.warning;
    final date = AppUtils.formatDate(c.createdAt.toDate());
    final methodLabel = AppUtils.paymentMethodLabel(c.paymentMethod);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.textDark.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left status bar
              Container(width: 4, color: statusColor),
              // Card content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spaceMD),
                  child: Row(
                    children: [
                      // Method icon
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: paymentMethodIcon(c.paymentMethod, size: 20, color: statusColor),
                      ),
                      const SizedBox(width: AppConstants.spaceMD),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _periodLabel(c.period),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$date · $methodLabel',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: AppColors.textGray,
                              ),
                            ),
                            if (c.receiptNumber.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'N° ${c.receiptNumber}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  color: AppColors.textGray.withValues(alpha: 0.7),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: AppConstants.spaceSM),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            AppUtils.formatAmount(c.amount),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                            ),
                            child: Text(
                              isConfirmed ? 'Confirmé' : 'En attente',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Detail bottom sheet ───────────────────────────────────────

class _ReceiptDetailSheet extends StatelessWidget {
  final ContributionModel contribution;
  final AppLocalizations l;

  const _ReceiptDetailSheet({required this.contribution, required this.l});

  @override
  Widget build(BuildContext context) {
    final c = contribution;
    final isConfirmed = c.isConfirmed;
    final statusColor = isConfirmed ? AppColors.success : AppColors.warning;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppConstants.radiusXL)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppConstants.spaceMD),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
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
                  AppConstants.spaceXL,
                ),
                children: [
                  // Title row
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                        ),
                        child: paymentMethodIcon(c.paymentMethod, size: 24, color: statusColor),
                      ),
                      const SizedBox(width: AppConstants.spaceMD),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _periodLabel(c.period),
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                            ),
                            Text(
                              AppUtils.paymentMethodLabel(c.paymentMethod),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: AppColors.textGray,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusFull),
                          border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          isConfirmed ? 'Confirmé' : 'En attente',
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

                  // Amount
                  Container(
                    padding: const EdgeInsets.all(AppConstants.spaceLG),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(AppConstants.radiusLG),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Montant',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: AppColors.textGray,
                          ),
                        ),
                        Text(
                          AppUtils.formatAmount(c.amount),
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceMD),

                  // Details
                  _DetailRow(
                    icon: Icons.receipt_outlined,
                    label: l.receiptNo,
                    value: c.receiptNumber.isNotEmpty ? c.receiptNumber : '—',
                    copyable: c.receiptNumber.isNotEmpty,
                  ),
                  _DetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Date de paiement',
                    value: AppUtils.formatDateTime(c.createdAt.toDate()),
                  ),
                  if (c.confirmedAt != null)
                    _DetailRow(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Confirmé le',
                      value: AppUtils.formatDateTime(c.confirmedAt!.toDate()),
                    ),
                  _DetailRow(
                    icon: Icons.calendar_month_outlined,
                    label: 'Période',
                    value: _periodLabel(c.period),
                  ),
                  _DetailRow(
                    icon: Icons.category_outlined,
                    label: 'Type',
                    value: AppUtils.periodTypeLabel(c.periodType),
                  ),
                  if (c.notes != null && c.notes!.isNotEmpty)
                    _DetailRow(
                      icon: Icons.notes_rounded,
                      label: 'Notes',
                      value: c.notes!,
                    ),

                  if (c.validationRequired && !isConfirmed) ...[
                    const SizedBox(height: AppConstants.spaceMD),
                    Container(
                      padding: const EdgeInsets.all(AppConstants.spaceMD),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.08),
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusMD),
                        border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              color: AppColors.warning, size: 16),
                          const SizedBox(width: AppConstants.spaceSM),
                          Expanded(
                            child: Text(
                              l.pendingValidationMsg,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
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

// ── Helpers ───────────────────────────────────────────────────

String _periodLabel(String period) {
  try {
    final parts = period.split('-');
    if (parts.length == 2) {
      final d = DateTime(int.parse(parts[0]), int.parse(parts[1]));
      final formatted = DateFormat('MMMM yyyy', 'fr_FR').format(d);
      return formatted[0].toUpperCase() + formatted.substring(1);
    }
  } catch (_) {}
  return period;
}


// ── Sub-widgets ───────────────────────────────────────────────

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;
  final Color? valueColor;

  const _HeaderStat({
    required this.label,
    required this.value,
    this.suffix,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.6),
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: valueColor ?? Colors.white,
              ),
            ),
            if (suffix != null) ...[
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  suffix!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedColor;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? selectedColor : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: selected ? selectedColor : AppColors.border,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: selectedColor.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textGray,
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool copyable;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.copyable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceSM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textGray),
          const SizedBox(width: AppConstants.spaceSM),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppColors.textGray,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                if (copyable)
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copié'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.copy_rounded,
                          size: 14, color: AppColors.primary),
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

class _EmptyReceipts extends StatelessWidget {
  final AppLocalizations l;
  const _EmptyReceipts({required this.l});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spaceXL),
      child: Column(
        children: [
          const SizedBox(height: AppConstants.spaceLG),
          const Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.border),
          const SizedBox(height: AppConstants.spaceLG),
          Text(
            l.noPaymentYet,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textGray,
            ),
          ),
          const SizedBox(height: AppConstants.spaceSM),
          Text(
            'Vos reçus apparaîtront ici après chaque paiement',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppColors.textGray.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
