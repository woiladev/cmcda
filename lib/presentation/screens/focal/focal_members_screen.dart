import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/contribution_repository.dart';
import 'focal_providers.dart';
import 'focal_pawapay_sheet.dart';
import '../../widgets/common/payment_method_icon.dart';
import '../../widgets/common/super_badge_avatar.dart';

const _focalLight = Color(0xFF26A8F3);
const _focalDark = Color(0xFF0A5F8C);

const _amountPresets = [
  (AppConstants.amountDaily, AppConstants.periodDaily),
  (AppConstants.amountMonthly, AppConstants.periodMonthly),
  (AppConstants.amountAnnual, AppConstants.periodAnnual),
];

// ── Screen ────────────────────────────────────────────────────

class FocalMembersScreen extends ConsumerStatefulWidget {
  const FocalMembersScreen({super.key});

  @override
  ConsumerState<FocalMembersScreen> createState() =>
      _FocalMembersScreenState();
}

class _FocalMembersScreenState
    extends ConsumerState<FocalMembersScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openMemberDetail(UserModel member, String focalId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemberDetailSheet(
        member: member,
        focalId: focalId,
        parentContext: context,
      ),
    );
  }

  void _openReminder(UserModel member) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReminderSheet(member: member),
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
      data: (focal) {
        if (focal == null) {
          return Scaffold(body: Center(child: Text(l.unknownError)));
        }
        final membersAsync = ref.watch(focalMembersProvider(focal.id));
        final all = membersAsync.valueOrNull ?? [];
        final filtered = _search.isEmpty
            ? all
            : all.where((m) {
                final q = _search.toLowerCase();
                return m.fullName.toLowerCase().contains(q) ||
                    m.memberNumber.toLowerCase().contains(q) ||
                    m.phone.contains(q);
              }).toList();

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: CustomScrollView(
            slivers: [
              // ── Header ───────────────────────────────────────
              SliverToBoxAdapter(
                child: _buildHeader(context, l, focal, all.length),
              ),
              // ── Search bar ───────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.spaceLG,
                    AppConstants.spaceMD,
                    AppConstants.spaceLG,
                    AppConstants.spaceSM,
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v.trim()),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, color: AppColors.textDark),
                    decoration: InputDecoration(
                      hintText: l.searchMembers,
                      hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: AppColors.textGray),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppColors.textGray, size: 20),
                      suffixIcon: _search.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchCtrl.clear();
                                setState(() => _search = '');
                              },
                              child: const Icon(Icons.clear_rounded,
                                  color: AppColors.textGray, size: 18),
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spaceMD,
                          vertical: AppConstants.spaceMD),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusMD),
                        borderSide:
                            const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusMD),
                        borderSide:
                            const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusMD),
                        borderSide: const BorderSide(
                            color: _focalLight, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
              // ── List ─────────────────────────────────────────
              membersAsync.when(
                loading: () => const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => SliverFillRemaining(
                  child: Center(child: Text(l.unknownError)),
                ),
                data: (_) {
                  if (all.isEmpty) {
                    return SliverFillRemaining(
                      child: _EmptyMembers(l: l),
                    );
                  }
                  if (filtered.isEmpty) {
                    return SliverFillRemaining(
                      child: Center(
                        child: Text(
                          l.noMembersFound,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: AppColors.textGray),
                        ),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.spaceLG,
                      AppConstants.spaceSM,
                      AppConstants.spaceLG,
                      AppConstants.spaceXL,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _MemberTile(
                          member: filtered[i],
                          onTap: () => _openMemberDetail(filtered[i], focal.id),
                          onRemind: () => _openReminder(filtered[i]),
                        ),
                        childCount: filtered.length,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l,
      UserModel focal, int memberCount) {
    final statusBarH = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        statusBarH + AppConstants.spaceMD,
        AppConstants.spaceLG,
        AppConstants.spaceLG,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_focalLight, _focalDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.myMembers,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  '$memberCount',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceXS),
          Text(
            focal.focalZone?.isNotEmpty == true
                ? focal.focalZone!
                : focal.region,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Member tile ───────────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  final UserModel member;
  final VoidCallback onTap;
  final VoidCallback onRemind;

  const _MemberTile({required this.member, required this.onTap, required this.onRemind});

  @override
  Widget build(BuildContext context) {
    final m = member;
    final isActive = m.isActive;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spaceSM),
        padding: const EdgeInsets.all(AppConstants.spaceMD),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.textDark.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            SuperBadgeAvatar(
              initials: m.initials,
              isSuperContributor: m.isSuperContributor,
              size: 44,
              backgroundColor: _focalLight.withValues(alpha: 0.12),
              textColor: _focalLight,
            ),
            const SizedBox(width: AppConstants.spaceMD),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          m.fullName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.success.withValues(alpha: 0.1)
                              : AppColors.textGray.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull),
                        ),
                        child: Text(
                          isActive
                              ? AppLocalizations.of(context).active
                              : AppLocalizations.of(context).inactive,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: isActive
                                ? AppColors.success
                                : AppColors.textGray,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        m.memberNumber,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: _focalLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (m.phone.isNotEmpty) ...[
                        Text(
                          ' · ',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: AppColors.textGray),
                        ),
                        Text(
                          m.phone,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: AppColors.textGray),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onRemind,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceSM, vertical: AppConstants.spaceSM),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                  ),
                  child: const Icon(Icons.phone_outlined,
                      color: AppColors.warning, size: 17),
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textGray, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Member detail sheet ───────────────────────────────────────

class _MemberDetailSheet extends StatefulWidget {
  final UserModel member;
  final String focalId;
  final BuildContext parentContext;

  const _MemberDetailSheet(
      {required this.member, required this.focalId, required this.parentContext});

  @override
  State<_MemberDetailSheet> createState() => _MemberDetailSheetState();
}

class _MemberDetailSheetState extends State<_MemberDetailSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _openRecordPayment() {
    Navigator.of(context).pop();
    showModalBottomSheet(
      context: widget.parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecordPaymentSheet(
        member: widget.member,
        focalId: widget.focalId,
      ),
    );
  }

  void _openEditInfo() {
    Navigator.of(context).pop();
    showModalBottomSheet(
      context: widget.parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditMemberSheet(member: widget.member),
    );
  }

  void _openReminder() {
    Navigator.of(context).pop();
    showModalBottomSheet(
      context: widget.parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReminderSheet(member: widget.member),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final m = widget.member;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppConstants.radiusXL)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: AppConstants.spaceMD),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
              ),
            ),
            // Member header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spaceLG,
                0,
                AppConstants.spaceLG,
                AppConstants.spaceMD,
              ),
              child: Row(
                children: [
                  SuperBadgeAvatar(
                    initials: m.initials,
                    isSuperContributor: m.isSuperContributor,
                    size: 52,
                    backgroundColor: _focalLight,
                    textColor: Colors.white,
                  ),
                  const SizedBox(width: AppConstants.spaceMD),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.fullName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(
                                    ClipboardData(text: m.memberNumber));
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text(l.copiedToClipboard),
                                  backgroundColor: AppColors.info,
                                ));
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    m.memberNumber,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: _focalLight,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  const Icon(Icons.copy_rounded,
                                      size: 11, color: _focalLight),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: m.isActive
                          ? AppColors.success.withValues(alpha: 0.1)
                          : AppColors.textGray.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(
                      m.isActive ? l.active : l.inactive,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: m.isActive
                            ? AppColors.success
                            : AppColors.textGray,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spaceLG,
                0,
                AppConstants.spaceLG,
                AppConstants.spaceMD,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.payments_outlined,
                      label: l.recordPayment,
                      color: AppColors.success,
                      onTap: _openRecordPayment,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceSM),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.phone_outlined,
                      label: l.remindMember,
                      color: AppColors.warning,
                      onTap: _openReminder,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceSM),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.edit_outlined,
                      label: l.editInfo,
                      color: AppColors.primary,
                      onTap: _openEditInfo,
                    ),
                  ),
                ],
              ),
            ),
            // Tabs
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.border),
                ),
              ),
              child: TabBar(
                controller: _tabs,
                labelColor: _focalLight,
                unselectedLabelColor: AppColors.textGray,
                indicatorColor: _focalLight,
                indicatorWeight: 2,
                labelStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12, fontWeight: FontWeight.w700),
                unselectedLabelStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12, fontWeight: FontWeight.w500),
                tabs: [
                  Tab(text: l.personalInfo),
                  Tab(text: l.contributionsTab),
                ],
              ),
            ),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _InfoTab(member: m, l: l),
                  _ContributionsTab(memberId: m.id, l: l),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Info tab ──────────────────────────────────────────────────

