import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  bool _navigationScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();

    // Allow early navigation once animation is done (logged-in fast path only).
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      _tryEarlyNavigate();
    });

    // Original safe fallback: runs at 3 s regardless.
    // Firebase Auth is always restored by this point.
    Future.delayed(const Duration(seconds: 3), _navigate);
  }

  // Early path: only fires for a logged-in user whose profile is already loaded.
  // Never navigates to login/onboarding — that is left to the safe 3 s path.
  void _tryEarlyNavigate() {
    if (!mounted || _navigationScheduled) return;
    final auth = ref.read(authStateProvider);
    final user = auth.valueOrNull;
    if (user == null) return; // not ready or not logged in — let 3 s timer decide
    final profileAsync = ref.read(currentUserProfileProvider);
    if (profileAsync.isLoading) return; // still fetching from Firestore
    final profile = profileAsync.valueOrNull;
    if (profile == null) {
      // Logged in but no Firestore doc yet — needs profile completion
      _navigationScheduled = true;
      context.go(AppRoutes.completeProfile);
      return;
    }
    _navigationScheduled = true;
    _goByRole(profile.role);
  }

  // Safe fallback path — same logic as before, just runs at 3 s.
  Future<void> _navigate() async {
    if (!mounted || _navigationScheduled) return;
    _navigationScheduled = true;

    final authAsync = ref.read(authStateProvider);
    final profileAsync = ref.read(currentUserProfileProvider);

    final user = authAsync.valueOrNull;
    if (user == null) {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool('onboarding_done') ?? false;
      if (!mounted) return;
      context.go(done ? AppRoutes.login : AppRoutes.onboarding);
      return;
    }

    final profile = profileAsync.valueOrNull;
    if (profile == null) {
      // Profile still loading — wait a bit more.
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        final pa = ref.read(currentUserProfileProvider);
        final p = pa.valueOrNull;
        if (p == null) {
          // Still no profile: either Firestore is slow or doc truly doesn't exist.
          // Route to complete-profile; the router redirect will handle any edge case.
          context.go(AppRoutes.completeProfile);
          return;
        }
        _goByRole(p.role);
      });
      return;
    }

    _goByRole(profile.role);
  }

  void _goByRole(String role) {
    if (!mounted) return;
    if (role == AppConstants.roleAdmin || role == AppConstants.roleSuperAdmin) {
      context.go(AppRoutes.admin);
    } else if (role == AppConstants.roleFocal) {
      context.go(AppRoutes.focal);
    } else {
      context.go(AppRoutes.dashboard);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // React immediately when auth or profile emits — no polling needed.
    // _tryEarlyNavigate guards against transient null Auth emissions.
    ref.listen(authStateProvider, (_, __) => _tryEarlyNavigate());
    ref.listen(currentUserProfileProvider, (_, __) => _tryEarlyNavigate());

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.primaryDark,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Gradient background ──────────────────────────────
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.primary, AppColors.primaryDark],
                  stops: [0.0, 1.0],
                ),
              ),
            ),

            // ── Animated content ─────────────────────────────────
            FadeTransition(
              opacity: _fadeAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: _SplashContent(),
              ),
            ),

            // ── Footer (outside animation so it fades only) ──────
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: const _SplashFooter(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Logo container ─────────────────────────────────────
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Image.asset(
                'assets/images/cmcda_logo.png',
                fit: BoxFit.contain,
              ),
            ),
          ),

          const SizedBox(height: 32),

          // ── CMCDA title ────────────────────────────────────────
          Text(
            AppConstants.acronym,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 42,
                  letterSpacing: 6,
                ),
          ),

          const SizedBox(height: 8),

          // ── Subtitle ───────────────────────────────────────────
          Text(
            l10n.officialPlatform,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontStyle: FontStyle.italic,
              letterSpacing: 2,
            ),
          ),

          const SizedBox(height: 24),

          // ── Gold decorative divider ────────────────────────────
          const Text(
            '✦  ✦  ✦',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 18,
              letterSpacing: 8,
            ),
          ),

          const SizedBox(height: 40),

          // ── Loading indicator ──────────────────────────────────
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              color: AppColors.gold,
              strokeWidth: 3,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            l10n.loading,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashFooter extends StatelessWidget {
  const _SplashFooter();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Text(
      '${l10n.developedBy} ${AppConstants.devCompany}',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 12,
      ),
    );
  }
}
