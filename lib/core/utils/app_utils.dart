import 'package:intl/intl.dart';
import '../../data/models/focal_report_model.dart';
import '../constants/app_constants.dart';

class AppUtils {
  AppUtils._();

  // ── Amount Formatting ─────────────────────────────────────

  /// e.g. 3000 → "3 000 FCFA"
  static String formatAmount(int amount) {
    final formatter = NumberFormat('#,##0', 'fr_FR');
    return '${formatter.format(amount)} FCFA';
  }

  // ── Date Formatting ───────────────────────────────────────

  /// French long format: "4 mai 2026"
  static String formatDate(DateTime date) {
    return DateFormat('d MMMM yyyy', 'fr_FR').format(date);
  }

  /// Short: "04/05/2026"
  static String formatDateShort(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  /// Full with time: "04/05/2026 à 14:30"
  static String formatDateTime(DateTime date) {
    return DateFormat("dd/MM/yyyy 'à' HH:mm", 'fr_FR').format(date);
  }

  // ── Period Helpers ────────────────────────────────────────

  /// e.g. "Mai 2026"
  static String getCurrentPeriod() {
    return DateFormat('MMMM yyyy', 'fr_FR')
        .format(DateTime.now())
        .replaceFirstMapped(
          RegExp(r'^.'),
          (m) => m.group(0)!.toUpperCase(),
        );
  }

  /// Period string for a given date: "2026-05" (ISO year-month)
  static String getPeriodForDate(DateTime date) {
    return DateFormat('yyyy-MM').format(date);
  }

  /// Human-readable relative time in French
  static String timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 60) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays == 1) return 'Hier';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} jours';
    if (diff.inDays < 30) return 'Il y a ${(diff.inDays / 7).floor()} sem.';
    if (diff.inDays < 365) return 'Il y a ${(diff.inDays / 30).floor()} mois';
    return 'Il y a ${(diff.inDays / 365).floor()} an(s)';
  }

  // ── Label Helpers (French fallback — prefer AppLocalizations in UI) ───

  static String paymentMethodLabel(String method) {
    switch (method) {
      case AppConstants.paymentMtnMomo:
        return 'MTN Mobile Money';
      case AppConstants.paymentOrangeMoney:
        return 'Orange Money';
      case AppConstants.paymentCash:
        return 'Espèces';
      case AppConstants.paymentBankTransfer:
        return 'Virement bancaire';
      default:
        return method;
    }
  }

  static String paymentMethodIcon(String method) {
    switch (method) {
      case AppConstants.paymentMtnMomo:
        return '📱';
      case AppConstants.paymentOrangeMoney:
        return '🟠';
      case AppConstants.paymentCash:
        return '💵';
      case AppConstants.paymentBankTransfer:
        return '🏦';
      default:
        return '💳';
    }
  }

  static String statusLabel(String status) {
    switch (status) {
      case AppConstants.statusConfirmed:
        return 'Confirmé';
      case AppConstants.statusPending:
        return 'En attente';
      case AppConstants.statusFailed:
        return 'Échoué';
      case AppConstants.statusRefunded:
        return 'Remboursé';
      case AppConstants.userStatusActive:
        return 'Actif';
      case AppConstants.userStatusInactive:
        return 'Inactif';
      case AppConstants.userStatusSuspended:
        return 'Suspendu';
      default:
        return status;
    }
  }

  static String roleLabel(String role) {
    switch (role) {
      case AppConstants.roleMember:
        return 'Membre';
      case AppConstants.roleFocal:
        return 'Responsable Focal';
      case AppConstants.roleAdmin:
        return 'Administrateur';
      case AppConstants.roleSuperAdmin:
        return 'Super Administrateur';
      default:
        return role;
    }
  }

  static String periodTypeLabel(String type) {
    switch (type) {
      case AppConstants.periodDaily:
        return 'Quotidien';
      case AppConstants.periodMonthly:
        return 'Mensuel';
      case AppConstants.periodAnnual:
        return 'Annuel';
      case AppConstants.periodCustom:
        return 'Personnalisé';
      default:
        return type;
    }
  }

  // ── Progress ──────────────────────────────────────────────

  /// Annual progress: totalPaid / annualAmount clamped to [0.0, 1.0]
  static double annualProgress(int totalPaid) {
    return (totalPaid / AppConstants.amountAnnual).clamp(0.0, 1.0);
  }

  // ── Validation ────────────────────────────────────────────

  /// Validates Cameroonian mobile phone numbers.
  /// Accepts: 6XXXXXXXX (9 digits), +2376XXXXXXXX, 2376XXXXXXXX
  static bool isValidCameroonPhone(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\s\-()]+'), '');
    final pattern = RegExp(r'^(\+?237)?6[0-9]{8}$');
    return pattern.hasMatch(cleaned);
  }

  // ── WhatsApp Report ───────────────────────────────────────

  /// Generates a formatted text string suitable for WhatsApp sharing.
  static String generateWhatsAppReport(FocalReportModel report) {
    final separator = '─' * 30;
    final lines = [
      '📊 *Rapport Focal — CMCDA*',
      separator,
      '📍 *Zone :* ${report.location}',
      '📅 *Date :* ${formatDate(report.reportDate.toDate())}',
      '🆔 *N° Rapport :* ${report.id}',
      separator,
      '👥 *Membres servis :* ${report.membersServed}',
      '🆕 *Nouveaux membres :* ${report.newMembersCount}',
      '💰 *Total collecté :* ${formatAmount(report.totalCollected)}',
      separator,
      '👤 *Responsable :* ${report.focalName}',
      '📋 *Statut :* ${statusLabel(report.status)}',
    ];

    if (report.notes != null && report.notes!.isNotEmpty) {
      lines.add('📝 *Notes :* ${report.notes}');
    }

    lines.addAll([
      separator,
      '_Généré par CMCDA Platform — WoilaTech_',
    ]);

    return lines.join('\n');
  }
}