class _InfoTab extends StatelessWidget {
  final UserModel member;
  final AppLocalizations l;

  const _InfoTab({required this.member, required this.l});

  @override
  Widget build(BuildContext context) {
    final m = member;
    return ListView(
      padding: const EdgeInsets.all(AppConstants.spaceLG),
      children: [
        _InfoRow(
            icon: Icons.phone_outlined, label: l.phone, value: m.phone),
        _InfoRow(
            icon: Icons.map_outlined,
            label: l.region,
            value: m.region.isNotEmpty ? m.region : '—'),
        _InfoRow(
            icon: Icons.location_city_outlined,
            label: l.department,
            value: m.department.isNotEmpty ? m.department : '—'),
        if ((m.city?.isNotEmpty ?? false) || (m.quarter?.isNotEmpty ?? false))
          _InfoRow(
            icon: Icons.holiday_village_outlined,
            label: l.cityQuarter,
            value: [
              if (m.city?.isNotEmpty ?? false) m.city!,
              if (m.quarter?.isNotEmpty ?? false) m.quarter!,
            ].join(' · '),
          ),
        _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: l.memberSince,
            value: AppUtils.formatDate(m.createdAt.toDate())),
        _InfoRow(
            icon: Icons.payment_outlined,
            label: l.preferredPayment,
            value: AppUtils.paymentMethodLabel(m.preferredPayment)),
        _InfoRow(
            icon: Icons.repeat_rounded,
            label: l.preferredFrequency,
            value: AppUtils.periodTypeLabel(m.preferredFrequency)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceMD),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _focalLight.withValues(alpha: 0.08),
              borderRadius:
                  BorderRadius.circular(AppConstants.radiusSM),
            ),
            child: Icon(icon, color: _focalLight, size: 17),
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10, color: AppColors.textGray),
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
          ),
        ],
      ),
    );
  }
}

