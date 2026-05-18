import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../widgets/common/payment_method_icon.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final bool startOnSignup;
  const LoginScreen({super.key, this.startOnSignup = false});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // ── Tab ──────────────────────────────────────────────────────
  late int _tabIndex; // 0 = login, 1 = signup

  // ── Global ────────────────────────────────────────────────────
  bool _loading = false;
  String? _errorMsg;

  // ── Phone Auth ────────────────────────────────────────────────
  final _phoneCtrl = TextEditingController();
  bool _otpSent = false;
  String? _verificationId;
  int? _resendToken;
  final List<TextEditingController> _otpCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes =
      List.generate(6, (_) => FocusNode());
  int _countdown = 0;
  Timer? _timer;

  // ── Email Auth ────────────────────────────────────────────────
  bool _showEmailSection = false;
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _pwVisible = false;
  final _loginFormKey = GlobalKey<FormState>();

  // ── Signup ────────────────────────────────────────────────────
  int _signupStep = 0;
  bool _signupPhoneMode = false;
  final _signupForm1Key = GlobalKey<FormState>();
  final _signupForm2Key = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _signupPhoneCtrl = TextEditingController();
  final _signupEmailCtrl = TextEditingController();
  final _signupPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();
  bool _signupPwVisible = false;
  bool _confirmPwVisible = false;
  String? _selectedRegion;
  final _deptCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _quarterCtrl = TextEditingController();
  String _selectedFrequency = AppConstants.periodMonthly;
  String _selectedPayment = AppConstants.paymentMtnMomo;
  String _selectedLanguage = AppConstants.defaultLocale;

  final _authRepo = AuthRepository();

  // ── Lifecycle ─────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.startOnSignup ? 1 : 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    for (final c in _otpCtrls) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _signupPhoneCtrl.dispose();
    _signupEmailCtrl.dispose();
    _signupPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    _deptCtrl.dispose();
    _cityCtrl.dispose();
    _quarterCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────

  void _navigateByRole(UserModel? user) {
    if (!mounted || user == null) return;
    final role = user.role;
    if (role == AppConstants.roleAdmin || role == AppConstants.roleSuperAdmin) {
      context.go(AppRoutes.admin);
    } else if (role == AppConstants.roleFocal) {
      context.go(AppRoutes.focal);
    } else {
      context.go(AppRoutes.dashboard);
    }
  }

  // ── Phone Auth ────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    final raw = _phoneCtrl.text.trim().replaceAll(' ', '');
    if (raw.isEmpty) {
      setState(() => _errorMsg = 'Entrez votre numéro de téléphone');
      return;
    }
    setState(() { _loading = true; _errorMsg = null; });

    await _authRepo.verifyPhoneNumber(
      phoneNumber: '+237$raw',
      resendToken: _resendToken,
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _otpSent = true;
          _loading = false;
          _countdown = 60;
        });
        _startCountdown();
      },
      onFailed: (error) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _errorMsg = error.message ?? 'Erreur lors de l\'envoi';
        });
      },
    );
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_countdown <= 0) { t.cancel(); return; }
      setState(() => _countdown--);
    });
  }

  Future<void> _verifyOtp() async {
    final otp = _otpCtrls.map((c) => c.text).join();
    if (otp.length < 6 || _verificationId == null) return;
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final user = await _authRepo.verifyOTP(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      _navigateByRole(user);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _errorMsg = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _errorMsg = e.toString(); });
    }
  }

  // ── Google Auth ───────────────────────────────────────────────

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final user = await _authRepo.signInWithGoogle();
      if (user != null) {
        _navigateByRole(user);
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _errorMsg = e.toString(); });
    }
  }

  // ── Apple Auth ────────────────────────────────────────────────

  Future<void> _signInWithApple() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final user = await _authRepo.signInWithApple();
      if (user != null) {
        _navigateByRole(user);
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Email Auth ────────────────────────────────────────────────

  Future<void> _signInWithEmail() async {
    if (!_loginFormKey.currentState!.validate()) return;
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final user = await _authRepo.signIn(
        email: _emailCtrl.text.trim(),
        password: _pwCtrl.text,
      );
      _navigateByRole(user);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _errorMsg = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _errorMsg = e.toString(); });
    }
  }

  // ── Sign Up ───────────────────────────────────────────────────

  Future<void> _createAccount() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final user = await _authRepo.signUp(
        email: _signupEmailCtrl.text.trim(),
        password: _signupPwCtrl.text,
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        phone: '+237${_signupPhoneCtrl.text.trim().replaceAll(' ', '')}',
        region: _selectedRegion ?? '',
        department: _deptCtrl.text.trim(),
        city: _cityCtrl.text.trim().isNotEmpty ? _cityCtrl.text.trim() : null,
        quarter: _quarterCtrl.text.trim().isNotEmpty ? _quarterCtrl.text.trim() : null,
        preferredFrequency: _selectedFrequency,
        preferredPayment: _selectedPayment,
        language: _selectedLanguage,
      );
      NotificationService.instance.notifyWelcome(
        userId: user.id,
        firstName: user.firstName,
      ).ignore();
      _navigateByRole(user);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _errorMsg = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _errorMsg = e.toString(); });
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
                child: _tabIndex == 0
                    ? _buildLoginContent(context)
                    : _buildSignupContent(context),
              ),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  // ── Header (gradient + tab bar) ───────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 240,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          AppConstants.acronym,
                          style: GoogleFonts.playfairDisplay(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.welcome,
                      style: GoogleFonts.playfairDisplay(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 28,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.accessYourAccount,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Tab bar anchored at bottom of the header
          Positioned(
            bottom: 0,
            left: 24,
            right: 24,
            child: Container(
              height: 56,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _TabButton(
                    label: l10n.connexion,
                    active: _tabIndex == 0,
                    onTap: () => setState(() {
                      _tabIndex = 0;
                      _signupPhoneMode = false;
                      _errorMsg = null;
                    }),
                  ),
                  _TabButton(
                    label: l10n.inscription,
                    active: _tabIndex == 1,
                    onTap: () => setState(() {
                      _tabIndex = 1;
                      _signupStep = 0;
                      _signupPhoneMode = false;
                      _errorMsg = null;
                    }),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Login content ─────────────────────────────────────────────

  Widget _buildLoginContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMsg != null) ...[
            _ErrorBanner(message: _errorMsg!),
            const SizedBox(height: 16),
          ],

          // ── Phone section ───────────────────────────────────────
          Text(
            l10n.mobileAuth,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w700,
                ),
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
                  enabled: !_otpSent,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.phone,
                    hintText: '6XX XXX XXX',
                    prefixIcon: const Icon(Icons.phone_android_rounded),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (!_otpSent)
            ElevatedButton(
              onPressed: _loading ? null : _sendOtp,
              child: _loading
                  ? const _SmallLoader()
                  : Text(l10n.sendOtp),
            ),

          // ── OTP section ─────────────────────────────────────────
          if (_otpSent) ...[
            const SizedBox(height: 24),
            Text(
              l10n.enterOtpCode,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: AppColors.textGray),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                6,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _OtpBox(
                    controller: _otpCtrls[i],
                    focusNode: _otpFocusNodes[i],
                    onChanged: (val) {
                      if (val.isNotEmpty && i < 5) {
                        _otpFocusNodes[i + 1].requestFocus();
                      } else if (val.isEmpty && i > 0) {
                        _otpFocusNodes[i - 1].requestFocus();
                      }
                      final code = _otpCtrls.map((c) => c.text).join();
                      if (code.length == 6) _verifyOtp();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _countdown > 0
                      ? '0:${_countdown.toString().padLeft(2, '0')}'
                      : '',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                TextButton(
                  onPressed: _countdown == 0 && !_loading ? _sendOtp : null,
                  child: Text(l10n.resendCode),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loading ? null : _verifyOtp,
              child: _loading ? const _SmallLoader() : Text(l10n.verifyOtp),
            ),
          ],

          const SizedBox(height: 24),

          // ── "ou continuer avec" divider ─────────────────────────
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  l10n.orContinueWith,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppColors.textGray),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),

          // ── Google ──────────────────────────────────────────────
          _GoogleButton(
            label: l10n.continueWithGoogle,
            onPressed: _loading ? null : _signInWithGoogle,
          ),
          const SizedBox(height: 16),

          // ── Email toggle ────────────────────────────────────────
          GestureDetector(
            onTap: () =>
                setState(() => _showEmailSection = !_showEmailSection),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.mail_outline_rounded,
                  size: 16,
                  color: AppColors.textGray,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.useEmail,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showEmailSection
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),

          // ── Email form ──────────────────────────────────────────
          if (_showEmailSection) ...[
            const SizedBox(height: 16),
            Form(
              key: _loginFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: l10n.email,
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                    validator: (v) =>
                        (v?.isEmpty ?? true) ? l10n.fieldRequired : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pwCtrl,
                    obscureText: !_pwVisible,
                    decoration: InputDecoration(
                      labelText: l10n.password,
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_pwVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => _pwVisible = !_pwVisible),
                      ),
                    ),
                    validator: (v) =>
                        (v?.isEmpty ?? true) ? l10n.fieldRequired : null,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {},
                      child: Text(l10n.forgotPassword),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loading ? null : _signInWithEmail,
                    child: _loading
                        ? const _SmallLoader()
                        : Text(l10n.login),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Signup content ────────────────────────────────────────────

  Widget _buildSignupContent(BuildContext context) {
    if (_signupPhoneMode) return _buildSignupPhoneMode(context);

    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Quick sign-up buttons ─────────────────────────────
          Text(
            l10n.quickSignup,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
          ),
          const SizedBox(height: 12),

          // Phone
          _SocialButton(
            onPressed: _loading
                ? null
                : () => setState(() {
                      _signupPhoneMode = true;
                      _otpSent = false;
                      _verificationId = null;
                      _phoneCtrl.clear();
                      for (final c in _otpCtrls) {
                        c.clear();
                      }
                      _errorMsg = null;
                    }),
            icon: const Icon(Icons.phone_android_rounded,
                color: AppColors.primary, size: 22),
            label: l10n.continueWithPhone,
          ),
          const SizedBox(height: 10),

          // Google
          _GoogleButton(
            label: l10n.continueWithGoogle,
            onPressed: _loading ? null : _signInWithGoogle,
          ),
          const SizedBox(height: 10),

          // Apple
          _AppleButton(
            label: l10n.continueWithApple,
            onPressed: _loading ? null : _signInWithApple,
          ),

          const SizedBox(height: 20),

          // Divider
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  l10n.orRegisterWithEmail,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppColors.textGray),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),

          const SizedBox(height: 20),

          // ── Email form (3-step) ───────────────────────────────
          _buildStepIndicator(context),
          const SizedBox(height: 20),

          if (_errorMsg != null) ...[
            _ErrorBanner(message: _errorMsg!),
            const SizedBox(height: 16),
          ],

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => FadeTransition(
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
              key: ValueKey(_signupStep),
              child: [
                _buildStep1(context),
                _buildStep2(context),
                _buildStep3(context),
              ][_signupStep],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Signup — inline phone OTP mode ────────────────────────────

  Widget _buildSignupPhoneMode(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: AlignmentDirectional.centerStart,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => setState(() {
              _signupPhoneMode = false;
              _otpSent = false;
              _timer?.cancel();
              _errorMsg = null;
            }),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: Text(l10n.back),
          ),
          const SizedBox(height: 20),

          if (_errorMsg != null) ...[
            _ErrorBanner(message: _errorMsg!),
            const SizedBox(height: 16),
          ],

          // Phone input
          Text(
            l10n.mobileAuth,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w700,
                ),
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
                  enabled: !_otpSent,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.phone,
                    hintText: '6XX XXX XXX',
                    prefixIcon: const Icon(Icons.phone_android_rounded),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (!_otpSent)
            ElevatedButton(
              onPressed: _loading ? null : _sendOtp,
              child: _loading ? const _SmallLoader() : Text(l10n.sendOtp),
            ),

          // OTP boxes
          if (_otpSent) ...[
            const SizedBox(height: 24),
            Text(
              l10n.enterOtpCode,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: AppColors.textGray),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                6,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _OtpBox(
                    controller: _otpCtrls[i],
                    focusNode: _otpFocusNodes[i],
                    onChanged: (val) {
                      if (val.isNotEmpty && i < 5) {
                        _otpFocusNodes[i + 1].requestFocus();
                      } else if (val.isEmpty && i > 0) {
                        _otpFocusNodes[i - 1].requestFocus();
                      }
                      final code = _otpCtrls.map((c) => c.text).join();
                      if (code.length == 6) _verifyOtp();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _countdown > 0
                      ? '0:${_countdown.toString().padLeft(2, '0')}'
                      : '',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                TextButton(
                  onPressed: _countdown == 0 && !_loading ? _sendOtp : null,
                  child: Text(l10n.resendCode),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loading ? null : _verifyOtp,
              child: _loading ? const _SmallLoader() : Text(l10n.verifyOtp),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = [l10n.step1of3, l10n.step2of3, l10n.step3of3];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(3, (i) {
            final active = i <= _signupStep;
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
          labels[_signupStep],
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
      key: _signupForm1Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _firstNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: l10n.firstName),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? l10n.fieldRequired : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _lastNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: l10n.lastName),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? l10n.fieldRequired : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _signupPhoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: l10n.phone,
              hintText: '6XX XXX XXX',
              prefixText: '+237 ',
              prefixIcon: const Icon(Icons.phone_android_rounded),
            ),
            validator: (v) =>
                (v?.trim().isEmpty ?? true) ? l10n.fieldRequired : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _signupEmailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: l10n.emailRecommended,
              prefixIcon: const Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _signupPwCtrl,
            obscureText: !_signupPwVisible,
            decoration: InputDecoration(
              labelText: l10n.password,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_signupPwVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _signupPwVisible = !_signupPwVisible),
              ),
            ),
            validator: (v) =>
                (v?.length ?? 0) < 8 ? l10n.passwordTooShort : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmPwCtrl,
            obscureText: !_confirmPwVisible,
            decoration: InputDecoration(
              labelText: l10n.confirmPassword,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_confirmPwVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _confirmPwVisible = !_confirmPwVisible),
              ),
            ),
            validator: (v) =>
                v != _signupPwCtrl.text ? l10n.passwordMismatch : null,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (_signupForm1Key.currentState!.validate()) {
                setState(() => _signupStep = 1);
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
      key: _signupForm2Key,
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
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) => setState(() => _selectedRegion = v),
            validator: (v) => v == null ? l10n.fieldRequired : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _deptCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: l10n.department,
              prefixIcon: const Icon(Icons.apartment_outlined),
            ),
            validator: (v) =>
                (v?.trim().isEmpty ?? true) ? l10n.fieldRequired : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cityCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: '${l10n.city} (${l10n.optional})',
              prefixIcon: const Icon(Icons.location_city_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _quarterCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: '${l10n.quarter} (${l10n.optional})',
              prefixIcon: const Icon(Icons.holiday_village_outlined),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (_signupForm2Key.currentState!.validate()) {
                setState(() => _signupStep = 2);
              }
            },
            child: Text('${l10n.continueBtn} →'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _signupStep = 0),
            child: Text('← ${l10n.back}'),
          ),
        ],
      ),
    );
  }

  // ── Step 3 — Contribution preferences ────────────────────────

  Widget _buildStep3(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final frequencies = [
      (AppConstants.periodDaily, '☀️', l10n.daily, '100 FCFA / jour'),
      (AppConstants.periodMonthly, '📅', l10n.monthly, '3 000 FCFA / mois'),
      (AppConstants.periodAnnual, '📆', l10n.annual, '36 500 FCFA / an'),
    ];

    final payments = [
      (AppConstants.paymentMtnMomo, paymentMethodIcon(AppConstants.paymentMtnMomo, size: 24), l10n.mtnMomo),
      (AppConstants.paymentOrangeMoney, paymentMethodIcon(AppConstants.paymentOrangeMoney, size: 24), l10n.orangeMoney),
      (AppConstants.paymentCash, const Text('💵', style: TextStyle(fontSize: 20)), l10n.cash),
      (AppConstants.paymentBankTransfer, const Text('🏦', style: TextStyle(fontSize: 20)), l10n.bankTransfer),
    ];

    final languages = [
      ('fr', '🇫🇷', 'Français'),
      ('en', '🇬🇧', 'English'),
      ('ar', '🇸🇦', 'العربية'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Frequency grid
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
              onTap: () => setState(() => _selectedFrequency = f.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.06)
                      : Colors.white,
                  border: Border.all(
                    color: selected ? AppColors.gold : AppColors.border,
                    width: selected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.radiusLG),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(f.$2, style: const TextStyle(fontSize: 22)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
              onTap: () => setState(() => _selectedPayment = p.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.06)
                      : Colors.white,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                    width: selected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                          color:
                              selected ? AppColors.primary : AppColors.textDark,
                        ),
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle_rounded,
                          color: AppColors.primary, size: 20),
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
                padding: EdgeInsets.only(right: i < languages.length - 1 ? 8 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedLanguage = lang.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 64,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.08)
                          : Colors.white,
                      border: Border.all(
                        color: selected ? AppColors.primary : AppColors.border,
                        width: selected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(lang.$2,
                            style: const TextStyle(fontSize: 22)),
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
          onPressed: _loading ? null : _createAccount,
          child: _loading ? const _SmallLoader() : Text(l10n.createMyAccount),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _signupStep = 1),
          child: Text('← ${l10n.back}'),
        ),
      ],
    );
  }

  // ── Footer ────────────────────────────────────────────────────

  Widget _buildFooter(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${l10n.developedBy} ',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textGray),
          ),
          Text(
            AppConstants.devCompany,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.woilaNavy,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Private widgets ───────────────────────────────────────────

class _TabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white.withValues(alpha: 0.6),
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 56,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(1),
        ],
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
        ),
        decoration: const InputDecoration(
          counterText: '',
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: AppColors.gold, width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _GoogleButton({required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textDark,
        backgroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 54),
        side: const BorderSide(color: AppColors.border, width: 1.5),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'G',
            style: TextStyle(
              color: Color(0xFF4285F4),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallLoader extends StatelessWidget {
  const _SmallLoader();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;

  const _SocialButton({
    required this.icon,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textDark,
        backgroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 54),
        side: const BorderSide(color: AppColors.border, width: 1.5),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppleButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _AppleButton({required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textDark,
        backgroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 54),
        side: const BorderSide(color: AppColors.border, width: 1.5),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '',
            style: TextStyle(fontSize: 20),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
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
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
