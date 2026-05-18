import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/focal_report_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/contribution_repository.dart';
import '../../../data/repositories/focal_report_repository.dart';
import 'focal_providers.dart';

// ── Colors ────────────────────────────────────────────────────

const _focalLight = Color(0xFF26A8F3);
const _focalDark = Color(0xFF0A5F8C);

// ── Provider ──────────────────────────────────────────────────

// Providers are defined in focal_providers.dart

// ── Screen ────────────────────────────────────────────────────

class FocalDashboardScreen extends ConsumerStatefulWidget {
  const FocalDashboardScreen({super.key});

  @override
  ConsumerState<FocalDashboardScreen> createState() =>
      _FocalDashboardScreenState();
}

class _FocalDashboardScreenState extends ConsumerState<FocalDashboardScreen> {
  final _repo = FocalReportRepository();
  String? _selectedStatus; // null = all statuses

  // ── Report actions ────────────────────────────────────────

  Future<void> _createReport(UserModel user) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewReportSheet(
        focalId: user.id,
        focalName: user.fullName,
        defaultLocation: user.focalZone ?? user.region,
        onCreated: (msg) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(msg),
                backgroundColor: AppColors.success),
          );
        },
      ),
    );
  }

  Future<void> _submitReport(FocalReportModel report) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final lc = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(lc.submitConfirm,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, color: AppColors.textDark)),
          content: Text(lc.submitConfirmBody,
              style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textGray, fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(lc.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _focalLight),
              child: Text(lc.submitReport,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final successMsg = l.reportSubmitted;
    final errMsg = l.unknownError;
    try {
      await _repo.submitReport(report.id);
      NotificationService.instance.notifyFocalReport(
        focalName: report.focalName,
        reportId: report.id,
      ).ignore();
      messenger.showSnackBar(SnackBar(
        content: Text(successMsg),
        backgroundColor: AppColors.success,
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(errMsg),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _shareReport(FocalReportModel report) async {
    final text = AppUtils.generateWhatsAppReport(report);
    final encoded = Uri.encodeComponent(text);
    final url = Uri.parse('whatsapp://send?text=$encoded');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).copiedToClipboard),
          backgroundColor: AppColors.info,
        ));
      }
    }
  }

  void _openReportDetail(FocalReportModel report) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReportDetailSheet(
        report: report,
        onSubmit: () {
          Navigator.of(context).pop();
          _submitReport(report);
        },
        onShare: () => _shareReport(report),
      ),
    );
  }

  void _openProfileSheet(UserModel user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FocalProfileSheet(user: user),
    );
  }

  Future<void> _registerMember(UserModel focalUser) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RegisterMemberSheet(
        focalId: focalUser.id,
        defaultZone: focalUser.focalZone ?? focalUser.region,
        onRegistered: (memberNumber) {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) =>
                _MemberNumberDialog(memberNumber: memberNumber),
          );
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final profileAsync = ref.watch(currentUserProfileProvider);

    return profileAsync.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (_, __) =>
          Scaffold(body: Center(child: Text(l.unknownError))),
      data: (user) {
        if (user == null) {
          return Scaffold(body: Center(child: Text(l.unknownError)));
        }
        final reportsAsync =
            ref.watch(focalReportsProvider(user.id));
        return _buildScaffold(context, l, user, reportsAsync);
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    AppLocalizations l,
    UserModel user,
    AsyncValue<List<FocalReportModel>> reportsAsync,
  ) {
    final reports = reportsAsync.valueOrNull ?? [];
    final unreadCount =
        ref.watch(focalUnreadCountProvider(user.id)).valueOrNull ?? 0;
    final now = DateTime.now();

    final monthSessionCount = reports.where((r) {
      final d = r.createdAt.toDate();
      return d.year == now.year && d.month == now.month;
    }).length;

    final monthTotal =
        ref.watch(focalMonthCollectedProvider(user.id)).valueOrNull ?? 0;
    final memberCount =
        ref.watch(focalMembersProvider(user.id)).valueOrNull?.length ?? 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _buildHeader(
                context, l, user,
                monthTotal, memberCount, monthSessionCount,
                unreadCount,
              ),
            ),
            SliverToBoxAdapter(
              child: _buildQuickActions(context, l, user),
            ),
            SliverToBoxAdapter(
              child: _buildReportsSection(
                  context, l, user, reports, reportsAsync),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppConstants.spaceXL),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    AppLocalizations l,
    UserModel user,
    int monthTotal,
    int monthMembers,
    int monthSessionCount,
    int unreadCount,
  ) {
    final statusBarH = MediaQuery.of(context).padding.top;
    final zone = (user.focalZone?.isNotEmpty == true)
        ? user.focalZone!
        : (user.region.isNotEmpty ? user.region : '—');

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
          // ── Top row: identity + notification bell
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar (tappable → profile sheet)
              GestureDetector(
                onTap: () => _openProfileSheet(user),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    user.initials,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spaceMD),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l.welcome} 👋',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
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
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            color: Colors.white60, size: 12),
                        const SizedBox(width: 2),
                        Text(
                          zone,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // FOCAL badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4)),
                ),
                child: Text(
                  l.focalBadge,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spaceSM),
              // Switch to member space
              Tooltip(
                message: l.myMemberSpace,
                child: GestureDetector(
                  onTap: () {
                    ref.read(viewingAsMemberProvider.notifier).state = true;
                    context.push(AppRoutes.dashboard);
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.switch_account_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spaceSM),
              // Notification bell with unread badge
              GestureDetector(
                onTap: () => context.go(AppRoutes.focalNotifications),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_outlined,
                          color: Colors.white, size: 20),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: 1,
                        top: 1,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _focalDark, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceLG),
          // ── Glass stats card
          Container(
            padding: const EdgeInsets.all(AppConstants.spaceLG),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius:
                  BorderRadius.circular(AppConstants.radiusLG),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _GlassStat(
                    label: l.totalCollectedLabel,
                    value: monthTotal > 0
                        ? AppUtils.formatAmount(monthTotal)
                            .replaceAll(' FCFA', '')
                        : '0',
                    suffix: 'FCFA',
                  ),
                ),
                _VerticalDivider(),
                Expanded(
                  child: _GlassStat(
                    label: l.myMembers,
                    value: monthMembers.toString(),
                  ),
                ),
                _VerticalDivider(),
                Expanded(
                  child: _GlassStat(
                    label: l.thisMonthSessions,
                    value: monthSessionCount.toString(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick actions ──────────────────────────────────────────

  Widget _buildQuickActions(
      BuildContext context, AppLocalizations l, UserModel user) {
    final actions = [
      (
        Icons.payments_outlined,
        l.recordPayment,
        AppColors.success,
        () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _FocalQuickPaymentSheet(focalId: user.id),
        ),
      ),
      (
        Icons.add_chart_rounded,
        l.myReports,
        AppColors.gold,
        () => context.go(AppRoutes.focalReports),
      ),
      (
        Icons.group_outlined,
        l.registerMember,
        AppColors.accentCyan,
        () => _registerMember(user),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.all(AppConstants.spaceLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.quickActionsTitle,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: AppConstants.spaceMD),
          Row(
            children: [
              for (int i = 0; i < 2; i++) ...[
                if (i > 0)
                  const SizedBox(width: AppConstants.spaceMD),
                Expanded(
                  child: _ActionCard(
                    icon: actions[i].$1,
                    label: actions[i].$2,
                    color: actions[i].$3,
                    onTap: actions[i].$4,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppConstants.spaceMD),
          Row(
            children: [
              for (int i = 2; i < actions.length; i++) ...[
                if (i > 2)
                  const SizedBox(width: AppConstants.spaceMD),
                Expanded(
                  child: _ActionCard(
                    icon: actions[i].$1,
                    label: actions[i].$2,
                    color: actions[i].$3,
                    onTap: actions[i].$4,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Reports section ────────────────────────────────────────

  Widget _buildReportsSection(
    BuildContext context,
    AppLocalizations l,
    UserModel user,
    List<FocalReportModel> reports,
    AsyncValue<List<FocalReportModel>> reportsAsync,
  ) {
    final filters = [
      (null, l.allFilter),
      (FocalReportModel.statusDraft, l.draftStatus),
      (FocalReportModel.statusSubmitted, l.submittedStatus),
      (FocalReportModel.statusValidated, l.validatedStatus),
      (FocalReportModel.statusRejected, l.rejectedStatus),
    ];

    final filtered = _selectedStatus == null
        ? reports
        : reports.where((r) => r.status == _selectedStatus).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        0,
        AppConstants.spaceLG,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l.myReports,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              GestureDetector(
                onTap: () => _createReport(user),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spaceMD,
                      vertical: AppConstants.spaceXS),
                  decoration: BoxDecoration(
                    color: _focalLight.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                    border: Border.all(
                        color: _focalLight.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded,
                          color: _focalLight, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        l.newReport,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _focalLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceSM),
          // ── Status filter chips ─────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (status, label) in filters) ...[
                  _StatusFilterChip(
                    label: label,
                    selected: _selectedStatus == status,
                    onTap: () =>
                        setState(() => _selectedStatus = status),
                  ),
                  const SizedBox(width: AppConstants.spaceSM),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spaceMD),
          reportsAsync.when(
            loading: () => const Center(
                child: Padding(
              padding:
                  EdgeInsets.symmetric(vertical: AppConstants.spaceLG),
              child: CircularProgressIndicator(),
            )),
            error: (_, __) =>
                Center(child: Text(l.unknownError)),
            data: (_) {
              if (reports.isEmpty) {
                return _EmptyReports(
                    message: l.noReports,
                    onTap: () => _createReport(user));
              }
              if (filtered.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: AppConstants.spaceXL),
                  child: Center(
                    child: Text(
                      l.noReports,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: AppColors.textGray),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final report in filtered.take(20))
                    _ReportCard(
                      report: report,
                      onTap: () => _openReportDetail(report),
                      onSubmit: report.isDraft
                          ? () => _submitReport(report)
                          : null,
                      onShare: () => _shareReport(report),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── New report bottom sheet ────────────────────────────────────

class _NewReportSheet extends StatefulWidget {
  final String focalId;
  final String focalName;
  final String defaultLocation;
  final void Function(String message) onCreated;

  const _NewReportSheet({
    required this.focalId,
    required this.focalName,
    required this.defaultLocation,
    required this.onCreated,
  });

  @override
  State<_NewReportSheet> createState() => _NewReportSheetState();
}

class _NewReportSheetState extends State<_NewReportSheet> {
  final _repo = FocalReportRepository();
  final _formKey = GlobalKey<FormState>();
  final _locationCtrl = TextEditingController();
  final _membersCtrl = TextEditingController();
  final _newMembersCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  DateTime _reportDate = DateTime.now();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _locationCtrl.text = widget.defaultLocation;
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    _membersCtrl.dispose();
    _newMembersCtrl.dispose();
    _totalCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _reportDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _focalLight),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _reportDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final l = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    final successMsg = l.reportCreated;
    final errMsg = l.unknownError;

    try {
      await _repo.createReport(
        focalId: widget.focalId,
        focalName: widget.focalName,
        location: _locationCtrl.text.trim(),
        reportDate: _reportDate,
        totalCollected: int.tryParse(_totalCtrl.text.trim()) ?? 0,
        membersServed: int.tryParse(_membersCtrl.text.trim()) ?? 0,
        newMembersCount:
            int.tryParse(_newMembersCtrl.text.trim()) ?? 0,
        notes: _notesCtrl.text.trim().isNotEmpty
            ? _notesCtrl.text.trim()
            : null,
      );
      nav.pop();
      widget.onCreated(successMsg);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(errMsg),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
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
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppConstants.spaceLG, 0,
                  AppConstants.spaceLG, AppConstants.spaceMD),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _focalLight.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                          AppConstants.radiusMD),
                    ),
                    child: const Icon(Icons.add_chart_rounded,
                        color: _focalLight, size: 20),
                  ),
                  const SizedBox(width: AppConstants.spaceMD),
                  Text(
                    l.newReport,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            // Form
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(AppConstants.spaceLG),
                  children: [
                    _FormField(
                      controller: _locationCtrl,
                      label: l.locationLabel,
                      icon: Icons.location_on_outlined,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? l.fieldRequired
                          : null,
                    ),
                    const SizedBox(height: AppConstants.spaceMD),
                    // Date picker
                    GestureDetector(
                      onTap: _pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spaceMD,
                          vertical: 15,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusMD),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined,
                                color: AppColors.textGray, size: 18),
                            const SizedBox(
                                width: AppConstants.spaceSM),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.reportDateLabel,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      color: AppColors.textGray,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    AppUtils.formatDate(_reportDate),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      color: AppColors.textDark,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: AppColors.textGray, size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppConstants.spaceMD),
                    Row(
                      children: [
                        Expanded(
                          child: _FormField(
                            controller: _membersCtrl,
                            label: l.membersServedLabel,
                            icon: Icons.group_outlined,
                            keyboardType: TextInputType.number,
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? l.fieldRequired
                                    : null,
                          ),
                        ),
                        const SizedBox(width: AppConstants.spaceMD),
                        Expanded(
                          child: _FormField(
                            controller: _newMembersCtrl,
                            label: l.newMembersLabel,
                            icon: Icons.person_add_outlined,
                            keyboardType: TextInputType.number,
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? l.fieldRequired
                                    : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spaceMD),
                    _FormField(
                      controller: _totalCtrl,
                      label: '${l.totalCollectedLabel} (FCFA)',
                      icon: Icons.payments_outlined,
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty)
                              ? l.fieldRequired
                              : null,
                    ),
                    const SizedBox(height: AppConstants.spaceMD),
                    _FormField(
                      controller: _notesCtrl,
                      label: l.notesOptional,
                      icon: Icons.notes_rounded,
                      maxLines: 3,
                    ),
                    const SizedBox(height: AppConstants.spaceLG),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _focalLight,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusMD),
                          ),
                        ),
                        child: _loading
                            ? const CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2)
                            : Text(
                                l.createDraft,
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
            ),
          ],
        ),
      ),
    );
  }
}

// ── Report detail bottom sheet ────────────────────────────────

class _ReportDetailSheet extends StatelessWidget {
  final FocalReportModel report;
  final VoidCallback? onSubmit;
  final VoidCallback onShare;

  const _ReportDetailSheet({
    required this.report,
    required this.onSubmit,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = report;
    final (statusColor, statusLabel, statusIcon) = _statusInfo(r.status);

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppConstants.radiusXL)),
        ),
        child: Column(
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
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(
                    AppConstants.spaceLG,
                    0,
                    AppConstants.spaceLG,
                    AppConstants.spaceXL),
                children: [
                  // ── Status + Location header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusMD),
                        ),
                        child: Icon(statusIcon,
                            color: statusColor, size: 24),
                      ),
                      const SizedBox(width: AppConstants.spaceMD),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.location.isNotEmpty
                                  ? r.location
                                  : '—',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppUtils.formatDate(
                                  r.reportDate.toDate()),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: AppColors.textGray),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull),
                          border: Border.all(
                              color: statusColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          statusLabel,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // ── Stats row
                  Container(
                    padding: const EdgeInsets.all(AppConstants.spaceMD),
                    decoration: BoxDecoration(
                      color: _focalLight.withValues(alpha: 0.06),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusLG),
                      border: Border.all(
                          color: _focalLight.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceAround,
                      children: [
                        _DetailStat(
                          label: l.totalCollectedLabel,
                          value: AppUtils.formatAmount(
                              r.totalCollected),
                          color: _focalLight,
                        ),
                        _DetailStat(
                          label: l.membersServedLabel,
                          value: '${r.membersServed}',
                          color: AppColors.success,
                        ),
                        _DetailStat(
                          label: l.newMembersLabel,
                          value: '${r.newMembersCount}',
                          color: AppColors.gold,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceMD),

                  // ── Notes
                  if (!r.isRejected && r.notes != null && r.notes!.isNotEmpty) ...[
                    Container(
                      padding:
                          const EdgeInsets.all(AppConstants.spaceMD),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusMD),
                        border:
                            Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.notes_rounded,
                              color: AppColors.textGray, size: 16),
                          const SizedBox(width: AppConstants.spaceSM),
                          Expanded(
                            child: Text(
                              r.notes!,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: AppColors.textDark,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppConstants.spaceMD),
                  ],

                  // ── Rejection notes
                  if (r.isRejected &&
                      r.notes != null &&
                      r.notes!.isNotEmpty) ...[
                    Container(
                      padding:
                          const EdgeInsets.all(AppConstants.spaceMD),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.06),
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusMD),
                        border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              color: AppColors.error, size: 16),
                          const SizedBox(width: AppConstants.spaceSM),
                          Expanded(
                            child: Text(
                              r.notes!,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13, color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppConstants.spaceMD),
                  ],

                  const Divider(color: AppColors.border),
                  const SizedBox(height: AppConstants.spaceMD),

                  // ── Actions
                  Row(
                    children: [
                      // Share WhatsApp
                      Expanded(
                        child: _SheetButton(
                          icon: Icons.share_rounded,
                          label: l.shareWhatsApp,
                          color: const Color(0xFF25D366),
                          outlined: true,
                          onTap: onShare,
                        ),
                      ),
                      if (r.isDraft && onSubmit != null) ...[
                        const SizedBox(width: AppConstants.spaceMD),
                        Expanded(
                          child: _SheetButton(
                            icon: Icons.send_rounded,
                            label: l.submitReport,
                            color: _focalLight,
                            outlined: false,
                            onTap: onSubmit!,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Report card ───────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final FocalReportModel report;
  final VoidCallback onTap;
  final VoidCallback? onSubmit;
  final VoidCallback onShare;

  const _ReportCard({
    required this.report,
    required this.onTap,
    required this.onSubmit,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = report;
    final (statusColor, statusLabel, _) = _statusInfo(r.status);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spaceSM),
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
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: statusColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spaceMD),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.location.isNotEmpty ? r.location : '—',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusFull),
                            ),
                            child: Text(
                              statusLabel,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppUtils.formatDate(r.reportDate.toDate()),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: AppColors.textGray),
                      ),
                      const SizedBox(height: AppConstants.spaceSM),
                      Row(
                        children: [
                          _MiniChip(
                            icon: Icons.payments_outlined,
                            label: AppUtils.formatAmount(r.totalCollected),
                            color: _focalLight,
                          ),
                          const SizedBox(width: AppConstants.spaceSM),
                          _MiniChip(
                            icon: Icons.group_outlined,
                            label: '${r.membersServed} membres',
                            color: AppColors.success,
                          ),
                          const Spacer(),
                          if (r.isDraft && onSubmit != null)
                            GestureDetector(
                              onTap: onSubmit,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _focalLight,
                                  borderRadius: BorderRadius.circular(
                                      AppConstants.radiusFull),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.send_rounded,
                                        color: Colors.white, size: 12),
                                    const SizedBox(width: 4),
                                    Text(
                                      l.submit,
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
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────

class _GlassStat extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;

  const _GlassStat({required this.label, required this.value, this.suffix});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            if (suffix != null) ...[
              const SizedBox(width: 2),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  suffix!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
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
            fontSize: 9,
            color: Colors.white.withValues(alpha: 0.65),
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
        ),
      ],
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: Colors.white.withValues(alpha: 0.2),
      margin: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceSM),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
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
        padding: const EdgeInsets.symmetric(
          vertical: AppConstants.spaceLG,
          horizontal: AppConstants.spaceMD,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusLG),
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
                color: color.withValues(alpha: 0.1),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusMD),
              ),
              child: Icon(icon, color: color, size: 22),
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
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;
  final int maxLines;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      style: GoogleFonts.plusJakartaSans(
          fontSize: 14, color: AppColors.textDark),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13, color: AppColors.textGray),
        prefixIcon:
            Icon(icon, color: AppColors.textGray, size: 18),
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
        errorBorder: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(AppConstants.radiusMD),
          borderSide:
              const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MiniChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _DetailStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _DetailStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 10, color: AppColors.textGray),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _SheetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool outlined;
  final VoidCallback onTap;

  const _SheetButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.outlined,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(
              color: color, width: outlined ? 1.5 : 0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16, color: outlined ? color : Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: outlined ? color : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyReports extends StatelessWidget {
  final String message;
  final VoidCallback onTap;

  const _EmptyReports({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceXL),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.description_outlined,
              size: 48, color: AppColors.border),
          const SizedBox(height: AppConstants.spaceMD),
          Text(
            message,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, color: AppColors.textGray),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spaceMD),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceLG,
                  vertical: AppConstants.spaceSM),
              decoration: BoxDecoration(
                color: _focalLight,
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Text(
                l.newReport,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Register member bottom sheet ──────────────────────────────

class _RegisterMemberSheet extends StatefulWidget {
  final String focalId;
  final String defaultZone;
  final void Function(String memberNumber) onRegistered;

  const _RegisterMemberSheet({
    required this.focalId,
    required this.defaultZone,
    required this.onRegistered,
  });

  @override
  State<_RegisterMemberSheet> createState() => _RegisterMemberSheetState();
}

class _RegisterMemberSheetState extends State<_RegisterMemberSheet> {
  final _authRepo = AuthRepository();
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _regionCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _quarterCtrl = TextEditingController();

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _regionCtrl.text = widget.defaultZone;
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _regionCtrl.dispose();
    _departmentCtrl.dispose();
    _cityCtrl.dispose();
    _quarterCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final l = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    final errMsg = l.unknownError;

    try {
      final memberNumber = await _authRepo.generateMemberNumber(_regionCtrl.text.trim());
      final now = Timestamp.now();
      final docRef = FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc();

      final city = _cityCtrl.text.trim();
      final quarter = _quarterCtrl.text.trim();
      await docRef.set({
        'firstName': _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'region': _regionCtrl.text.trim(),
        'department': _departmentCtrl.text.trim(),
        if (city.isNotEmpty) 'city': city,
        if (quarter.isNotEmpty) 'quarter': quarter,
        'role': AppConstants.roleMember,
        'memberNumber': memberNumber,
        'status': AppConstants.userStatusActive,
        'preferredPayment': AppConstants.paymentMtnMomo,
        'preferredFrequency': AppConstants.periodMonthly,
        'language': AppConstants.defaultLocale,
        'registeredByFocalId': widget.focalId,
        'createdAt': now,
        'updatedAt': now,
      });

      nav.pop();
      widget.onRegistered(memberNumber);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(errMsg),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
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
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppConstants.spaceLG, 0,
                  AppConstants.spaceLG, AppConstants.spaceMD),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accentCyan.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMD),
                    ),
                    child: const Icon(Icons.person_add_outlined,
                        color: AppColors.accentCyan, size: 20),
                  ),
                  const SizedBox(width: AppConstants.spaceMD),
                  Text(
                    l.registerMember,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            // Form
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(AppConstants.spaceLG),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _FormField(
                            controller: _firstNameCtrl,
                            label: l.firstName,
                            icon: Icons.person_outline_rounded,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? l.fieldRequired
                                : null,
                          ),
                        ),
                        const SizedBox(width: AppConstants.spaceMD),
                        Expanded(
                          child: _FormField(
                            controller: _lastNameCtrl,
                            label: l.lastName,
                            icon: Icons.person_outline_rounded,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? l.fieldRequired
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spaceMD),
                    _FormField(
                      controller: _phoneCtrl,
                      label: l.phone,
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return l.fieldRequired;
                        }
                        if (!AppUtils.isValidCameroonPhone(v.trim())) {
                          return l.invalidPhone;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppConstants.spaceMD),
                    Row(
                      children: [
                        Expanded(
                          child: _FormField(
                            controller: _regionCtrl,
                            label: l.region,
                            icon: Icons.map_outlined,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? l.fieldRequired
                                : null,
                          ),
                        ),
                        const SizedBox(width: AppConstants.spaceMD),
                        Expanded(
                          child: _FormField(
                            controller: _departmentCtrl,
                            label: l.department,
                            icon: Icons.location_city_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spaceMD),
                    Row(
                      children: [
                        Expanded(
                          child: _FormField(
                            controller: _cityCtrl,
                            label: '${l.city} (${l.optional})',
                            icon: Icons.location_city_outlined,
                          ),
                        ),
                        const SizedBox(width: AppConstants.spaceMD),
                        Expanded(
                          child: _FormField(
                            controller: _quarterCtrl,
                            label: '${l.quarter} (${l.optional})',
                            icon: Icons.holiday_village_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spaceLG),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentCyan,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusMD),
                          ),
                        ),
                        child: _loading
                            ? const CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2)
                            : Text(
                                l.registerMember,
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
            ),
          ],
        ),
      ),
    );
  }
}

// ── Member number success dialog ──────────────────────────────

class _MemberNumberDialog extends StatelessWidget {
  final String memberNumber;

  const _MemberNumberDialog({required this.memberNumber});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 36),
          ),
          const SizedBox(height: AppConstants.spaceMD),
          Text(
            l.memberRegistered,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spaceMD),
          Text(
            l.memberNumberAssigned,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: AppColors.textGray),
          ),
          const SizedBox(height: AppConstants.spaceSM),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceLG,
              vertical: AppConstants.spaceMD,
            ),
            decoration: BoxDecoration(
              color: AppColors.accentCyan.withValues(alpha: 0.08),
              borderRadius:
                  BorderRadius.circular(AppConstants.radiusMD),
              border: Border.all(
                  color: AppColors.accentCyan.withValues(alpha: 0.3)),
            ),
            child: Text(
              memberNumber,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.accentCyan,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spaceSM),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: memberNumber));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(l.copiedToClipboard),
                backgroundColor: AppColors.info,
              ));
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: Text(l.copyMemberNumber),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.accentCyan),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentCyan,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusMD),
              ),
            ),
            child: Text(
              l.confirm,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Status filter chip ────────────────────────────────────────

class _StatusFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StatusFilterChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _focalLight : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: selected ? _focalLight : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textGray,
          ),
        ),
      ),
    );
  }
}

