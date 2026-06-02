import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/privacy_policy_content.dart';
import '../../../core/theme/app_theme.dart';

class PrivacyPolicyScreen extends ConsumerWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final code = l.locale.languageCode;
    final sections =
        privacyPolicySections[code] ?? privacyPolicySections['fr']!;

    return Scaffold(
      appBar: AppBar(title: Text(l.privacyPolicy)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.spaceLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              privacyPolicyLastUpdated,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppColors.textGray,
              ),
            ),
            const SizedBox(height: AppConstants.spaceLG),
            for (final section in sections) ...[
              Text(
                section.heading,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: AppConstants.spaceSM),
              Text(
                section.body,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  height: 1.6,
                  color: AppColors.textGray,
                ),
              ),
              const SizedBox(height: AppConstants.spaceLG),
            ],
          ],
        ),
      ),
    );
  }
}
