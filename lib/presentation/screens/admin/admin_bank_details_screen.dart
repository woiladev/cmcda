import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/bank_details_model.dart';
import '../../../data/repositories/app_config_repository.dart';

class AdminBankDetailsScreen extends ConsumerStatefulWidget {
  const AdminBankDetailsScreen({super.key});

  @override
  ConsumerState<AdminBankDetailsScreen> createState() =>
      _AdminBankDetailsScreenState();
}

class _AdminBankDetailsScreenState
    extends ConsumerState<AdminBankDetailsScreen> {
  final _repo = AppConfigRepository();
  final _bankNameCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();

  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _accountNameCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  void _prefill(BankDetailsModel b) {
    if (_initialized) return;
    _bankNameCtrl.text = b.bankName;
    _accountNumberCtrl.text = b.accountNumber;
    _accountNameCtrl.text = b.accountName;
    _instructionsCtrl.text = b.instructions;
    _initialized = true;
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final uid = ref.read(currentUserProfileProvider).valueOrNull?.id ?? '';

    if (_bankNameCtrl.text.trim().isEmpty ||
        _accountNumberCtrl.text.trim().isEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text(l.fillRequiredFields),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      await _repo.updateBankDetails(
        bankName: _bankNameCtrl.text.trim(),
        accountNumber: _accountNumberCtrl.text.trim(),
        accountName: _accountNameCtrl.text.trim(),
        instructions: _instructionsCtrl.text.trim(),
        updatedBy: uid,
      );
      messenger.showSnackBar(SnackBar(
        content: Text(l.savedSuccessfully),
        backgroundColor: AppColors.success,
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(l.unknownError),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bankAsync = ref.watch(bankDetailsProvider);
    bankAsync.whenData(_prefill);
    // If the stream errors (permission issue, offline), fall back to defaults
    // so the form is still usable rather than stuck on the spinner forever.
    if (!_initialized && bankAsync.hasError) {
      _prefill(BankDetailsModel.defaults());
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(
          l.bankDetailsTitle,
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700),
        ),
      ),
      body: !_initialized
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(AppConstants.spaceLG),
              children: [
                Text(
                  l.bankDetailsSubtitle,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppColors.textGray,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppConstants.spaceLG),
                _Field(
                  controller: _bankNameCtrl,
                  label: l.bankNameLabel,
                  icon: Icons.account_balance_outlined,
                ),
                const SizedBox(height: AppConstants.spaceMD),
                _Field(
                  controller: _accountNumberCtrl,
                  label: l.accountNumberLabel,
                  icon: Icons.numbers_rounded,
                ),
                const SizedBox(height: AppConstants.spaceMD),
                _Field(
                  controller: _accountNameCtrl,
                  label: l.accountHolderLabel,
                  icon: Icons.person_outline_rounded,
                ),
                const SizedBox(height: AppConstants.spaceMD),
                _Field(
                  controller: _instructionsCtrl,
                  label: l.instructionsOptional,
                  icon: Icons.notes_rounded,
                  maxLines: 3,
                ),
                const SizedBox(height: AppConstants.spaceXL),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusLG),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : Text(
                            l.save,
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: GoogleFonts.plusJakartaSans(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
      ),
    );
  }
}
