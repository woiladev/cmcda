import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';

// ══════════════════════════════════════════════════════════════
// ABOUT SCREEN
// ══════════════════════════════════════════════════════════════

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static String _whatsAppUrl() {
    // wa.me requires the number without + or spaces
    final phone = AppConstants.contactPhone
        .replaceAll(RegExp(r'[\s+]'), '');
    final text = Uri.encodeComponent(
        "Bonjour, j'ai besoin d'aide avec CMCDA Platform");
    return 'https://wa.me/$phone?text=$text';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textDark),
          onPressed: () => context.pop(),
        ),
        title: Text(
          l.aboutApp,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.spaceLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── App header ────────────────────────────────────
            _AppHeader(l: l),
            const SizedBox(height: AppConstants.spaceLG),

            // ── Contact section ───────────────────────────────
            _SectionLabel(title: l.contactUs),
            const SizedBox(height: AppConstants.spaceSM),
            _Card(
              children: [
                _ContactTile(
                  icon: Icons.chat_rounded,
                  iconColor: const Color(0xFF25D366),
                  label: l.contactViaWhatsApp,
                  onTap: () => _launch(_whatsAppUrl()),
                ),
                const Divider(height: 1, color: AppColors.border),
                _ContactTile(
                  icon: Icons.email_outlined,
                  iconColor: AppColors.primary,
                  label: l.contactViaEmail,
                  value: AppConstants.contactEmail,
                  onTap: () => _launch('mailto:${AppConstants.contactEmail}'),
                ),
                const Divider(height: 1, color: AppColors.border),
                _ContactTile(
                  icon: Icons.language_rounded,
                  iconColor: AppColors.primary,
                  label: l.contactWebsite,
                  value: AppConstants.contactWebsite,
                  onTap: () => _launch(AppConstants.contactWebsite),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceLG),

            // ── Legal section ─────────────────────────────────
            _SectionLabel(title: l.legalSection),
            const SizedBox(height: AppConstants.spaceSM),
            _Card(
              children: [
                _ContactTile(
                  icon: Icons.shield_outlined,
                  iconColor: AppColors.primary,
                  label: l.privacyPolicy,
                  onTap: () => context.push(AppRoutes.privacyPolicy),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceXL),

            // ── Footer ────────────────────────────────────────
            Center(
              child: Text(
                l.developedBy,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: AppColors.textLight,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppConstants.spaceLG),
          ],
        ),
      ),
    );
  }
}

// ── App header card ───────────────────────────────────────────

class _AppHeader extends StatelessWidget {
  final AppLocalizations l;
  const _AppHeader({required this.l});

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
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              AppConstants.acronym,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spaceMD),
          Text(
            AppConstants.appName,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: AppConstants.spaceXS),
          Text(
            AppConstants.orgNameFr,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppColors.textGray,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spaceSM),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            ),
            child: Text(
              '${l.appVersion} ${AppConstants.appVersion}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel({required this.title});

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

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

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

// ── Contact tile ──────────────────────────────────────────────

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? value;
  final VoidCallback onTap;

  const _ContactTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.value,
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
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppConstants.radiusSM),
              ),
              child: Icon(icon, size: 18, color: iconColor),
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
                      color: AppColors.textDark,
                    ),
                  ),
                  if (value != null)
                    Text(
                      value!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textGray,
                      ),
                    ),
                ],
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