// ── Contributions tab ─────────────────────────────────────────

class _ContributionsTab extends StatelessWidget {
  final String memberId;
  final AppLocalizations l;

  const _ContributionsTab({required this.memberId, required this.l});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ContributionModel>>(
      stream: ContributionRepository().getMemberContributions(memberId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final contributions = snap.data ?? [];

        final year = DateTime.now().year.toString();
        final thisYearPaid = contributions
            .where((c) => c.isConfirmed && c.period.startsWith(year))
            .fold<int>(0, (s, c) => s + c.amount);
        final allTimeTotal = contributions
            .where((c) => c.isConfirmed)
            .fold<int>(0, (s, c) => s + c.amount);
        final progress =
            (thisYearPaid / AppConstants.amountAnnual).clamp(0.0, 1.0);
        final remaining =
            (AppConstants.amountAnnual - thisYearPaid).clamp(0, AppConstants.amountAnnual);

        if (contributions.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(AppConstants.spaceLG),
            children: [
              _AnnualProgressCard(
                year: year,
                progress: 0.0,
                contributed: 0,
                remaining: AppConstants.amountAnnual,
                l: l,
              ),
              const SizedBox(height: AppConstants.spaceXL),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long_outlined,
                        size: 48, color: AppColors.border),
                    const SizedBox(height: AppConstants.spaceMD),
                    Text(
                      l.noPaymentYet,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, color: AppColors.textGray),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.all(AppConstants.spaceLG),
          children: [
            // Annual progress card
            _AnnualProgressCard(
              year: year,
              progress: progress,
              contributed: thisYearPaid,
              remaining: remaining,
              l: l,
            ),
            const SizedBox(height: AppConstants.spaceMD),
            // All-time summary
            _AllTimeSummary(
                total: allTimeTotal, count: contributions.length, l: l),
            const SizedBox(height: AppConstants.spaceLG),
            // History label
            Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spaceSM),
              child: Text(
                l.contributionHistory.toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textGray,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            for (final c in contributions)
              _ContributionRow(contribution: c, l: l),
          ],
        );
      },
    );
  }
}

