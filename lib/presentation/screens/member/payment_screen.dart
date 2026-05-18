import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/notification_service.dart';
import '../../widgets/common/payment_method_icon.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/repositories/contribution_repository.dart';

// ── Responsive breakpoints ────────────────────────────────────

const double _kWideBreakpoint = 860;
const double _kMaxContentWidth = 1080;
const double _kSummaryWidth = 360;

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

  String _buildUssd() {
    final a = _amount;
    if (_selectedMethod == AppConstants.paymentMtnMomo) {
      return '${AppConstants.mtnMomoUssd}$a#';
    }
    return '${AppConstants.orangeMoneyUssd}$a#';
  }

  // Simulated PINs — MTN: 12345, Orange: 0000
  String get _correctPin =>
      _selectedMethod == AppConstants.paymentMtnMomo ? '12345' : '0000';

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
      _showMobileMoneySheet(context, l);
    } else {
      _showCashBankDialog(context, l);
    }
  }

  void _showMobileMoneySheet(BuildContext context, AppLocalizations l) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _MobileMoneySheet(
            ussdCode: _buildUssd(),
            correctPin: _correctPin,
            methodLabel: _methodLabel(_selectedMethod, l),
            amount: _amount,
            isMtn: _selectedMethod == AppConstants.paymentMtnMomo,
            l: l,
            onConfirmed: () {
              Navigator.pop(context);
              _processPayment(isCashBank: false);
            },
          ),
        ),
      ),
    );
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

  Future<void> _processPayment({required bool isCashBank}) async {
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
      final c = await _repo.createContribution(
        memberId: user.id,
        memberName: user.fullName,
        memberNumber: user.memberNumber,
        amount: _amount,
        periodType: _periodType,
        paymentMethod: _selectedMethod,
        recordedBy: user.id,
      );
      // Mobile money contributions are auto-confirmed — notify the member.
      if (!isCashBank) {
        NotificationService.instance
            .notifyPaymentConfirmed(
              userId: user.id,
              amount: AppUtils.formatAmount(c.amount),
              receiptNumber: c.receiptNumber,
            )
            .ignore();
      }
      setState(() {
        _receiptNumber = c.receiptNumber;
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
      if (_step == _PaymentStep.success) {
        setState(() {
          _step = _PaymentStep.form;
          _receiptNumber = null;
          _isCashBank = false;
        });
        _successAnim.reset();
      }
    });

    if (_step == _PaymentStep.success) return _buildSuccess(context);
    return _buildForm(context);
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
              colors: [AppColors.primary, AppColors.primaryDark],
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
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.32),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 58,
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
                                  Text(
                                    '#${_receiptNumber ?? '---'}',
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.accent,
                                    ),
                                  ),
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
                                onPressed: () =>
                                    context.go(AppRoutes.dashboard),
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
      appBar: AppBar(title: const Text('Contribution')),
      bottomNavigationBar: wide ? null : _buildBottomPanel(context, l),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
          child: wide
              ? _buildWideBody(context, l)
              : _buildNarrowBody(context, l),
        ),
      ),
    );
  }

  // ── Narrow (mobile) body ───────────────────────────────────

  Widget _buildNarrowBody(BuildContext context, AppLocalizations l) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        AppConstants.spaceLG,
        AppConstants.spaceLG,
        AppConstants.spaceLG,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAmountSection(context, l),
          const SizedBox(height: AppConstants.spaceLG),
          _buildMethodSection(context, l),
        ],
      ),
    );
  }

  // ── Wide (web / tablet) body ───────────────────────────────

  Widget _buildWideBody(BuildContext context, AppLocalizations l) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(AppConstants.spaceXL),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: AppConstants.spaceSM,
              mainAxisSpacing: AppConstants.spaceSM,
              mainAxisExtent: 96,
            ),
            itemCount: _amountOptions.length,
            itemBuilder: (_, i) {
              final opt = _amountOptions[i];
              return _PlanCard(
                periodType: opt.periodType,
                label: _optionLabel(i, l),
                amount: opt.amount,
                isPopular: opt.isPopular,
                selected: _selectedIndex == i,
                onTap: () => setState(() {
                  _selectedIndex = i;
                  _customCtrl.clear();
                  _customFocus.unfocus();
                  if (opt.periodType == AppConstants.periodDaily &&
                      _selectedMethod == AppConstants.paymentBankTransfer) {
                    _selectedMethod = AppConstants.paymentMtnMomo;
                  }
                }),
              );
            },
          ),
          const SizedBox(height: AppConstants.spaceMD),
          TextFormField(
            controller: _customCtrl,
            focusNode: _customFocus,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onTap: () => setState(() => _selectedIndex = null),
            decoration: InputDecoration(
              labelText: l.customAmount,
              hintText: l.enterAmount,
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
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: AppConstants.spaceSM,
          mainAxisSpacing: AppConstants.spaceSM,
          mainAxisExtent: 96,
        ),
        itemCount: visibleMethods.length,
        itemBuilder: (_, i) {
          final opt = visibleMethods[i];
          return _MethodCard(
            methodKey: opt.key,
            label: _methodLabel(opt.key, l),
            subtitle: _methodSubtitle(opt.key, l),
            selected: _selectedMethod == opt.key,
            onTap: () => setState(() => _selectedMethod = opt.key),
          );
        },
      ),
    );
  }

  // ── Summary card (shared by bottom panel & wide side column) ─

  Widget _buildSummaryCard(BuildContext context, AppLocalizations l) {
    final amount = _amount;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _SummaryRow(
            label: l.periodLabel,
            value: _periodDisplayLabel(l),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: AppConstants.spaceSM),
            child: Divider(
              color: Colors.white.withValues(alpha: 0.14),
              height: 1,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  l.totalToPay,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
              Text(
                amount > 0 ? AppUtils.formatAmount(amount) : '— FCFA',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceMD),
          SizedBox(
            height: 52,
            child: _isProcessing
                ? const _LoadingButton()
                : _PayButton(
                    amount: amount,
                    methodKey: _selectedMethod,
                    methodLabel: _methodLabel(_selectedMethod, l),
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
    // Use viewPadding (not padding) so the value is stable even when the
    // keyboard is visible. Scaffold's bottomNavigationBar slot already sits
    // above the system navigation bar, so we only need this for the gesture
    // strip on phones that have one.
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final amount = _amount;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        AppConstants.spaceSM,
        AppConstants.spaceLG,
        bottomInset > 0 ? bottomInset : AppConstants.spaceSM,
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
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: SizedBox(
              height: 50,
              child: _isProcessing
                  ? const _LoadingButton()
                  : _PayButton(
                      amount: amount,
                      methodKey: _selectedMethod,
                      methodLabel: _methodLabel(_selectedMethod, l),
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
// MOBILE MONEY BOTTOM SHEET
// ══════════════════════════════════════════════════════════════

class _MobileMoneySheet extends StatefulWidget {
  final String ussdCode;
  final String correctPin;
  final String methodLabel;
  final int amount;
  final bool isMtn;
  final AppLocalizations l;
  final VoidCallback onConfirmed;

  const _MobileMoneySheet({
    required this.ussdCode,
    required this.correctPin,
    required this.methodLabel,
    required this.amount,
    required this.isMtn,
    required this.l,
    required this.onConfirmed,
  });

  @override
  State<_MobileMoneySheet> createState() => _MobileMoneySheetState();
}

class _MobileMoneySheetState extends State<_MobileMoneySheet> {
  final _pinCtrl = TextEditingController();
  final _pinFocus = FocusNode();
  bool _pinError = false;
  bool _isVerifying = false;
  bool _pinVisible = false;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  void _copyUssd() {
    Clipboard.setData(ClipboardData(text: widget.ussdCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.l.codeCopied),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Future<void> _confirmPin() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _pinError = true);
      return;
    }

    setState(() {
      _isVerifying = true;
      _pinError = false;
    });

    // Simulate USSD response delay
    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;

    if (pin == widget.correctPin) {
      setState(() => _isVerifying = false);
      widget.onConfirmed();
    } else {
      setState(() {
        _isVerifying = false;
        _pinError = true;
        _pinCtrl.clear();
      });
      _pinFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final Color accentColor =
        widget.isMtn ? const Color(0xFFFFCC00) : const Color(0xFFFF6600);

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
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
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
                    color: accentColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: paymentMethodIcon(
                      widget.isMtn
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
                        l.ussdSimulation,
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
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textGray),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceLG),
            _UssdDisplay(
              label: l.composeUssd,
              code: widget.ussdCode,
              onCopy: _copyUssd,
            ),
            const SizedBox(height: AppConstants.spaceLG),
            Row(
              children: [
                const Expanded(child: Divider(color: AppColors.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spaceSM),
                  child: Text(
                    'Simulation',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: AppColors.textGray,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: AppColors.border)),
              ],
            ),
            const SizedBox(height: AppConstants.spaceMD),
            Container(
              padding: const EdgeInsets.all(AppConstants.spaceMD),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusMD),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.textGray,
                  ),
                  const SizedBox(width: AppConstants.spaceSM),
                  Expanded(
                    child: Text(
                      widget.isMtn
                          ? 'PIN de test MTN : 12345'
                          : 'PIN de test Orange : 0000',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textGray,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceMD),
            TextFormField(
              controller: _pinCtrl,
              focusNode: _pinFocus,
              keyboardType: TextInputType.number,
              obscureText: !_pinVisible,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                labelText: l.enterPin,
                prefixIcon: const Icon(
                  Icons.lock_outline_rounded,
                  color: AppColors.primary,
                ),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _pinVisible = !_pinVisible),
                  icon: Icon(
                    _pinVisible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: AppColors.textGray,
                    size: 20,
                  ),
                ),
                errorText: _pinError ? l.wrongPin : null,
              ),
              onFieldSubmitted: (_) => _confirmPin(),
            ),
            const SizedBox(height: AppConstants.spaceLG),
            SizedBox(
              height: 54,
              child: _isVerifying
                  ? const _LoadingButton()
                  : ElevatedButton(
                      onPressed: _confirmPin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusLG),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        l.iHavePaid,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
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
      padding: const EdgeInsets.all(AppConstants.spaceLG),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusSM),
                ),
                child: Icon(icon, size: 17, color: AppColors.primary),
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
  final bool selected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.periodType,
    required this.label,
    required this.amount,
    required this.isPopular,
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
          horizontal: AppConstants.spaceSM,
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
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.border.withValues(alpha: 0.5),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusSM),
                  ),
                  child: Icon(_icon, size: 17, color: iconColor),
                ),
                const Spacer(),
                if (isPopular)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.star_rounded,
                      size: 11,
                      color: AppColors.gold,
                    ),
                  ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppColors.primary : AppColors.border,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 5),
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
            Text(
              AppUtils.formatAmount(amount),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.primary : AppColors.textMid,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final String methodKey;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _MethodCard({
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
          horizontal: AppConstants.spaceSM,
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
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.border.withValues(alpha: 0.5),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusSM),
                  ),
                  child: Center(
                    child: paymentMethodIcon(
                        methodKey, size: 22, color: iconColor),
                  ),
                ),
                const Spacer(),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppColors.primary : AppColors.border,
                  size: 18,
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
            Text(
              subtitle,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                color: AppColors.textGray,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
  final String methodLabel;
  final bool canPay;
  final VoidCallback onTap;

  const _PayButton({
    required this.amount,
    required this.methodKey,
    required this.methodLabel,
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
          color: canPay ? AppColors.accent : Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          boxShadow: canPay
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (canPay)
              paymentMethodIcon(methodKey,
                  size: 20, color: AppColors.primaryDark),
            if (canPay) const SizedBox(width: AppConstants.spaceSM),
            Flexible(
              child: Text(
                amount > 0
                    ? 'Contribuer ${AppUtils.formatAmount(amount)}'
                    : 'Sélectionner un montant',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: canPay
                      ? AppColors.primaryDark
                      : Colors.white.withValues(alpha: 0.6),
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
