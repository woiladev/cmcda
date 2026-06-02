import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/notification_model.dart';

// ── Target audience ───────────────────────────────────────────

enum _Target {
  activeMembers,
  focal,
  admins;

  String label(AppLocalizations l) => switch (this) {
        activeMembers => l.targetActiveMembers,
        focal => l.targetFocal,
        admins => l.targetAdmins,
      };

  String get icon => switch (this) {
        activeMembers => '👥',
        focal => '📋',
        admins => '🛡️',
      };
}

// ── Sheet entry-point ─────────────────────────────────────────

Future<void> showSendNotificationSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SendNotificationSheet(),
  );
}

// ── Sheet widget ──────────────────────────────────────────────

class _SendNotificationSheet extends StatefulWidget {
  const _SendNotificationSheet();

  @override
  State<_SendNotificationSheet> createState() =>
      _SendNotificationSheetState();
}

class _SendNotificationSheetState extends State<_SendNotificationSheet> {
  _Target _target = _Target.activeMembers;
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  // ── Fetch target user IDs ─────────────────────────────────

  Future<List<String>> _fetchTargetUserIds() async {
    final db = FirebaseFirestore.instance;
    QuerySnapshot snap;

    switch (_target) {
      case _Target.activeMembers:
        snap = await db
            .collection(AppConstants.usersCollection)
            .where('role', isEqualTo: AppConstants.roleMember)
            .where('status', isEqualTo: AppConstants.userStatusActive)
            .get();
      case _Target.focal:
        snap = await db
            .collection(AppConstants.usersCollection)
            .where('role', isEqualTo: AppConstants.roleFocal)
            .get();
      case _Target.admins:
        snap = await db
            .collection(AppConstants.usersCollection)
            .where('role', whereIn: [
          AppConstants.roleAdmin,
          AppConstants.roleSuperAdmin,
        ]).get();
    }

    return snap.docs.map((d) => d.id).toList();
  }

  // ── Send ──────────────────────────────────────────────────

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final l = AppLocalizations.of(context);
    setState(() => _sending = true);

    try {
      final userIds = await _fetchTargetUserIds();

      if (userIds.isEmpty) {
        _showSnack(l.noRecipientsFound, isError: true);
        return;
      }

      // Batch-create notification docs (500 per Firestore batch limit)
      final db = FirebaseFirestore.instance;
      final title = _titleCtrl.text.trim();
      final body = _messageCtrl.text.trim();
      final now = Timestamp.now();

      for (var i = 0; i < userIds.length; i += 400) {
        final chunk = userIds.sublist(
            i, i + 400 > userIds.length ? userIds.length : i + 400);
        final batch = db.batch();
        for (final uid in chunk) {
          final ref =
              db.collection(AppConstants.notificationsCollection).doc();
          batch.set(ref, {
            'userId': uid,
            'type': NotificationModel.typeAdminAlert,
            'title': title,
            'body': body,
            'read': false,
            'data': {},
            'createdAt': now,
          });
        }
        await batch.commit();
      }

      if (mounted) {
        Navigator.pop(context);
        _showSnack(l.notificationsSent(userIds.length));
      }
    } catch (_) {
      if (mounted) _showSnack(l.sendError, isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500)),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXL)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        AppConstants.spaceMD,
        AppConstants.spaceLG,
        AppConstants.spaceLG + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceLG),

              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMD),
                    ),
                    child: const Icon(Icons.notifications_outlined,
                        color: AppColors.warning, size: 20),
                  ),
                  const SizedBox(width: AppConstants.spaceMD),
                  Text(
                    l.sendNotificationTitle,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceLG),

              // Target section
              _SectionLabel(l.recipientsLabel),
              const SizedBox(height: AppConstants.spaceSM),
              Wrap(
                spacing: AppConstants.spaceSM,
                children: _Target.values.map((t) {
                  final selected = _target == t;
                  return GestureDetector(
                    onTap: () => setState(() => _target = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spaceMD,
                          vertical: AppConstants.spaceSM),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : AppColors.bg,
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusFull),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : AppColors.border,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.icon,
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(
                            t.label(l),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppConstants.spaceLG),

              // Title field
              _SectionLabel(l.titleLabel),
              const SizedBox(height: AppConstants.spaceSM),
              TextFormField(
                controller: _titleCtrl,
                maxLength: 80,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, color: AppColors.textDark),
                decoration: _inputDeco(l.titlePlaceholder),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l.titleRequired
                    : null,
              ),
              const SizedBox(height: AppConstants.spaceMD),

              // Message field
              _SectionLabel(l.messageLabel),
              const SizedBox(height: AppConstants.spaceSM),
              TextFormField(
                controller: _messageCtrl,
                maxLength: 300,
                maxLines: 4,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, color: AppColors.textDark),
                decoration: _inputDeco(l.messagePlaceholder),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l.messageRequired
                    : null,
              ),
              const SizedBox(height: AppConstants.spaceLG),

              // Send button
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _sending ? null : _send,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMD),
                    ),
                  ),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    _sending ? l.sendingInProgress : l.sendBtn,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13, color: AppColors.textLight),
        filled: true,
        fillColor: AppColors.bg,
        counterStyle:
            GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight),
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
              const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          borderSide:
              const BorderSide(color: AppColors.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMD,
          vertical: AppConstants.spaceMD,
        ),
      );
}

// ── Section label ─────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.textGray,
        letterSpacing: 0.8,
      ),
    );
  }
}
