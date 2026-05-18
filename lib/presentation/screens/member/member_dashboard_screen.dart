import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/contribution_repository.dart';
import '../../widgets/common/super_badge_avatar.dart';

// ── Providers ─────────────────────────────────────────────────

final _contributionRepo = ContributionRepository();

final _memberContributionsProvider =
    StreamProvider.autoDispose.family<List<ContributionModel>, String>(
  (ref, uid) => _contributionRepo.getMemberContributions(uid),
);

final _platformTotalProvider = StreamProvider.autoDispose<double>(
  (ref) => _contributionRepo.streamPlatformTotal(),
);

final _memberCountProvider = StreamProvider.autoDispose<int>(
  (ref) => _contributionRepo.streamMemberCount(),
);

// ── Screen ────────────────────────────────────────────────────

class MemberDashboardScreen extends ConsumerStatefulWidget {
  const MemberDashboardScreen({super.key});

  @override
  ConsumerState<MemberDashboardScreen> createState() =>
      _MemberDashboardScreenState();
}

class _MemberDashboardScreenState extends ConsumerState<MemberDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fabController;
  late final Animation<double> _fabScale;
  late final Animation<double> _fabGlow;

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _fabScale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _fabController, curve: Curves.easeInOut),
    );
    _fabGlow = Tween<double>(begin: 4.0, end: 18.0).animate(
      CurvedAnimation(parent: _fabController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final profileAsync = ref.watch(currentUserProfileProvider);

    return profileAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        body: Center(child: Text(l.unknownError)),
      ),
      data: (user) {
        if (user == null) {
          return Scaffold(body: Center(child: Text(l.unknownError)));
        }
        return _buildDashboard(context, user, l);
      },
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    UserModel user,
    AppLocalizations l,
  ) {
    final contributionsAsync =
        ref.watch(_memberContributionsProvider(user.id));

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: AnimatedBuilder(
        animation: _fabController,
        builder: (context, child) => Transform.scale(
          scale: _fabScale.value,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.45),
                  blurRadius: _fabGlow.value,
                  spreadRadius: _fabGlow.value * 0.3,
                ),
              ],
            ),
            child: child,
          ),
        ),
        child: FloatingActionButton(
          onPressed: () => context.go(AppRoutes.payment),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 0,
          child: const Icon(Icons.volunteer_activism_rounded, size: 26),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildHeader(context, user, contributionsAsync, l),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(AppConstants.spaceLG),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildQuickActions(context, l),
                const SizedBox(height: AppConstants.spaceLG),
                _buildPaymentHistory(context, contributionsAsync, l),
                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    UserModel user,
    AsyncValue<List<ContributionModel>> contributionsAsync,
    AppLocalizations l,
  ) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final contributions = contributionsAsync.valueOrNull ?? [];
    final confirmed = contributions.where((c) => c.isConfirmed).toList();
    final totalAll = confirmed.fold<int>(0, (s, c) => s + c.amount);
    final activeMonths = confirmed.map((c) => c.period).toSet().length;
    final currentPeriod = AppUtils.getPeriodForDate(DateTime.now());
    final thisMonthTotal = confirmed
        .where((c) => c.period == currentPeriod)
        .fold<int>(0, (s, c) => s + c.amount);
    final delayCount = contributions.where((c) => c.isPending).length;
    final isActive = delayCount == 0;
    final platformTotal = ref.watch(_platformTotalProvider).valueOrNull ?? 0.0;
    final memberCount = ref.watch(_memberCountProvider).valueOrNull ?? 0;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        statusBarHeight + AppConstants.spaceMD,
        AppConstants.spaceLG,
        AppConstants.spaceLG,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top row: avatar + name | admin badge + bell
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  SuperBadgeAvatar(
                    initials: user.initials,
                    isSuperContributor: user.isSuperContributor,
                    size: 44,
                    backgroundColor: AppColors.gold,
                    textColor: AppColors.primaryDark,
                  ),
                  const SizedBox(width: AppConstants.spaceMD),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${l.welcome} 👋',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      Text(
                        user.firstName,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  if (user.hasAdminAccess) ...[
                    GestureDetector(
                      onTap: () {
                        ref.read(viewingAsMemberProvider.notifier).state = false;
                        context.go(AppRoutes.admin);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull),
                          border: Border.all(
                              color: AppColors.gold.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.admin_panel_settings_outlined,
                                color: AppColors.gold, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'Admin',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.gold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spaceSM),
                  ],
                  GestureDetector(
                    onTap: () => context.go(AppRoutes.notifications),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceMD),
          // Compact glass card
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOTAL CONTRIBUÉ',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.65),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppUtils.formatAmount(totalAll),
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'N° ${user.memberNumber}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Status chip (top-right of card)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (isActive ? AppColors.success : AppColors.warning)
                            .withValues(alpha: 0.25),
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusFull),
                        border: Border.all(
                          color: (isActive ? AppColors.success : AppColors.warning)
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isActive
                                ? Icons.check_circle_rounded
                                : Icons.schedule_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isActive ? l.memberActiveStatus : l.memberLateStatus,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spaceMD),
                // 3 mini-stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _MiniStat(
                      label: l.activeMonths,
                      value: activeMonths.toString().padLeft(2, '0'),
                    ),
                    _MiniStat(
                      label: l.thisMonth,
                      value: thisMonthTotal > 0
                          ? AppUtils.formatAmount(thisMonthTotal)
                              .replaceAll(' FCFA', '')
                          : '0',
                      suffix: 'FCFA',
                    ),
                    _MiniStat(
                      label: l.delays,
                      value: delayCount.toString().padLeft(2, '0'),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spaceMD),
                Divider(
                  color: Colors.white.withValues(alpha: 0.15),
                  height: 1,
                ),
                const SizedBox(height: AppConstants.spaceMD),
                // Platform progress
                _PlatformProgressInline(
                  total: platformTotal,
                  memberCount: memberCount,
                  l: l,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── QUICK ACTIONS ──────────────────────────────────────────────

  Widget _buildQuickActions(BuildContext context, AppLocalizations l) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.volunteer_activism_rounded,
                label: 'Contribuer',
                onTap: () => context.go(AppRoutes.payment),
              ),
            ),
            const SizedBox(width: AppConstants.spaceMD),
            Expanded(
              child: _ActionCard(
                icon: Icons.description_rounded,
                label: l.myReceipts,
                onTap: () => context.push(AppRoutes.receipts),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceMD),
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.account_balance_wallet_outlined,
                label: l.transparencyTitle,
                onTap: () => context.push(AppRoutes.transparency),
              ),
            ),
            const SizedBox(width: AppConstants.spaceMD),
            Expanded(
              child: _ActionCard(
                icon: Icons.person_rounded,
                label: l.profile,
                onTap: () => context.go(AppRoutes.profile),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── PAYMENT HISTORY ────────────────────────────────────────────

  Widget _buildPaymentHistory(
    BuildContext context,
    AsyncValue<List<ContributionModel>> contributionsAsync,
    AppLocalizations l,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              l.paymentHistory,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
            ),
            GestureDetector(
              onTap: () => context.push(AppRoutes.receipts),
              child: Row(
                children: [
                  Text(
                    l.viewAll,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.arrow_forward,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceMD),
        contributionsAsync.when(
          loading: () => const _HistoryShimmer(),
          error: (_, __) => Center(child: Text(l.unknownError)),
          data: (contributions) {
            if (contributions.isEmpty) {
              return _EmptyHistory(message: l.noPaymentYet);
            }
            final recent = contributions.take(5).toList();
            return Column(
              children: [
                for (int i = 0; i < recent.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppConstants.spaceSM),
                  _HistoryItem(contribution: recent[i]),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceLG),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: child,
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;
  const _MiniStat({required this.label, required this.value, this.suffix});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            if (suffix != null) ...[
              const SizedBox(width: 2),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text(
                  suffix!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppConstants.spaceLG,
          horizontal: AppConstants.spaceMD,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppConstants.radiusMD),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(height: AppConstants.spaceSM),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final ContributionModel contribution;
  const _HistoryItem({required this.contribution});

  @override
  Widget build(BuildContext context) {
    final isConfirmed = contribution.isConfirmed;
    final date = AppUtils.formatDate(contribution.createdAt.toDate());
    final methodLabel = AppUtils.paymentMethodLabel(contribution.paymentMethod);

    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isConfirmed ? AppColors.success : AppColors.warning)
                  .withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isConfirmed
                  ? Icons.check_circle_outline_rounded
                  : Icons.hourglass_empty_rounded,
              color: isConfirmed ? AppColors.success : AppColors.warning,
              size: 20,
            ),
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _buildTitle(contribution),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$date · $methodLabel',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppConstants.spaceSM),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                AppUtils.formatAmount(contribution.amount),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      (isConfirmed ? AppColors.success : AppColors.warning)
                          .withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  isConfirmed ? 'Confirmé' : 'En attente',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isConfirmed
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _buildTitle(ContributionModel c) {
    try {
      final parts = c.period.split('-');
      if (parts.length == 2) {
        final date =
            DateTime(int.parse(parts[0]), int.parse(parts[1]));
        final formatted = DateFormat('MMMM yyyy', 'fr_FR').format(date);
        final cap = formatted[0].toUpperCase() + formatted.substring(1);
        return 'Contribution $cap';
      }
    } catch (_) {}
    return 'Contribution';
  }
}

class _EmptyHistory extends StatelessWidget {
  final String message;
  const _EmptyHistory({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceXL),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: AppColors.border,
          ),
          const SizedBox(height: AppConstants.spaceMD),
          Text(
            message,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: AppColors.textGray,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PlatformProgressInline extends StatelessWidget {
  final double total;
  final int memberCount;
  final AppLocalizations l;

  const _PlatformProgressInline({
    required this.total,
    required this.memberCount,
    required this.l,
  });

  String _formatMoney(double amount) {
    if (amount >= 1e9) {
      return '${(amount / 1e9).toStringAsFixed(2).replaceAll('.', ',')} Mrd FCFA';
    }
    if (amount >= 1e6) {
      return '${(amount / 1e6).toStringAsFixed(2).replaceAll('.', ',')} M FCFA';
    }
    return AppUtils.formatAmount(amount.toInt());
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(2)} M';
    final s = count.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final target = AppConstants.targetAnnualRevenue.toDouble();
    final ratio = (total / target).clamp(0.0, 1.0);
    final pct = (ratio * 100).toStringAsFixed(3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.platformProgressCard.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.gold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatMoney(total),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Text(
              '$pct%',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.gold,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceSM),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
          ),
        ),
        const SizedBox(height: AppConstants.spaceSM),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l.reachedLabel,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            Text(
              '36,5 Mrd FCFA',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceMD),
        // ── Member count bar ─────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.membersGoal.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.gold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatCount(memberCount),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Text(
              '${((memberCount / AppConstants.targetMembers) * 100).toStringAsFixed(3)}%',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.gold,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceSM),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          child: LinearProgressIndicator(
            value: (memberCount / AppConstants.targetMembers).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
          ),
        ),
        const SizedBox(height: AppConstants.spaceSM),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l.reachedLabel,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            Text(
              '1 000 000',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HistoryShimmer extends StatelessWidget {
  const _HistoryShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: EdgeInsets.only(
            bottom: i < 2 ? AppConstants.spaceSM : 0,
          ),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.border.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppConstants.radiusLG),
            ),
          ),
        ),
      ),
    );
  }
}

