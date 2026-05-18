import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/contribution_repository.dart';

// ── Filter enum ───────────────────────────────────────────────

enum _MemberFilter { all, active, inactive, suspended }

// ── Provider ──────────────────────────────────────────────────

final _allUsersProvider = StreamProvider.autoDispose<List<UserModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(AppConstants.usersCollection)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => UserModel.fromFirestore(d)).toList());
});

// ── Screen ────────────────────────────────────────────────────

class AdminMembersScreen extends ConsumerStatefulWidget {
  const AdminMembersScreen({super.key});

  @override
  ConsumerState<AdminMembersScreen> createState() =>
      _AdminMembersScreenState();
}

class _AdminMembersScreenState extends ConsumerState<AdminMembersScreen> {
  final _searchCtrl = TextEditingController();
  final _authRepo = AuthRepository();
  _MemberFilter _filter = _MemberFilter.all;
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<UserModel> _applyFilters(List<UserModel> users) {
    var result = users;

    if (_filter != _MemberFilter.all) {
      result = result.where((u) {
        switch (_filter) {
          case _MemberFilter.active:
            return u.status == AppConstants.userStatusActive;
          case _MemberFilter.inactive:
            return u.status == AppConstants.userStatusInactive;
          case _MemberFilter.suspended:
            return u.status == AppConstants.userStatusSuspended;
          case _MemberFilter.all:
            return true;
        }
      }).toList();
    }

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      result = result
          .where((u) =>
              u.fullName.toLowerCase().contains(q) ||
              u.memberNumber.toLowerCase().contains(q) ||
              u.phone.contains(q) ||
              (u.email?.toLowerCase().contains(q) ?? false))
          .toList();
    }

