import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/focal_report_model.dart';
import '../../../data/repositories/focal_report_repository.dart';

// ── Providers ──────────────────────────────────────────────────

final _allReportsProvider =
    StreamProvider.autoDispose<List<FocalReportModel>>((ref) {
  return FocalReportRepository().streamAllReports();
});

// ── Screen ────────────────────────────────────────────────────

class AdminFocalReportsScreen extends ConsumerStatefulWidget {
  const AdminFocalReportsScreen({super.key});

  @override
  ConsumerState<AdminFocalReportsScreen> createState() =>
      _AdminFocalReportsScreenState();
}

class _AdminFocalReportsScreenState
    extends ConsumerState<AdminFocalReportsScreen> {
  final _repo = FocalReportRepository();
  String? _filterStatus; // null = all

  // ── Actions ───────────────────────────────────────────────

  Future<void> _validate(FocalReportModel report) async {
    final adminId =
        ref.read(currentUserProfileProvider).valueOrNull?.id ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Valider ce rapport ?',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, color: AppColors.textDark)),
        content: Text(
          'Le rapport de ${report.focalName} (${report.location}) sera marqué comme validé.',
          style:
              GoogleFonts.plusJakartaSans(color: AppColors.textGray, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _repo.validateReport(report.id, adminId);
  }

  Future<void> _reject(FocalReportModel report) async {
    final adminId =
        ref.read(currentUserProfileProvider).valueOrNull?.id ?? '';
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rejeter ce rapport ?',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, color: AppColors.textDark)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Indiquez la raison du rejet :',
              style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textGray, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Raison...',
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMD)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: const Text('Rejeter'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _repo.rejectReport(
        report.id, adminId, reasonCtrl.text.trim());
    reasonCtrl.dispose();
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(_allReportsProvider);

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
            Expanded(
              child: reportsAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary)),
                error: (e, _) => Center(
                    child: Text('Erreur: $e',
                        style: const TextStyle(color: AppColors.error))),
                data: (reports) => _buildBody(context, reports),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
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
        AppConstants.spaceLG,
      ),
      child: Row(
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rapports focaux',
                style: GoogleFonts.playfairDisplay(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Soumissions des officiers focaux',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────

  Widget _buildBody(BuildContext context, List<FocalReportModel> all) {
    final submitted =
        all.where((r) => r.status == FocalReportModel.statusSubmitted).length;
    final validated =
        all.where((r) => r.status == FocalReportModel.statusValidated).length;
    final rejected =
        all.where((r) => r.status == FocalReportModel.statusRejected).length;

    final filtered = _filterStatus == null
        ? all
        : all.where((r) => r.status == _filterStatus).toList();

    return Column(
      children: [
        // Stats strip
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(
              vertical: AppConstants.spaceMD,
              horizontal: AppConstants.spaceMD),
          child: Row(
            children: [
              _StatChip(
                label: 'En attente',
                count: submitted,
                color: AppColors.warning,
                selected: _filterStatus == FocalReportModel.statusSubmitted,
                onTap: () => setState(() => _filterStatus =
                    _filterStatus == FocalReportModel.statusSubmitted
                        ? null
                        : FocalReportModel.statusSubmitted),
              ),
              const SizedBox(width: AppConstants.spaceSM),
              _StatChip(
                label: 'Validés',
                count: validated,
                color: AppColors.success,
                selected: _filterStatus == FocalReportModel.statusValidated,
                onTap: () => setState(() => _filterStatus =
                    _filterStatus == FocalReportModel.statusValidated
                        ? null
                        : FocalReportModel.statusValidated),
              ),
              const SizedBox(width: AppConstants.spaceSM),
              _StatChip(
                label: 'Rejetés',
                count: rejected,
                color: AppColors.error,
                selected: _filterStatus == FocalReportModel.statusRejected,
                onTap: () => setState(() => _filterStatus =
                    _filterStatus == FocalReportModel.statusRejected
                        ? null
                        : FocalReportModel.statusRejected),
              ),
              const Spacer(),
              Text(
                '${all.length} total',
                style: const TextStyle(
                    color: AppColors.textGray, fontSize: 11),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // List
        Expanded(
          child: filtered.isEmpty
              ? _buildEmpty()
              : ListView.separated(
                  padding: const EdgeInsets.all(AppConstants.spaceMD),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppConstants.spaceSM),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => context.push(
                        AppRoutes.focalReport, extra: filtered[i].id),
                    child: _ReportCard(
                      report: filtered[i],
                      onValidate: () => _validate(filtered[i]),
                      onReject: () => _reject(filtered[i]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.assignment_outlined,
              size: 56, color: AppColors.border),
          const SizedBox(height: AppConstants.spaceMD),
          Text(
            _filterStatus == null
                ? 'Aucun rapport focal'
                : 'Aucun rapport dans cette catégorie',
            style: const TextStyle(color: AppColors.textGray, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ── Stat chip ─────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : AppColors.bg,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
              color: selected ? color : AppColors.border,
              width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? color : AppColors.textDark,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? color : AppColors.textGray,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Report card ───────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final FocalReportModel report;
  final VoidCallback onValidate;
  final VoidCallback onReject;

  const _ReportCard({
    required this.report,
    required this.onValidate,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(report.status);
    final date = report.reportDate.toDate();
    final dateLabel =
        DateFormat('d MMM yyyy', 'fr_FR').format(date);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: statusColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spaceMD),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: name + status badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            report.focalName,
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        _StatusBadge(status: report.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Location + date
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 12, color: AppColors.textGray),
                        const SizedBox(width: 2),
                        Text(
                          report.location,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textGray),
                        ),
                        const SizedBox(width: AppConstants.spaceSM),
                        const Icon(Icons.calendar_today_outlined,
                            size: 12, color: AppColors.textGray),
                        const SizedBox(width: 2),
                        Text(
                          dateLabel,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textGray),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spaceSM),
                    // Stats row
                    Row(
                      children: [
                        _MiniStat(
                          icon: Icons.people_outline,
                          label: '${report.membersServed} membres',
                        ),
                        const SizedBox(width: AppConstants.spaceMD),
                        _MiniStat(
                          icon: Icons.person_add_outlined,
                          label: '${report.newMembersCount} nouveaux',
                        ),
                        const Spacer(),
                        Text(
                          AppUtils.formatAmount(report.totalCollected),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    // Notes (if rejected)
                    if (report.notes != null &&
                        report.notes!.isNotEmpty &&
                        report.isRejected) ...[
                      const SizedBox(height: AppConstants.spaceSM),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.07),
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusSM),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline,
                                size: 12, color: AppColors.error),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                report.notes!,
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Action buttons for submitted reports
                    if (report.isSubmitted) ...[
                      const SizedBox(height: AppConstants.spaceSM),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onReject,
                              icon: const Icon(Icons.close_rounded, size: 14),
                              label: const Text('Rejeter'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.error,
                                side: const BorderSide(
                                    color: AppColors.error),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8),
                                textStyle:
                                    const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppConstants.spaceSM),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: onValidate,
                              icon: const Icon(Icons.check_rounded,
                                  size: 14),
                              label: const Text('Valider'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8),
                                textStyle:
                                    const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case FocalReportModel.statusSubmitted:
        return AppColors.warning;
      case FocalReportModel.statusValidated:
        return AppColors.success;
      case FocalReportModel.statusRejected:
        return AppColors.error;
      default:
        return AppColors.border;
    }
  }
}

// ── Status badge ──────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      FocalReportModel.statusSubmitted => ('En attente', AppColors.warning),
      FocalReportModel.statusValidated => ('Validé', AppColors.success),
      FocalReportModel.statusRejected => ('Rejeté', AppColors.error),
      _ => ('Brouillon', AppColors.border),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ── Mini stat ─────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MiniStat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textGray),
        const SizedBox(width: 3),
        Text(
          label,
          style:
              const TextStyle(fontSize: 11, color: AppColors.textGray),
        ),
      ],
    );
  }
}
