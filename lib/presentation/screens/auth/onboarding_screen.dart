import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';

const _kOnboardingDone = 'onboarding_done';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageCtrl = PageController();
  int _page = 0;

  late final AnimationController _serviceCtrl;
  late final List<Animation<double>> _cardFades;
  late final List<Animation<Offset>> _cardSlides;

  @override
  void initState() {
    super.initState();
    _pageCtrl.addListener(_onScroll);

    // 700ms total: 6 cards × 60ms stagger, each card animates for 400ms.
    _serviceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _cardFades = [];
    _cardSlides = [];
    for (int i = 0; i < 6; i++) {
      final start = (i * 60 / 700).clamp(0.0, 1.0);
      final end = (start + 400 / 700).clamp(0.0, 1.0);
      final curve = Interval(start, end, curve: Curves.easeOut);
      _cardFades.add(
        CurvedAnimation(parent: _serviceCtrl, curve: curve),
      );
      _cardSlides.add(
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
            .animate(CurvedAnimation(parent: _serviceCtrl, curve: curve)),
      );
    }
  }

  void _onScroll() {
    final p = _pageCtrl.page?.round() ?? 0;
    if (p == _page) return;
    setState(() => _page = p);
    if (p == 1) {
      _serviceCtrl.forward(from: 0);
    } else {
      _serviceCtrl.reset();
    }
    if (p == 2) _markDone();
  }

  Future<void> _markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingDone, true);
  }

  Future<void> _skip() async {
    await _markDone();
    if (mounted) context.go(AppRoutes.login);
  }

  void _next() {
    _pageCtrl.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pageCtrl.removeListener(_onScroll);
    _pageCtrl.dispose();
    _serviceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Stack(
          children: [
            PageView(
              controller: _pageCtrl,
              children: [
                _buildPage1(context, l),
                _buildPage2(context, l),
                _buildPage3(context, l),
              ],
            ),

            // Skip button — pages 1 & 2 only
            if (_page < 2)
              Positioned(
                top: top + 6,
                right: 12,
                child: TextButton(
                  onPressed: _skip,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textGray,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    textStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(l.skip),
                ),
              ),

            // Page indicator dots
            Positioned(
              bottom: bottom + 14,
              left: 0,
              right: 0,
              child: _buildDots(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final active = i == _page;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.border,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ── PAGE 1 — Hero ─────────────────────────────────────────────

  Widget _buildPage1(BuildContext context, AppLocalizations l) {
    return SafeArea(
      child: Column(
        children: [
          // Skip button clearance
          const SizedBox(height: 44),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 24),

                  // Circular logo
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.18),
                        width: 3.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.18),
                          blurRadius: 28,
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

                  const SizedBox(height: 28),

                  // Tagline H1
                  Text(
                    l.heroTagline,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 14),

                  // Subhead
                  Text(
                    l.heroSubhead,
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 15,
                      height: 1.55,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 32),

                  // Stat row — 3 cards
                  Row(
                    children: [
                      _buildStatCard(
                        icon: Icons.people_rounded,
                        value: '1M+',
                        label: l.heroStatMembersLabel,
                      ),
                      const SizedBox(width: 8),
                      _buildStatCard(
                        icon: Icons.today_rounded,
                        value: '100',
                        unit: 'FCFA',
                        label: l.heroStatDailyLabel,
                      ),
                      const SizedBox(width: 8),
                      _buildStatCard(
                        icon: Icons.calendar_month_rounded,
                        value: '36 500',
                        unit: 'FCFA',
                        label: l.heroStatYearlyLabel,
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),

          // CTA area
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: _next,
                  child: Text(l.continueBtn),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _skip,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textGray,
                  ),
                  child: Text(l.alreadyHaveAccount),
                ),
                const SizedBox(height: 42), // dots clearance
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    String? unit,
    required String label,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.textDark.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.gold, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.playfairDisplay(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            if (unit != null)
              Text(
                unit,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.gold,
                ),
              ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textGray,
                fontSize: 10,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── PAGE 2 — Services ─────────────────────────────────────────

  Widget _buildPage2(BuildContext context, AppLocalizations l) {
    final services = [
      (Icons.account_balance_wallet_rounded, l.serviceFinanceTitle, l.serviceFinanceDesc),
      (Icons.school_rounded,                 l.serviceEducationTitle, l.serviceEducationDesc),
      (Icons.health_and_safety_rounded,      l.serviceHealthTitle,    l.serviceHealthDesc),
      (Icons.work_rounded,                   l.serviceEmploymentTitle, l.serviceEmploymentDesc),
      (Icons.people_rounded,                 l.serviceSocialTitle,    l.serviceSocialDesc),
      (Icons.foundation_rounded,             l.serviceInfraTitle,     l.serviceInfraDesc),
    ];

    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 44),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Eyebrow
                  Text(
                    l.servicesEyebrow,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.gold,
                      letterSpacing: 2.2,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // H2 title
                  Text(
                    l.servicesTitle,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                      height: 1.2,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Subtitle
                  Text(
                    l.servicesSubtitle,
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 22),

                  // 2×3 service grid
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.82,
                    children: List.generate(6, (i) {
                      final (icon, title, desc) = services[i];
                      return FadeTransition(
                        opacity: _cardFades[i],
                        child: SlideTransition(
                          position: _cardSlides[i],
                          child: _ServiceCard(
                            icon: icon,
                            title: title,
                            description: desc,
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // CTA
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: _next,
                  child: Text(l.continueBtn),
                ),
                const SizedBox(height: 42),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── PAGE 3 — How it works + Final CTA ────────────────────────

  Widget _buildPage3(BuildContext context, AppLocalizations l) {
    final steps = [
      (Icons.person_add_rounded,              l.howStep1Title, l.howStep1Desc),
      (Icons.account_balance_wallet_rounded,  l.howStep2Title, l.howStep2Desc),
      (Icons.auto_awesome_rounded,            l.howStep3Title, l.howStep3Desc),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Eyebrow
            Text(
              l.howEyebrow,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.gold,
                letterSpacing: 2.2,
              ),
            ),

            const SizedBox(height: 8),

            // H2
            Text(
              l.howTitle,
              style: GoogleFonts.playfairDisplay(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
                height: 1.2,
              ),
            ),

            const SizedBox(height: 32),

            // Steps
            ...List.generate(3, (i) {
              final (icon, title, desc) = steps[i];
              return _buildStep(i + 1, icon, title, desc);
            }),

            const SizedBox(height: 28),

            // CTA band
            _buildCtaBand(context, l),

            const SizedBox(height: 12),

            // Already member link
            Center(
              child: TextButton(
                onPressed: () => context.go(AppRoutes.login),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textGray,
                  textStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
                ),
                child: Text(l.alreadyMemberLogin),
              ),
            ),

            const SizedBox(height: 48), // dots clearance
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int number, IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon tile with number badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.gold],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              Positioned(
                top: -7,
                right: -7,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$number',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: const TextStyle(
                      color: AppColors.textGray,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCtaBand(BuildContext context, AppLocalizations l) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.ctaTitle,
            style: GoogleFonts.playfairDisplay(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l.ctaSubtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => context.go(AppRoutes.signup),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.textDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
                textStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(l.joinCmcda),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Service Card (stateful for press animation) ───────────────

class _ServiceCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;

  const _ServiceCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: _pressed
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.gold],
                )
              : null,
          color: _pressed ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          border: _pressed ? null : Border.all(color: AppColors.border),
          boxShadow: _pressed
              ? null
              : [
                  BoxShadow(
                    color: AppColors.textDark.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _pressed
                    ? Colors.white.withValues(alpha: 0.2)
                    : AppColors.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                widget.icon,
                color: _pressed ? Colors.white : AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _pressed ? Colors.white : AppColors.textDark,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              widget.description,
              style: TextStyle(
                fontSize: 11,
                color: _pressed
                    ? Colors.white.withValues(alpha: 0.82)
                    : AppColors.textGray,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
