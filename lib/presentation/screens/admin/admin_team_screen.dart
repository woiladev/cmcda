import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';

final _teamUsersProvider = StreamProvider.autoDispose<List<UserModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(AppConstants.usersCollection)
      .orderBy('createdAt', descending: true)
      .limit(500)
      .snapshots()
      .map((s) => s.docs.map((d) => UserModel.fromFirestore(d)).toList());
});

class AdminTeamScreen extends ConsumerStatefulWidget {
  const AdminTeamScreen({super.key});

  @override
  ConsumerState<AdminTeamScreen> createState() => _AdminTeamScreenState();
}

class _AdminTeamScreenState extends ConsumerState<AdminTeamScreen> {
  final _authRepo = AuthRepository();

  Future<void> _changeRole(UserModel user, String newRole) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _confirm(
      l.confirmRoleChange,
      '${user.fullName} → ${l.roleName(newRole)}',
    );
    if (!ok) return;
    try {
      await _authRepo.setUserRole(user.id, newRole);
      messenger.showSnackBar(SnackBar(
        content: Text(l.memberRoleUpdated(user.fullName)),
        backgroundColor: AppColors.success,
      ));
    } on FirebaseFunctionsException catch (e) {
      final msg = e.code == 'failed-precondition'
          ? l.cannotRemoveLastSuperAdmin
          : l.unknownError;
      messenger.showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.error));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(l.unknownError), backgroundColor: AppColors.error));
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final l = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, color: AppColors.textDark)),
        content: Text(body,
            style: GoogleFonts.plusJakartaSans(color: AppColors.textGray)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(l.confirm, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _openPromoteSheet(List<UserModel> candidates) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PromoteSheet(
        candidates: candidates,
        onPromote: (user) {
          Navigator.pop(context);
          _changeRole(user, AppConstants.roleAdmin);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final usersAsync = ref.watch(_teamUsersProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(
          l.manageAdmins,
          style: GoogleFonts.playfairDisplay(
              fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      floatingActionButton: usersAsync.maybeWhen(
        data: (users) {
          final candidates = users
              .where((u) => !u.hasAdminAccess)
              .toList();
          return FloatingActionButton.extended(
            onPressed: () => _openPromoteSheet(candidates),
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
            label: Text(l.addAdmin,
                style: GoogleFonts.plusJakartaSans(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          );
        },
        orElse: () => null,
      ),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(l.unknownError)),
        data: (users) {
          final admins = users.where((u) => u.hasAdminAccess).toList()
            ..sort((a, b) => a.isSuperAdmin == b.isSuperAdmin
                ? 0
                : (a.isSuperAdmin ? -1 : 1));
          if (admins.isEmpty) {
            return Center(
              child: Text(l.noAdminsFound,
                  style: GoogleFonts.plusJakartaSans(color: AppColors.textGray)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppConstants.spaceMD),
            itemCount: admins.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppConstants.spaceSM),
            itemBuilder: (_, i) => _AdminCard(
              user: admins[i],
              onChangeRole: (role) => _changeRole(admins[i], role),
            ),
          );
        },
      ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  final UserModel user;
  final ValueChanged<String> onChangeRole;

  const _AdminCard({required this.user, required this.onChangeRole});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = _roleColor(user.role);
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Text(user.initials,
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700, color: color)),
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.fullName,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark)),
                const SizedBox(height: 2),
                Text(l.roleName(user.role),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: color, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textGray),
            onSelected: onChangeRole,
            itemBuilder: (_) => [
              if (!user.isSuperAdmin)
                PopupMenuItem(
                  value: AppConstants.roleSuperAdmin,
                  child: Text('${l.promoteAction} → ${l.superAdmin}'),
                ),
              if (user.isSuperAdmin)
                PopupMenuItem(
                  value: AppConstants.roleAdmin,
                  child: Text('${l.demoteAction} → ${l.admin}'),
                ),
              PopupMenuItem(
                value: AppConstants.roleMember,
                child: Text('${l.demoteAction} → ${l.roleName(AppConstants.roleMember)}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PromoteSheet extends StatefulWidget {
  final List<UserModel> candidates;
  final ValueChanged<UserModel> onPromote;

  const _PromoteSheet({required this.candidates, required this.onPromote});

  @override
  State<_PromoteSheet> createState() => _PromoteSheetState();
}

class _PromoteSheetState extends State<_PromoteSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final q = _query.toLowerCase();
    final filtered = q.isEmpty
        ? widget.candidates
        : widget.candidates
            .where((u) =>
                u.fullName.toLowerCase().contains(q) ||
                u.memberNumber.toLowerCase().contains(q) ||
                u.phone.contains(q))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(AppConstants.spaceLG),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: AppConstants.spaceMD),
            Text(l.selectUserToPromote,
                style: GoogleFonts.playfairDisplay(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppConstants.spaceMD),
            TextField(
              decoration: InputDecoration(
                hintText: l.search,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppConstants.spaceMD),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(l.noMembersFound,
                          style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textGray)))
                  : ListView.separated(
                      controller: scrollCtrl,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppColors.border),
                      itemBuilder: (_, i) {
                        final u = filtered[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor:
                                AppColors.memberColor.withValues(alpha: 0.12),
                            child: Text(u.initials,
                                style: GoogleFonts.plusJakartaSans(
                                    color: AppColors.memberColor,
                                    fontWeight: FontWeight.w700)),
                          ),
                          title: Text(u.fullName,
                              style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(u.memberNumber,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12, color: AppColors.textGray)),
                          trailing: const Icon(Icons.add_circle_outline_rounded,
                              color: AppColors.primary),
                          onTap: () => widget.onPromote(u),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

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