// ── Annual progress card ───────────────────────────────────────

class _AnnualProgressCard extends StatelessWidget {
  final String year;
  final double progress;
  final int contributed;
  final int remaining;
  final AppLocalizations l;

  const _AnnualProgressCard({
    required this.year,
    required this.progress,
    required this.contributed,
    required this.remaining,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    final goalReached = progress >= 1.0;
    final color = goalReached
        ? AppColors.success
        : progress >= 0.5
            ? _focalLight
            : AppColors.warning;
    final pct = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(Icons.track_changes_rounded, color: color, size: 16),
              const SizedBox(width: AppConstants.spaceSM),
              Expanded(
                child: Text(
                  '${l.progressionLabel} $year',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  '$pct%',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceMD),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 10,
            ),
          ),
          if (goalReached) ...[
            const SizedBox(height: AppConstants.spaceSM),
            Center(
              child: Text(
                l.annualGoalReached,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppConstants.spaceMD),
          // Paid / Remaining
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppUtils.formatAmount(contributed),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success,
                      ),
                    ),
                    Text(
                      l.paidSuffix,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10, color: AppColors.textGray),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 32, color: AppColors.border),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      AppUtils.formatAmount(remaining),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: goalReached
                            ? AppColors.textGray
                            : AppColors.warning,
                      ),
                    ),
                    Text(
                      l.remainingSuffix,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10, color: AppColors.textGray),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceSM),
          Center(
            child: Text(
              '${l.annualObjective} · ${AppUtils.formatAmount(AppConstants.amountAnnual)}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, color: AppColors.textGray),
            ),
          ),
        ],
      ),
    );
  }
}

// ── All-time summary ──────────────────────────────────────────

class _AllTimeSummary extends StatelessWidget {
  final int total;
  final int count;
  final AppLocalizations l;