// ── Focal profile sheet ───────────────────────────────────────

class _FocalProfileSheet extends StatefulWidget {
  final UserModel user;

  const _FocalProfileSheet({required this.user});

  @override
  State<_FocalProfileSheet> createState() => _FocalProfileSheetState();
}

class _FocalProfileSheetState extends State<_FocalProfileSheet> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await AuthRepository().signOut();
      // GoRouter redirect picks up the auth state change automatically
    } catch (_) {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final u = widget.user;
    final zone = (u.focalZone?.isNotEmpty == true)
        ? u.focalZone!
        : (u.region.isNotEmpty ? u.region : '—');

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXL)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: AppConstants.spaceMD),
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
          // Avatar + name
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppConstants.spaceLG,
                AppConstants.spaceSM,
                AppConstants.spaceLG,
                AppConstants.spaceLG),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_focalLight, _focalDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    u.initials,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spaceMD),
                Text(
                  u.fullName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _focalLight.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(
                    l.focalBadge,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _focalLight,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spaceLG),
                // Info rows
                _ProfileInfoRow(
                    icon: Icons.badge_outlined,
                    label: l.memberNumber,
                    value: u.memberNumber.isNotEmpty ? u.memberNumber : '—'),
                const SizedBox(height: AppConstants.spaceSM),
                _ProfileInfoRow(
                    icon: Icons.phone_outlined,
                    label: l.phone,
                    value: u.phone.isNotEmpty ? u.phone : '—'),
                const SizedBox(height: AppConstants.spaceSM),
                _ProfileInfoRow(
                    icon: Icons.location_on_outlined,
                    label: l.focalZoneLabel,
                    value: zone),
                const SizedBox(height: AppConstants.spaceLG),
                const Divider(color: AppColors.border),
                const SizedBox(height: AppConstants.spaceMD),
                // Sign out button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _signingOut ? null : _signOut,
                    icon: _signingOut
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.error))
                        : const Icon(Icons.logout_rounded,
                            color: AppColors.error, size: 18),
                    label: Text(
                      l.logout,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: AppColors.error.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusMD),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                    height: MediaQuery.of(context).padding.bottom +
                        AppConstants.spaceMD),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileInfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textGray),
        const SizedBox(width: AppConstants.spaceSM),
        Text(
          '$label : ',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: AppColors.textGray),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Pure helpers ──────────────────────────────────────────────

