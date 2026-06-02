import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/focal_report_model.dart';
import '../../../data/repositories/focal_report_repository.dart';
import 'focal_providers.dart';

const _focalLight = Color(0xFF26A8F3);

class FocalReportsScreen extends ConsumerStatefulWidget {
  const FocalReportsScreen({super.key});

  @override
  ConsumerState<FocalReportsScreen> createState() =>
      _FocalReportsScreenState();
}

class _FocalReportsScreenState extends ConsumerState<FocalReportsScreen> {
  final _repo = FocalReportRepository();
  String? _selectedStatus;

  Future<void> _submitReport(FocalReportModel report) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final lc = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(lc.submitConfirm,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark)),
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
              style:
                  ElevatedButton.styleFrom(backgroundColor: _focalLight),
              child: Text(lc.submitReport,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.submitReport(report.id);
      NotificationService.instance.notifyFocalReport(
        focalName: report.focalName,
        reportId: report.id,
      ).ignore();
      messenger.showSnackBar(SnackBar(
        content: Text(l.reportSubmitted),
        backgroundColor: AppColors.success,
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(l.unknownError),
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

  void _openDetail(FocalReportModel report) {
    context.push(AppRoutes.focalReport, extra: report.id);
  }

  Future<void> _createReport(String focalId, String focalName,
      String defaultLocation) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewReportSheet(
        focalId: focalId,
        focalName: focalName,
        defaultLocation: defaultLocation,
        onCreated: (msg) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.success,
          ));
        },
      ),
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
      data: (user) {
        if (user == null) {
          return Scaffold(body: Center(child: Text(l.unknownError)));
        }

        final reportsAsync = ref.watch(focalReportsProvider(user.id));
        final reports = reportsAsync.valueOrNull ?? [];
        final filters = [
          (null, l.allFilter),
          (FocalReportModel.statusDraft, l.draftStatus),
          (FocalReportModel.statusSubmitted, l.submittedStatus),
          (FocalReportModel.statusValidated, l.validatedStatus),
          (FocalReportModel.statusRejected, l.rejectedStatus),
        ];
        final filtered = _selectedStatus == null
            ? reports
            : reports
                .where((r) => r.status == _selectedStatus)
                .toList();

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: CustomScrollView(
            slivers: [
              // ── App bar ────────────────────────────────────
              SliverAppBar(
                pinned: true,
                backgroundColor: _focalLight,
                foregroundColor: Colors.white,
                expandedHeight: 0,
                title: Text(
                  l.myReports,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                    onPressed: () {
                      final zone = (user.focalZone?.isNotEmpty == true)
                          ? user.focalZone!
                          : user.region;
                      _createReport(user.id, user.fullName, zone);
                    },
                  ),
                ],
              ),
              // ── Filter chips ────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  color: AppColors.surface,
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.spaceLG,
                    AppConstants.spaceMD,
                    AppConstants.spaceLG,
                    AppConstants.spaceMD,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (status, label) in filters) ...[
                          _FilterChip(
                            label: label,
                            count: status == null
                                ? reports.length
                                : reports
                                    .where((r) => r.status == status)
                                    .length,
                            selected: _selectedStatus == status,
                            onTap: () => setState(
                                () => _selectedStatus = status),
                          ),
                          const SizedBox(width: AppConstants.spaceSM),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: AppConstants.spaceSM),
              ),
              // ── Report list ─────────────────────────────────
              reportsAsync.when(
                loading: () => const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => SliverFillRemaining(
                  child: Center(child: Text(l.unknownError)),
                ),
                data: (_) {
                  if (reports.isEmpty) {
                    return SliverFillRemaining(
                      child: _EmptyState(
                        onCreateTap: () {
                          final zone =
                              (user.focalZone?.isNotEmpty == true)
                                  ? user.focalZone!
                                  : user.region;
                          _createReport(
                              user.id, user.fullName, zone);
                        },
                        l: l,
                      ),
                    );
                  }
                  if (filtered.isEmpty) {
                    return SliverFillRemaining(
                      child: Center(
                        child: Text(
                          l.noReports,
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
                      0,
                      AppConstants.spaceLG,
                      AppConstants.spaceXL,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final r = filtered[i];
                          return _ReportTile(
                            report: r,
                            onTap: () => _openDetail(r),
                            onSubmit: r.isDraft
                                ? () => _submitReport(r)
                                : null,
                            onShare: () => _shareReport(r),
                          );
                        },
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
}

// ── Filter chip ───────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _focalLight : AppColors.surface,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
              color: selected ? _focalLight : AppColors.border),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _focalLight.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textGray,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.25)
                      : _focalLight.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : _focalLight,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Report tile ───────────────────────────────────────────────

class _ReportTile extends StatelessWidget {
  final FocalReportModel report;
  final VoidCallback onTap;
  final VoidCallback? onSubmit;
  final VoidCallback onShare;

  const _ReportTile({
    required this.report,
    required this.onTap,
    required this.onSubmit,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = report;
    final (statusColor, statusLabel, statusIcon) = _statusInfo(r.status, l);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spaceMD),
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
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: statusColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spaceMD),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusMD),
                            ),
                            child: Icon(statusIcon, color: statusColor, size: 18),
                          ),
                          const SizedBox(width: AppConstants.spaceMD),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.location.isNotEmpty ? r.location : '—',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  AppUtils.formatDate(r.reportDate.toDate()),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: AppColors.textGray,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
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
                      const SizedBox(height: AppConstants.spaceSM),
                      Row(
                        children: [
                          _Chip(
                            icon: Icons.payments_outlined,
                            label: AppUtils.formatAmount(r.totalCollected),
                            color: _focalLight,
                          ),
                          const SizedBox(width: AppConstants.spaceSM),
                          _Chip(
                            icon: Icons.group_outlined,
                            label: '${r.membersServed}',
                            color: AppColors.success,
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: onShare,
                            child: const Icon(Icons.share_rounded,
                                color: AppColors.textGray, size: 18),
                          ),
                          if (r.isDraft && onSubmit != null) ...[
                            const SizedBox(width: AppConstants.spaceMD),
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

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip({required this.icon, required this.label, required this.color});

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

// ── New report sheet ──────────────────────────────────────────

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
      widget.onCreated(l.reportCreated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.unknownError),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppConstants.spaceLG,
                  0,
                  AppConstants.spaceLG,
                  AppConstants.spaceMD),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _focalLight.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMD),
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
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: controller,
                  padding:
                      const EdgeInsets.all(AppConstants.spaceLG),
                  children: [
                    _Field(
                      controller: _locationCtrl,
                      label: l.locationLabel,
                      icon: Icons.location_on_outlined,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty)
                              ? l.fieldRequired
                              : null,
                    ),
                    const SizedBox(height: AppConstants.spaceMD),
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
                          border:
                              Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                                Icons.calendar_today_outlined,
                                color: AppColors.textGray,
                                size: 18),
                            const SizedBox(
                                width: AppConstants.spaceSM),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.reportDateLabel,
                                    style:
                                        GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      color: AppColors.textGray,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    AppUtils.formatDate(_reportDate),
                                    style:
                                        GoogleFonts.plusJakartaSans(
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
                          child: _Field(
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
                        const SizedBox(
                            width: AppConstants.spaceMD),
                        Expanded(
                          child: _Field(
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
                    _Field(
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
                    _Field(
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

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;
  final int maxLines;
  final String? Function(String?)? validator;

  const _Field({
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
          borderSide: const BorderSide(
              color: AppColors.error, width: 1.5),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateTap;
  final AppLocalizations l;

  const _EmptyState({required this.onCreateTap, required this.l});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined,
                size: 56, color: AppColors.border),
            const SizedBox(height: AppConstants.spaceMD),
            Text(
              l.noReports,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: AppColors.textGray),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spaceLG),
            GestureDetector(
              onTap: onCreateTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceLG,
                    vertical: AppConstants.spaceMD),
                decoration: BoxDecoration(
                  color: _focalLight,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded,
                        color: Colors.white, size: 16),
                    const SizedBox(width: AppConstants.spaceSM),
                    Text(
                      l.newReport,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
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

// ── Status helper ─────────────────────────────────────────────

(Color, String, IconData) _statusInfo(String status, AppLocalizations l) {
  switch (status) {
    case FocalReportModel.statusSubmitted:
      return (AppColors.info, l.submittedStatus, Icons.hourglass_top_rounded);
    case FocalReportModel.statusValidated:
      return (AppColors.success, l.validatedStatus, Icons.check_circle_rounded);
    case FocalReportModel.statusRejected:
      return (AppColors.error, l.rejectedStatus, Icons.cancel_rounded);
    default:
      return (AppColors.warning, l.draftStatus, Icons.edit_note_rounded);
  }
}
