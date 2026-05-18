import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:cmcda_platform/core/constants/app_constants.dart';
import 'package:cmcda_platform/core/utils/app_utils.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  // ── AppUtils.formatAmount ──────────────────────────────────────

  group('AppUtils.formatAmount', () {
    test('formats the four standard contribution amounts', () {
      expect(AppUtils.formatAmount(AppConstants.amountDaily), '100 FCFA');
      expect(AppUtils.formatAmount(AppConstants.amountMonthly), '3 000 FCFA');
      expect(AppUtils.formatAmount(AppConstants.amountAnnual), '36 500 FCFA');
    });

    test('formats zero', () {
      expect(AppUtils.formatAmount(0), '0 FCFA');
    });

    test('formats large amounts with thousands separator', () {
      final result = AppUtils.formatAmount(1000000);
      expect(result, contains('FCFA'));
      expect(result, contains('000'));
    });
  });

  // ── AppUtils.isValidCameroonPhone ─────────────────────────────

  group('AppUtils.isValidCameroonPhone', () {
    test('accepts 9-digit local format starting with 6', () {
      expect(AppUtils.isValidCameroonPhone('699000000'), isTrue);
      expect(AppUtils.isValidCameroonPhone('676543210'), isTrue);
      expect(AppUtils.isValidCameroonPhone('650000000'), isTrue);
    });

    test('accepts E.164 format with +237', () {
      expect(AppUtils.isValidCameroonPhone('+237699000000'), isTrue);
      expect(AppUtils.isValidCameroonPhone('+237676543210'), isTrue);
    });

    test('accepts country code without leading +', () {
      expect(AppUtils.isValidCameroonPhone('237699000000'), isTrue);
    });

    test('rejects numbers not starting with 6 after country code', () {
      expect(AppUtils.isValidCameroonPhone('123456789'), isFalse);
      expect(AppUtils.isValidCameroonPhone('+237123456789'), isFalse);
    });

    test('rejects too short numbers', () {
      expect(AppUtils.isValidCameroonPhone('699'), isFalse);
      expect(AppUtils.isValidCameroonPhone(''), isFalse);
    });

    test('rejects other country codes', () {
      expect(AppUtils.isValidCameroonPhone('+33699000000'), isFalse);
      expect(AppUtils.isValidCameroonPhone('+1234567890'), isFalse);
    });
  });

  // ── AppUtils.annualProgress ───────────────────────────────────

  group('AppUtils.annualProgress', () {
    test('zero paid = 0.0', () {
      expect(AppUtils.annualProgress(0), 0.0);
    });

    test('full annual amount = 1.0', () {
      expect(AppUtils.annualProgress(AppConstants.amountAnnual), 1.0);
    });

    test('half paid ≈ 0.5', () {
      const half = AppConstants.amountAnnual ~/ 2;
      expect(AppUtils.annualProgress(half), closeTo(0.5, 0.01));
    });

    test('overpayment is clamped to 1.0', () {
      expect(AppUtils.annualProgress(AppConstants.amountAnnual * 2), 1.0);
    });
  });

  // ── AppUtils.statusLabel ──────────────────────────────────────

  group('AppUtils.statusLabel', () {
    test('returns French labels for known statuses', () {
      expect(AppUtils.statusLabel(AppConstants.statusConfirmed), 'Confirmé');
      expect(AppUtils.statusLabel(AppConstants.statusPending), 'En attente');
      expect(AppUtils.statusLabel(AppConstants.statusFailed), 'Échoué');
      expect(AppUtils.statusLabel(AppConstants.statusRefunded), 'Remboursé');
    });

    test('returns raw string for unknown status', () {
      expect(AppUtils.statusLabel('unknown_xyz'), 'unknown_xyz');
    });
  });

  // ── AppUtils.roleLabel ────────────────────────────────────────

  group('AppUtils.roleLabel', () {
    test('returns French labels for all four roles', () {
      expect(AppUtils.roleLabel(AppConstants.roleMember), 'Membre');
      expect(AppUtils.roleLabel(AppConstants.roleFocal), 'Responsable Focal');
      expect(AppUtils.roleLabel(AppConstants.roleAdmin), 'Administrateur');
      expect(AppUtils.roleLabel(AppConstants.roleSuperAdmin), 'Super Administrateur');
    });
  });

  // ── AppUtils.paymentMethodLabel ───────────────────────────────

  group('AppUtils.paymentMethodLabel', () {
    test('returns French labels for all payment methods', () {
      expect(AppUtils.paymentMethodLabel(AppConstants.paymentMtnMomo), 'MTN Mobile Money');
      expect(AppUtils.paymentMethodLabel(AppConstants.paymentOrangeMoney), 'Orange Money');
      expect(AppUtils.paymentMethodLabel(AppConstants.paymentCash), 'Espèces');
      expect(AppUtils.paymentMethodLabel(AppConstants.paymentBankTransfer), 'Virement bancaire');
    });
  });

  // ── Member number format ──────────────────────────────────────

  group('Member number format', () {
    test('first member gets CM-000001', () {
      const count = 1;
      final number = '${AppConstants.memberPrefix}${count.toString().padLeft(6, '0')}';
      expect(number, 'CM-000001');
    });

    test('million-th member gets CM-1000000 (7 digits, no truncation)', () {
      const count = 1000000;
      final number = '${AppConstants.memberPrefix}${count.toString().padLeft(6, '0')}';
      expect(number, 'CM-1000000');
    });

    test('padded up to 6 zeros', () {
      const count = 42;
      final number = '${AppConstants.memberPrefix}${count.toString().padLeft(6, '0')}';
      expect(number, 'CM-000042');
    });
  });

  // ── AppUtils.getPeriodForDate ─────────────────────────────────

  group('AppUtils.getPeriodForDate', () {
    test('returns ISO year-month string', () {
      expect(AppUtils.getPeriodForDate(DateTime(2026, 5, 8)), '2026-05');
      expect(AppUtils.getPeriodForDate(DateTime(2026, 1, 1)), '2026-01');
      expect(AppUtils.getPeriodForDate(DateTime(2026, 12, 31)), '2026-12');
    });
  });

  // ── AppUtils.periodTypeLabel ──────────────────────────────────

  group('AppUtils.periodTypeLabel', () {
    test('returns French labels', () {
      expect(AppUtils.periodTypeLabel(AppConstants.periodDaily), 'Quotidien');
      expect(AppUtils.periodTypeLabel(AppConstants.periodMonthly), 'Mensuel');
      expect(AppUtils.periodTypeLabel(AppConstants.periodAnnual), 'Annuel');
      expect(AppUtils.periodTypeLabel(AppConstants.periodCustom), 'Personnalisé');
    });
  });
}
