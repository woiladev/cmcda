import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/repositories/notification_repository.dart';

// ── Filter enum ───────────────────────────────────────────────

enum _NotifFilter { all, unread, payments, alerts, system }

// ── Provider ──────────────────────────────────────────────────

final _notifRepo = NotificationRepository();

final _notificationsProvider =
    StreamProvider.autoDispose.family<List<NotificationModel>, String>(
  (ref, userId) => _notifRepo.streamNotifications(userId),
);

// ── Screen ────────────────────────────────────────────────────

class NotificationsScreen extends ConsumerStatefulWidget {
  final Color themeColor;
  final Color themeColorDark;

  const NotificationsScreen({
    super.key,
    this.themeColor = AppColors.primary,
    this.themeColorDark = AppColors.primaryDark,
  });

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  _NotifFilter _filter = _NotifFilter.all;

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
        final notificationsAsync =
            ref.watch(_notificationsProvider(user.id));
        return _buildScreen(context, user.id, notificationsAsync, l);
      },
    );
  }

  Widget _buildScreen(
    BuildContext context,
    String userId,
    AsyncValue<List<NotificationModel>> notificationsAsync,
    AppLocalizations l,
  ) {
    final unreadCount =
        notificationsAsync.valueOrNull?.where((n) => !n.read).length ?? 0;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, userId, unreadCount, l),
          Expanded(
            child: notificationsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(child: Text(l.unknownError)),
              data: (notifications) {
                final filtered = _applyFilter(notifications);
                if (filtered.isEmpty) return _buildEmptyState(l);
                final groups = _groupByDate(filtered);
                return _buildList(groups, userId, l);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    String userId,
    int unreadCount,
    AppLocalizations l,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [widget.themeColor, widget.themeColorDark],
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + AppConstants.spaceMD,
        left: AppConstants.spaceLG,
        right: AppConstants.spaceLG,
        bottom: AppConstants.spaceMD,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      final router = GoRouter.of(context);
                      if (router.canPop()) {
                        router.pop();
                      } else {
                        context.go(AppRoutes.dashboard);
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(right: AppConstants.spaceSM),
                      child: Icon(
                        Icons.arrow_back_ios_rounded,
                        color: AppColors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  Text(
                    l.notifications,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                    ),
                  ),
                ],
              ),
              if (unreadCount > 0)
                GestureDetector(
                  onTap: () => _markAllAsRead(userId, l),
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    l.markAllRead,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.white.withValues(alpha: 0.85),
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceMD),
          _buildFilterTabs(l, unreadCount, widget.themeColorDark),
        ],
      ),
    );
  }

  Widget _buildFilterTabs(AppLocalizations l, int unreadCount, Color themeColorDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip(filter: _NotifFilter.all, label: l.filterAll, themeColorDark: themeColorDark),
          _filterChip(
            filter: _NotifFilter.unread,
            label: unreadCount > 0
                ? '${l.filterUnread} ($unreadCount)'
                : l.filterUnread,
            themeColorDark: themeColorDark,
          ),
          _filterChip(filter: _NotifFilter.payments, label: l.filterPayments, themeColorDark: themeColorDark),
          _filterChip(filter: _NotifFilter.alerts, label: l.filterAlerts, themeColorDark: themeColorDark),
          _filterChip(filter: _NotifFilter.system, label: l.filterSystem, themeColorDark: themeColorDark),
        ],
      ),
    );
  }

  Widget _filterChip({
    required _NotifFilter filter,
    required String label,
    required Color themeColorDark,
  }) {
    final selected = _filter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: AppConstants.spaceSM),
      child: GestureDetector(
        onTap: () => setState(() => _filter = filter),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceMD,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.gold
                : AppColors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          ),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? themeColorDark : AppColors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ── Notification List ──────────────────────────────────────

  Widget _buildList(
    Map<String, List<NotificationModel>> groups,
    String userId,
    AppLocalizations l,
  ) {
    return ListView(
      padding: const EdgeInsets.all(AppConstants.spaceLG),
      children: [
        for (final entry in groups.entries) ...[
          _SectionHeader(label: _sectionLabel(entry.key, l), color: widget.themeColor),
          const SizedBox(height: AppConstants.spaceSM),
          for (final notif in entry.value) ...[
            _NotificationItem(
              notification: notif,
              onTap: () => _onNotifTap(notif),
              themeColor: widget.themeColor,
            ),
            const SizedBox(height: AppConstants.spaceSM),
          ],
          const SizedBox(height: AppConstants.spaceMD),
        ],
      ],
    );
  }

  // ── Empty State ────────────────────────────────────────────

  Widget _buildEmptyState(AppLocalizations l) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: widget.themeColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_off_outlined,
                size: 48,
                color: widget.themeColor,
              ),
            ),
            const SizedBox(height: AppConstants.spaceLG),
            Text(
              l.noNotifications,
              style: GoogleFonts.playfairDisplay(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spaceSM),
            Text(
              l.noNotificationsBody,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: AppColors.textGray,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Logic Helpers ──────────────────────────────────────────

  List<NotificationModel> _applyFilter(List<NotificationModel> all) {
    switch (_filter) {
      case _NotifFilter.all:
        return all;
      case _NotifFilter.unread:
        return all.where((n) => !n.read).toList();
      case _NotifFilter.payments:
        const types = [
          NotificationModel.typePaymentConfirmed,
          NotificationModel.typePaymentRejected,
          NotificationModel.typePaymentReminder,
          NotificationModel.typeManualPayment,
        ];
        return all.where((n) => types.contains(n.type)).toList();
      case _NotifFilter.alerts:
        return all
            .where((n) => n.type == NotificationModel.typeAdminAlert)
            .toList();
      case _NotifFilter.system:
        const types = [
          NotificationModel.typeWelcome,
          NotificationModel.typeMilestone,
          NotificationModel.typeFocalReport,
          NotificationModel.typeRoleChange,
        ];
        return all.where((n) => types.contains(n.type)).toList();
    }
  }

  Map<String, List<NotificationModel>> _groupByDate(
    List<NotificationModel> notifications,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final raw = <String, List<NotificationModel>>{};
    for (final notif in notifications) {
      final date = notif.createdAt.toDate();
      final dateOnly = DateTime(date.year, date.month, date.day);

      final String key;
      if (dateOnly == today) {
        key = 'today';
      } else if (dateOnly == yesterday) {
        key = 'yesterday';
      } else if (dateOnly.isAfter(weekAgo)) {
        key = 'thisWeek';
      } else {
        key = 'older';
      }
      raw.putIfAbsent(key, () => []).add(notif);
    }

    final ordered = <String, List<NotificationModel>>{};
    for (final key in ['today', 'yesterday', 'thisWeek', 'older']) {
      if (raw.containsKey(key)) ordered[key] = raw[key]!;
    }
    return ordered;
  }

  String _sectionLabel(String key, AppLocalizations l) {
    switch (key) {
      case 'today':
        return l.todayLabel;
      case 'yesterday':
        return l.yesterdayLabel;
      case 'thisWeek':
        return l.thisWeekLabel;
      case 'older':
        return l.olderLabel;
      default:
        return key;
    }
  }

  Future<void> _onNotifTap(NotificationModel notif) async {
    if (!notif.read) {
      await _notifRepo.markAsRead(notif.id);
    }
  }

  Future<void> _markAllAsRead(String userId, AppLocalizations l) async {
    try {
      await _notifRepo.markAllAsRead(userId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.unknownError)),
        );
      }
    }
  }
}