(Color, String, IconData) _statusInfo(String status) {
  switch (status) {
    case FocalReportModel.statusSubmitted:
      return (AppColors.info, 'Soumis',
          Icons.hourglass_top_rounded);
    case FocalReportModel.statusValidated:
      return (AppColors.success, 'Validé',
          Icons.check_circle_rounded);
    case FocalReportModel.statusRejected:
      return (AppColors.error, 'Rejeté',
          Icons.cancel_rounded);
    default:
      return (AppColors.warning, 'Brouillon',
          Icons.edit_note_rounded);
  }
}

// ── Focal quick payment sheet ─────────────────────────────────
// One-off payment for a single member, no session/report created.

class _FocalQuickPaymentSheet extends StatefulWidget {
  final String focalId;
  const _FocalQuickPaymentSheet({required this.focalId});

  @override
  State<_FocalQuickPaymentSheet> createState() =>
      _FocalQuickPaymentSheetState();
}

class _FocalQuickPaymentSheetState
    extends State<_FocalQuickPaymentSheet> {
  final _repo = ContributionRepository();
  final _searchCtrl = TextEditingController();

  String _searchQuery = '';
  List<UserModel> _allMembers = [];
  bool _loadingMembers = true;
  UserModel? _selectedMember;

  String _periodType = AppConstants.periodMonthly;
  int? _presetAmount = AppConstants.amountMonthly;
  final _customCtrl = TextEditingController();
  String _paymentMethod = AppConstants.paymentCash;
  bool _submitting = false;

  static const _amountPresets = [
    (AppConstants.amountDaily, AppConstants.periodDaily, 'Quotidien'),
    (AppConstants.amountMonthly, AppConstants.periodMonthly, 'Mensuel'),
    (AppConstants.amountAnnual, AppConstants.periodAnnual, 'Annuel'),
  ];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    final snap = await FirebaseFirestore.instance
        .collection(AppConstants.usersCollection)
        .where('role', isEqualTo: AppConstants.roleMember)
        .limit(200)
        .get();
    if (mounted) {
      setState(() {
        _allMembers = snap.docs.map(UserModel.fromFirestore).toList();
        _loadingMembers = false;
      });
    }
  }

  List<UserModel> get _filtered {
    final q = _searchQuery.trim().toLowerCase();
    if (q.length < 2) return [];
    return _allMembers
        .where((m) =>
            m.memberNumber.toLowerCase().contains(q) ||
            m.firstName.toLowerCase().startsWith(q) ||
            m.lastName.toLowerCase().startsWith(q))
        .take(6)
        .toList();
  }

  int get _amount {
    if (_presetAmount != null) return _presetAmount!;
    return int.tryParse(_customCtrl.text.trim()) ?? 0;
  }

  bool get _canSubmit =>
      _selectedMember != null && _amount > 0 && !_submitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.createContribution(
        memberId: _selectedMember!.id,
        memberName: _selectedMember!.fullName,
        memberNumber: _selectedMember!.memberNumber,
        amount: _amount,
        periodType: _periodType,
        paymentMethod: _paymentMethod,
        recordedBy: widget.focalId,
        period: AppUtils.getCurrentPeriod(),
      );
      nav.pop();
      messenger.showSnackBar(const SnackBar(
        content: Text('Paiement enregistré avec succès'),
        backgroundColor: AppColors.success,
      ));
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
      messenger.showSnackBar(const SnackBar(
        content: Text('Erreur lors de l\'enregistrement'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
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
              padding:
                  const EdgeInsets.symmetric(vertical: AppConstants.spaceMD),
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
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMD),
                    ),
                    child: const Icon(Icons.payments_outlined,
                        color: AppColors.success, size: 18),
                  ),
                  const SizedBox(width: AppConstants.spaceMD),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Paiement rapide',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        'Sans session — paiement unique',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: AppColors.textGray),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(AppConstants.spaceLG),
                children: [
                  // ── Member search ──────────────────────────
                  const _Label('Membre'),
                  const SizedBox(height: AppConstants.spaceSM),
                  if (_selectedMember == null) ...[
                    TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Nom ou numéro de membre...',
                        prefixIcon: _loadingMembers
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _focalLight),
                                ),
                              )
                            : const Icon(Icons.search_rounded,
                                color: _focalLight),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: AppColors.bg,
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
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                    if (_searchQuery.trim().length >= 2) ...[
                      const SizedBox(height: AppConstants.spaceSM),
                      if (_filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                              vertical: AppConstants.spaceSM),
                          child: Text('Aucun membre trouvé',
                              style: TextStyle(
                                  color: AppColors.textGray, fontSize: 13)),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusMD),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            children: _filtered.asMap().entries.map((e) {
                              final i = e.key;
                              final m = e.value;
                              return Column(
                                children: [
                                  InkWell(
                                    onTap: () => setState(() {
                                      _selectedMember = m;
                                      _searchQuery = '';
                                      _searchCtrl.clear();
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppConstants.spaceMD,
                                        vertical: AppConstants.spaceSM + 2,
                                      ),
                                      child: Row(
                                        children: [
                                          _Avatar(m.firstName),
                                          const SizedBox(
                                              width: AppConstants.spaceSM),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(m.fullName,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 13,
                                                        color: AppColors
                                                            .textDark)),
                                                Text(
                                                    '${m.memberNumber} · ${m.region}',
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color: AppColors
                                                            .textGray)),
                                              ],
                                            ),
                                          ),
                                          const Icon(
                                              Icons.chevron_right_rounded,
                                              color: AppColors.textGray,
                                              size: 16),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (i < _filtered.length - 1)
                                    const Divider(height: 1, indent: 52),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ] else
                    // Selected member card
                    Container(
                      padding: const EdgeInsets.all(AppConstants.spaceMD),
                      decoration: BoxDecoration(
                        color: _focalLight.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusLG),
                        border: Border.all(
                            color: _focalLight.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          _Avatar(_selectedMember!.firstName,
                              color: _focalLight, size: 40),
                          const SizedBox(width: AppConstants.spaceMD),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_selectedMember!.fullName,
                                    style: GoogleFonts.plusJakartaSans(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: AppColors.textDark)),
                                Text(
                                    '${_selectedMember!.memberNumber} · ${_selectedMember!.region}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textGray)),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _selectedMember = null),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.error
                                    .withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded,
                                  color: AppColors.error, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // ── Amount presets ─────────────────────────
                  const _Label('Montant'),
                  const SizedBox(height: AppConstants.spaceSM),
                  Wrap(
                    spacing: AppConstants.spaceSM,
                    runSpacing: AppConstants.spaceSM,
                    children: [
                      for (final (amt, period, label) in _amountPresets)
                        _Chip(
                          label: '${AppUtils.formatAmount(amt)} · $label',
                          selected: _presetAmount == amt,
                          color: _focalLight,
                          onTap: () => setState(() {
                            _presetAmount = amt;
                            _periodType = period;
                          }),
                        ),
                      _Chip(
                        label: 'Autre montant',
                        selected: _presetAmount == null,
                        color: _focalLight,
                        onTap: () => setState(() {
                          _presetAmount = null;
                          _customCtrl.clear();
                        }),
                      ),
                    ],
                  ),
                  if (_presetAmount == null) ...[
                    const SizedBox(height: AppConstants.spaceSM),
                    TextField(
                      controller: _customCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Montant en FCFA',
                        suffixText: 'FCFA',
                        filled: true,
                        fillColor: AppColors.bg,
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
                  ],
                  const SizedBox(height: AppConstants.spaceLG),

                  // ── Payment method ─────────────────────────
                  const _Label('Méthode de paiement'),
                  const SizedBox(height: AppConstants.spaceSM),
                  Wrap(
                    spacing: AppConstants.spaceSM,
                    runSpacing: AppConstants.spaceSM,
                    children: [
                      _Chip(
                        label: 'Espèces',
                        selected: _paymentMethod ==
                            AppConstants.paymentCash,
                        color: AppColors.success,
                        onTap: () => setState(() =>
                            _paymentMethod = AppConstants.paymentCash),
                      ),
                      _Chip(
                        label: 'MTN MoMo',
                        selected: _paymentMethod ==
                            AppConstants.paymentMtnMomo,
                        color: const Color(0xFFFFCC00),
                        onTap: () => setState(() =>
                            _paymentMethod = AppConstants.paymentMtnMomo),
                      ),
                      _Chip(
                        label: 'Orange Money',
                        selected: _paymentMethod ==
                            AppConstants.paymentOrangeMoney,
                        color: const Color(0xFFFF6600),
                        onTap: () => setState(() => _paymentMethod =
                            AppConstants.paymentOrangeMoney),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spaceXL),

                  // ── Submit ─────────────────────────────────
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _canSubmit ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        disabledBackgroundColor: AppColors.border,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusMD),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              'Enregistrer le paiement',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceLG),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textDark,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : AppColors.bg,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? color : AppColors.textDark,
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final Color color;
  final double size;

  const _Avatar(this.name,
      {this.color = _focalLight, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}
