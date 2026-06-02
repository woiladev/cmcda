import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/contribution_repository.dart';
import '../../../data/repositories/pawapay_repository.dart';
import '../../widgets/common/payment_method_icon.dart';

// ── Focal pawaPay (mobile money) sheet ────────────────────────
// Triggers a real pawaPay PIN prompt on the member's phone for a focal-recorded
// MoMo payment. The deposit is created server-side on the member's behalf and
// confirmed via webhook/poll; this sheet pops `true` once it confirms.

const _focalLight = Color(0xFF26A8F3);

enum _FppStep { phone, waiting }

class FocalPawaPaySheet extends StatefulWidget {
  final UserModel member;
  final int amount;
  final String periodType;
  final bool isMtn;

  const FocalPawaPaySheet({
    super.key,
    required this.member,
    required this.amount,
    required this.periodType,
    required this.isMtn,
  });

  @override
  State<FocalPawaPaySheet> createState() => _FocalPawaPaySheetState();
}

class _FocalPawaPaySheetState extends State<FocalPawaPaySheet> {
  final _pawaPay = PawaPayRepository();
  final _contribRepo = ContributionRepository();
  final _phoneCtrl = TextEditingController();
  final _phoneFocus = FocusNode();

  late String _provider;
  _FppStep _step = _FppStep.phone;
  bool _busy = false;
  bool _checking = false;
  String? _error;
  String? _contribId;
  StreamSubscription<ContributionModel?>? _sub;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _provider = widget.isMtn
        ? AppConstants.pawaPayProviderMtn
        : AppConstants.pawaPayProviderOrange;
    _phoneCtrl.text = widget.member.phone;
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _phoneFocus.dispose();
    _sub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  bool get _isMtnSelected => _provider == AppConstants.pawaPayProviderMtn;
  Color get _accent =>
      _isMtnSelected ? const Color(0xFFFFCC00) : const Color(0xFFFF6600);

  Future<void> _pay() async {
    final l = AppLocalizations.of(context);
    final phone = _phoneCtrl.text.trim();
    if (!AppUtils.isValidCameroonPhone(phone)) {
      setState(() => _error = l.invalidPhone);
      return;
    }
    _phoneFocus.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _pawaPay.initiateDeposit(
        amount: widget.amount,
        periodType: widget.periodType,
        phoneNumber: phone,
        provider: _provider,
        memberId: widget.member.id,
      );
      if (!mounted) return;
      _contribId = r.contributionId;
      setState(() {
        _busy = false;
        _step = _FppStep.waiting;
      });
      _watch(r.contributionId);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message ?? l.paymentFailed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l.paymentFailed;
      });
    }
  }

  void _watch(String contributionId) {
    final l = AppLocalizations.of(context);
    _sub = _contribRepo.streamContribution(contributionId).listen((c) {
      if (c == null || !mounted) return;
      if (c.status == AppConstants.statusConfirmed) {
        _sub?.cancel();
        _pollTimer?.cancel();
        Navigator.of(context).pop(true);
      } else if (c.status == AppConstants.statusFailed) {
        _sub?.cancel();
        _pollTimer?.cancel();
        setState(() {
          _step = _FppStep.phone;
          _error = (c.notes != null && c.notes!.isNotEmpty)
              ? c.notes
              : l.paymentFailed;
        });
      }
    });
    // Poll fallback once after 60s in case no webhook callback arrives.
    _pollTimer = Timer(const Duration(seconds: 60), _refreshStatus);
  }

  Future<void> _refreshStatus() async {
    final id = _contribId;
    if (id == null || _checking) return;
    setState(() => _checking = true);
    try {
      await _pawaPay.checkDeposit(id);
      // The stream listener reacts to the resulting status change.
    } catch (_) {
      // Ignore; the stream/webhook may still resolve it.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXL),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        AppConstants.spaceMD,
        AppConstants.spaceLG,
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            AppConstants.spaceLG,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spaceLG),
            _header(),
            const SizedBox(height: AppConstants.spaceLG),
            if (_step == _FppStep.phone) ..._phoneStep() else ..._waitingStep(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: paymentMethodIcon(
              _isMtnSelected
                  ? AppConstants.paymentMtnMomo
                  : AppConstants.paymentOrangeMoney,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: AppConstants.spaceMD),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.mobileMoneyPayment,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                '${widget.member.fullName} · ${AppUtils.formatAmount(widget.amount)}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppColors.textGray,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: AppColors.textGray),
        ),
      ],
    );
  }

  Widget _providerChip({
    required String label,
    required bool selected,
    required Color accent,
    required String method,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppConstants.spaceMD,
            horizontal: AppConstants.spaceSM,
          ),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.12) : AppColors.bg,
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            border: Border.all(
              color: selected ? accent : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              paymentMethodIcon(method, size: 20),
              const SizedBox(width: AppConstants.spaceSM),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.textDark : AppColors.textGray,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _phoneStep() {
    final l = AppLocalizations.of(context);
    return [
      Row(
        children: [
          _providerChip(
            label: l.mtnMomo,
            selected: _isMtnSelected,
            accent: const Color(0xFFFFCC00),
            method: AppConstants.paymentMtnMomo,
            onTap: () =>
                setState(() => _provider = AppConstants.pawaPayProviderMtn),
          ),
          const SizedBox(width: AppConstants.spaceSM),
          _providerChip(
            label: l.orangeMoney,
            selected: !_isMtnSelected,
            accent: const Color(0xFFFF6600),
            method: AppConstants.paymentOrangeMoney,
            onTap: () =>
                setState(() => _provider = AppConstants.pawaPayProviderOrange),
          ),
        ],
      ),
      const SizedBox(height: AppConstants.spaceMD),
      TextFormField(
        controller: _phoneCtrl,
        focusNode: _phoneFocus,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
          LengthLimitingTextInputFormatter(16),
        ],
        decoration: InputDecoration(
          labelText: l.enterMomoNumber,
          hintText: '+237 6XX XXX XXX',
          prefixIcon: const Icon(
            Icons.smartphone_rounded,
            color: _focalLight,
          ),
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onFieldSubmitted: (_) => _pay(),
      ),
      const SizedBox(height: AppConstants.spaceLG),
      SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: _busy ? null : _pay,
          style: ElevatedButton.styleFrom(
            backgroundColor: _focalLight,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.border,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLG),
            ),
            elevation: 0,
          ),
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  '${l.payNow} · ${AppUtils.formatAmount(widget.amount)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
        ),
      ),
    ];
  }

  List<Widget> _waitingStep() {
    final l = AppLocalizations.of(context);
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppConstants.spaceMD),
        child: Column(
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(_accent),
              ),
            ),
            const SizedBox(height: AppConstants.spaceLG),
            Text(
              l.confirmOnPhone,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: AppConstants.spaceSM),
            Text(
              l.pinPromptMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.textGray,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppConstants.spaceMD),
      SizedBox(
        height: 54,
        child: OutlinedButton.icon(
          onPressed: _checking ? null : _refreshStatus,
          icon: _checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
          label: Text(
            l.refreshStatus,
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _focalLight,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLG),
            ),
          ),
        ),
      ),
    ];
  }
}
