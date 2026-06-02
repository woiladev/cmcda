import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';

const _focalLight = Color(0xFF26A8F3);
const _focalDark = Color(0xFF0A5F8C);

class FocalProfileScreen extends ConsumerStatefulWidget {
  const FocalProfileScreen({super.key});

  @override
  ConsumerState<FocalProfileScreen> createState() =>
      _FocalProfileScreenState();
}

class _FocalProfileScreenState
    extends ConsumerState<FocalProfileScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await AuthRepository().signOut();
      // GoRouter redirect picks up the auth state change automatically
    } catch (_) {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _confirmSignOut(AppLocalizations l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final lc = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(lc.logoutConfirmTitle,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark)),
          content: Text(lc.logoutConfirmMsg,
              style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textGray, fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(lc.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error),
              child: Text(lc.logout,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    if (ok == true) await _signOut();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final profileAsync = ref.watch(currentUserProfileProvider);

    return profileAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) =>
          Scaffold(body: Center(child: Text(l.unknownError))),
      data: (user) {
        if (user == null) {
          return Scaffold(body: Center(child: Text(l.unknownError)));
        }
        return _buildContent(context, l, user);
      },
    );
  }

  Widget _buildContent(
      BuildContext context, AppLocalizations l, UserModel user) {
    final statusBarH = MediaQuery.of(context).padding.top;
    final zone = (user.focalZone?.isNotEmpty == true)
        ? user.focalZone!
        : (user.region.isNotEmpty ? user.region : '—');

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          // ── Header ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.fromLTRB(
                AppConstants.spaceLG,
                statusBarH + AppConstants.spaceLG,
                AppConstants.spaceLG,
                AppConstants.spaceXL,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_focalLight, _focalDark],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      user.initials,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceMD),
                  Text(
                    user.fullName,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceXS),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusFull),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      l.focalBadge,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Info section ────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spaceLG),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Info card
                  _InfoCard(
                    children: [
                      _InfoRow(
                        icon: Icons.badge_outlined,
                        label: l.memberNumber,
                        value: user.memberNumber.isNotEmpty
                            ? user.memberNumber
                            : '—',
                      ),
                      const Divider(
                          height: 1, color: AppColors.border),
                      _InfoRow(
                        icon: Icons.phone_outlined,
                        label: l.phone,
                        value: user.phone.isNotEmpty
                            ? user.phone
                            : '—',
                      ),
                      const Divider(
                          height: 1, color: AppColors.border),
                      _InfoRow(
                        icon: Icons.location_on_outlined,
                        label: l.focalZoneLabel,
                        value: zone,
                      ),
                      const Divider(
                          height: 1, color: AppColors.border),
                      _InfoRow(
                        icon: Icons.map_outlined,
                        label: l.region,
                        value: user.region.isNotEmpty
                            ? user.region
                            : '—',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // Member space shortcut
                  GestureDetector(
                    onTap: () {
                      ref
                          .read(viewingAsMemberProvider.notifier)
                          .state = true;
                      context.push(AppRoutes.dashboard);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(AppConstants.spaceMD),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusLG),
                        border:
                            Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color:
                                  AppColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                                Icons.account_circle_outlined,
                                color: AppColors.primary,
                                size: 22),
                          ),
                          const SizedBox(width: AppConstants.spaceMD),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.myMemberSpace,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                Text(
                                  l.myMemberSpaceSub,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: AppColors.textGray,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: AppColors.primary, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // ── Support links ───────────────────────────
                  _InfoCard(
                    children: [
                      _ActionTile(
                        icon: Icons.help_outline_rounded,
                        label: l.helpFaq,
                        onTap: () => context.push(AppRoutes.help),
                      ),
                      const Divider(height: 1, color: AppColors.border),
                      _ActionTile(
                        icon: Icons.info_outline_rounded,
                        label: l.aboutApp,
                        onTap: () => context.push(AppRoutes.about),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // Sign out
                  SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed:
                          _signingOut ? null : () => _confirmSignOut(l),
                      icon: _signingOut
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.error))
                          : const Icon(Icons.logout_rounded,
                              color: AppColors.error, size: 18),
                      label: Text(
                        l.logout,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.error,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: AppColors.error.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusMD),
                        ),
                      ),
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
}

// ── Info card ─────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMD,
        vertical: AppConstants.spaceMD,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _focalLight),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: AppColors.textGray),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action tile (tappable) ────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusLG),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMD,
          vertical: AppConstants.spaceMD,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _focalLight),
            const SizedBox(width: AppConstants.spaceMD),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: AppColors.textGray),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textLight, size: 18),
          ],
        ),
      ),
    );
  }
}
