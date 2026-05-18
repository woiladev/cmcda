import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';

class MemberShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const MemberShell({required this.navigationShell, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final isViewingAsMember = ref.watch(viewingAsMemberProvider);
    final user = ref.watch(currentUserProfileProvider).valueOrNull;
    final isFocalViewing =
        isViewingAsMember && (user?.isFocal ?? false);
    final isAdminViewing =
        isViewingAsMember && (user?.hasAdminAccess ?? false);
    final showBanner = isFocalViewing || isAdminViewing;

    return Scaffold(
      body: Column(
        children: [
          if (isFocalViewing)
            _AdminViewBanner(
              label: 'Mode Membre · Espace personnel',
              returnLabel: 'Focal',
              onReturn: () {
                ref.read(viewingAsMemberProvider.notifier).state = false;
                context.go(AppRoutes.focal);
              },
            )
          else if (isAdminViewing)
            _AdminViewBanner(
              label: 'Mode Membre · Vue de contribution',
              returnLabel: 'Admin',
              onReturn: () {
                ref.read(viewingAsMemberProvider.notifier).state = false;
                context.go(AppRoutes.admin);
              },
            ),
          Expanded(
            child: showBanner
                ? MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: navigationShell,
                  )
                : navigationShell,
          ),
        ],
      ),
      bottomNavigationBar: _MemberNavBar(
        selectedIndex: navigationShell.currentIndex,
        onTabSelected: (index) {
          // Re-entering the Pay tab from another tab — signal PaymentScreen
          // to discard any lingering success state.
          if (index == 1 && navigationShell.currentIndex != 1) {
            ref.read(paymentTabActivationProvider.notifier).update((n) => n + 1);
          }
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        l: l,
      ),
    );
  }
}

class _AdminViewBanner extends StatelessWidget {
  final String label;
  final String returnLabel;
  final VoidCallback onReturn;

  const _AdminViewBanner({
    required this.label,
    required this.returnLabel,
    required this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    final statusBarH = MediaQuery.of(context).padding.top;
    return Material(
      color: AppColors.primaryDark,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppConstants.spaceMD,
          statusBarH + AppConstants.spaceSM,
          AppConstants.spaceSM,
          AppConstants.spaceSM,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.admin_panel_settings_outlined,
              color: Colors.white70,
              size: 16,
            ),
            const SizedBox(width: AppConstants.spaceSM),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            GestureDetector(
              onTap: onReturn,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceMD,
                  vertical: AppConstants.spaceXS,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_back_rounded,
                        color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      returnLabel,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final AppLocalizations l;

  const _MemberNavBar({
    required this.selectedIndex,
    required this.onTabSelected,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textDark.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
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
                icon: Icons.volunteer_activism_rounded,
                label: 'Contribuer',
                selected: selectedIndex == 1,
                onTap: () => onTabSelected(1),
              ),
              _NavItem(
                icon: Icons.notifications_outlined,
                label: l.alerts,
                selected: selectedIndex == 2,
                onTap: () => onTabSelected(2),
              ),
              _NavItem(
                icon: Icons.person_outline_rounded,
                label: l.profile,
                selected: selectedIndex == 3,
                onTap: () => onTabSelected(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: selected ? AppColors.primary : AppColors.textGray,
            size: 24,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.primary : AppColors.textGray,
            ),
          ),
          if (selected) ...[
            const SizedBox(height: 2),
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
