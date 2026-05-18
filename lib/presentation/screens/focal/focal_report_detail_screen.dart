import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/models/focal_report_model.dart';
import '../../../data/repositories/focal_report_repository.dart';

const _focalBlue = Color(0xFF26A8F3);

// ── Providers ──────────────────────────────────────────────────

final _reportDetailProvider =
    StreamProvider.autoDispose.family<FocalReportModel?, String>(
        (ref, reportId) {
  return FirebaseFirestore.instance
      .collection(AppConstants.focalReportsCollection)
      .doc(reportId)
      .snapshots()
      .map((s) => s.exists ? FocalReportModel.fromFirestore(s) : null);
});

final _reportContributionsProvider =
    StreamProvider.autoDispose.family<List<ContributionModel>, String>(
        (ref, reportId) {
  return FirebaseFirestore.instance
      .collection(AppConstants.contributionsCollection)
      .where('focalReportId', isEqualTo: reportId)
      .orderBy('createdAt', descending: false)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => ContributionModel.fromFirestore(d)).toList());
});

// ── Screen ────────────────────────────────────────────────────

class FocalReportDetailScreen extends ConsumerStatefulWidget {
  final String reportId;
  const FocalReportDetailScreen({super.key, required this.reportId});

  @override
  ConsumerState<FocalReportDetailScreen> createState() =>
      _FocalReportDetailScreenState();
}

