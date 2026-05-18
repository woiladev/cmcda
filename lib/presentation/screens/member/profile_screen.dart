import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/language_service.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../widgets/common/payment_method_icon.dart';

// ── Providers ────────────────────────────────────────────────
final _authRepo = AuthRepository();

// ══════════════════════════════════════════════════════════════
// PROFILE SCREEN
// ══════════════════════════════════════════════════════════════

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _notificationsEnabled = true;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final userAsync = ref.watch(currentUserProfileProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: userAsync.when(
          loading: () => const _LoadingBody(),
          error: (_, __) => _ErrorBody(onRetry: () => ref.invalidate(currentUserProfileProvider)),
          data: (user) {
            if (user == null) return _ErrorBody(onRetry: () => ref.invalidate(currentUserProfileProvider));
            return _buildBody(context, l, user);
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l, UserModel user) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: bottomPad + AppConstants.spaceLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopBar(context, l, user, topPad),
          const SizedBox(height: AppConstants.spaceLG),
          _buildAvatarSection(context, l, user),
          const SizedBox(height: AppConstants.spaceLG),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceLG),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPersonalInfoSection(context, l, user),
                const SizedBox(height: AppConstants.spaceLG),
                _buildMembershipSection(context, l, user),
                const SizedBox(height: AppConstants.spaceLG),
                _buildPreferredPaymentSection(context, l, user),
                const SizedBox(height: AppConstants.spaceLG),
                _buildLanguageSection(context, l, user),
                const SizedBox(height: AppConstants.spaceLG),
                _buildSettingsSection(context, l),
                const SizedBox(height: AppConstants.spaceXL),
                _buildLogoutButton(context, l),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context, AppLocalizations l, UserModel user, double topPad) {
    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        topPad + AppConstants.spaceLG,
        AppConstants.spaceLG,
        AppConstants.spaceMD,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            l.profile,
            style: GoogleFonts.playfairDisplay(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          GestureDetector(
            onTap: () => _showEditSheet(context, l, user),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0F0D2818),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.edit_rounded,
                color: AppColors.primary,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Avatar section ───────────────────────────────────────────

  Widget _buildAvatarSection(BuildContext context, AppLocalizations l, UserModel user) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Outer ring
            Container(
              width: 124,
              height: 124,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  width: 3,
                ),
              ),
              child: ClipOval(
                child: user.avatarUrl != null
                    ? Image.network(
                        user.avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _InitialsAvatar(initials: user.initials, size: 118),
                      )
                    : _InitialsAvatar(initials: user.initials, size: 118),
              ),
            ),
            // Super contributor crown top-right
            if (user.isSuperContributor)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x55C49A00),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            // Status badge bottom-right
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: user.isActive ? AppColors.primary : AppColors.warning,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  user.isActive ? l.memberActive : l.memberLateStatus,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceMD),
        Text(
          user.fullName,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppConstants.spaceXS),
        Text(
          '${l.memberNumber} #${user.memberNumber}',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: AppColors.textGray,
          ),
          textAlign: TextAlign.center,
        ),
        if (user.isSuperContributor) ...[
          const SizedBox(height: AppConstants.spaceSM),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF5C842), Color(0xFFE0A800)],
              ),
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44C49A00),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: Colors.white, size: 14),
                const SizedBox(width: 5),
                Text(
                  l.superContributor,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Personal info section ────────────────────────────────────

  Widget _buildPersonalInfoSection(BuildContext context, AppLocalizations l, UserModel user) {
    return _SectionCard(
      title: l.personalInfo,
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.person_outline_rounded,
            label: l.fullName,
            value: user.fullName,
          ),
          _Divider(),
          _InfoRow(
            icon: Icons.mail_outline_rounded,
            label: l.email,
            value: user.email?.isNotEmpty == true ? user.email! : '—',
          ),
          _Divider(),
          _InfoRow(
            icon: Icons.phone_iphone_rounded,
            label: l.phone,
            value: user.phone.isNotEmpty ? user.phone : '—',
          ),
          if (user.region.isNotEmpty) ...[
            _Divider(),
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: l.region,
              value: '${user.region}${user.department.isNotEmpty ? ' · ${user.department}' : ''}',
            ),
          ],
          if ((user.city?.isNotEmpty ?? false) || (user.quarter?.isNotEmpty ?? false)) ...[
            _Divider(),
            _InfoRow(
              icon: Icons.location_city_outlined,
              label: l.cityQuarter,
              value: [
                if (user.city?.isNotEmpty ?? false) user.city!,
                if (user.quarter?.isNotEmpty ?? false) user.quarter!,
              ].join(' · '),
            ),
          ],
        ],
      ),
    );
  }

  // ── Membership section ───────────────────────────────────────

  Widget _buildMembershipSection(BuildContext context, AppLocalizations l, UserModel user) {
    final since = user.createdAt.toDate();
    final sinceFormatted = DateFormat('MMMM yyyy', 'fr_FR').format(since);
    final cap = sinceFormatted[0].toUpperCase() + sinceFormatted.substring(1);

    return _SectionCard(
      title: l.membershipStatus,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.currentLevel,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textGray,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceXS),
                  Text(
                    user.isActive ? l.memberActive : l.memberLateStatus,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: user.isActive ? AppColors.primary : AppColors.warning,
                    ),
                  ),
                ],
              ),
              Icon(
                user.isActive
                    ? Icons.verified_rounded
                    : Icons.warning_amber_rounded,
                color: user.isActive ? AppColors.primary : AppColors.warning,
                size: 32,
              ),
            ],
          ),
          _Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.memberSinceLabel,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textGray,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceXS),
                  Text(
                    cap,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceMD,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSM),
                ),
                child: Text(
                  l.autoRenewal,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Preferred payment section ────────────────────────────────

  Widget _buildPreferredPaymentSection(BuildContext context, AppLocalizations l, UserModel user) {
    final opts = _paymentOptions(l);
    return _SectionCard(
      title: l.paymentMethods,
      child: Column(
        children: [
          for (int i = 0; i < opts.length; i++) ...[
            _PaymentOptionRow(
              methodKey: opts[i].key,
              label: opts[i].label,
              selected: user.preferredPayment == opts[i].key,
              onTap: () => _changePreferredPayment(user, opts[i].key, l),
            ),
            if (i < opts.length - 1) _Divider(),
          ],
        ],
      ),
    );
  }

  List<_PaymentOpt> _paymentOptions(AppLocalizations l) => [
    _PaymentOpt(key: AppConstants.paymentMtnMomo, label: l.mtnMomo),
    _PaymentOpt(key: AppConstants.paymentOrangeMoney, label: l.orangeMoney),
    _PaymentOpt(key: AppConstants.paymentCash, label: l.cash),
    _PaymentOpt(key: AppConstants.paymentBankTransfer, label: l.bankTransfer),
  ];

  Future<void> _changePreferredPayment(UserModel user, String key, AppLocalizations l) async {
    if (user.preferredPayment == key) return;
    try {
      await _authRepo.updateProfile(user.id, {'preferredPayment': key});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.error), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // ── Language section ─────────────────────────────────────────

  Widget _buildLanguageSection(BuildContext context, AppLocalizations l, UserModel user) {
    return _SectionCard(
      title: l.languageDisplay,
      child: Row(
        children: [
          _LangPill(code: 'fr', flag: '🇫🇷', label: 'Français', active: user.language == 'fr',
              onTap: () => _changeLanguage(user, 'fr')),
          const SizedBox(width: AppConstants.spaceSM),
          _LangPill(code: 'en', flag: '🇬🇧', label: 'English', active: user.language == 'en',
              onTap: () => _changeLanguage(user, 'en')),
          const SizedBox(width: AppConstants.spaceSM),
          _LangPill(code: 'ar', flag: '🇸🇦', label: 'عربي', active: user.language == 'ar',
              onTap: () => _changeLanguage(user, 'ar')),
        ],
      ),
    );
  }

  Future<void> _changeLanguage(UserModel user, String code) async {
    if (user.language == code) return;
    await ref.read(languageProvider.notifier).changeLanguage(code);
    await _authRepo.updateLanguage(user.id, code);
  }

  // ── Settings section ─────────────────────────────────────────

  Widget _buildSettingsSection(BuildContext context, AppLocalizations l) {
    return _SectionCard(
      title: l.settings,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppConstants.radiusSM),
                    ),
                    child: const Icon(Icons.notifications_outlined, color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: AppConstants.spaceMD),
                  Text(
                    l.pushNotifications,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              Switch(
                value: _notificationsEnabled,
                onChanged: (v) => setState(() => _notificationsEnabled = v),
                activeThumbColor: AppColors.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          _Divider(),
          GestureDetector(
            onTap: () {},
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppConstants.radiusSM),
                      ),
                      child: const Icon(Icons.shield_outlined, color: AppColors.primary, size: 18),
                    ),
                    const SizedBox(width: AppConstants.spaceMD),
                    Text(
                      l.privacyPolicy,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textGray),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Logout button ────────────────────────────────────────────

  Widget _buildLogoutButton(BuildContext context, AppLocalizations l) {
    return SizedBox(
      height: 54,
      child: OutlinedButton.icon(
        onPressed: () => _confirmLogout(context, l),
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: Text(l.logout),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────

  void _confirmLogout(BuildContext context, AppLocalizations l) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        ),
        title: Text(
          l.logoutConfirmTitle,
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.textDark,
          ),
        ),
        content: Text(
          l.logoutConfirmMsg,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: AppColors.textMid,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _authRepo.signOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text(l.logout),
          ),
        ],
      ),
    );
  }

  void _showEditSheet(BuildContext context, AppLocalizations l, UserModel user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(user: user, l: l),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// EDIT PROFILE BOTTOM SHEET
// ══════════════════════════════════════════════════════════════

class _EditProfileSheet extends ConsumerStatefulWidget {
  final UserModel user;
  final AppLocalizations l;

  const _EditProfileSheet({required this.user, required this.l});

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _regionCtrl;
  late final TextEditingController _departmentCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _quarterCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _firstNameCtrl = TextEditingController(text: widget.user.firstName);
    _lastNameCtrl = TextEditingController(text: widget.user.lastName);
    _emailCtrl = TextEditingController(text: widget.user.email ?? '');
    _regionCtrl = TextEditingController(text: widget.user.region);
    _departmentCtrl = TextEditingController(text: widget.user.department);
    _cityCtrl = TextEditingController(text: widget.user.city ?? '');
    _quarterCtrl = TextEditingController(text: widget.user.quarter ?? '');
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _regionCtrl.dispose();
    _departmentCtrl.dispose();
    _cityCtrl.dispose();
    _quarterCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final city = _cityCtrl.text.trim();
      final quarter = _quarterCtrl.text.trim();
      await AuthRepository().updateProfile(widget.user.id, {
        'firstName': _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim(),
        if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
        'region': _regionCtrl.text.trim(),
        'department': _departmentCtrl.text.trim(),
        if (city.isNotEmpty) 'city': city,
        if (quarter.isNotEmpty) 'quarter': quarter,
        'updatedAt': Timestamp.now(),
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.l.profileUpdated),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.l.error), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusXL)),
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
                      prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.primary),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? l.fieldRequired : null,
                  ),
                ),
                const SizedBox(width: AppConstants.spaceMD),
                Expanded(
                  child: TextFormField(
                    controller: _lastNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: l.lastName,
                      prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.primary),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? l.fieldRequired : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceMD),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: '${l.email} (${l.optional})',
                prefixIcon: const Icon(Icons.mail_outline_rounded, color: AppColors.primary),
              ),
              validator: (v) {
                if (v != null && v.trim().isNotEmpty) {
                  if (!v.contains('@') || !v.contains('.')) return l.invalidEmail;
                }
                return null;
              },
            ),
            const SizedBox(height: AppConstants.spaceMD),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _regionCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: l.region,
                      prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: AppConstants.spaceMD),
                Expanded(
                  child: TextFormField(
                    controller: _departmentCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: l.department,
                      prefixIcon: const Icon(Icons.map_outlined, color: AppColors.primary),
                    ),
                  ),
                ),
              ],
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
                      prefixIcon: const Icon(Icons.location_city_outlined, color: AppColors.primary),
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
                      prefixIcon: const Icon(Icons.holiday_village_outlined, color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceLG),
            SizedBox(
              height: 54,
              child: _isSaving
                  ? _SavingButton()
                  : ElevatedButton(
                      onPressed: _save,
                      child: Text(l.saveChanges),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// REUSABLE SUB-WIDGETS
// ══════════════════════════════════════════════════════════════

class _InitialsAvatar extends StatelessWidget {
  final String initials;
  final double size;
  const _InitialsAvatar({required this.initials, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: AppColors.primary,
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.plusJakartaSans(
            fontSize: size * 0.32,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: AppConstants.spaceMD),
        Container(
          padding: const EdgeInsets.all(AppConstants.spaceMD),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusLG),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F0D2818),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppConstants.radiusSM),
          ),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: AppConstants.spaceMD),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textGray,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaymentOptionRow extends StatelessWidget {
  final String methodKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PaymentOptionRow({
    required this.methodKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (selected ? AppColors.primary : AppColors.textGray).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppConstants.radiusSM),
            ),
            child: paymentMethodIcon(
              methodKey,
              size: 18,
              color: selected ? AppColors.primary : AppColors.textGray,
            ),
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.textDark,
              ),
            ),
          ),
          if (selected)
            Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 13),
            )
          else
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _LangPill extends StatelessWidget {
  final String code;
  final String flag;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _LangPill({
    required this.code,
    required this.flag,
    required this.label,
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
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.bg,
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
              width: active ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(flag, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AppColors.textGray,
                ),
                textAlign: TextAlign.center,
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

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppConstants.spaceMD),
        child: Divider(height: 1, color: AppColors.border),
      );
}

class _SavingButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorBody({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
          const SizedBox(height: AppConstants.spaceMD),
          Text(l.unknownError, style: GoogleFonts.plusJakartaSans(color: AppColors.textMid)),
          const SizedBox(height: AppConstants.spaceMD),
          TextButton(onPressed: onRetry, child: Text(l.retry)),
        ],
      ),
    );
  }
}

// ── Data helpers ─────────────────────────────────────────────

class _PaymentOpt {
  final String key;
  final String label;
  const _PaymentOpt({required this.key, required this.label});
}
