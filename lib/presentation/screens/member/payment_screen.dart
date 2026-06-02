import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../widgets/common/payment_method_icon.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/bank_details_model.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/repositories/app_config_repository.dart';
import '../../../data/repositories/contribution_repository.dart';
import '../../../data/repositories/pawapay_repository.dart';

// ── Responsive breakpoints ────────────────────────────────────

const double _kWideBreakpoint = 900;
const double _kMaxContentWidth = 1120;
const double _kSummaryWidth = 380;

bool _isWide(BuildContext c) =>
    MediaQuery.of(c).size.width >= _kWideBreakpoint;

// ── Data models (const, no localized labels here) ─────────────

class _AmountOption {
  final int amount;
  final String periodType;
  final bool isPopular;
  const _AmountOption({
    required this.amount,
    required this.periodType,
    this.isPopular = false,
  });
}

const _amountOptions = [
  _AmountOption(
    amount: AppConstants.amountDaily,
    periodType: AppConstants.periodDaily,
  ),
  _AmountOption(
    amount: AppConstants.amountMonthly,
    periodType: AppConstants.periodMonthly,
    isPopular: true,
  ),
  _AmountOption(
    amount: AppConstants.amountAnnual,
    periodType: AppConstants.periodAnnual,
  ),
];

class _MethodOption {
  final String key;
  const _MethodOption({required this.key});
}

const _methodOptions = [
  _MethodOption(key: AppConstants.paymentMtnMomo),
  _MethodOption(key: AppConstants.paymentOrangeMoney),
  _MethodOption(key: AppConstants.paymentBankTransfer),
];

// ── Screen ────────────────────────────────────────────────────