  const _AllTimeSummary(
      {required this.total, required this.count, required this.l});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMD,
        vertical: AppConstants.spaceSM + 2,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_focalLight, _focalDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              color: Colors.white, size: 18),
          const SizedBox(width: AppConstants.spaceSM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.totalContributed,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                Text(
                  AppUtils.formatAmount(total),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Text(
                l.contributionsTab.toLowerCase(),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContributionRow extends StatelessWidget {
  final ContributionModel contribution;
  final AppLocalizations l;

  const _ContributionRow(
      {required this.contribution, required this.l});

  @override
  Widget build(BuildContext context) {
    final c = contribution;
    final statusColor = c.isConfirmed
        ? AppColors.success
        : c.isFailed
            ? AppColors.error
            : AppColors.warning;
    final statusLabel =
        c.isConfirmed ? l.confirmed : c.isFailed ? l.failed : l.pending;

    return Container(
      margin:
          const EdgeInsets.only(bottom: AppConstants.spaceSM),
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              c.isConfirmed
                  ? Icons.check_rounded
                  : c.isFailed
                      ? Icons.close_rounded
                      : Icons.hourglass_top_rounded,
              color: statusColor,
              size: 18,
            ),
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppUtils.formatAmount(c.amount),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  '${AppUtils.periodTypeLabel(c.periodType)} · ${c.period}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: AppColors.textGray),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                AppUtils.formatDateShort(c.createdAt.toDate()),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: AppColors.textGray),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Record payment sheet ──────────────────────────────────────

class _RecordPaymentSheet extends StatefulWidget {
  final UserModel member;
  final String focalId;

  const _RecordPaymentSheet(
      {required this.member, required this.focalId});

  @override
  State<_RecordPaymentSheet> createState() =>
      _RecordPaymentSheetState();
}

class _RecordPaymentSheetState
    extends State<_RecordPaymentSheet> {
  final _repo = ContributionRepository();
  final _customCtrl = TextEditingController();
  int? _selectedAmount;
  bool _customMode = false;
  String _selectedPeriodType = AppConstants.periodMonthly;
  String _selectedMethod = AppConstants.paymentCash;
  bool _loading = false;

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  int get _amount => _customMode
      ? (int.tryParse(_customCtrl.text.trim()) ?? 0)
      : (_selectedAmount ?? 0);

  String get _periodType =>
      _customMode ? AppConstants.periodCustom : _selectedPeriodType;

  bool get _isMomo =>
      _selectedMethod == AppConstants.paymentMtnMomo ||
      _selectedMethod == AppConstants.paymentOrangeMoney;

  bool get _canSubmit => _amount > 0;

  void _onConfirm() {
    if (!_canSubmit || _loading) return;
    if (_isMomo) {
      _startMomoCharge();
    } else {
      _recordCash();
    }
  }

  // Mobile money: trigger a real pawaPay PIN prompt on the member's phone. The
  // deposit is initiated server-side on the member's behalf; this sheet only
  // closes once the deposit confirms.
  Future<void> _startMomoCharge() async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: FocalPawaPaySheet(
            member: widget.member,
            amount: _amount,
            periodType: _periodType,
            isMtn: _selectedMethod == AppConstants.paymentMtnMomo,
          ),
        ),
      ),
    );
    if (confirmed == true && mounted) {
      nav.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(l.paymentRecorded),
        backgroundColor: AppColors.success,
      ));
    }
  }

  Future<void> _recordCash() async {
    setState(() => _loading = true);
    final l = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _repo.createContribution(
        memberId: widget.member.id,
        memberName: widget.member.fullName,
        memberNumber: widget.member.memberNumber,
        amount: _amount,
        periodType: _periodType,
        paymentMethod: _selectedMethod,
        recordedBy: widget.focalId,
      );
      nav.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(l.paymentRecorded),
        backgroundColor: AppColors.success,
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(l.unknownError),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final methods = [
      (AppConstants.paymentCash, l.cash),
      (AppConstants.paymentMtnMomo, l.mtnMomo),
      (AppConstants.paymentOrangeMoney, l.orangeMoney),
    ];

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppConstants.radiusXL)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: AppConstants.spaceMD),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spaceLG,
                0,
                AppConstants.spaceLG,
                AppConstants.spaceMD,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.payments_outlined,
                        color: AppColors.success, size: 20),
                  ),
                  const SizedBox(width: AppConstants.spaceMD),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.recordPayment,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        Text(
                          widget.member.fullName,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppColors.textGray),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.all(AppConstants.spaceLG),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Amount presets
                  Text(
                    l.chooseAmount,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textGray,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceSM),
                  Wrap(
                    spacing: AppConstants.spaceSM,
                    runSpacing: AppConstants.spaceSM,
                    children: [
                      for (final (amount, period) in _amountPresets)
                        _AmountChip(
                          amount: amount,
                          period: period,
                          selected: !_customMode && _selectedAmount == amount,
                          onTap: () => setState(() {
                            _customMode = false;
                            _selectedAmount = amount;
                            _selectedPeriodType = period;
                          }),
                          l: l,
                        ),
                      _CustomChip(
                        label: l.custom,
                        selected: _customMode,
                        onTap: () => setState(() => _customMode = true),
                      ),
                    ],
                  ),
                  if (_customMode) ...[
                    const SizedBox(height: AppConstants.spaceSM),
                    TextField(
                      controller: _customCtrl,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: '${l.amount} (FCFA)',
                        prefixIcon: const Icon(Icons.payments_outlined,
                            color: AppColors.textGray, size: 18),
                        filled: true,
                        fillColor: AppColors.bg,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusMD),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusMD),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusMD),
                          borderSide:
                              const BorderSide(color: _focalLight, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppConstants.spaceLG),
                  // Payment method
                  Text(
                    l.chooseMethod,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textGray,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceSM),
                  ...methods.map((m) => _MethodTile(
                        value: m.$1,
                        label: m.$2,
                        selected: _selectedMethod == m.$1,
                        onTap: () =>
                            setState(() => _selectedMethod = m.$1),
                      )),
                  const SizedBox(height: AppConstants.spaceLG),
                  // Confirm
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (_canSubmit && !_loading)
                          ? _onConfirm
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        disabledBackgroundColor:
                            AppColors.border,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusMD),
                        ),
                      ),
                      child: _loading
                          ? const CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2)
                          : Text(
                              l.confirmPayment,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(
                      height: MediaQuery.of(context).padding.bottom),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  final int amount;
  final String period;
  final bool selected;
  final VoidCallback onTap;
  final AppLocalizations l;

  const _AmountChip({
    required this.amount,
    required this.period,
    required this.selected,
    required this.onTap,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceMD,
            vertical: AppConstants.spaceSM),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.success
              : AppColors.surface,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(
            color: selected
                ? AppColors.success
                : AppColors.border,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppUtils.formatAmount(amount),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textDark,
              ),
            ),
            Text(
              AppUtils.periodTypeLabel(period),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: selected
                    ? Colors.white.withValues(alpha: 0.85)
                    : AppColors.textGray,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CustomChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceMD, vertical: AppConstants.spaceSM),
        decoration: BoxDecoration(
          color: selected ? AppColors.success : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(
            color: selected ? AppColors.success : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded,
                size: 15,
                color: selected ? Colors.white : AppColors.textGray),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final String value;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MethodTile({
    required this.value,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin:
            const EdgeInsets.only(bottom: AppConstants.spaceSM),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMD,
          vertical: AppConstants.spaceMD,
        ),
        decoration: BoxDecoration(
          color: selected
              ? _focalLight.withValues(alpha: 0.05)
              : AppColors.surface,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(
            color: selected ? _focalLight : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            paymentMethodIcon(value,
                size: 20,
                color: selected ? _focalLight : AppColors.textGray),
            const SizedBox(width: AppConstants.spaceMD),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? AppColors.textDark
                      : AppColors.textGray,
                ),
              ),
            ),
            if (selected)
              Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: _focalLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 12),
              )
            else
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Reminder sheet ────────────────────────────────────────────

