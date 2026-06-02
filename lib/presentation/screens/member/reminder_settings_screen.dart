import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/reminder_plan_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/reminder_plan_repository.dart';

// ── Providers ────────────────────────────────────────────────
final reminderPlanRepositoryProvider =
    Provider<ReminderPlanRepository>((ref) => ReminderPlanRepository());

final reminderPlanProvider =
    StreamProvider.autoDispose.family<ReminderPlanModel?, String>(
  (ref, memberId) =>
      ref.watch(reminderPlanRepositoryProvider).streamPlan(memberId),
);

// ══════════════════════════════════════════════════════════════
// REMINDER SETTINGS SCREEN
// ══════════════════════════════════════════════════════════════

class ReminderSettingsScreen extends ConsumerWidget {
  const ReminderSettingsScreen({super.key});

  static const _frequencies = [
    AppConstants.periodDaily,
    AppConstants.periodMonthly,
    AppConstants.periodAnnual,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final userAsync = ref.watch(currentUserProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(
          l.reminders,
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700),
        ),
      ),
      body: userAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (_, __) => Center(child: Text(l.unknownError)),
        data: (user) {
          if (user == null) return Center(child: Text(l.unknownError));
          return _Body(user: user);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final UserModel user;
  const _Body({required this.user});

  String _freqLabel(AppLocalizations l, String freq) {
    switch (freq) {
      case AppConstants.periodDaily:
        return l.freqDaily;
      case AppConstants.periodAnnual:
        return l.freqAnnual;
      case AppConstants.periodMonthly:
      default:
        return l.freqMonthly;
    }
  }

  Future<void> _toggle(WidgetRef ref, ReminderPlanModel? plan, bool on) async {
    final repo = ref.read(reminderPlanRepositoryProvider);
    if (plan == null) {
      // No plan yet (e.g. member created before this feature) — create one.
      await repo.upsertForMember(user.id, user.preferredFrequency);
      if (!on) await repo.setActive(user.id, false);
    } else {
      await repo.setActive(user.id, on);
    }
  }

  Future<void> _changeFreq(WidgetRef ref, ReminderPlanModel? plan, String freq) async {
    if (plan?.frequency == freq) return;
    final repo = ref.read(reminderPlanRepositoryProvider);
    if (plan == null) {
      await repo.upsertForMember(user.id, freq);
    } else {
      await repo.updateFrequency(user.id, freq);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final planAsync = ref.watch(reminderPlanProvider(user.id));
    final plan = planAsync.valueOrNull;
    final active = plan?.active ?? false;
    final selectedFreq = plan?.frequency ?? user.preferredFrequency;
    final goalReached = user.totalContributed >= AppConstants.amountAnnual;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spaceLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.remindersSubtitle,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textMid,
            ),
          ),
          const SizedBox(height: AppConstants.spaceLG),

          // Enable toggle
          _Card(
            child: Row(
              children: [
                _IconBox(active ? Icons.notifications_active_rounded
                    : Icons.notifications_off_outlined),
                const SizedBox(width: AppConstants.spaceMD),
                Expanded(
                  child: Text(
                    l.enableReminders,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                Switch(
                  value: active,
                  onChanged: (v) => _toggle(ref, plan, v),
                  activeThumbColor: AppColors.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spaceLG),

          // Frequency selector
          Opacity(
            opacity: active ? 1 : 0.5,
            child: IgnorePointer(
              ignoring: !active,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.reminderFrequency,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textGray,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceSM),
                  Row(
                    children: [
                      for (final f in ReminderSettingsScreen._frequencies) ...[
                        _FreqPill(
                          label: _freqLabel(l, f),
                          amount: AppUtils.formatAmount(
                              ReminderPlanModel.amountForFrequency(f)),
                          active: selectedFreq == f,
                          onTap: () => _changeFreq(ref, plan, f),
                        ),
                        if (f != ReminderSettingsScreen._frequencies.last)
                          const SizedBox(width: AppConstants.spaceSM),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spaceLG),

          // Status: next reminder / goal / disabled
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!active)
                  _StatusRow(Icons.info_outline_rounded, l.remindersDisabledHint)
                else if (goalReached)
                  _StatusRow(Icons.emoji_events_rounded, l.remindersGoalReached,
                      color: AppColors.gold)
                else if (plan != null)
                  _StatusRow(
                    Icons.event_rounded,
                    '${l.nextReminder} : '
                    '${AppUtils.formatDate(plan.nextReminderAt.toDate())}',
                  ),
                const SizedBox(height: AppConstants.spaceMD),
                Text(
                  l.annualObjective,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textGray,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  child: LinearProgressIndicator(
                    value: AppUtils.annualProgress(user.totalContributed),
                    minHeight: 8,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${AppUtils.formatAmount(user.totalContributed)} / '
                  '${AppUtils.formatAmount(AppConstants.amountAnnual)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textMid,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  const _IconBox(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusSM),
      ),
      child: Icon(icon, color: AppColors.primary, size: 18),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _StatusRow(this.icon, this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textMid;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: AppConstants.spaceSM),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: c,
            ),
          ),
        ),
      ],
    );
  }
}

class _FreqPill extends StatelessWidget {
  final String label;
  final String amount;
  final bool active;
  final VoidCallback onTap;
  const _FreqPill({
    required this.label,
    required this.amount,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
              width: active ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppColors.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                amount,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: active ? Colors.white70 : AppColors.textGray,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
