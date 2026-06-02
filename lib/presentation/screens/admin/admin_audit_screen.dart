import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/auth_repository.dart';

/// One-shot audit of matricule integrity across the user base.
///
/// Surfaces three numbers an admin needs to know before trusting the data:
///   1. members whose `memberNumber` is empty or missing,
///   2. members whose `memberNumber` doesn't match any known region prefix
///      (legacy / hand-edited records),
///   3. contributions whose `memberId` is empty (orphaned payment records).
///
/// Read-only — no automatic backfill. The numbers tell the team whether a
/// manual cleanup pass is needed.
class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key});

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  bool _loading = false;
  bool _hasError = false;
  bool _repairing = false;
  _AuditResult? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final db = FirebaseFirestore.instance;
      final usersSnap =
          await db.collection(AppConstants.usersCollection).get();

      final validPrefixes = {
        ...AppConstants.regionMemberPrefixes.values,
        AppConstants.memberPrefixFallback,
      };

      var missing = 0;
      var malformed = 0;
      final seen = <String, int>{};
      for (final doc in usersSnap.docs) {
        final num = (doc.data()['memberNumber'] as String?)?.trim() ?? '';
        if (num.isEmpty) {
          missing++;
          continue;
        }
        seen[num] = (seen[num] ?? 0) + 1;
        final prefix = num.contains('-') ? num.split('-').first : '';
        if (prefix.isEmpty || !validPrefixes.contains(prefix)) {
          malformed++;
        }
      }
      // Duplicates = extra docs beyond the first holder of each number.
      final duplicates = seen.values
          .where((c) => c > 1)
          .fold<int>(0, (s, c) => s + (c - 1));

      // Contributions with empty memberId — Firestore can't query "is empty",
      // so we read recent docs and count client-side. Capped to a sane window.
      final contribSnap = await db
          .collection(AppConstants.contributionsCollection)
          .orderBy('createdAt', descending: true)
          .limit(500)
          .get();
      final orphanContribs = contribSnap.docs.where((d) {
        final id = (d.data()['memberId'] as String?)?.trim() ?? '';
        return id.isEmpty;
      }).length;

      setState(() {
        _result = _AuditResult(
          totalMembers: usersSnap.size,
          missingMatricule: missing,
          malformedMatricule: malformed,
          duplicateMatricule: duplicates,
          orphanContributions: orphanContribs,
          contribsScanned: contribSnap.size,
        );
        _loading = false;
      });
    } catch (e, st) {
      developer.log('Audit failed', error: e, stackTrace: st);
      setState(() {
        _hasError = true;
        _loading = false;
      });
    }
  }

  Future<void> _repair() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final lc = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(lc.repairConfirmTitle,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, color: AppColors.textDark)),
          content: Text(lc.repairConfirmMsg,
              style: GoogleFonts.plusJakartaSans(color: AppColors.textGray)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(lc.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text(lc.confirm, style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    setState(() => _repairing = true);
    try {
      final result = await AuthRepository().repairMemberNumbers();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(
          result.repaired > 0
              ? l.repairResult(result.repaired)
              : l.repairNoneNeeded,
          style: GoogleFonts.plusJakartaSans(fontSize: 13),
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ));
      await _run();
    } catch (e, st) {
      developer.log('Matricule repair failed', error: e, stackTrace: st);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(l.repairError,
            style: GoogleFonts.plusJakartaSans(fontSize: 13)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _repairing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(
          l.auditMatricules,
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _run,
            tooltip: l.refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spaceLG),
                    child: Text(
                      l.auditFailed,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                )
              : _buildResult(l, _result!),
    );
  }

  Widget _buildResult(AppLocalizations l, _AuditResult r) {
    final allClean = r.missingMatricule == 0 &&
        r.malformedMatricule == 0 &&
        r.duplicateMatricule == 0 &&
        r.orphanContributions == 0;
    final canRepair = r.missingMatricule > 0 || r.duplicateMatricule > 0;

    return ListView(
      padding: const EdgeInsets.all(AppConstants.spaceLG),
      children: [
        _BannerCard(allClean: allClean),
        const SizedBox(height: AppConstants.spaceLG),
        _StatCard(
          icon: Icons.people_outline_rounded,
          label: l.auditMembersTotal,
          value: '${r.totalMembers}',
          color: AppColors.primary,
        ),
        const SizedBox(height: AppConstants.spaceMD),
        _StatCard(
          icon: Icons.error_outline_rounded,
          label: l.auditMissingMatricule,
          value: '${r.missingMatricule}',
          color: r.missingMatricule == 0
              ? AppColors.success
              : AppColors.error,
        ),
        const SizedBox(height: AppConstants.spaceMD),
        _StatCard(
          icon: Icons.content_copy_rounded,
          label: l.auditDuplicateMatricule,
          value: '${r.duplicateMatricule}',
          color: r.duplicateMatricule == 0
              ? AppColors.success
              : AppColors.error,
        ),
        const SizedBox(height: AppConstants.spaceMD),
        _StatCard(
          icon: Icons.warning_amber_rounded,
          label: l.auditMalformedMatricule,
          value: '${r.malformedMatricule}',
          color: r.malformedMatricule == 0
              ? AppColors.success
              : AppColors.warning,
        ),
        const SizedBox(height: AppConstants.spaceMD),
        _StatCard(
          icon: Icons.link_off_rounded,
          label: l.auditOrphanContributions(r.contribsScanned),
          value: '${r.orphanContributions}',
          color: r.orphanContributions == 0
              ? AppColors.success
              : AppColors.error,
        ),
        if (canRepair) ...[
          const SizedBox(height: AppConstants.spaceLG),
          _RepairCard(
            busy: _repairing,
            onRepair: _repairing ? null : _repair,
          ),
        ],
      ],
    );
  }
}

class _AuditResult {
  final int totalMembers;
  final int missingMatricule;
  final int malformedMatricule;
  final int duplicateMatricule;
  final int orphanContributions;
  final int contribsScanned;

  const _AuditResult({
    required this.totalMembers,
    required this.missingMatricule,
    required this.malformedMatricule,
    required this.duplicateMatricule,
    required this.orphanContributions,
    required this.contribsScanned,
  });
}

class _RepairCard extends StatelessWidget {
  final bool busy;
  final VoidCallback? onRepair;
  const _RepairCard({required this.busy, required this.onRepair});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
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
            l.repairMemberNumbersDesc,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppColors.textGray,
            ),
          ),
          const SizedBox(height: AppConstants.spaceMD),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRepair,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    vertical: AppConstants.spaceMD),
              ),
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high_rounded, size: 20),
              label: Text(
                l.repairMemberNumbers,
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  final bool allClean;
  const _BannerCard({required this.allClean});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = allClean ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            allClean
                ? Icons.check_circle_rounded
                : Icons.info_outline_rounded,
            color: color,
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: Text(
              allClean ? l.auditAllClean : l.auditIssuesDetected,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Text(
            value,
            style: GoogleFonts.playfairDisplay(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
