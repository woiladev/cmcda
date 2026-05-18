import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/contribution_repository.dart';
import '../../../data/repositories/focal_report_repository.dart';
import '../../widgets/common/payment_method_icon.dart';

// ── Palette ───────────────────────────────────────────────────

const _blue = Color(0xFF26A8F3);
const _blueDark = Color(0xFF0A5F8C);

// ── In-memory session entry ───────────────────────────────────

class _Entry {
  final int uid;
  final String? memberId;
  final String memberName;
  final String memberNumber;
  final int amount;
  final String periodType;
  final String period;
  final String paymentMethod;
  final bool isNewMember;

  const _Entry({
    required this.uid,
    this.memberId,
    required this.memberName,
    required this.memberNumber,
    required this.amount,
    required this.periodType,
    required this.period,
    required this.paymentMethod,
    this.isNewMember = false,
  });
}

// ── Screen ────────────────────────────────────────────────────

class FocalSessionScreen extends ConsumerStatefulWidget {
  const FocalSessionScreen({super.key});

  @override
  ConsumerState<FocalSessionScreen> createState() => _State();
}

class _State extends ConsumerState<FocalSessionScreen> {
  // Key gives us a context that is BELOW the Scaffold — required for
  // showModalBottomSheet when this screen sits on the root navigator
  // with no Scaffold ancestor above its own build context.
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _focalRepo = FocalReportRepository();
  final _contribRepo = ContributionRepository();
  final _locationCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  final List<_Entry> _entries = [];
  bool _finalizing = false;
  bool _locationSet = false;
  int _uidCounter = 0;

  // Always below the Scaffold — safe for showModalBottomSheet / showDialog.
  BuildContext get _ctx => _scaffoldKey.currentContext ?? context;

  int get _total => _entries.fold(0, (s, e) => s + e.amount);
  int get _newCount => _entries.where((e) => e.isNewMember).length;

  @override
  void dispose() {
    _locationCtrl.dispose();
    super.dispose();
  }

