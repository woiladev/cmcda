import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/language_service.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/contribution_repository.dart';
import '../../../core/utils/app_utils.dart';

const _adminGoldLight = Color(0xFFC9A227);
const _adminGoldDark = Color(0xFF6B5214);

class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() =>
      _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  bool _signingOut = false;
  bool _syncing = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await AuthRepository().signOut();
    } catch (_) {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _syncCounters(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _syncing = true);
    try {
      final result = await ContributionRepository().backfillPlatformCounters();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l.syncCountersResult(
                result.members, AppUtils.formatAmount(result.total.toInt())),
            style: GoogleFonts.plusJakartaSans(fontSize: 13),
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l.syncCountersError,
            style: GoogleFonts.plusJakartaSans(fontSize: 13),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _confirmSignOut(AppLocalizations l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final lc = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(
            lc.logoutConfirmTitle,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, color: AppColors.textDark),
          ),
          content: Text(
            lc.logoutConfirmMsg,
            style: GoogleFonts.plusJakartaSans(
                color: AppColors.textGray, fontSize: 13),
          ),
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

  void _showLanguagePicker(BuildContext context, AppLocalizations l, String current) {
    final options = [
      ('fr', 'Français', '🇫🇷'),
      ('en', 'English', '🇬🇧'),
      ('ar', 'العربية', '🇸🇦'),
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXL)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppConstants.spaceLG),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
              ),
              const SizedBox(height: AppConstants.spaceLG),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceLG),
                child: Text(
                  l.languageDisplay,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceMD),
              ...options.map((opt) {
                final selected = opt.$1 == current;
                return ListTile(
                  leading: Text(opt.$3,
                      style: const TextStyle(fontSize: 22)),
                  title: Text(
                    opt.$2,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textDark,
                    ),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppColors.primary, size: 20)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    ref
                        .read(languageProvider.notifier)
                        .changeLanguage(opt.$1);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
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
    final langState = ref.watch(languageProvider);
    final currentLangCode = langState.locale.languageCode;
    final langLabel = switch (currentLangCode) {
      'en' => 'English',
      'ar' => 'العربية',
      _ => 'Français',
    };

    final roleBadge = (user.isSuperAdmin ? l.superAdmin : l.admin).toUpperCase();

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
                  colors: [_adminGoldLight, _adminGoldDark],
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
                          color: Colors.white.withValues(alpha: 0.5), width: 2),
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
                      border:
                          Border.all(color: Colors.white.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      roleBadge,
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

          // ── Body ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spaceLG),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Profile info ────────────────────────────
                  _SectionHeader(title: l.personalInfo),
                  const SizedBox(height: AppConstants.spaceSM),
                  _InfoCard(
                    children: [
                      _InfoRow(
                        icon: Icons.badge_outlined,
                        label: l.memberNumber,
                        value: user.memberNumber.isNotEmpty
                            ? user.memberNumber
                            : '—',
                      ),
                      const Divider(height: 1, color: AppColors.border),
                      _InfoRow(
                        icon: Icons.phone_outlined,
                        label: l.phone,
                        value: user.phone.isNotEmpty ? user.phone : '—',
                      ),
                      if (user.email?.isNotEmpty == true) ...[
                        const Divider(height: 1, color: AppColors.border),
                        _InfoRow(
                          icon: Icons.email_outlined,
                          label: l.email,
                          value: user.email!,
                        ),
                      ],
                      const Divider(height: 1, color: AppColors.border),
                      _InfoRow(
                        icon: Icons.location_on_outlined,
                        label: l.region,
                        value: user.region.isNotEmpty ? user.region : '—',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // ── Preferences ─────────────────────────────
                  _SectionHeader(title: l.settings),
                  const SizedBox(height: AppConstants.spaceSM),
                  _InfoCard(
                    children: [
                      _ActionTile(
                        icon: Icons.language_outlined,
                        label: l.languageDisplay,
                        value: langLabel,
                        onTap: () => _showLanguagePicker(
                            context, l, currentLangCode),
                      ),
                      const Divider(height: 1, color: AppColors.border),
                      _ActionTile(
                        icon: Icons.shield_outlined,
                        label: l.privacyPolicy,
                        value: '',
                        onTap: () => context.push(AppRoutes.privacyPolicy),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // ── Quick access ────────────────────────────
                  _SectionHeader(title: l.quickActionsTitle),
                  const SizedBox(height: AppConstants.spaceSM),
                  _InfoCard(
                    children: [
                      _ActionTile(
                        icon: Icons.account_circle_outlined,
                        label: l.myMemberSpace,
                        value: '',
                        onTap: () {
                          ref
                              .read(viewingAsMemberProvider.notifier)
                              .state = true;
                          context.push(AppRoutes.dashboard);
                        },
                      ),
                      const Divider(height: 1, color: AppColors.border),
                      _ActionTile(
                        icon: Icons.account_balance_outlined,
                        label: l.treasuryTitle,
                        value: '',
                        onTap: () => context.go(AppRoutes.adminWallet),
                      ),
                      if (user.isSuperAdmin) ...[
                        const Divider(height: 1, color: AppColors.border),
                        _ActionTile(
                          icon: Icons.admin_panel_settings_outlined,
                          label: l.manageAdmins,
                          value: '',
                          onTap: () => context.push(AppRoutes.adminTeam),
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        _ActionTile(
                          icon: Icons.account_balance_outlined,
                          label: l.bankDetailsTitle,
                          value: '',
                          onTap: () => context.push(AppRoutes.adminBankDetails),
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        _ActionTile(
                          icon: Icons.sync_rounded,
                          label: l.syncCounters,
                          value: _syncing ? '…' : '',
                          onTap:
                              _syncing ? () {} : () => _syncCounters(context),
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        _ActionTile(
                          icon: Icons.fact_check_outlined,
                          label: l.auditMatricules,
                          value: '',
                          onTap: () => context.push(AppRoutes.adminAudit),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // ── Support ─────────────────────────────────
                  _SectionHeader(title: l.contactUs),
                  const SizedBox(height: AppConstants.spaceSM),
                  _InfoCard(
                    children: [
                      _ActionTile(
                        icon: Icons.help_outline_rounded,
                        label: l.helpFaq,
                        value: '',
                        onTap: () => context.push(AppRoutes.help),
                      ),
                      const Divider(height: 1, color: AppColors.border),
                      _ActionTile(
                        icon: Icons.info_outline_rounded,
                        label: l.aboutApp,
                        value: '',
                        onTap: () => context.push(AppRoutes.about),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // ── Sign out ────────────────────────────────
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
                        side: const BorderSide(color: AppColors.error),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusMD),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceLG),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textGray,
        letterSpacing: 0.8,
      ),
    );
  }
}

// ── Card container ────────────────────────────────────────────

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

// ── Info row (read-only) ──────────────────────────────────────

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
          Icon(icon, size: 18, color: _adminGoldLight),
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
  final String value;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.value,
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
            Icon(icon, size: 18, color: _adminGoldLight),
            const SizedBox(width: AppConstants.spaceMD),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: AppColors.textGray),
              ),
            ),
            if (value.isNotEmpty)
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            const SizedBox(width: AppConstants.spaceXS),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textLight, size: 18),
          ],
        ),
      ),
    );
  }
}
