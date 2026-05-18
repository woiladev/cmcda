import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

/// Circular avatar showing initials with an optional gold crown badge
/// for super contributors (totalContributed >= amountAnnual).
class SuperBadgeAvatar extends StatelessWidget {
  final String initials;
  final bool isSuperContributor;
  final double size;
  final Color backgroundColor;
  final Color textColor;

  const SuperBadgeAvatar({
    required this.initials,
    required this.isSuperContributor,
    this.size = 44,
    this.backgroundColor = AppColors.primary,
    this.textColor = Colors.white,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: GoogleFonts.plusJakartaSans(
              fontSize: size * 0.32,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
        if (isSuperContributor)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              width: size * 0.40,
              height: size * 0.40,
              decoration: const BoxDecoration(
                color: AppColors.gold,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x55C49A00),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                Icons.workspace_premium_rounded,
                color: Colors.white,
                size: size * 0.22,
              ),
            ),
          ),
      ],
    );
  }
}