// ── Section Header ─────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionHeader({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.8,
      ),
    );
  }
}

// ── Notification Item ─────────────────────────────────────────

class _NotificationItem extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;
  final Color themeColor;

  const _NotificationItem({
    required this.notification,
    required this.onTap,
    required this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    final (iconData, iconBg, iconColor) = _iconForType(notification.type);
    final isUnread = !notification.read;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppConstants.spaceMD),
        decoration: BoxDecoration(
          color: isUnread ? AppColors.white : const Color(0xFFF5FAF7),
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          border: Border.all(
            color: isUnread
                ? AppColors.border
                : AppColors.border.withValues(alpha: 0.45),
          ),
          boxShadow: isUnread
              ? [
                  BoxShadow(
                    color: themeColor.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(iconData, color: iconColor, size: 22),
            ),
            const SizedBox(width: AppConstants.spaceMD),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight:
                          isUnread ? FontWeight.w700 : FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notification.body,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: AppColors.textGray,
                      height: 1.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatTime(notification.createdAt),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: AppColors.textLight,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (isUnread) ...[
              const SizedBox(width: AppConstants.spaceSM),
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.info,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  (IconData, Color, Color) _iconForType(String type) {
    switch (type) {
      case NotificationModel.typePaymentConfirmed:
        return (
          Icons.check_circle_rounded,
          AppColors.success.withValues(alpha: 0.15),
          AppColors.success,
        );
      case NotificationModel.typePaymentRejected:
        return (
          Icons.cancel_rounded,
          AppColors.error.withValues(alpha: 0.15),
          AppColors.error,
        );
      case NotificationModel.typePaymentReminder:
        return (
          Icons.alarm_rounded,
          AppColors.warning.withValues(alpha: 0.15),
          AppColors.warning,
        );
      case NotificationModel.typeRoleChange:
        return (
          Icons.badge_rounded,
          AppColors.info.withValues(alpha: 0.15),
          AppColors.info,
        );
      case NotificationModel.typeWelcome:
      case NotificationModel.typeMilestone:
        return (
          Icons.stars_rounded,
          AppColors.gold.withValues(alpha: 0.15),
          AppColors.gold,
        );
      case NotificationModel.typeAdminAlert:
        return (
          Icons.security_rounded,
          AppColors.error.withValues(alpha: 0.15),
          AppColors.error,
        );
      case NotificationModel.typeFocalReport:
        return (
          Icons.description_rounded,
          AppColors.accentCyan.withValues(alpha: 0.15),
          AppColors.accentCyan,
        );
      case NotificationModel.typeManualPayment:
        return (
          Icons.receipt_long_rounded,
          AppColors.warning.withValues(alpha: 0.15),
          AppColors.warning,
        );
      default:
        return (
          Icons.notifications_rounded,
          themeColor.withValues(alpha: 0.15),
          themeColor,
        );
    }
  }

  String _formatTime(Timestamp timestamp) {
    final date = timestamp.toDate();
    final diff = DateTime.now().difference(date);

    if (diff.inMinutes < 1) return "À l'instant";
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    return AppUtils.formatDate(date);
  }
}