class _ReminderSheet extends StatefulWidget {
  final UserModel member;
  const _ReminderSheet({required this.member});

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  late final TextEditingController _msgCtrl;

  @override
  void initState() {
    super.initState();
    _msgCtrl = TextEditingController(text: _buildSmsBody());
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  String _buildSmsBody() {
    final m = widget.member;
    final amount = _amountForFrequency(m.preferredFrequency);
    final periodLabel = _periodLabel(m.preferredFrequency);
    return 'Bonjour ${m.firstName},\n\n'
        'Je vous rappelle que votre cotisation $periodLabel CMCDA '
        '(${AppUtils.formatAmount(amount)}) est attendue. '
        'Merci de me contacter dès que possible pour effectuer votre paiement.\n\n'
        'CMCDA';
  }

  int _amountForFrequency(String freq) {
    switch (freq) {
      case AppConstants.periodDaily:
        return AppConstants.amountDaily;
      case AppConstants.periodAnnual:
        return AppConstants.amountAnnual;
      default:
        return AppConstants.amountMonthly;
    }
  }

  String _periodLabel(String freq) {
    switch (freq) {
      case AppConstants.periodDaily:
        return 'quotidienne';
      case AppConstants.periodAnnual:
        return 'annuelle';
      default:
        return 'mensuelle';
    }
  }

  Future<void> _launch(Uri uri, BuildContext ctx) async {
    final l = AppLocalizations.of(ctx);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(l.launchError),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _call(BuildContext ctx) async {
    final phone = widget.member.phone;
    await _launch(Uri(scheme: 'tel', path: phone), ctx);
  }

  Future<void> _sendSms(BuildContext ctx) async {
    final phone = widget.member.phone;
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': _msgCtrl.text},
    );
    await _launch(uri, ctx);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final m = widget.member;
    final hasPhone = m.phone.isNotEmpty;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXL)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        AppConstants.spaceLG,
        AppConstants.spaceLG,
        bottomPad + AppConstants.spaceLG,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spaceLG),