  // Pre-fill location from focal officer's zone (only on first build).
  void _initLocation(UserModel user) {
    if (_locationSet) return;
    _locationSet = true;
    final zone = (user.focalZone?.isNotEmpty == true)
        ? user.focalZone!
        : user.region;
    if (zone.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _locationCtrl.text = zone;
      });
    }
  }

  // ── Actions ────────────────────────────────────────────────

  Future<void> _addPayment() async {
    if (!mounted) return;
    final entry = await showModalBottomSheet<_Entry>(
      context: _ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddSheet(uid: _uidCounter, date: _date),
    );
    if (entry != null && mounted) {
      setState(() {
        _uidCounter++;
        _entries.insert(0, entry);
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: _ctx,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _blue),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _finalize(AppLocalizations l, UserModel user) async {
    if (_entries.isEmpty || _finalizing) return;

    final messenger = ScaffoldMessenger.of(_ctx);
    final nav = Navigator.of(_ctx);
    final successMsg = l.sessionSaved;
    final errMsg = l.unknownError;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: _ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FinalizeSheet(
        total: _total,
        memberCount: _entries.length,
        newCount: _newCount,
        defaultLocation: _locationCtrl.text.trim(),
      ),
    );

    if (result == null || !mounted) return;
    setState(() => _finalizing = true);

    try {
      final location = result['location'] as String;
      final newMembers = result['newMembers'] as int;
      final notes = result['notes'] as String?;

      final reportId = await _focalRepo.createReport(
        focalId: user.id,
        focalName: user.fullName,
        location: location,
        reportDate: _date,
        totalCollected: _total,
        membersServed: _entries.length,
        newMembersCount: newMembers,
        notes: notes,
      );

      final contributions = await Future.wait(
        _entries.map((e) => _contribRepo.createContribution(
          memberId: e.memberId ?? '',
          memberName: e.memberName,
          memberNumber: e.memberNumber,
          amount: e.amount,
          period: e.period,
          periodType: e.periodType,
          paymentMethod: e.paymentMethod,
          recordedBy: user.id,
          focalReportId: reportId,
        )),
      );

      await _focalRepo.updateReport(reportId, {
        'contributionIds': contributions.map((c) => c.id).toList(),
      });

      messenger.showSnackBar(SnackBar(
        content: Text(successMsg),
        backgroundColor: AppColors.success,
      ));
      nav.pop();
    } catch (_) {
      if (mounted) setState(() => _finalizing = false);
      messenger.showSnackBar(SnackBar(
        content: Text(errMsg),
        backgroundColor: AppColors.error,
      ));
    }
  }

  void _confirmDiscard(AppLocalizations l) {
    if (_entries.isEmpty) {
      Navigator.of(_ctx).pop();
      return;
    }
    showDialog(
      context: _ctx,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusLG)),
        title: Text(l.discardSession,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, color: AppColors.textDark)),
        content: Text(l.discardSessionBody,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, color: AppColors.textGray)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(_ctx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(l.discard,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _delete(int index) => setState(() => _entries.removeAt(index));

  // ── Build ──────────────────────────────────────────────────

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
        _initLocation(user);
        return _buildScaffold(l, user);
      },
    );
  }

  Widget _buildScaffold(AppLocalizations l, UserModel user) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard(l);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.bg,
          body: Column(
            children: [
              _Header(
                l: l,
                user: user,
                date: _date,
                total: _total,
                memberCount: _entries.length,
                newCount: _newCount,
                finalizing: _finalizing,
                hasEntries: _entries.isNotEmpty,
                locationCtrl: _locationCtrl,
                onBack: () => _confirmDiscard(l),
                onPickDate: _pickDate,
                onFinalize: () => _finalize(l, user),
              ),
              Expanded(
                child: _entries.isEmpty
                    ? _EmptyState(onAdd: _addPayment)
                    : _EntryList(
                        entries: _entries,
                        l: l,
                        onDelete: _delete,
                      ),
              ),
            ],
          ),
          floatingActionButton: _entries.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: _finalizing ? null : _addPayment,
                  backgroundColor: _blue,
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  label: Text(
                    l.recordPayment,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

// ── Header widget ─────────────────────────────────────────────

class _Header extends StatelessWidget {
  final AppLocalizations l;
  final UserModel user;
  final DateTime date;
  final int total;
  final int memberCount;
  final int newCount;
  final bool finalizing;
  final bool hasEntries;
  final TextEditingController locationCtrl;
  final VoidCallback onBack;
  final VoidCallback onPickDate;
  final VoidCallback onFinalize;

  const _Header({
    required this.l,
    required this.user,
    required this.date,
    required this.total,
    required this.memberCount,
    required this.newCount,
    required this.finalizing,
    required this.hasEntries,
    required this.locationCtrl,
    required this.onBack,
    required this.onPickDate,
    required this.onFinalize,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        top + AppConstants.spaceSM,
        AppConstants.spaceLG,
        AppConstants.spaceLG,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_blue, _blueDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Nav row
          Row(
            children: [
              _CircleBtn(
                icon: Icons.arrow_back_rounded,
                onTap: onBack,
              ),
              const SizedBox(width: AppConstants.spaceMD),
              Expanded(
                child: Text(
                  l.startSession,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (finalizing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              else if (hasEntries)
                GestureDetector(
                  onTap: onFinalize,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(
                      l.finalizeSession,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _blueDark,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceMD),

          // ── Location + Date row
          Row(
            children: [
              Expanded(
                child: _GlassTextField(
                  controller: locationCtrl,
                  hint: l.locationLabel,
                  icon: Icons.location_on_rounded,
                ),
              ),
              const SizedBox(width: AppConstants.spaceSM),
              GestureDetector(
                onTap: onPickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMD),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          color: Colors.white70, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        AppUtils.formatDateShort(date),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceMD),

          // ── Stats row
          Row(
            children: [
              Expanded(
                child: _StatPill(
                  label: l.totalCollectedLabel,
                  value: total > 0
                      ? AppUtils.formatAmount(total).replaceAll(' FCFA', '')
                      : '0',
                  suffix: 'FCFA',
                ),
              ),
              const SizedBox(width: AppConstants.spaceSM),
              Expanded(
                child: _StatPill(
                  label: l.membersServedLabel,
                  value: '$memberCount',
                ),
              ),
              if (newCount > 0) ...[
                const SizedBox(width: AppConstants.spaceSM),
                Expanded(
                  child: _StatPill(
                    label: l.newMembersLabel,
                    value: '$newCount',
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceLG),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.receipt_long_rounded,
                  size: 36, color: _blue),
            ),
            const SizedBox(height: AppConstants.spaceLG),
            Text(
              l.noSessionPayments,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textGray,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spaceSM),
            Text(
              'Ajoutez les paiements collectés lors de cette session.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: AppColors.textGray),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spaceLG),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(l.recordPayment),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                textStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Entry list ────────────────────────────────────────────────

class _EntryList extends StatelessWidget {
  final List<_Entry> entries;
  final AppLocalizations l;
  final void Function(int index) onDelete;

  const _EntryList({
    required this.entries,
    required this.l,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        AppConstants.spaceMD,
        AppConstants.spaceLG,
        96,
      ),
      itemCount: entries.length,
      itemBuilder: (_, i) => _EntryCard(
        entry: entries[i],
        position: i + 1,
        l: l,
        onDelete: () => onDelete(i),
      ),
    );
  }
}

// ── Entry card ────────────────────────────────────────────────

class _EntryCard extends StatelessWidget {
  final _Entry entry;
  final int position;
  final AppLocalizations l;
  final VoidCallback onDelete;

  const _EntryCard({
    required this.entry,
    required this.position,
    required this.l,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('entry_${entry.uid}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppConstants.spaceLG),
        margin: const EdgeInsets.only(bottom: AppConstants.spaceSM),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: AppColors.error, size: 22),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spaceSM),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Position accent
              Container(
                width: 3,
                decoration: const BoxDecoration(
                  color: _blue,
                  borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(AppConstants.radiusLG)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spaceMD),
                  child: Row(
                    children: [
                      // Position bubble
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _blue.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$position',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _blue,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spaceMD),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.memberName,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textDark,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (entry.isNewMember)
                                  Container(
                                    margin:
                                        const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.gold
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(
                                          AppConstants.radiusFull),
                                    ),
                                    child: Text(
                                      'Nouveau',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.gold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${entry.memberNumber} · ${_periodShort(entry.period)}',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: AppColors.textGray),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppConstants.spaceSM),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            AppUtils.formatAmount(entry.amount),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _blue,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _methodIcon(entry.paymentMethod,
                                  size: 11,
                                  color: _methodColor(entry.paymentMethod)),
                              const SizedBox(width: 3),
                              Text(
                                _methodLabel(entry.paymentMethod, l),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      _methodColor(entry.paymentMethod),
                                ),
                              ),
                            ],
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

// ── Add Payment Sheet ─────────────────────────────────────────

class _AddSheet extends StatefulWidget {
  final int uid;
  final DateTime date;
  const _AddSheet({required this.uid, required this.date});

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final _numCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _customCtrl = TextEditingController();

  String? _memberId;
  bool _searching = false;
  String? _searchStatus; // 'found' | 'not_found'
  bool _nameReadOnly = false;
  bool _isNewMember = false;

  int? _presetAmount = AppConstants.amountMonthly;
  String _periodType = AppConstants.periodMonthly;
  String _method = AppConstants.paymentCash;
  late DateTime _coverMonth;

  bool get _isCustom => _presetAmount == null;

  static const _presets = [
    (AppConstants.amountDaily, AppConstants.periodDaily, 'Quotidien'),
    (AppConstants.amountMonthly, AppConstants.periodMonthly, 'Mensuel'),
    (AppConstants.amountAnnual, AppConstants.periodAnnual, 'Annuel'),
  ];

  @override
  void initState() {
    super.initState();
    _coverMonth = DateTime(widget.date.year, widget.date.month);
  }

  @override
  void dispose() {
    _numCtrl.dispose();
    _nameCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  String _fmt(String raw) {
    final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return d.isEmpty ? '' : 'CM-${d.padLeft(6, '0')}';
  }

  Future<void> _search(AppLocalizations l) async {
    final num = _fmt(_numCtrl.text.trim());
    if (num.isEmpty) return;
    setState(() {
      _searching = true;
      _searchStatus = null;
      _memberId = null;
      _nameReadOnly = false;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .where('memberNumber', isEqualTo: num)
          .limit(1)
          .get();
      if (!mounted) return;
      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first.data();
        _memberId = snap.docs.first.id;
        _numCtrl.text = num;
        _nameCtrl.text =
            '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim();
        setState(() {
          _nameReadOnly = true;
          _searchStatus = 'found';
        });
      } else {
        _numCtrl.text = num;
        setState(() => _searchStatus = 'not_found');
      }
    } catch (_) {
      if (mounted) setState(() => _searchStatus = 'not_found');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  bool get _canSubmit {
    if (_nameCtrl.text.trim().isEmpty) return false;
    if (_numCtrl.text.trim().isEmpty) return false;
    if (_isCustom) {
      final v = int.tryParse(_customCtrl.text.trim());
      return v != null && v > 0;
    }
    return true;
  }

  void _submit() {
    if (!_canSubmit) return;
    final amount =
        _isCustom ? int.parse(_customCtrl.text.trim()) : _presetAmount!;
    Navigator.of(context).pop(_Entry(
      uid: widget.uid,
      memberId: _memberId,
      memberName: _nameCtrl.text.trim(),
      memberNumber: _fmt(_numCtrl.text.trim()),
      amount: amount,
      periodType: _periodType,
      period: AppUtils.getPeriodForDate(_coverMonth),
      paymentMethod: _method,
      isNewMember: _isNewMember,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.96,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppConstants.radiusXL)),
        ),
        child: Column(
          children: [
            _Handle(),
            _SheetTitle(
              icon: Icons.payments_outlined,
              iconColor: _blue,
              title: l.recordPayment,
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.all(AppConstants.spaceLG),
                children: [
                  // Member lookup
                  _Label(l.memberNumber),
                  const SizedBox(height: AppConstants.spaceSM),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _numCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9CMcm\-]')),
                            LengthLimitingTextInputFormatter(10),
                          ],
                          onSubmitted: (_) => _search(l),
                          decoration: _inputDeco(
                            hint: 'CM-000001',
                            icon: Icons.badge_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spaceSM),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _searching ? null : () => _search(l),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _blue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusMD),
                            ),
                          ),
                          child: _searching
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2),
                                )
                              : Text(
                                  l.searchMember,
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
                  if (_searchStatus == 'found')
                    _SearchBadge(
                      icon: Icons.check_circle_rounded,
                      color: AppColors.success,
                      text: _nameCtrl.text,
                    )
                  else if (_searchStatus == 'not_found')
                    _SearchBadge(
                      icon: Icons.info_outline_rounded,
                      color: AppColors.warning,
                      text: l.memberNotFound,
                    ),
                  const SizedBox(height: AppConstants.spaceMD),

                  // Member name
                  TextField(
                    controller: _nameCtrl,
                    readOnly: _nameReadOnly,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: _inputDeco(
                      hint: l.fullName,
                      icon: Icons.person_outline_rounded,
                      filled: _nameReadOnly,
                      fillColor: _nameReadOnly
                          ? AppColors.success.withValues(alpha: 0.05)
                          : null,
                      borderColor: _nameReadOnly ? AppColors.success : null,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // Amount presets
                  _Label('${l.amount} (FCFA)'),
                  const SizedBox(height: AppConstants.spaceSM),
                  Wrap(
                    spacing: AppConstants.spaceSM,
                    runSpacing: AppConstants.spaceSM,
                    children: [
                      for (final (amt, period, label) in _presets)
                        _Chip(
                          label: label,
                          sub: AppUtils.formatAmount(amt)
                              .replaceAll(' FCFA', ''),
                          selected: _presetAmount == amt,
                          onTap: () => setState(() {
                            _presetAmount = amt;
                            _periodType = period;
                          }),
                        ),
                      _Chip(
                        label: l.custom,
                        selected: _isCustom,
                        onTap: () => setState(() {
                          _presetAmount = null;
                          _customCtrl.clear();
                        }),
                      ),
                    ],
                  ),
                  if (_isCustom) ...[
                    const SizedBox(height: AppConstants.spaceSM),
                    TextField(
                      controller: _customCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: _inputDeco(
                        hint: '${l.amount} (FCFA)',
                        icon: Icons.payments_outlined,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppConstants.spaceLG),

                  // Month picker
                  const _Label('Mois concerné'),
                  const SizedBox(height: AppConstants.spaceSM),
                  _MonthRow(
                    selected: _coverMonth,
                    year: widget.date.year,
                    onChanged: (m) => setState(() => _coverMonth = m),
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // Period type
                  _Label(l.periodLabel),
                  const SizedBox(height: AppConstants.spaceSM),
                  Wrap(
                    spacing: AppConstants.spaceSM,
                    runSpacing: AppConstants.spaceSM,
                    children: [
                      _SmallChip(
                        label: l.daily,
                        selected: _periodType == AppConstants.periodDaily,
                        onTap: () => setState(
                            () => _periodType = AppConstants.periodDaily),
                      ),
                      _SmallChip(
                        label: l.monthly,
                        selected:
                            _periodType == AppConstants.periodMonthly,
                        onTap: () => setState(
                            () => _periodType = AppConstants.periodMonthly),
                      ),
                      _SmallChip(
                        label: l.annual,
                        selected:
                            _periodType == AppConstants.periodAnnual,
                        onTap: () => setState(
                            () => _periodType = AppConstants.periodAnnual),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // Payment method
                  _Label(l.paymentMethod),
                  const SizedBox(height: AppConstants.spaceSM),
                  Wrap(
                    spacing: AppConstants.spaceSM,
                    runSpacing: AppConstants.spaceSM,
                    children: [
                      _MethodChip(
                        label: l.cash,
                        methodKey: AppConstants.paymentCash,
                        selected: _method == AppConstants.paymentCash,
                        onTap: () => setState(
                            () => _method = AppConstants.paymentCash),
                      ),
                      _MethodChip(
                        label: 'MTN MoMo',
                        methodKey: AppConstants.paymentMtnMomo,
                        selected:
                            _method == AppConstants.paymentMtnMomo,
                        onTap: () => setState(
                            () => _method = AppConstants.paymentMtnMomo),
                      ),
                      _MethodChip(
                        label: 'Orange Money',
                        methodKey: AppConstants.paymentOrangeMoney,
                        selected:
                            _method == AppConstants.paymentOrangeMoney,
                        onTap: () => setState(() =>
                            _method = AppConstants.paymentOrangeMoney),
                      ),
                      _MethodChip(
                        label: l.bankTransfer,
                        methodKey: AppConstants.paymentBankTransfer,
                        selected:
                            _method == AppConstants.paymentBankTransfer,
                        onTap: () => setState(() =>
                            _method = AppConstants.paymentBankTransfer),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // New member toggle
                  GestureDetector(
                    onTap: () =>
                        setState(() => _isNewMember = !_isNewMember),
                    child: Container(
                      padding:
                          const EdgeInsets.all(AppConstants.spaceMD),
                      decoration: BoxDecoration(
                        color: _isNewMember
                            ? AppColors.gold.withValues(alpha: 0.08)
                            : AppColors.bg,
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusMD),
                        border: Border.all(
                          color: _isNewMember
                              ? AppColors.gold.withValues(alpha: 0.4)
                              : AppColors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_add_outlined,
                            color: _isNewMember
                                ? AppColors.gold
                                : AppColors.textGray,
                            size: 20,
                          ),
                          const SizedBox(width: AppConstants.spaceMD),
                          Expanded(
                            child: Text(
                              l.newMembersLabel,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _isNewMember
                                    ? AppColors.gold
                                    : AppColors.textGray,
                              ),
                            ),
                          ),
                          Switch(
                            value: _isNewMember,
                            onChanged: (v) =>
                                setState(() => _isNewMember = v),
                            activeThumbColor: AppColors.gold,
                            activeTrackColor:
                                AppColors.gold.withValues(alpha: 0.3),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceLG),

                  // Submit
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _canSubmit ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        disabledBackgroundColor: AppColors.border,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusMD),
                        ),
                      ),
                      child: Text(
                        l.recordPayment,
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

// ── Finalize Sheet ────────────────────────────────────────────

class _FinalizeSheet extends StatefulWidget {
  final int total;
  final int memberCount;
  final int newCount;
  final String defaultLocation;

  const _FinalizeSheet({
    required this.total,
    required this.memberCount,
    required this.newCount,
    required this.defaultLocation,
  });

  @override
  State<_FinalizeSheet> createState() => _FinalizeSheetState();
}

class _FinalizeSheetState extends State<_FinalizeSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _locationCtrl;
  late final TextEditingController _newCtrl;
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _locationCtrl = TextEditingController(text: widget.defaultLocation);
    _newCtrl = TextEditingController(
        text: widget.newCount > 0 ? '${widget.newCount}' : '');
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    _newCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop({
      'location': _locationCtrl.text.trim(),
      'newMembers': int.tryParse(_newCtrl.text.trim()) ?? 0,
      'notes': _notesCtrl.text.trim().isNotEmpty
          ? _notesCtrl.text.trim()
          : null,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppConstants.radiusXL)),
        ),
        child: Column(
          children: [
            _Handle(),
            _SheetTitle(
              icon: Icons.check_circle_outline_rounded,
              iconColor: _blue,
              title: l.finalizeSession,
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.all(AppConstants.spaceLG),
                  children: [
                    // Summary card
                    Container(
                      padding:
                          const EdgeInsets.all(AppConstants.spaceMD),
                      decoration: BoxDecoration(
                        color: _blue.withValues(alpha: 0.06),
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusLG),
                        border: Border.all(
                            color: _blue.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceAround,
                        children: [
                          _SummaryItem(
                            label: l.totalCollectedLabel,
                            value: AppUtils.formatAmount(widget.total),
                            color: _blue,
                          ),
                          _SummaryItem(
                            label: l.membersServedLabel,
                            value: '${widget.memberCount}',
                            color: AppColors.success,
                          ),
                          _SummaryItem(
                            label: l.newMembersLabel,
                            value: '${widget.newCount}',
                            color: AppColors.gold,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppConstants.spaceLG),

                    // Location
                    TextFormField(
                      controller: _locationCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: _inputDeco(
                        hint: l.locationLabel,
                        icon: Icons.location_on_outlined,
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty)
                              ? l.fieldRequired
                              : null,
                    ),
                    const SizedBox(height: AppConstants.spaceMD),

                    // New members count
                    TextFormField(
                      controller: _newCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: _inputDeco(
                        hint: l.newMembersLabel,
                        icon: Icons.person_add_outlined,
                      ),
                    ),
                    const SizedBox(height: AppConstants.spaceMD),

                    // Notes
                    TextFormField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: _inputDeco(
                        hint: l.notesOptional,
                        icon: Icons.notes_rounded,
                      ),
                    ),
                    const SizedBox(height: AppConstants.spaceLG),

                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusMD),
                          ),
                        ),
                        child: Text(
                          l.finalizeSession,
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

// ── Small shared widgets ──────────────────────────────────────

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;
  const _StatPill({required this.label, required this.value, this.suffix});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: AppConstants.spaceSM,
          horizontal: AppConstants.spaceSM),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  )),
              if (suffix != null) ...[
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: Text(suffix!,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          color: Colors.white70,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 9,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
              maxLines: 2),
        ],
      ),
    );
  }
}

class _GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  const _GlassTextField(
      {required this.controller, required this.hint, required this.icon});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      style: GoogleFonts.plusJakartaSans(
          fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            GoogleFonts.plusJakartaSans(color: Colors.white60, fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.white60, size: 16),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.7), width: 1.5),
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.spaceMD),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  const _SheetTitle(
      {required this.icon, required this.iconColor, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
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
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
        ));
  }
}

class _SearchBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _SearchBadge(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppConstants.spaceXS),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Expanded(
            child: Text(text,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label,
      this.sub,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _blue : AppColors.surface,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: selected ? _blue : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.textDark,
                )),
            if (sub != null)
              Text(sub!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: selected
                        ? Colors.white70
                        : AppColors.textGray,
                  )),
          ],
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SmallChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _blue : AppColors.surface,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
              color: selected ? _blue : AppColors.border,
              width: selected ? 1.5 : 1),
        ),
        child: Text(label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textDark,
            )),
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  final String label;
  final String methodKey;
  final bool selected;
  final VoidCallback onTap;
  const _MethodChip(
      {required this.label,
      required this.methodKey,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _blue.withValues(alpha: 0.10) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(
              color: selected ? _blue : AppColors.border,
              width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            paymentMethodIcon(methodKey,
                size: 14,
                color: selected ? _blue : AppColors.textGray),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? _blue : AppColors.textDark,
                )),
          ],
        ),
      ),
    );
  }
}

class _MonthRow extends StatelessWidget {
  final DateTime selected;
  final int year;
  final ValueChanged<DateTime> onChanged;

  static const _months = [
    'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin',
    'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc',
  ];

  const _MonthRow(
      {required this.selected,
      required this.year,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int m = 1; m <= 12; m++)
            if (year < now.year || (year == now.year && m <= now.month))
              GestureDetector(
                onTap: () => onChanged(DateTime(year, m)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: AppConstants.spaceSM),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected.month == m && selected.year == year
                        ? _blue
                        : AppColors.surface,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                    border: Border.all(
                      color: selected.month == m && selected.year == year
                          ? _blue
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    _months[m - 1],
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color:
                          selected.month == m && selected.year == year
                              ? Colors.white
                              : AppColors.textGray,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryItem(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            )),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 10, color: AppColors.textGray),
            textAlign: TextAlign.center,
            maxLines: 2),
      ],
    );
  }
}

// ── Shared input decoration ───────────────────────────────────

InputDecoration _inputDeco({
  required String hint,
  required IconData icon,
  bool filled = true,
  Color? fillColor,
  Color? borderColor,
}) {
  return InputDecoration(
    labelText: hint,
    labelStyle: GoogleFonts.plusJakartaSans(
        fontSize: 13, color: AppColors.textGray),
    prefixIcon: Icon(icon, color: AppColors.textGray, size: 18),
    filled: filled,
    fillColor: fillColor ?? AppColors.bg,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      borderSide: BorderSide(color: borderColor ?? AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      borderSide: const BorderSide(color: _blue, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      borderSide: const BorderSide(color: AppColors.error, width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      borderSide: const BorderSide(color: AppColors.error, width: 1.5),
    ),
  );
}

// ── Pure helpers ──────────────────────────────────────────────

String _periodShort(String period) {
  try {
    final p = period.split('-');
    if (p.length == 2) {
      return DateFormat('MMM yyyy', 'fr_FR')
          .format(DateTime(int.parse(p[0]), int.parse(p[1])));
    }
  } catch (_) {}
  return period;
}

Widget _methodIcon(String m, {double size = 24, Color? color}) =>
    paymentMethodIcon(m, size: size, color: color);

Color _methodColor(String m) {
  switch (m) {
    case AppConstants.paymentCash:
      return AppColors.success;
    case AppConstants.paymentMtnMomo:
      return const Color(0xFFFFCC00);
    case AppConstants.paymentOrangeMoney:
      return const Color(0xFFFF6600);
    case AppConstants.paymentBankTransfer:
      return AppColors.info;
    default:
      return AppColors.textGray;
  }
}

String _methodLabel(String m, AppLocalizations l) {
  switch (m) {
    case AppConstants.paymentCash:
      return l.cash;
    case AppConstants.paymentMtnMomo:
      return 'MTN MoMo';
    case AppConstants.paymentOrangeMoney:
      return 'Orange Money';
    case AppConstants.paymentBankTransfer:
      return l.bankTransfer;
    default:
      return m;
  }
}