enum _PaymentStep { form, success }

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen>
    with SingleTickerProviderStateMixin {
  final _repo = ContributionRepository();
  final _customCtrl = TextEditingController();
  final _customFocus = FocusNode();

  int? _selectedIndex = 1; // monthly by default
  String _selectedMethod = AppConstants.paymentMtnMomo;
  bool _isProcessing = false;
  _PaymentStep _step = _PaymentStep.form;
  String? _receiptNumber;
  String? _contribId; // created doc id — used to live-watch the receipt number
  bool _isCashBank = false;

  late final AnimationController _successAnim;
  late final Animation<double> _checkScale;
  late final Animation<double> _contentFade;

  @override
  void initState() {
    super.initState();
    _successAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _checkScale = CurvedAnimation(
      parent: _successAnim,
      curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
    );
    _contentFade = CurvedAnimation(
      parent: _successAnim,
      curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
    );
    _customCtrl.addListener(() {
      if (_customCtrl.text.isNotEmpty && _selectedIndex != null) {
        setState(() => _selectedIndex = null);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _successAnim.dispose();
    _customCtrl.dispose();
    _customFocus.dispose();
    super.dispose();
  }

  // ── Computed ───────────────────────────────────────────────

  int get _amount {
    if (_selectedIndex != null) return _amountOptions[_selectedIndex!].amount;
    return int.tryParse(_customCtrl.text.trim()) ?? 0;
  }

  String get _periodType {
    if (_selectedIndex != null) {
      return _amountOptions[_selectedIndex!].periodType;
    }
    return AppConstants.periodCustom;
  }

  bool get _isMobileMoney =>
      _selectedMethod == AppConstants.paymentMtnMomo ||
      _selectedMethod == AppConstants.paymentOrangeMoney;

  bool get _canPay => _amount > 0;

  String _periodDisplayLabel(AppLocalizations l) {
    final now = DateTime.now();
    final monthYear = DateFormat('MMMM yyyy', 'fr_FR').format(now);
    final cap = monthYear[0].toUpperCase() + monthYear.substring(1);
    switch (_periodType) {
      case AppConstants.periodDaily:
        return '${l.daily} (${AppUtils.formatDate(now)})';
      case AppConstants.periodMonthly:
        return '${l.monthly} ($cap)';
      case AppConstants.periodAnnual:
        return '${l.annual} (${now.year})';
      default:
        return l.custom;
    }
  }

  String _methodLabel(String key, AppLocalizations l) {
    switch (key) {
      case AppConstants.paymentMtnMomo:
        return l.mtnMomo;
      case AppConstants.paymentOrangeMoney:
        return l.orangeMoney;
      case AppConstants.paymentCash:
        return l.cash;
      case AppConstants.paymentBankTransfer:
        return l.bankTransfer;
      default:
        return key;
    }
  }

  String _optionLabel(int index, AppLocalizations l) {
    switch (_amountOptions[index].periodType) {
      case AppConstants.periodDaily:
        return l.daily;
      case AppConstants.periodMonthly:
        return l.monthly;
      case AppConstants.periodAnnual:
        return l.annual;
      default:
        return l.custom;
    }
  }

  String _methodSubtitle(String key, AppLocalizations l) {
    switch (key) {
      case AppConstants.paymentMtnMomo:
      case AppConstants.paymentOrangeMoney:
        return l.viaUssd;
      case AppConstants.paymentCash:
        return l.cashToResponsible;
      case AppConstants.paymentBankTransfer:
        return AppConstants.bankName;
      default:
        return '';
    }
  }

  // ── Actions ────────────────────────────────────────────────

  void _onPayTap(BuildContext context, AppLocalizations l) {
    if (!_canPay) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.selectAnAmount)),
      );
      return;
    }
    _customFocus.unfocus();
    if (_isMobileMoney) {
      _showPawaPaySheet(context, l);
    } else if (_selectedMethod == AppConstants.paymentBankTransfer) {
      _showBankTransferSheet(context, l);
    } else {
      _showCashBankDialog(context, l);
    }
  }

  void _showBankTransferSheet(BuildContext context, AppLocalizations l) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _BankTransferSheet(
            amount: _amount,
            l: l,
            onConfirmed: (proof) {
              Navigator.pop(context);
              _processPayment(isCashBank: true, proof: proof);
            },
          ),
        ),
      ),
    );
  }

  void _showPawaPaySheet(BuildContext context, AppLocalizations l) {
    final isMtn = _selectedMethod == AppConstants.paymentMtnMomo;
    final user = ref.read(currentUserProfileProvider).valueOrNull;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _PawaPaySheet(
            amount: _amount,
            periodType: _periodType,
            isMtn: isMtn,
            initialPhone: user?.phone ?? '',
            methodLabel: _methodLabel(_selectedMethod, l),
            l: l,
            onConfirmed: (contributionId) {
              Navigator.pop(context);
              _onPawaPaySuccess(contributionId);
            },
          ),
        ),
      ),
    );
  }

  // Mobile-money deposits are created and confirmed server-side (pawaPay), so we
  // jump straight to the success screen; it live-watches the contribution doc
  // to reveal the receipt number once onContributionCreated assigns it.
  void _onPawaPaySuccess(String contributionId) {
    setState(() {
      _contribId = contributionId;
      _receiptNumber = null;
      _isCashBank = false;
      _step = _PaymentStep.success;
    });
    _successAnim.forward();
  }

  void _showCashBankDialog(BuildContext context, AppLocalizations l) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        ),
        title: Text(
          l.confirmRequest,
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.textDark,
          ),
        ),
        content: Text(
          '${AppUtils.formatAmount(_amount)} via ${_methodLabel(_selectedMethod, l)} — ${l.pendingValidationMsg}.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: AppColors.textMid,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _processPayment(isCashBank: true);
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 44),
            ),
            child: Text(l.confirm),
          ),
        ],
      ),
    );
  }

  Future<void> _processPayment(
      {required bool isCashBank, XFile? proof}) async {
    final user = ref.read(currentUserProfileProvider).valueOrNull;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${AppLocalizations.of(context).error}: profil utilisateur non chargé'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    setState(() => _isProcessing = true);
    try {
      String? proofUrl;
      if (proof != null) {
        proofUrl = await _repo.uploadProof(proof, user.id);
      }
      final c = await _repo.createContribution(
        memberId: user.id,
        memberName: user.fullName,
        memberNumber: user.memberNumber,
        amount: _amount,
        periodType: _periodType,
        paymentMethod: _selectedMethod,
        recordedBy: user.id,
        proofUrl: proofUrl,
      );
      // The "payment confirmed" push is sent server-side by the
      // onContributionConfirmed Cloud Function when status flips to confirmed.
      setState(() {
        _receiptNumber = c.receiptNumber.isEmpty ? null : c.receiptNumber;
        _contribId = c.id;
        _isCashBank = isCashBank;
        _step = _PaymentStep.success;
      });
      _successAnim.forward();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context).error}: $e'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Reset success state whenever the Pay tab is re-entered from another tab.
    ref.listen<int>(paymentTabActivationProvider, (_, __) {
      if (_step == _PaymentStep.success) _resetToForm();
    });

    if (_step == _PaymentStep.success) return _buildSuccess(context);
    return _buildForm(context);
  }

  // Discard a shown receipt so the form is fresh next time the payment branch
  // is displayed. The screen stays alive in the StatefulNavigationShell, so the
  // success step would otherwise linger when re-entered via context.go(...)
  // (e.g. the dashboard's "record a payment" buttons), which don't bump
  // paymentTabActivationProvider the way the nav bar does.
  void _resetToForm() {
    if (!mounted) return;
    setState(() {
      _step = _PaymentStep.form;
      _receiptNumber = null;
      _contribId = null;
      _isCashBank = false;
    });
    _successAnim.reset();
  }

  // The receipt number is assigned server-side (onContributionCreated), so it
  // arrives a moment after the write — and only after sync if created offline.
  // Watch the doc and reveal the number once present, with a pending hint
  // until then.
  Widget _buildReceiptNumber(AppLocalizations l) {
    Widget big(String n) => Text(
          '#$n',
          style: GoogleFonts.playfairDisplay(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.accent,
          ),
        );

    if (_receiptNumber != null) return big(_receiptNumber!);
    if (_contribId == null) return big('---');

    return StreamBuilder<ContributionModel?>(
      stream: _repo.streamContribution(_contribId!),
      builder: (context, snap) {
        final number = snap.data?.receiptNumber ?? '';
        if (number.isNotEmpty) return big(number);
        return Text(
          l.receiptPendingSync,
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12.5,
            fontStyle: FontStyle.italic,
            color: Colors.white.withValues(alpha: 0.72),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════
  // SUCCESS SCREEN
  // ══════════════════════════════════════════════════════════

  Widget _buildSuccess(BuildContext context) {
    final l = AppLocalizations.of(context);
    final capturedAmount = _amount;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primaryLight,
                AppColors.primary,
                AppColors.primaryDark,
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppConstants.spaceLG),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ScaleTransition(
                        scale: _checkScale,
                        child: Container(
                          width: 116,
                          height: 116,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.32),
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 78,
                              height: 78,
                              decoration: const BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: AppColors.primaryDark,
                                size: 46,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppConstants.spaceLG),
                      FadeTransition(
                        opacity: _contentFade,
                        child: Column(
                          children: [
                            Text(
                              _isCashBank
                                  ? l.requestRegistered
                                  : l.paymentDone,
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppConstants.spaceSM),
                            Text(
                              _isCashBank
                                  ? l.pendingValidationMsg
                                  : l.thanksContribution,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.72),
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppConstants.spaceXL),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppConstants.spaceXL,
                                vertical: AppConstants.spaceLG,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusLG),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    l.receipt.toUpperCase(),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      letterSpacing: 1.4,
                                      color: Colors.white
                                          .withValues(alpha: 0.6),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(
                                      height: AppConstants.spaceXS),
                                  _buildReceiptNumber(l),
                                  const SizedBox(
                                      height: AppConstants.spaceSM),
                                  Divider(
                                    color:
                                        Colors.white.withValues(alpha: 0.16),
                                    height: 1,
                                  ),
                                  const SizedBox(
                                      height: AppConstants.spaceSM),
                                  Text(
                                    AppUtils.formatAmount(capturedAmount),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppConstants.spaceXL),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed: () {
                                  _resetToForm();
                                  context.go(AppRoutes.dashboard);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColors.primaryDark,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppConstants.radiusLG),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  l.backToDashboard,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // FORM SCREEN
  // ══════════════════════════════════════════════════════════

  Widget _buildForm(BuildContext context) {
    final l = AppLocalizations.of(context);
    final wide = _isWide(context);

    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: wide ? null : _buildBottomPanel(context, l),
      body: wide ? _buildWideBody(context, l) : _buildNarrowBody(context, l),
    );
  }

  // ── Narrow (mobile) body ───────────────────────────────────

  Widget _buildNarrowBody(BuildContext context, AppLocalizations l) {
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(child: _HeroHeader(l: l)),
        SliverPadding(
          padding: const EdgeInsets.all(AppConstants.spaceMD),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildAmountSection(context, l),
              const SizedBox(height: AppConstants.spaceMD),
              _buildMethodSection(context, l),
            ]),
          ),
        ),
      ],
    );
  }

  // ── Wide (web / tablet) body ───────────────────────────────

  Widget _buildWideBody(BuildContext context, AppLocalizations l) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: _kMaxContentWidth),
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spaceXL),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _CompactHeader(l: l),
                              const SizedBox(height: AppConstants.spaceLG),
                              _buildAmountSection(context, l),
                              const SizedBox(height: AppConstants.spaceLG),
                              _buildMethodSection(context, l),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppConstants.spaceXL),
                        SizedBox(
                          width: _kSummaryWidth,
                          child: _buildSummaryCard(context, l),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Amount section ─────────────────────────────────────────

  Widget _buildAmountSection(BuildContext context, AppLocalizations l) {
    return _SectionCard(
      icon: Icons.savings_rounded,
      title: l.chooseAmount,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _amountOptions.length; i++) ...[
                  Expanded(
                    child: _PlanCard(
                      periodType: _amountOptions[i].periodType,
                      label: _optionLabel(i, l),
                      amount: _amountOptions[i].amount,
                      isPopular: _amountOptions[i].isPopular,
                      popularLabel: l.popularBadge,
                      selected: _selectedIndex == i,
                      onTap: () => setState(() {
                        _selectedIndex = i;
                        _customCtrl.clear();
                        _customFocus.unfocus();
                        if (_amountOptions[i].periodType ==
                                AppConstants.periodDaily &&
                            _selectedMethod ==
                                AppConstants.paymentBankTransfer) {
                          _selectedMethod = AppConstants.paymentMtnMomo;
                        }
                      }),
                    ),
                  ),
                  if (i != _amountOptions.length - 1)
                    const SizedBox(width: AppConstants.spaceSM),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spaceMD),
          _CustomAmountCard(
            l: l,
            selected: _selectedIndex == null,
            controller: _customCtrl,
            focusNode: _customFocus,
            onTap: () {
              setState(() => _selectedIndex = null);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _customFocus.requestFocus();
              });
            },
          ),
        ],
      ),
    );
  }

  // ── Method section ─────────────────────────────────────────

  Widget _buildMethodSection(BuildContext context, AppLocalizations l) {
    final visibleMethods = _methodOptions
        .where((o) => !(_periodType == AppConstants.periodDaily &&
            o.key == AppConstants.paymentBankTransfer))
        .toList();
    return _SectionCard(
      icon: Icons.account_balance_wallet_rounded,
      title: l.paymentMethod,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < visibleMethods.length; i++) ...[
            _MethodTile(
              methodKey: visibleMethods[i].key,
              label: _methodLabel(visibleMethods[i].key, l),
              subtitle: _methodSubtitle(visibleMethods[i].key, l),
              selected: _selectedMethod == visibleMethods[i].key,
              onTap: () =>
                  setState(() => _selectedMethod = visibleMethods[i].key),
            ),
            if (i != visibleMethods.length - 1)
              const SizedBox(height: AppConstants.spaceSM),
          ],
        ],
      ),
    );
  }

  // ── Summary card (wide side column) ────────────────────────

  Widget _buildSummaryCard(BuildContext context, AppLocalizations l) {
    final amount = _amount;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceLG),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.totalToPay.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: AppConstants.spaceXS),
          Text(
            amount > 0 ? AppUtils.formatAmount(amount) : '— FCFA',
            style: GoogleFonts.playfairDisplay(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: AppConstants.spaceLG),
          _SummaryRow(label: l.periodLabel, value: _periodDisplayLabel(l)),
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: AppConstants.spaceSM),
            child: Divider(
              color: Colors.white.withValues(alpha: 0.14),
              height: 1,
            ),
          ),
          _SummaryRow(
            label: l.modeLabel,
            value: _methodLabel(_selectedMethod, l),
          ),
          const SizedBox(height: AppConstants.spaceLG),
          SizedBox(
            height: 54,
            child: _isProcessing
                ? const _LoadingButton()
                : _PayButton(
                    amount: amount,
                    methodKey: _selectedMethod,
                    canPay: _canPay,
                    onTap: () => _onPayTap(context, l),
                  ),
          ),
          const SizedBox(height: AppConstants.spaceSM),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded,
                  size: 12, color: Colors.white.withValues(alpha: 0.55)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  l.securePaymentBadge,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Bottom panel (mobile) ──────────────────────────────────

  Widget _buildBottomPanel(BuildContext context, AppLocalizations l) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final amount = _amount;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        AppConstants.spaceMD,
        AppConstants.spaceLG,
        bottomInset > 0 ? bottomInset : AppConstants.spaceMD,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.totalToPay,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: AppColors.textGray,
                ),
              ),
              Text(
                amount > 0 ? AppUtils.formatAmount(amount) : '—  FCFA',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: SizedBox(
              height: 52,
              child: _isProcessing
                  ? const _LoadingButton()
                  : _PayButton(
                      amount: amount,
                      methodKey: _selectedMethod,
                      canPay: _canPay,
                      onTap: () => _onPayTap(context, l),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// HERO HEADER (mobile)
// ══════════════════════════════════════════════════════════════

class _HeroHeader extends StatelessWidget {
  final AppLocalizations l;

  const _HeroHeader({required this.l});

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        topInset + AppConstants.spaceMD,
        AppConstants.spaceLG,
        AppConstants.spaceMD,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryLight,
            AppColors.primary,
            AppColors.primaryDark,
          ],
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(AppConstants.radiusLG),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            ),
            child: const Icon(
              Icons.volunteer_activism_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.makePayment,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.lock_rounded,
                        size: 11,
                        color: Colors.white.withValues(alpha: 0.7)),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        l.securePaymentBadge,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactHeader extends StatelessWidget {
  final AppLocalizations l;
  const _CompactHeader({required this.l});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          ),
          child: const Icon(
            Icons.volunteer_activism_rounded,
            color: AppColors.primary,
            size: 24,
          ),
        ),
        const SizedBox(width: AppConstants.spaceMD),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.makePayment,
              style: GoogleFonts.playfairDisplay(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            Text(
              l.securePaymentBadge,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.textGray,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// PAWAPAY (MOBILE MONEY) BOTTOM SHEET
// ══════════════════════════════════════════════════════════════

enum _PpStep { phone, waiting }

class _PawaPaySheet extends StatefulWidget {
  final int amount;
  final String periodType;
  final bool isMtn;
  final String initialPhone;
  final String methodLabel;
  final AppLocalizations l;
  final void Function(String contributionId) onConfirmed;

  const _PawaPaySheet({
    required this.amount,
    required this.periodType,
    required this.isMtn,
    required this.initialPhone,
    required this.methodLabel,
    required this.l,
    required this.onConfirmed,
  });

  @override
  State<_PawaPaySheet> createState() => _PawaPaySheetState();
}

class _PawaPaySheetState extends State<_PawaPaySheet> {
  final _pawaPay = PawaPayRepository();
  final _contribRepo = ContributionRepository();
  final _phoneCtrl = TextEditingController();
  final _phoneFocus = FocusNode();

  late String _provider; // pawaPay provider code (MTN_MOMO_CMR / ORANGE_CMR)
  _PpStep _step = _PpStep.phone;
  bool _busy = false;
  bool _checking = false;
  String? _error;
  String? _contribId;
  StreamSubscription<ContributionModel?>? _sub;
  Timer? _predictDebounce;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _provider = widget.isMtn
        ? AppConstants.pawaPayProviderMtn
        : AppConstants.pawaPayProviderOrange;
    _phoneCtrl.text = widget.initialPhone;
    _phoneCtrl.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _phoneFocus.dispose();
    _sub?.cancel();
    _predictDebounce?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  // Best-effort provider prediction as the user types — auto-selects MTN/Orange
  // but the user can still override with the chips.
  void _onPhoneChanged() {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    _predictDebounce?.cancel();
    if (digits.length < 9) return;
    _predictDebounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final p = await _pawaPay.predictProvider(_phoneCtrl.text.trim());
        if (!mounted) return;
        if (p == AppConstants.pawaPayProviderMtn ||
            p == AppConstants.pawaPayProviderOrange) {
          setState(() => _provider = p);
        }
      } catch (_) {
        // Prediction is best-effort; ignore failures.
      }
    });
  }

  bool get _isMtnSelected => _provider == AppConstants.pawaPayProviderMtn;

  Future<void> _pay() async {
    final phone = _phoneCtrl.text.trim();
    if (!AppUtils.isValidCameroonPhone(phone)) {
      setState(() => _error = widget.l.invalidPhone);
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
      );
      if (!mounted) return;
      _contribId = r.contributionId;
      setState(() {
        _busy = false;
        _step = _PpStep.waiting;
      });
      _watch(r.contributionId);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message ?? widget.l.paymentFailed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = widget.l.paymentFailed;
      });
    }
  }

  void _watch(String contributionId) {
    _sub = _contribRepo.streamContribution(contributionId).listen((c) {
      if (c == null || !mounted) return;
      if (c.status == AppConstants.statusConfirmed) {
        _sub?.cancel();
        _pollTimer?.cancel();
        widget.onConfirmed(contributionId);
      } else if (c.status == AppConstants.statusFailed) {
        _sub?.cancel();
        _pollTimer?.cancel();
        setState(() {
          _step = _PpStep.phone;
          _error = (c.notes != null && c.notes!.isNotEmpty)
              ? c.notes
              : widget.l.paymentFailed;
        });
      }
    });
    // Poll fallback once after 60s in case no callback arrives (e.g. sandbox).
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

  Color get _accent =>
      _isMtnSelected ? const Color(0xFFFFCC00) : const Color(0xFFFF6600);

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
            if (_step == _PpStep.phone) ..._phoneStep() else ..._waitingStep(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final l = widget.l;
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
                '${widget.methodLabel} · ${AppUtils.formatAmount(widget.amount)}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppColors.textGray,
                ),
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

  List<Widget> _phoneStep() {
    final l = widget.l;
    return [
      Row(
        children: [
          Expanded(
            child: _ProviderChip(
              label: l.mtnMomo,
              selected: _isMtnSelected,
              accent: const Color(0xFFFFCC00),
              method: AppConstants.paymentMtnMomo,
              onTap: () =>
                  setState(() => _provider = AppConstants.pawaPayProviderMtn),
            ),
          ),
          const SizedBox(width: AppConstants.spaceSM),
          Expanded(
            child: _ProviderChip(
              label: l.orangeMoney,
              selected: !_isMtnSelected,
              accent: const Color(0xFFFF6600),
              method: AppConstants.paymentOrangeMoney,
              onTap: () => setState(
                  () => _provider = AppConstants.pawaPayProviderOrange),
            ),
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
            color: AppColors.primary,
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
        child: _busy
            ? const _LoadingButton()
            : ElevatedButton(
                onPressed: _pay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusLG),
                  ),
                  elevation: 0,
                ),
                child: Text(
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
    final l = widget.l;
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
            foregroundColor: AppColors.primary,
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

// Selectable MTN / Orange provider chip for the pawaPay phone step.
class _ProviderChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final String method;
  final VoidCallback onTap;

  const _ProviderChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.method,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
    );
  }
}

// ══════════════════════════════════════════════════════════════
// BANK TRANSFER BOTTOM SHEET
// ══════════════════════════════════════════════════════════════

class _BankTransferSheet extends ConsumerStatefulWidget {
  final int amount;
  final AppLocalizations l;
  final void Function(XFile proof) onConfirmed;

  const _BankTransferSheet({
    required this.amount,
    required this.l,
    required this.onConfirmed,
  });

  @override
  ConsumerState<_BankTransferSheet> createState() => _BankTransferSheetState();
}

class _BankTransferSheetState extends ConsumerState<_BankTransferSheet> {
  XFile? _proof;
  Uint8List? _proofBytes;
  bool _picking = false;

  Future<void> _pickProof() async {
    setState(() => _picking = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _proof = picked;
        _proofBytes = bytes;
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _copy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.l.codeCopied),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final bank =
        ref.watch(bankDetailsProvider).valueOrNull ?? BankDetailsModel.defaults();

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
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.account_balance_rounded,
                        size: 22, color: AppColors.gold),
                  ),
                ),
                const SizedBox(width: AppConstants.spaceMD),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.bankTransferTitle,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        AppUtils.formatAmount(widget.amount),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textGray),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceMD),
            Text(
              l.bankTransferInstructions,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.textMid,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppConstants.spaceLG),
            _BankInfoRow(label: l.bankNameLabel, value: bank.bankName),
            const SizedBox(height: AppConstants.spaceSM),
            _BankInfoRow(label: l.accountHolderLabel, value: bank.accountName),
            const SizedBox(height: AppConstants.spaceMD),
            _UssdDisplay(
              label: l.accountNumberLabel,
              code: bank.accountNumber,
              onCopy: () => _copy(bank.accountNumber),
            ),
            if (bank.instructions.trim().isNotEmpty) ...[
              const SizedBox(height: AppConstants.spaceMD),
              Container(
                padding: const EdgeInsets.all(AppConstants.spaceMD),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 16, color: AppColors.textGray),
                    const SizedBox(width: AppConstants.spaceSM),
                    Expanded(
                      child: Text(
                        bank.instructions,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppColors.textGray,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppConstants.spaceLG),
            // ── Proof attachment ──────────────────────────────
            _ProofPicker(
              l: l,
              bytes: _proofBytes,
              picking: _picking,
              onPick: _pickProof,
            ),
            const SizedBox(height: AppConstants.spaceLG),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _proof == null
                    ? null
                    : () => widget.onConfirmed(_proof!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.border.withValues(alpha: 0.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusLG),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  l.confirmContributionBtn,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            if (_proof == null) ...[
              const SizedBox(height: AppConstants.spaceSM),
              Text(
                l.proofRequired,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppColors.textGray,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BankInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _BankInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppColors.textGray,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProofPicker extends StatelessWidget {
  final AppLocalizations l;
  final Uint8List? bytes;
  final bool picking;
  final VoidCallback onPick;

  const _ProofPicker({
    required this.l,
    required this.bytes,
    required this.picking,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: picking ? null : onPick,
      borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spaceMD),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(
            color: bytes != null ? AppColors.primary : AppColors.border,
            width: bytes != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            if (bytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppConstants.radiusSM),
                child: Image.memory(
                  bytes!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSM),
                ),
                child: picking
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.gold),
                        ),
                      )
                    : const Icon(Icons.upload_file_rounded,
                        color: AppColors.gold),
              ),
            const SizedBox(width: AppConstants.spaceMD),
            Expanded(
              child: Text(
                bytes != null ? l.proofAttached : l.attachProof,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: bytes != null
                      ? AppColors.primary
                      : AppColors.textDark,
                ),
              ),
            ),
            Icon(
              bytes != null ? Icons.edit_rounded : Icons.add_rounded,
              size: 18,
              color: AppColors.textGray,
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// REUSABLE SUB-WIDGETS
// ══════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusSM),
                ),
                child: Icon(icon, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: AppConstants.spaceSM),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceMD),
          child,
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: AppConstants.spaceMD),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String periodType;
  final String label;
  final int amount;
  final bool isPopular;
  final String popularLabel;
  final bool selected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.periodType,
    required this.label,
    required this.amount,
    required this.isPopular,
    required this.popularLabel,
    required this.selected,
    required this.onTap,
  });

  IconData get _icon {
    switch (periodType) {
      case AppConstants.periodDaily:
        return Icons.wb_sunny_rounded;
      case AppConstants.periodMonthly:
        return Icons.calendar_month_rounded;
      case AppConstants.periodAnnual:
        return Icons.star_rounded;
      default:
        return Icons.edit_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? AppColors.primary : AppColors.textGray;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: AppConstants.spaceSM,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.07)
              : AppColors.bg,
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : AppColors.border.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon, size: 18, color: iconColor),
                ),
                if (selected)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          size: 11, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.primary : AppColors.textDark,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                AppUtils.formatAmount(amount),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.primary : AppColors.textMid,
                ),
              ),
            ),
            if (isPopular) ...[
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  popularLabel,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: AppColors.gold,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CustomAmountCard extends StatelessWidget {
  final AppLocalizations l;
  final bool selected;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTap;

  const _CustomAmountCard({
    required this.l,
    required this.selected,
    required this.controller,
    required this.focusNode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: selected ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(AppConstants.spaceMD),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.07)
              : AppColors.bg,
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    blurRadius: 8,
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
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : AppColors.border.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        selected ? Icons.edit_rounded : Icons.add_rounded,
                        size: 18,
                        color:
                            selected ? AppColors.primary : AppColors.textGray,
                      ),
                    ),
                    if (selected)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded,
                              size: 11, color: Colors.white),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: AppConstants.spaceMD),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.customAmount,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textDark,
                        ),
                      ),
                      Text(
                        l.enterAmount,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: AppColors.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!selected)
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textGray, size: 20),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: selected
                  ? Padding(
                      padding:
                          const EdgeInsets.only(top: AppConstants.spaceMD),
                      child: TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: l.enterAmount,
                          suffixText: 'FCFA',
                          suffixStyle: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textGray,
                          ),
                          prefixIcon: const Icon(
                            Icons.volunteer_activism_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final String methodKey;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _MethodTile({
    required this.methodKey,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? AppColors.primary : AppColors.textGray;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMD,
          vertical: AppConstants.spaceSM,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.bg,
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(AppConstants.radiusSM),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.6),
                ),
              ),
              child: Center(
                child: paymentMethodIcon(methodKey, size: 22, color: iconColor),
              ),
            ),
            const SizedBox(width: AppConstants.spaceMD),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.primary : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: AppColors.textGray,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppConstants.spaceSM),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? AppColors.primary : AppColors.border,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _UssdDisplay extends StatelessWidget {
  final String label;
  final String code;
  final VoidCallback onCopy;

  const _UssdDisplay({
    required this.label,
    required this.code,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: AppColors.textGray,
          ),
        ),
        const SizedBox(height: AppConstants.spaceSM),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceLG,
            vertical: AppConstants.spaceMD,
          ),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            border:
                Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  code,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    letterSpacing: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              GestureDetector(
                onTap: onCopy,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.2),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusSM),
                  ),
                  child: const Icon(
                    Icons.copy_rounded,
                    size: 18,
                    color: AppColors.gold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PayButton extends StatelessWidget {
  final int amount;
  final String methodKey;
  final bool canPay;
  final VoidCallback onTap;

  const _PayButton({
    required this.amount,
    required this.methodKey,
    required this.canPay,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: canPay
              ? const LinearGradient(
                  colors: [AppColors.accent, Color(0xFFE0A800)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: canPay ? null : AppColors.border.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          boxShadow: canPay
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (canPay) ...[
              paymentMethodIcon(methodKey,
                  size: 20, color: AppColors.primaryDark),
              const SizedBox(width: AppConstants.spaceSM),
            ],
            Flexible(
              child: Text(
                amount > 0
                    ? 'Contribuer ${AppUtils.formatAmount(amount)}'
                    : 'Sélectionner un montant',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: canPay ? AppColors.primaryDark : AppColors.textGray,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingButton extends StatelessWidget {
  const _LoadingButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: AppColors.primaryDark,
            strokeWidth: 2.5,
          ),
        ),
      ),
    );
  }
}
