import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/language_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/auth_error_messages.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../widgets/common/payment_method_icon.dart';

class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState
    extends ConsumerState<CompleteProfileScreen> {
  int _step = 0;
  bool _loading = false;
  String? _errorMsg;

  final _form1Key = GlobalKey<FormState>();
  final _form2Key = GlobalKey<FormState>();

  // Step 1
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _phoneFromAuth = false;

  // Step 2
  String? _selectedRegion;
  final _deptCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _quarterCtrl = TextEditingController();

  // Step 3
  String _selectedFrequency = AppConstants.periodMonthly;
  String _selectedPayment = AppConstants.paymentMtnMomo;
  String _selectedLanguage = AppConstants.defaultLocale;

  final _authRepo = AuthRepository();

  @override
  void initState() {
    super.initState();
    _selectedLanguage = ref.read(languageProvider).locale.languageCode;
    _prefillFromFirebase();
  }

  void _prefillFromFirebase() {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;

    final displayName = firebaseUser.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) {
      final parts = displayName.split(' ');
      _firstNameCtrl.text = parts.first;
      if (parts.length > 1) _lastNameCtrl.text = parts.sublist(1).join(' ');
    }

    final phone = firebaseUser.phoneNumber ?? '';
    if (phone.isNotEmpty) {
      _phoneCtrl.text =
          phone.startsWith('+237') ? phone.substring(4) : phone;
      _phoneFromAuth = true;
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _deptCtrl.dispose();
    _cityCtrl.dispose();
    _quarterCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser!;
      final rawPhone =
          _phoneCtrl.text.trim().replaceAll(' ', '');
      final phone =
          rawPhone.startsWith('+') ? rawPhone : '+237$rawPhone';

      await _authRepo.completeProfile(
        uid: firebaseUser.uid,
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        phone: phone,
        email: firebaseUser.email,
        avatarUrl: firebaseUser.photoURL,
        region: _selectedRegion!,
        department: _deptCtrl.text.trim(),
        city: _cityCtrl.text.trim().isNotEmpty
            ? _cityCtrl.text.trim()
            : null,
        quarter: _quarterCtrl.text.trim().isNotEmpty
            ? _quarterCtrl.text.trim()
            : null,
        preferredFrequency: _selectedFrequency,
        preferredPayment: _selectedPayment,
        language: _selectedLanguage,
      );
      // The welcome push is sent server-side by the onUserWelcome Cloud
      // Function once the profile (region) is complete.

      if (mounted) context.go(AppRoutes.dashboard);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = authErrorMessage(l10n, e);
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStepIndicator(context),
                    const SizedBox(height: 24),
                    if (_errorMsg != null) ...[
                      _buildErrorBanner(_errorMsg!),
                      const SizedBox(height: 16),
                    ],
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) =>
                          FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.04, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_step),
                        child: [
                          _buildStep1(context),
                          _buildStep2(context),
                          _buildStep3(context),
                        ][_step],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.completeProfileTitle,
                style: GoogleFonts.playfairDisplay(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.completeProfileSubtitle,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step indicator ────────────────────────────────────────────

  Widget _buildStepIndicator(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = [l10n.step1of3, l10n.step2of3, l10n.step3of3];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(3, (i) {
            final active = i <= _step;
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                decoration: BoxDecoration(
                  color: active ? AppColors.gold : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(
          labels[_step],
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.textGray),
        ),
      ],
    );
  }

  // ── Step 1 — Personal info ────────────────────────────────────

  Widget _buildStep1(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Form(
      key: _form1Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _firstNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      InputDecoration(labelText: l10n.firstName),
                  validator: (v) => (v?.trim().isEmpty ?? true)
                      ? l10n.fieldRequired
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _lastNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      InputDecoration(labelText: l10n.lastName),
                  validator: (v) => (v?.trim().isEmpty ?? true)
                      ? l10n.fieldRequired
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 80,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🇨🇲', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 4),
                    Text(
                      '+237',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  readOnly: _phoneFromAuth,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  decoration: InputDecoration(
                    labelText: l10n.phone,
                    hintText: '6XX XXX XXX',
                    prefixIcon:
                        const Icon(Icons.phone_android_rounded),
                    suffixIcon: _phoneFromAuth
                        ? const Icon(Icons.verified_rounded,
                            color: AppColors.primary, size: 20)
                        : null,
                  ),
                  validator: (v) => (v?.trim().isEmpty ?? true)
                      ? l10n.fieldRequired
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (_form1Key.currentState!.validate()) {
                setState(() {
                  _step = 1;
                  _errorMsg = null;
                });
              }
            },
            child: Text('${l10n.continueBtn} →'),
          ),
        ],
      ),
    );
  }

  // ── Step 2 — Location ─────────────────────────────────────────

  Widget _buildStep2(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Form(
      key: _form2Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedRegion,
            decoration: InputDecoration(
              labelText: l10n.region,
              prefixIcon: const Icon(Icons.location_on_outlined),
            ),
            items: AppConstants.cameroonRegions
                .map((r) =>
                    DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) =>
                setState(() => _selectedRegion = v),
            validator: (v) =>
                v == null ? l10n.fieldRequired : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _deptCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: '${l10n.department} (${l10n.optional})',
              prefixIcon:
                  const Icon(Icons.apartment_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cityCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: '${l10n.city} (${l10n.optional})',
              prefixIcon:
                  const Icon(Icons.location_city_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _quarterCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: '${l10n.quarter} (${l10n.optional})',
              prefixIcon:
                  const Icon(Icons.holiday_village_outlined),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (_form2Key.currentState!.validate()) {
                setState(() {
                  _step = 2;
                  _errorMsg = null;
                });
              }
            },
            child: Text('${l10n.continueBtn} →'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () =>
                setState(() {
                  _step = 0;
                  _errorMsg = null;
                }),
            child: Text('← ${l10n.back}'),
          ),
        ],
      ),
    );
  }

  // ── Step 3 — Preferences ──────────────────────────────────────

  Widget _buildStep3(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final frequencies = [
      (AppConstants.periodDaily, '☀️', l10n.daily,
          '100 FCFA / jour'),
      (AppConstants.periodMonthly, '📅', l10n.monthly,
          '3 000 FCFA / mois'),
      (AppConstants.periodAnnual, '📆', l10n.annual,
          '36 500 FCFA / an'),
    ];

    final payments = [
      (
        AppConstants.paymentMtnMomo,
        paymentMethodIcon(AppConstants.paymentMtnMomo, size: 24),
        l10n.mtnMomo
      ),
      (
        AppConstants.paymentOrangeMoney,
        paymentMethodIcon(AppConstants.paymentOrangeMoney,
            size: 24),
        l10n.orangeMoney
      ),
      (
        AppConstants.paymentCash,
        paymentMethodIcon(AppConstants.paymentCash, size: 24),
        l10n.cash
      ),
      (
        AppConstants.paymentBankTransfer,
        paymentMethodIcon(AppConstants.paymentBankTransfer, size: 24),
        l10n.bankTransfer
      ),
    ];

    final languages = [
      ('fr', '🇫🇷', 'Français'),
      ('en', '🇬🇧', 'English'),
      ('ar', '🇸🇦', 'العربية'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.preferencesEditableLater,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.textGray),
        ),
        const SizedBox(height: 16),
        // Frequency
        Text(
          l10n.preferredFrequency,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.55,
          children: frequencies.map((f) {
            final selected = _selectedFrequency == f.$1;
            return GestureDetector(
              onTap: () =>
                  setState(() => _selectedFrequency = f.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary
                          .withValues(alpha: 0.06)
                      : Colors.white,
                  border: Border.all(
                    color: selected
                        ? AppColors.gold
                        : AppColors.border,
                    width: selected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(
                      AppConstants.radiusLG),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    Text(f.$2,
                        style:
                            const TextStyle(fontSize: 22)),
                    Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.$3,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textDark,
                          ),
                        ),
                        Text(
                          f.$4,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textGray,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 24),

        // Payment method
        Text(
          l10n.preferredPayment,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...payments.map((p) {
          final selected = _selectedPayment == p.$1;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () =>
                  setState(() => _selectedPayment = p.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary
                          .withValues(alpha: 0.06)
                      : Colors.white,
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : AppColors.border,
                    width: selected ? 2 : 1,
                  ),
                  borderRadius:
                      BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    p.$2,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p.$3,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textDark,
                        ),
                      ),
                    ),
                    if (selected)
                      const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.primary,
                          size: 20),
                  ],
                ),
              ),
            ),
          );
        }),

        const SizedBox(height: 24),

        // Language
        Text(
          l10n.chooseLanguage,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Row(
          children: List.generate(languages.length, (i) {
            final lang = languages[i];
            final selected = _selectedLanguage == lang.$1;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    right: i < languages.length - 1 ? 8 : 0),
                child: GestureDetector(
                  onTap: () => setState(
                      () => _selectedLanguage = lang.$1),
                  child: AnimatedContainer(
                    duration:
                        const Duration(milliseconds: 150),
                    height: 64,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary
                              .withValues(alpha: 0.08)
                          : Colors.white,
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : AppColors.border,
                        width: selected ? 2 : 1,
                      ),
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Text(lang.$2,
                            style: const TextStyle(
                                fontSize: 22)),
                        const SizedBox(height: 2),
                        Text(
                          lang.$3,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),

        const SizedBox(height: 32),

        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Text(l10n.createMyAccount),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _loading
              ? null
              : () => setState(() {
                    _step = 1;
                    _errorMsg = null;
                  }),
          child: Text('← ${l10n.back}'),
        ),
      ],
    );
  }

  // ── Error banner ──────────────────────────────────────────────

  Widget _buildErrorBanner(String message) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        border: Border.all(
            color: AppColors.error.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