    return result;
  }

  Future<void> _updateStatus(UserModel user, String newStatus) async {
    final messenger = ScaffoldMessenger.of(context);
    final errMsg = AppLocalizations.of(context).unknownError;
    try {
      await _authRepo.updateProfile(user.id, {'status': newStatus});
      messenger.showSnackBar(SnackBar(
        content: Text('${user.fullName} — statut mis à jour'),
        backgroundColor: AppColors.success,
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(errMsg),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _updateRole(UserModel user, String newRole) async {
    final messenger = ScaffoldMessenger.of(context);
    final errMsg = AppLocalizations.of(context).unknownError;
    try {
      await _authRepo.updateProfile(user.id, {'role': newRole});
      messenger.showSnackBar(SnackBar(
        content: Text('${user.fullName} — rôle mis à jour'),
        backgroundColor: AppColors.success,
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(errMsg),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<bool> _confirmDialog(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, color: AppColors.textDark)),
          content: Text(body,
              style: GoogleFonts.plusJakartaSans(color: AppColors.textGray)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary),
              child: Text(l.confirm,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  void _openMemberDetail(UserModel user) {
    final currentUser = ref.read(currentUserProfileProvider).valueOrNull;
    final isSuperAdmin =
        currentUser?.isSuperAdmin ?? false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemberDetailSheet(
        user: user,
        isSuperAdmin: isSuperAdmin,
        isCurrentUser: currentUser?.id == user.id,
        onStatusChange: (newStatus) async {
          final l = AppLocalizations.of(context);
          final nav = Navigator.of(context);
          final ok = await _confirmDialog(
            l.confirmStatusChange,
            '${user.fullName} → ${_statusLabel(newStatus)}',
          );
          if (!ok) return;
          nav.pop();
          await _updateStatus(user, newStatus);
        },
        onRoleChange: (newRole) async {
          final l = AppLocalizations.of(context);
          final nav = Navigator.of(context);
          final ok = await _confirmDialog(
            l.confirmRoleChange,
            '${user.fullName} → ${_roleLabel(newRole)}',
          );
          if (!ok) return;
          nav.pop();
          await _updateRole(user, newRole);
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final usersAsync = ref.watch(_allUsersProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(context, l, usersAsync),
          _buildSearchBar(l),
          _buildFilterChips(l),
          Expanded(child: _buildList(l, usersAsync)),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    AppLocalizations l,
    AsyncValue<List<UserModel>> usersAsync,
  ) {
    final total = usersAsync.valueOrNull?.length ?? 0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceMD,
        MediaQuery.of(context).padding.top + AppConstants.spaceSM,
        AppConstants.spaceMD,
        AppConstants.spaceMD,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: Text(
              l.membersManagement,
              style: GoogleFonts.playfairDisplay(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (total > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceMD, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Text(
                '$total',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Search bar ────────────────────────────────────────────

  Widget _buildSearchBar(AppLocalizations l) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMD,
        AppConstants.spaceMD,
        AppConstants.spaceMD,
        AppConstants.spaceSM,
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v.trim()),
        style: GoogleFonts.plusJakartaSans(
            fontSize: 14, color: AppColors.textDark),
        decoration: InputDecoration(
          hintText: l.searchMembers,
          hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: 14, color: AppColors.textGray),
          prefixIcon: const Icon(Icons.search_rounded,
              color: AppColors.textGray, size: 20),
          suffixIcon: _query.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.textGray, size: 18),
                )
              : null,
          filled: true,
          fillColor: AppColors.bg,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
                const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  // ── Filter chips ──────────────────────────────────────────

  Widget _buildFilterChips(AppLocalizations l) {
    final chips = [
      (_MemberFilter.all, l.allFilter),
      (_MemberFilter.active, l.activeFilter),
      (_MemberFilter.inactive, l.inactiveFilter),
      (_MemberFilter.suspended, l.suspendedFilter),
    ];

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMD,
        0,
        AppConstants.spaceMD,
        AppConstants.spaceMD,
      ),
      child: Row(
        children: chips.map((chip) {
          final selected = _filter == chip.$1;
          return Padding(
            padding: const EdgeInsets.only(right: AppConstants.spaceSM),
            child: GestureDetector(
              onTap: () => setState(() => _filter = chip.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceMD, vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary
                      : AppColors.bg,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : AppColors.border,
                  ),
                ),
                child: Text(
                  chip.$2,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? Colors.white
                        : AppColors.textGray,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── List ──────────────────────────────────────────────────

  Widget _buildList(
      AppLocalizations l, AsyncValue<List<UserModel>> usersAsync) {
    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) =>
          Center(child: Text(l.unknownError)),
      data: (users) {
        final filtered = _applyFilters(users);
        if (filtered.isEmpty) {
          return _EmptyState(message: l.noMembersFound);
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceMD,
            AppConstants.spaceMD,
            AppConstants.spaceMD,
            AppConstants.spaceXL,
          ),
          itemCount: filtered.length,
          itemBuilder: (_, i) => _MemberCard(
            user: filtered[i],
            onTap: () => _openMemberDetail(filtered[i]),
          ),
        );
      },
    );
  }
}

// ── Member Card ───────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;

  const _MemberCard({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
            _RoleAvatar(user: user, size: 46),
            const SizedBox(width: AppConstants.spaceMD),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.fullName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _RoleBadge(role: user.role),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.memberNumber,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.region.isNotEmpty
                              ? '${user.region} · ${user.department}'
                              : user.phone,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppColors.textGray,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _StatusDot(status: user.status),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppConstants.spaceXS),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textLight, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Member Detail Sheet ───────────────────────────────────────

class _MemberDetailSheet extends StatefulWidget {
  final UserModel user;
  final bool isSuperAdmin;
  final bool isCurrentUser;
  final Future<void> Function(String status) onStatusChange;
  final Future<void> Function(String role) onRoleChange;

  const _MemberDetailSheet({
    required this.user,
    required this.isSuperAdmin,
    required this.isCurrentUser,
    required this.onStatusChange,
    required this.onRoleChange,
  });

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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final u = widget.user;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, __) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppConstants.radiusXL)),
        ),
        child: Column(
          children: [
            // Drag handle
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
            // Identity header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spaceLG,
                0,
                AppConstants.spaceLG,
                AppConstants.spaceMD,
              ),
              child: Row(
                children: [
                  _RoleAvatar(user: u, size: 56),
                  const SizedBox(width: AppConstants.spaceMD),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.fullName,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          u.memberNumber,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _RoleBadge(role: u.role),
                            const SizedBox(width: AppConstants.spaceSM),
                            _StatusBadge(status: u.status),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Tabs
            Container(
              decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: TabBar(
                controller: _tabs,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textGray,
                indicatorColor: AppColors.primary,
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
                  _AdminInfoTab(
                    user: u,
                    l: l,
                    isSuperAdmin: widget.isSuperAdmin,
                    isCurrentUser: widget.isCurrentUser,
                    onStatusChange: widget.onStatusChange,
                    onRoleChange: widget.onRoleChange,
                  ),
                  _AdminContributionsTab(memberId: u.id, l: l),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Admin info tab ────────────────────────────────────────────

class _AdminInfoTab extends StatelessWidget {
  final UserModel user;
  final AppLocalizations l;
  final bool isSuperAdmin;
  final bool isCurrentUser;
  final Future<void> Function(String) onStatusChange;
  final Future<void> Function(String) onRoleChange;

  const _AdminInfoTab({
    required this.user,
    required this.l,
    required this.isSuperAdmin,
    required this.isCurrentUser,
    required this.onStatusChange,
    required this.onRoleChange,
  });

  @override
  Widget build(BuildContext context) {
    final u = user;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        AppConstants.spaceMD,
        AppConstants.spaceLG,
        AppConstants.spaceXL,
      ),
      children: [
        const _SectionTitle('Contact'),
        const SizedBox(height: AppConstants.spaceSM),
        _InfoRow(icon: Icons.phone_rounded, label: u.phone),
        if (u.email != null && u.email!.isNotEmpty) ...[
          const SizedBox(height: AppConstants.spaceSM),
          _InfoRow(icon: Icons.email_outlined, label: u.email!),
        ],
        const SizedBox(height: AppConstants.spaceMD),
        if (u.region.isNotEmpty || (u.city?.isNotEmpty ?? false)) ...[
          const _SectionTitle('Localisation'),
          const SizedBox(height: AppConstants.spaceSM),
          if (u.region.isNotEmpty)
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: '${u.region} — ${u.department}',
            ),
          if ((u.city?.isNotEmpty ?? false) ||
              (u.quarter?.isNotEmpty ?? false)) ...[
            const SizedBox(height: AppConstants.spaceSM),
            _InfoRow(
              icon: Icons.location_city_outlined,
              label: [
                if (u.city?.isNotEmpty ?? false) u.city!,
                if (u.quarter?.isNotEmpty ?? false) u.quarter!,
              ].join(' — '),
            ),
          ],
          const SizedBox(height: AppConstants.spaceMD),
        ],
        const _SectionTitle("Date d'adhésion"),
        const SizedBox(height: AppConstants.spaceSM),
        _InfoRow(
          icon: Icons.calendar_today_outlined,
          label: DateFormat('d MMMM yyyy', 'fr_FR')
              .format(u.createdAt.toDate()),
        ),
        if (!isCurrentUser) ...[
          const SizedBox(height: AppConstants.spaceLG),
          const Divider(color: AppColors.border),
          const SizedBox(height: AppConstants.spaceMD),
          _SectionTitle(
              l.confirmStatusChange.replaceAll('Confirmer le ', '')),
          const SizedBox(height: AppConstants.spaceMD),
          _buildStatusActions(context, l),
        ],
        if (isSuperAdmin && !isCurrentUser) ...[
          const SizedBox(height: AppConstants.spaceLG),
          const Divider(color: AppColors.border),
          const SizedBox(height: AppConstants.spaceMD),
          _SectionTitle(l.changeRoleAction),
          const SizedBox(height: AppConstants.spaceMD),
          _buildRoleActions(context),
        ],
      ],
    );
  }

  Widget _buildStatusActions(BuildContext context, AppLocalizations l) {
    final statuses = [
      (AppConstants.userStatusActive, l.activateAction,
          AppColors.success, Icons.check_circle_outline_rounded),
      (AppConstants.userStatusInactive, l.deactivateAction,
          AppColors.textGray, Icons.block_outlined),
      (AppConstants.userStatusSuspended, l.suspendAction,
          AppColors.error, Icons.pause_circle_outline_rounded),
    ];
    return Row(
      children: statuses.map((s) {
        final isCurrent = user.status == s.$1;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: AppConstants.spaceSM),
            child: GestureDetector(
              onTap: isCurrent ? null : () => onStatusChange(s.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                    vertical: AppConstants.spaceMD),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? s.$3.withValues(alpha: 0.12)
                      : AppColors.bg,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMD),
                  border: Border.all(
                    color: isCurrent ? s.$3 : AppColors.border,
                    width: isCurrent ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(s.$4,
                        color: isCurrent ? s.$3 : AppColors.textGray,
                        size: 20),
                    const SizedBox(height: 4),
                    Text(
                      s.$2,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isCurrent ? s.$3 : AppColors.textGray,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRoleActions(BuildContext context) {
    final roles = [
      (AppConstants.roleMember, 'Membre', AppColors.memberColor),
      (AppConstants.roleFocal, 'Focal', AppColors.focalColor),
      (AppConstants.roleAdmin, 'Admin', AppColors.adminColor),
      (AppConstants.roleSuperAdmin, 'Super Admin', AppColors.superColor),
    ];
    return Wrap(
      spacing: AppConstants.spaceSM,
      runSpacing: AppConstants.spaceSM,
      children: roles.map((r) {
        final isCurrent = user.role == r.$1;
        return GestureDetector(
          onTap: isCurrent ? null : () => onRoleChange(r.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceMD,
                vertical: AppConstants.spaceSM),
            decoration: BoxDecoration(
              color: isCurrent
                  ? r.$3.withValues(alpha: 0.12)
                  : AppColors.bg,
              borderRadius:
                  BorderRadius.circular(AppConstants.radiusFull),
              border: Border.all(
                color: isCurrent ? r.$3 : AppColors.border,
                width: isCurrent ? 1.5 : 1,
              ),
            ),
            child: Text(
              r.$2,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isCurrent ? r.$3 : AppColors.textGray,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Admin contributions tab ───────────────────────────────────

class _AdminContributionsTab extends StatelessWidget {
  final String memberId;
  final AppLocalizations l;

  const _AdminContributionsTab(
      {required this.memberId, required this.l});

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
        final remaining = (AppConstants.amountAnnual - thisYearPaid)
            .clamp(0, AppConstants.amountAnnual);

        if (contributions.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(AppConstants.spaceLG),
            children: [
              _AdminProgressCard(
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
            _AdminProgressCard(
              year: year,
              progress: progress,
              contributed: thisYearPaid,
              remaining: remaining,
              l: l,
            ),
            const SizedBox(height: AppConstants.spaceMD),
            _AdminAllTimeSummary(
                total: allTimeTotal, count: contributions.length, l: l),
            const SizedBox(height: AppConstants.spaceLG),
            Padding(
              padding:
                  const EdgeInsets.only(bottom: AppConstants.spaceSM),
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
              _AdminContributionRow(contribution: c, l: l),
          ],
        );
      },
    );
  }
}

class _AdminProgressCard extends StatelessWidget {
  final String year;
  final double progress;
  final int contributed;
  final int remaining;
  final AppLocalizations l;

  const _AdminProgressCard({
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
            ? AppColors.primary
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
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

class _AdminAllTimeSummary extends StatelessWidget {
  final int total;
  final int count;
  final AppLocalizations l;

  const _AdminAllTimeSummary(
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
          colors: [AppColors.primary, AppColors.primaryDark],
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

class _AdminContributionRow extends StatelessWidget {
  final ContributionModel contribution;
  final AppLocalizations l;

  const _AdminContributionRow(
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
      margin: const EdgeInsets.only(bottom: AppConstants.spaceSM),
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

// ── Helper widgets ────────────────────────────────────────────

class _RoleAvatar extends StatelessWidget {
  final UserModel user;
  final double size;
  const _RoleAvatar({required this.user, required this.size});

  @override
  Widget build(BuildContext context) {
    final color = _roleColor(user.role);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            user.initials,
            style: GoogleFonts.plusJakartaSans(
              fontSize: size * 0.32,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        if (user.isSuperContributor)
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              width: size * 0.38,
              height: size * 0.38,
              decoration: const BoxDecoration(
                color: AppColors.gold,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x44C49A00),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                Icons.workspace_premium_rounded,
                color: Colors.white,
                size: size * 0.21,
              ),
            ),
          ),
      ],
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final color = _roleColor(role);
    final label = _roleLabel(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = _statusInfo(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, _) = _statusInfo(status);
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.plusJakartaSans(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.textGray,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: AppConstants.spaceSM),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.group_off_outlined,
              size: 56, color: AppColors.border),
          const SizedBox(height: AppConstants.spaceMD),
          Text(
            message,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, color: AppColors.textGray),
          ),
        ],
      ),
    );
  }
}

// ── Pure helpers ──────────────────────────────────────────────

Color _roleColor(String role) {
  switch (role) {
    case AppConstants.roleFocal:
      return AppColors.focalColor;
    case AppConstants.roleAdmin:
      return AppColors.adminColor;
    case AppConstants.roleSuperAdmin:
      return AppColors.superColor;
    default:
      return AppColors.memberColor;
  }
}

String _roleLabel(String role) {
  switch (role) {
    case AppConstants.roleFocal:
      return 'Focal';
    case AppConstants.roleAdmin:
      return 'Admin';
    case AppConstants.roleSuperAdmin:
      return 'Super Admin';
    default:
      return 'Membre';
  }
}

String _statusLabel(String status) {
  switch (status) {
    case AppConstants.userStatusInactive:
      return 'Inactif';
    case AppConstants.userStatusSuspended:
      return 'Suspendu';
    default:
      return 'Actif';
  }
}

(Color, String) _statusInfo(String status) {
  switch (status) {
    case AppConstants.userStatusInactive:
      return (AppColors.textGray, 'Inactif');
    case AppConstants.userStatusSuspended:
      return (AppColors.error, 'Suspendu');
    default:
      return (AppColors.success, 'Actif');
  }
}
