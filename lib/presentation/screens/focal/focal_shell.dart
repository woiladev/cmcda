import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import 'focal_providers.dart';

const _focalActive = Color(0xFF26A8F3);

class FocalShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const FocalShell({required this.navigationShell, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final profileAsync = ref.watch(currentUserProfileProvider);
    final userId = profileAsync.valueOrNull?.id ?? '';
    final unread =
        ref.watch(focalUnreadCountProvider(userId)).valueOrNull ?? 0;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: _FocalNavBar(
        selectedIndex: navigationShell.currentIndex,
        unreadCount: unread,
        l: l,
        onTabSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

// ── Nav bar ───────────────────────────────────────────────────

class _FocalNavBar extends StatelessWidget {
  final int selectedIndex;
  final int unreadCount;
  final AppLocalizations l;
  final ValueChanged<int> onTabSelected;

  const _FocalNavBar({
    required this.selectedIndex,
    required this.unreadCount,
    required this.l,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
            top: BorderSide(color: AppColors.border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppConstants.spaceMD,
            horizontal: AppConstants.spaceLG,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: l.home,
                selected: selectedIndex == 0,
                onTap: () => onTabSelected(0),
              ),
              _NavItem(
                icon: Icons.group_outlined,
                label: l.myMembers,
                selected: selectedIndex == 1,
                onTap: () => onTabSelected(1),
              ),
              _NavItem(
                icon: Icons.receipt_long_outlined,
                label: l.payments,
                selected: selectedIndex == 2,
                onTap: () => onTabSelected(2),
              ),
              _NavItem(
                icon: Icons.notifications_outlined,
                label: l.alerts,
                selected: selectedIndex == 3,
                badge: unreadCount,
                onTap: () => onTabSelected(3),
              ),
              _NavItem(
                icon: Icons.person_outline_rounded,
                label: l.profile,
                selected: selectedIndex == 4,
                onTap: () => onTabSelected(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Nav item ──────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40,
                height: 36,
                decoration: BoxDecoration(
                  color: selected
                      ? _focalActive.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMD),
                ),
                child: Icon(
                  icon,
                  color: selected ? _focalActive : AppColors.textGray,
                  size: 22,
                ),
              ),
              if (badge > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? _focalActive : AppColors.textGray,
            ),
          ),
        ],
      ),
    );
  }
}
