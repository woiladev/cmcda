import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/contribution_model.dart';
import '../../widgets/common/payment_method_icon.dart';
import 'focal_providers.dart';

const _focalLight = Color(0xFF26A8F3);
const _focalDark = Color(0xFF0A5F8C);

/// Lists every contribution the focal officer has recorded for their members,
/// newest first, with a status filter and a tap-to-open detail sheet.
class FocalPaymentsScreen extends ConsumerStatefulWidget {
  const FocalPaymentsScreen({super.key});

  @override
  ConsumerState<FocalPaymentsScreen> createState() =>
      _FocalPaymentsScreenState();
}

class _FocalPaymentsScreenState extends ConsumerState<FocalPaymentsScreen> {
  // null = all statuses
  String? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final userId = ref.watch(currentUserProfileProvider).valueOrNull?.id ?? '';
    final paymentsAsync = ref.watch(focalRecentPaymentsProvider(userId));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Column(
          children: [
            _header(context, l, _visible(paymentsAsync.valueOrNull)),
            _filterBar(l),
            Expanded(
              child: paymentsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: _focalLight),
                ),
                error: (_, __) => Center(
                  child: Text(
                    l.unknownError,
                    style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textGray),
                  ),
                ),
                data: (payments) {
                  final visible = _visible(payments);
                  if (visible.isEmpty) return _empty(l);
                  return ListView.builder(
                    padding: const EdgeInsets.all(AppConstants.spaceLG),
                    itemCount: visible.length,
                    itemBuilder: (_, i) => _PaymentRow(
                      contribution: visible[i],
                      l: l,
                      onTap: () => _openDetail(visible[i], l),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<ContributionModel> _visible(List<ContributionModel>? all) {
    final list = all ?? const <ContributionModel>[];
    if (_statusFilter == null) return list;
    return list.where((c) => c.status == _statusFilter).toList();
  }

  void _openDetail(ContributionModel c, AppLocalizations l) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentDetailSheet(contribution: c, l: l),
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l,
    List<ContributionModel> visible,
  ) {
    final statusBarH = MediaQuery.of(context).padding.top;
    final total = visible
        .where((c) => c.isConfirmed)
        .fold<int>(0, (s, c) => s + c.amount);

    return Container(
      width: double.infinity,
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
          colors: [_focalLight, _focalDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.recentPayments,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${visible.length} · ${AppUtils.formatAmount(total)}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.75),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar(AppLocalizations l) {
    final filters = <(String?, String)>[
      (null, l.filterAll),
      (AppConstants.statusConfirmed, l.confirmed),
      (AppConstants.statusPending, l.pending),
      (AppConstants.statusFailed, l.failed),
    ];
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceLG, vertical: AppConstants.spaceSM),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (value, label) in filters) ...[
              _FilterChip(
                label: label,
                selected: _statusFilter == value,
                onTap: () => setState(() => _statusFilter = value),
              ),
              const SizedBox(width: AppConstants.spaceSM),
            ],
          ],
        ),
      ),
    );
  }

  Widget _empty(AppLocalizations l) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _focalLight.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_outlined,
                color: _focalLight, size: 30),
          ),
          const SizedBox(height: AppConstants.spaceMD),
          Text(
            l.noPaymentYet,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textGray,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceMD, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _focalLight : AppColors.bg,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: selected ? _focalLight : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textGray,
          ),
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final ContributionModel contribution;
  final AppLocalizations l;
  final VoidCallback onTap;

  const _PaymentRow({
    required this.contribution,
    required this.l,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = contribution;
    final statusColor = c.isConfirmed
        ? AppColors.success
        : c.isFailed
            ? AppColors.error
            : AppColors.warning;
    final statusLabel =
        c.isConfirmed ? l.confirmed : c.isFailed ? l.failed : l.pending;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spaceSM),
        padding: const EdgeInsets.all(AppConstants.spaceMD),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: AppColors.bg,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: paymentMethodIcon(c.paymentMethod,
                  size: 20, color: AppColors.textGray),
            ),
            const SizedBox(width: AppConstants.spaceMD),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.memberName.isNotEmpty ? c.memberName : c.memberNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  Text(
                    '${AppUtils.formatAmount(c.amount)} · ${AppUtils.formatDateShort(c.createdAt.toDate())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: AppColors.textGray),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppConstants.spaceSM),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Text(
                statusLabel,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textGray),
          ],
        ),
      ),
    );
  }
}

// ── Detail sheet ──────────────────────────────────────────────

class _PaymentDetailSheet extends StatelessWidget {
  final ContributionModel contribution;
  final AppLocalizations l;

  const _PaymentDetailSheet({required this.contribution, required this.l});

  @override
  Widget build(BuildContext context) {
    final c = contribution;
    final statusColor = c.isConfirmed
        ? AppColors.success
        : c.isFailed
            ? AppColors.error
            : AppColors.warning;
    final statusLabel =
        c.isConfirmed ? l.confirmed : c.isFailed ? l.failed : l.pending;

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppConstants.radiusXL)),
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
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(
                    AppConstants.spaceLG, 0, AppConstants.spaceLG,
                    AppConstants.spaceXL),
                children: [
                  // Header: member + status
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: const BoxDecoration(
                          color: AppColors.bg,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: paymentMethodIcon(c.paymentMethod,
                            size: 24, color: AppColors.textGray),
                      ),
                      const SizedBox(width: AppConstants.spaceMD),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.memberName.isNotEmpty
                                  ? c.memberName
                                  : c.memberNumber,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                            ),
                            if (c.memberNumber.isNotEmpty)
                              Text(
                                c.memberNumber,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _focalLight,
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

                  // Amount hero
                  Container(
                    padding: const EdgeInsets.all(AppConstants.spaceLG),
                    decoration: BoxDecoration(
                      color: _focalLight.withValues(alpha: 0.06),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusLG),
                      border: Border.all(
                          color: _focalLight.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.amount,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11, color: AppColors.textGray),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppUtils.formatAmount(c.amount),
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: _focalDark,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              AppUtils.paymentMethodLabel(c.paymentMethod),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textDark),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${AppUtils.periodTypeLabel(c.periodType)} · ${c.period}',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12, color: AppColors.textGray),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // Detail rows
                  _DetailRow(
                    icon: Icons.receipt_outlined,
                    label: l.receiptNo,
                    value:
                        c.receiptNumber.isNotEmpty ? c.receiptNumber : '—',
                  ),
                  _DetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: l.submissionDate,
                    value: AppUtils.formatDateTime(c.createdAt.toDate()),
                  ),
                  if (c.confirmedAt != null)
                    _DetailRow(
                      icon: Icons.check_circle_outline_rounded,
                      label: l.confirmedOn,
                      value: AppUtils.formatDateTime(c.confirmedAt!.toDate()),
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
                ],
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
      padding: const EdgeInsets.symmetric(vertical: AppConstants.spaceSM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textGray),
          const SizedBox(width: AppConstants.spaceMD),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: AppColors.textGray),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