class _FocalReportDetailScreenState
    extends ConsumerState<FocalReportDetailScreen> {
  final _repo = FocalReportRepository();
  bool _actioning = false;

  // ── Actions ───────────────────────────────────────────────

  Future<void> _submit(FocalReportModel report) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Soumettre ce rapport ?',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, color: AppColors.textDark)),
        content: Text(
          'Le rapport sera envoyé aux administrateurs pour validation.',
          style: GoogleFonts.plusJakartaSans(
              color: AppColors.textGray, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _focalBlue, foregroundColor: Colors.white),
            child: const Text('Soumettre'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _actioning = true);
    try {
      await _repo.submitReport(report.id);
      NotificationService.instance.notifyFocalReport(
        focalName: report.focalName,
        reportId: report.id,
      ).ignore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rapport soumis avec succès'),
          backgroundColor: AppColors.success,
        ));
      }
    } finally {
      if (mounted) setState(() => _actioning = false);
    }
  }

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
          'Le rapport de ${report.focalName} sera marqué comme validé.',
          style: GoogleFonts.plusJakartaSans(
              color: AppColors.textGray, fontSize: 13),
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
    setState(() => _actioning = true);
    try {
      await _repo.validateReport(report.id, adminId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rapport validé'),
          backgroundColor: AppColors.success,
        ));
      }
    } finally {
      if (mounted) setState(() => _actioning = false);
    }
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
            Text('Indiquez la raison du rejet :',
                style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textGray, fontSize: 13)),
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
    setState(() => _actioning = true);
    try {
      await _repo.rejectReport(report.id, adminId, reasonCtrl.text.trim());
      reasonCtrl.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rapport rejeté'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _actioning = false);
    }
  }

  Future<void> _share(FocalReportModel report) async {
    final text = AppUtils.generateWhatsAppReport(report);
    final encoded = Uri.encodeComponent(text);
    final url = Uri.parse('whatsapp://send?text=$encoded');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Copié dans le presse-papier'),
          backgroundColor: AppColors.info,
        ));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final reportAsync =
        ref.watch(_reportDetailProvider(widget.reportId));
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final isAdmin = profile?.hasAdminAccess ?? false;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: reportAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: _focalBlue)),
          error: (e, _) => Center(
              child: Text('Erreur: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (report) {
            if (report == null) {
              return const Center(child: Text('Rapport introuvable'));
            }
            return _buildContent(context, report, isAdmin);
          },
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, FocalReportModel report, bool isAdmin) {
    final contribAsync =
        ref.watch(_reportContributionsProvider(widget.reportId));
    final (statusColor, statusLabel) = _statusInfo(report.status);
    final date = report.reportDate.toDate();

    return Column(
      children: [
        // Header
        _buildHeader(context, report, statusColor, statusLabel, date),
        // Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.spaceMD),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Stats card
                _buildStatsCard(report),
                const SizedBox(height: AppConstants.spaceMD),

                // Notes / rejection reason
                if (report.notes != null && report.notes!.isNotEmpty)
                  _buildNotesCard(report),

                // Contributions
                _buildContribSection(contribAsync),
                const SizedBox(height: AppConstants.spaceXL),
              ],
            ),
          ),
        ),
        // Action bar
        _buildActionBar(context, report, isAdmin),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, FocalReportModel report,
      Color statusColor, String statusLabel, DateTime date) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_focalBlue, Color(0xFF1A7FBF)],
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
              Expanded(
                child: Text(
                  report.location.isNotEmpty ? report.location : 'Rapport focal',
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4)),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceSM),
          Row(
            children: [
              const SizedBox(width: 54),
              const Icon(Icons.person_outline,
                  color: Colors.white70, size: 14),
              const SizedBox(width: 4),
              Text(
                report.focalName,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13),
              ),
              const SizedBox(width: AppConstants.spaceMD),
              const Icon(Icons.calendar_today_outlined,
                  color: Colors.white70, size: 14),
              const SizedBox(width: 4),
              Text(
                AppUtils.formatDate(date),
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Stats card ────────────────────────────────────────────

  Widget _buildStatsCard(FocalReportModel report) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: _focalBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: _focalBlue.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            label: 'Collecté',
            value: AppUtils.formatAmount(report.totalCollected),
            icon: Icons.payments_outlined,
            color: _focalBlue,
          ),
          _Divider(),
          _StatItem(
            label: 'Membres',
            value: '${report.membersServed}',
            icon: Icons.people_outline,
            color: AppColors.success,
          ),
          _Divider(),
          _StatItem(
            label: 'Nouveaux',
            value: '${report.newMembersCount}',
            icon: Icons.person_add_outlined,
            color: AppColors.gold,
          ),
        ],
      ),
    );
  }

  // ── Notes card ────────────────────────────────────────────

  Widget _buildNotesCard(FocalReportModel report) {
    final isRejected = report.isRejected;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceMD),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spaceMD),
        decoration: BoxDecoration(
          color: isRejected
              ? AppColors.error.withValues(alpha: 0.07)
              : AppColors.bg,
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(
            color: isRejected
                ? AppColors.error.withValues(alpha: 0.3)
                : AppColors.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isRejected
                  ? Icons.info_outline_rounded
                  : Icons.notes_rounded,
              color: isRejected ? AppColors.error : AppColors.textGray,
              size: 16,
            ),
            const SizedBox(width: AppConstants.spaceSM),
            Expanded(
              child: Text(
                report.notes!,
                style: TextStyle(
                  fontSize: 13,
                  color: isRejected ? AppColors.error : AppColors.textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Contributions ─────────────────────────────────────────

  Widget _buildContribSection(
      AsyncValue<List<ContributionModel>> contribAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.receipt_long_outlined,
                size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              'Paiements liés',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceSM),
        contribAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppConstants.spaceMD),
            child: Center(
                child: CircularProgressIndicator(
                    color: _focalBlue, strokeWidth: 2)),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (contributions) {
            if (contributions.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(AppConstants.spaceMD),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMD),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Center(
                  child: Text(
                    'Aucun paiement lié à ce rapport',
                    style: TextStyle(
                        color: AppColors.textGray, fontSize: 13),
                  ),
                ),
              );
            }
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusMD),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: contributions.asMap().entries.map((e) {
                  final i = e.key;
                  final c = e.value;
                  return Column(
                    children: [
                      _ContribRow(contribution: c),
                      if (i < contributions.length - 1)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    ],
                  );
                }).toList(),
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Action bar ────────────────────────────────────────────

  Widget _buildActionBar(
      BuildContext context, FocalReportModel report, bool isAdmin) {
    if (_actioning) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(AppConstants.spaceMD),
          child: Center(
              child:
                  CircularProgressIndicator(color: _focalBlue, strokeWidth: 2)),
        ),
      );
    }

    final buttons = <Widget>[];

    // Share button (always)
    buttons.add(
      OutlinedButton.icon(
        onPressed: () => _share(report),
        icon: const Icon(Icons.share_rounded, size: 16),
        label: const Text('Partager'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF25D366),
          side: const BorderSide(color: Color(0xFF25D366)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );

    // Focal officer: submit if draft
    if (!isAdmin && report.isDraft) {
      buttons.add(
        ElevatedButton.icon(
          onPressed: () => _submit(report),
          icon: const Icon(Icons.send_rounded, size: 16),
          label: const Text('Soumettre'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _focalBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );
    }

    // Admin: validate/reject if submitted
    if (isAdmin && report.isSubmitted) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => _reject(report),
          icon: const Icon(Icons.close_rounded, size: 16),
          label: const Text('Rejeter'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );
      buttons.add(
        ElevatedButton.icon(
          onPressed: () => _validate(report),
          icon: const Icon(Icons.check_rounded, size: 16),
          label: const Text('Valider'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceMD,
          AppConstants.spaceSM,
          AppConstants.spaceMD,
          AppConstants.spaceMD,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, -2)),
          ],
        ),
        child: Row(
          children: buttons
              .expand((b) => [Expanded(child: b), const SizedBox(width: 10)])
              .take(buttons.length * 2 - 1)
              .toList(),
        ),
      ),
    );
  }
}

// ── Stat item ─────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textGray),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 40, color: AppColors.border);
  }
}

// ── Contribution row ──────────────────────────────────────────

class _ContribRow extends StatelessWidget {
  final ContributionModel contribution;
  const _ContribRow({required this.contribution});

  @override
  Widget build(BuildContext context) {
    final c = contribution;
    final statusColor = c.status == AppConstants.statusConfirmed
        ? AppColors.success
        : c.status == AppConstants.statusPending
            ? AppColors.warning
            : AppColors.error;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMD,
          vertical: AppConstants.spaceSM + 2),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                c.memberName.isNotEmpty ? c.memberName[0].toUpperCase() : '?',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spaceSM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.memberName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  '${c.memberNumber} · ${AppUtils.paymentMethodLabel(c.paymentMethod)}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textGray),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                AppUtils.formatAmount(c.amount),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  AppUtils.statusLabel(c.status),
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: statusColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Status helper ─────────────────────────────────────────────

(Color, String) _statusInfo(String status) {
  return switch (status) {
    FocalReportModel.statusSubmitted => (AppColors.warning, 'En attente'),
    FocalReportModel.statusValidated => (AppColors.success, 'Validé'),
    FocalReportModel.statusRejected => (AppColors.error, 'Rejeté'),
    _ => (AppColors.textGray, 'Brouillon'),
  };
}