          // Member identity
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone_outlined,
                    color: AppColors.warning, size: 22),
              ),
              const SizedBox(width: AppConstants.spaceMD),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.fullName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      hasPhone ? m.phone : l.noPhoneNumber,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: hasPhone ? AppColors.primary : AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceLG),

          // Quick action buttons: Call + SMS
          Row(
            children: [
              Expanded(
                child: _QuickContactButton(
                  icon: Icons.call_rounded,
                  label: l.callAction,
                  color: AppColors.success,
                  enabled: hasPhone,
                  onTap: () => _call(context),
                ),
              ),
              const SizedBox(width: AppConstants.spaceMD),
              Expanded(
                child: _QuickContactButton(
                  icon: Icons.sms_outlined,
                  label: l.smsAction,
                  color: _focalLight,
                  enabled: hasPhone,
                  onTap: () => _sendSms(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceLG),

          // Editable SMS message
          Text(
            l.reminderMessage,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textGray,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppConstants.spaceSM),
          TextField(
            controller: _msgCtrl,
            maxLines: 6,
            minLines: 4,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppColors.textDark,
              height: 1.5,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.bg,
              contentPadding: const EdgeInsets.all(AppConstants.spaceMD),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                borderSide:
                    const BorderSide(color: AppColors.warning, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spaceMD),

          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: hasPhone ? () => _sendSms(context) : null,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(l.sendSmsReminder),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.border,
                textStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickContactButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _QuickContactButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effective = enabled ? color : AppColors.border;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppConstants.spaceMD),
        decoration: BoxDecoration(
          color: effective.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(color: effective.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: effective, size: 26),
            const SizedBox(height: AppConstants.spaceXS),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: effective,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Edit member sheet ─────────────────────────────────────────

class _EditMemberSheet extends StatefulWidget {
  final UserModel member;
  const _EditMemberSheet({required this.member});

  @override
  State<_EditMemberSheet> createState() => _EditMemberSheetState();
}

class _EditMemberSheetState extends State<_EditMemberSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _quarterCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    _firstNameCtrl = TextEditingController(text: m.firstName);
    _lastNameCtrl = TextEditingController(text: m.lastName);
    _phoneCtrl = TextEditingController(text: m.phone);
    _cityCtrl = TextEditingController(text: m.city ?? '');
    _quarterCtrl = TextEditingController(text: m.quarter ?? '');
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _quarterCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final city = _cityCtrl.text.trim();
      final quarter = _quarterCtrl.text.trim();
      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(widget.member.id)
          .update({
        'firstName': _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        if (city.isNotEmpty) 'city': city,
        if (quarter.isNotEmpty) 'quarter': quarter,
        'updatedAt': Timestamp.now(),
      });
      nav.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(l.profileUpdated),
        backgroundColor: AppColors.success,
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(l.unknownError),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXL)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        AppConstants.spaceLG,
        AppConstants.spaceLG,
        bottomPad + AppConstants.spaceLG,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spaceLG),
            Text(
              l.editProfile,
              style: GoogleFonts.playfairDisplay(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: AppConstants.spaceLG),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: l.firstName,
                      prefixIcon: const Icon(Icons.person_outline_rounded,
                          color: _focalLight),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l.fieldRequired
                        : null,
                  ),
                ),
                const SizedBox(width: AppConstants.spaceMD),
                Expanded(
                  child: TextFormField(
                    controller: _lastNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: l.lastName,
                      prefixIcon: const Icon(Icons.person_outline_rounded,
                          color: _focalLight),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l.fieldRequired
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceMD),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l.phone,
                prefixIcon: const Icon(Icons.phone_outlined, color: _focalLight),
              ),
            ),
            const SizedBox(height: AppConstants.spaceMD),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cityCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: '${l.city} (${l.optional})',
                      prefixIcon: const Icon(Icons.location_city_outlined,
                          color: _focalLight),
                    ),
                  ),
                ),
                const SizedBox(width: AppConstants.spaceMD),
                Expanded(
                  child: TextFormField(
                    controller: _quarterCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: '${l.quarter} (${l.optional})',
                      prefixIcon: const Icon(Icons.holiday_village_outlined,
                          color: _focalLight),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceLG),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _focalLight,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMD),
                  ),
                ),
                child: _saving
                    ? const CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)
                    : Text(
                        l.saveChanges,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared action button ──────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius:
              BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────

class _EmptyMembers extends StatelessWidget {
  final AppLocalizations l;
  const _EmptyMembers({required this.l});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_outlined, size: 56, color: AppColors.border),
            const SizedBox(height: AppConstants.spaceMD),
            Text(
              l.noMembersRegistered,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: AppColors.textGray),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
