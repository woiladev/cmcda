import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';

// ══════════════════════════════════════════════════════════════
// HELP SCREEN
// ══════════════════════════════════════════════════════════════

class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    final faqSections = [
      _FaqSectionData(
        category: l.faqCategoryPayments,
        icon: Icons.payments_outlined,
        items: [
          _FaqItem(question: l.faqQ1, answer: l.faqA1),
          _FaqItem(question: l.faqQ2, answer: l.faqA2),
          _FaqItem(question: l.faqQ3, answer: l.faqA3),
        ],
      ),
      _FaqSectionData(
        category: l.faqCategoryAccount,
        icon: Icons.person_outline_rounded,
        items: [
          _FaqItem(question: l.faqQ4, answer: l.faqA4),
          _FaqItem(question: l.faqQ5, answer: l.faqA5),
          _FaqItem(question: l.faqQ6, answer: l.faqA6),
        ],
      ),
      _FaqSectionData(
        category: l.faqCategoryGeneral,
        icon: Icons.info_outline_rounded,
        items: [
          _FaqItem(question: l.faqQ7, answer: l.faqA7),
          _FaqItem(question: l.faqQ8, answer: l.faqA8),
        ],
      ),
    ];

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
          l.helpFaq,
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
            // ── Subtitle ─────────────────────────────────────
            Text(
              l.helpFaqSubtitle,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.textGray,
              ),
            ),
            const SizedBox(height: AppConstants.spaceLG),

            // ── FAQ sections ─────────────────────────────────
            ...faqSections.map((section) => Padding(
                  padding: const EdgeInsets.only(bottom: AppConstants.spaceLG),
                  child: _FaqSection(data: section),
                )),

            // ── Need more help banner ─────────────────────────
            _MoreHelpBanner(l: l),
            const SizedBox(height: AppConstants.spaceLG),
          ],
        ),
      ),
    );
  }
}

// ── FAQ section ───────────────────────────────────────────────

class _FaqSectionData {
  final String category;
  final IconData icon;
  final List<_FaqItem> items;
  const _FaqSectionData(
      {required this.category, required this.icon, required this.items});
}

class _FaqItem {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});
}

class _FaqSection extends StatelessWidget {
  final _FaqSectionData data;
  const _FaqSection({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(data.icon, size: 15, color: AppColors.primary),
            const SizedBox(width: AppConstants.spaceXS),
            Text(
              data.category.toUpperCase(),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceSM),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusLG),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: data.items
                .map((item) => _FaqTile(item: item, isLast: item == data.items.last))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _FaqTile extends StatelessWidget {
  final _FaqItem item;
  final bool isLast;
  const _FaqTile({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceMD,
              vertical: AppConstants.spaceXS,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppConstants.spaceMD,
              0,
              AppConstants.spaceMD,
              AppConstants.spaceMD,
            ),
            iconColor: AppColors.primary,
            collapsedIconColor: AppColors.textGray,
            title: Text(
              item.question,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            children: [
              Text(
                item.answer,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppColors.textGray,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1, color: AppColors.border),
      ],
    );
  }
}

// ── "Need more help?" banner ──────────────────────────────────

class _MoreHelpBanner extends StatelessWidget {
  final AppLocalizations l;
  const _MoreHelpBanner({required this.l});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.about),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spaceMD),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.support_agent_rounded,
                  color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: AppConstants.spaceMD),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.needMoreHelp,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  Text(
                    l.needMoreHelpSub,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
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
    );
  }
}
