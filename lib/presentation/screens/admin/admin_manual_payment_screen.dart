import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'dart:async';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/contribution_repository.dart';

// ── Member search provider ────────────────────────────────────

final _memberSearchProvider =
    FutureProvider.autoDispose.family<List<UserModel>, String>((ref, query) async {
  final q = query.trim().toLowerCase();
  if (q.length < 2) return [];

  // Fetch all members (equality filter only — no composite index needed)
  final snap = await FirebaseFirestore.instance
      .collection(AppConstants.usersCollection)
      .where('role', isEqualTo: AppConstants.roleMember)
      .limit(200)
      .get();

  // Filter client-side: match memberNumber OR firstName prefix (case-insensitive)
  return snap.docs
      .map(UserModel.fromFirestore)
      .where((m) {
        final num = m.memberNumber.toLowerCase();
        final name = m.firstName.toLowerCase();
        return num.contains(q) || name.startsWith(q);
      })
      .take(8)
      .toList();
});

// ── Screen ────────────────────────────────────────────────────

class AdminManualPaymentScreen extends ConsumerStatefulWidget {
  const AdminManualPaymentScreen({super.key});

  @override
  ConsumerState<AdminManualPaymentScreen> createState() =>
      _AdminManualPaymentScreenState();
}

class _AdminManualPaymentScreenState
    extends ConsumerState<AdminManualPaymentScreen> {
  final _repo = ContributionRepository();

  // Search
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  UserModel? _selectedMember;
  Timer? _searchDebounce;

  // Payment form
  String _periodType = AppConstants.periodMonthly;
  DateTime _selectedMonth = DateTime.now();
  String _paymentMethod = AppConstants.paymentCash;
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;
  bool _success = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = AppConstants.amountMonthly.toString();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = v);
    });
  }

  // ── Helpers ───────────────────────────────────────────────

  int get _defaultAmount {
    switch (_periodType) {
      case AppConstants.periodDaily:
        return AppConstants.amountDaily;
      case AppConstants.periodAnnual:
        return AppConstants.amountAnnual;
      default:
        return AppConstants.amountMonthly;
    }
  }

  String get _periodString {
    if (_periodType == AppConstants.periodMonthly) {
      return DateFormat('yyyy-MM').format(_selectedMonth);
    }
    if (_periodType == AppConstants.periodAnnual) {
      return _selectedMonth.year.toString();
    }
    return AppUtils.getPeriodForDate(DateTime.now());
  }

  String _periodLabelFor(BuildContext context) {
    final localeCode = Localizations.localeOf(context).languageCode;
    if (_periodType == AppConstants.periodMonthly) {
      final s = DateFormat('MMMM yyyy', localeCode).format(_selectedMonth);
      return s[0].toUpperCase() + s.substring(1);
    }
    if (_periodType == AppConstants.periodAnnual) {
      return '${AppLocalizations.of(context).yearLabel} ${_selectedMonth.year}';
    }
    return AppUtils.formatDate(DateTime.now());
  }

  void _onPeriodTypeChanged(String type) {
    setState(() {
      _periodType = type;
      _amountCtrl.text = _defaultAmount.toString();
    });
  }

  void _prevPeriod() {
    setState(() {
      if (_periodType == AppConstants.periodAnnual) {
        _selectedMonth = DateTime(_selectedMonth.year - 1);
      } else {
        _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
      }
    });
  }

  void _nextPeriod() {
    final now = DateTime.now();
    setState(() {
      DateTime next;
      if (_periodType == AppConstants.periodAnnual) {
        next = DateTime(_selectedMonth.year + 1);
      } else {
        next = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
      }
      if (!next.isAfter(DateTime(now.year, now.month + 1))) {
        _selectedMonth = next;
      }
    });
  }

  // ── Submit ────────────────────────────────────────────────

  Future<void> _submit() async {
    final member = _selectedMember;
    if (member == null) return;

    final amount = int.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _errorMsg = 'Montant invalide');
      return;
    }

    setState(() { _submitting = true; _errorMsg = null; });

    try {
      final adminId = ref.read(currentUserProfileProvider).valueOrNull?.id ?? '';

      await _repo.createContribution(
        memberId: member.id,
        memberName: '${member.firstName} ${member.lastName}',
        memberNumber: member.memberNumber,
        amount: amount,
        periodType: _periodType,
        paymentMethod: _paymentMethod,
        recordedBy: adminId,
        period: _periodString,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      // Notify other admins a payment is pending validation
      if (adminId.isNotEmpty) {
        NotificationService.instance.notifyAdminPayment(
          creatorId: adminId,
          memberName: '${member.firstName} ${member.lastName}',
          amount: AppUtils.formatAmount(amount),
        ).ignore();
      }

      if (mounted) setState(() { _submitting = false; _success = true; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMsg = e.toString();
        });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: _success
                  ? _buildSuccess(context)
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(AppConstants.spaceMD),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildMemberSearch(context),
                          if (_selectedMember != null) ...[
                            const SizedBox(height: AppConstants.spaceMD),
                            _buildPaymentForm(context),
                          ],
                          const SizedBox(height: AppConstants.spaceXL),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
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
        MediaQuery.of(context).padding.top + AppConstants.spaceMD,
        AppConstants.spaceMD,
        AppConstants.spaceLG,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paiement manuel',
                style: GoogleFonts.playfairDisplay(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Enregistrer un paiement pour un membre',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Member search ─────────────────────────────────────────

  Widget _buildMemberSearch(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.person_search_outlined,
          label: 'Rechercher un membre',
        ),
        const SizedBox(height: AppConstants.spaceSM),
        if (_selectedMember == null) ...[
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Nom ou numéro de membre (CM-...)',
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
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
                borderSide: const BorderSide(color: AppColors.primary, width: 2),
              ),
            ),
            onChanged: _onSearchChanged,
          ),
          if (_searchQuery.trim().length >= 2) ...[
            const SizedBox(height: AppConstants.spaceSM),
            _buildSearchResults(),
          ],
        ] else
          _buildSelectedMemberCard(),
      ],
    );
  }

  Widget _buildSearchResults() {
    final searchAsync =
        ref.watch(_memberSearchProvider(_searchQuery.trim()));
    return searchAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppConstants.spaceMD),
        child: Center(
          child: CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppConstants.spaceSM),
        child: Text('Erreur: $e', style: const TextStyle(color: AppColors.error, fontSize: 12)),
      ),
      data: (members) {
        if (members.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppConstants.spaceMD),
            child: Center(
              child: Text(
                'Aucun membre trouvé',
                style: TextStyle(color: AppColors.textGray, fontSize: 13),
              ),
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: members.asMap().entries.map((e) {
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
                    borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spaceMD,
                        vertical: AppConstants.spaceSM + 2,
                      ),
                      child: Row(
                        children: [
                          _MemberAvatar(name: m.firstName),
                          const SizedBox(width: AppConstants.spaceSM),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${m.firstName} ${m.lastName}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                Text(
                                  '${m.memberNumber} · ${m.region}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textGray,
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
                  if (i < members.length - 1)
                    const Divider(height: 1, indent: 56),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildSelectedMemberCard() {
    final m = _selectedMember!;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMD),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          _MemberAvatar(name: m.firstName, size: 44, color: AppColors.primary),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${m.firstName} ${m.lastName}',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${m.memberNumber} · ${m.region}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textGray),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _selectedMember = null),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  color: AppColors.error, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ── Payment form ──────────────────────────────────────────

  Widget _buildPaymentForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          icon: Icons.receipt_long_outlined,
          label: 'Détails du paiement',
        ),
        const SizedBox(height: AppConstants.spaceSM),
        Container(
          padding: const EdgeInsets.all(AppConstants.spaceMD),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppConstants.radiusLG),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Period type
              const _FieldLabel('Type de période'),
              const SizedBox(height: AppConstants.spaceSM),
              _buildPeriodTypeSelector(),
              const SizedBox(height: AppConstants.spaceMD),

              // Period navigator (monthly/quarterly/annual)
              if (_periodType != AppConstants.periodDaily) ...[
                const _FieldLabel('Période'),
                const SizedBox(height: AppConstants.spaceSM),
                _buildPeriodNavigator(),
                const SizedBox(height: AppConstants.spaceMD),
              ],

              // Amount
              const _FieldLabel('Montant (FCFA)'),
              const SizedBox(height: AppConstants.spaceSM),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
                decoration: InputDecoration(
                  hintText: '0',
                  suffixText: 'FCFA',
                  suffixStyle: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  filled: true,
                  fillColor: AppColors.bg,
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
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceMD),

              // Payment method
              const _FieldLabel('Méthode de paiement'),
              const SizedBox(height: AppConstants.spaceSM),
              _buildPaymentMethodSelector(),
              const SizedBox(height: AppConstants.spaceMD),

              // Notes
              const _FieldLabel('Notes (optionnel)'),
              const SizedBox(height: AppConstants.spaceSM),
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                maxLength: 200,
                decoration: InputDecoration(
                  hintText: 'Remarques sur ce paiement...',
                  filled: true,
                  fillColor: AppColors.bg,
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
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spaceMD),

        // Error
        if (_errorMsg != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppColors.error, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMsg!,
                    style: const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spaceMD),
        ],

        // Submit
        ElevatedButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded, size: 20),
          label: Text(_submitting ? 'Enregistrement...' : 'Enregistrer le paiement'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            ),
            textStyle: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spaceSM),
        Text(
          _paymentMethod == AppConstants.paymentCash ||
                  _paymentMethod == AppConstants.paymentBankTransfer
              ? 'Ce paiement sera en attente de validation par un second administrateur.'
              : '',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textGray, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildPeriodTypeSelector() {
    final types = [
      (AppConstants.periodDaily, 'Quotidien', '☀️'),
      (AppConstants.periodMonthly, 'Mensuel', '📅'),
      (AppConstants.periodAnnual, 'Annuel', '📆'),
    ];

    return Wrap(
      spacing: AppConstants.spaceSM,
      runSpacing: AppConstants.spaceSM,
      children: types.map((t) {
        final selected = _periodType == t.$1;
        return GestureDetector(
          onTap: () => _onPeriodTypeChanged(t.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : AppColors.bg,
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.$3, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  t.$2,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPeriodNavigator() {
    final now = DateTime.now();
    final isMax = _periodType == AppConstants.periodAnnual
        ? _selectedMonth.year >= now.year
        : _selectedMonth.year >= now.year &&
            _selectedMonth.month >= now.month;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _prevPeriod,
            icon: const Icon(Icons.chevron_left_rounded),
            color: AppColors.primary,
          ),
          Expanded(
            child: Text(
              _periodLabelFor(context),
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          IconButton(
            onPressed: isMax ? null : _nextPeriod,
            icon: const Icon(Icons.chevron_right_rounded),
            color: isMax ? AppColors.border : AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodSelector() {
    final methods = [
      (AppConstants.paymentCash, '💵', 'Espèces'),
      (AppConstants.paymentBankTransfer, '🏦', 'Virement bancaire'),
    ];

    return Column(
      children: methods.map((m) {
        final selected = _paymentMethod == m.$1;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppConstants.spaceSM),
          child: GestureDetector(
            onTap: () => setState(() => _paymentMethod = m.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceMD,
                vertical: AppConstants.spaceSM + 4,
              ),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary.withValues(alpha: 0.06) : AppColors.bg,
                borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Text(m.$2, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: AppConstants.spaceSM),
                  Expanded(
                    child: Text(
                      m.$3,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: selected ? AppColors.primary : AppColors.textDark,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.primary, size: 20),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Success state ─────────────────────────────────────────

  Widget _buildSuccess(BuildContext context) {
    final m = _selectedMember;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: AppColors.success, size: 44),
            ),
            const SizedBox(height: AppConstants.spaceLG),
            Text(
              'Paiement enregistré',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: AppConstants.spaceSM),
            if (m != null)
              Text(
                'Le paiement de ${m.firstName} ${m.lastName} a été enregistré.\nEn attente de validation.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textGray,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            const SizedBox(height: AppConstants.spaceXL),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => setState(() {
                  _success = false;
                  _selectedMember = null;
                  _amountCtrl.text = AppConstants.amountMonthly.toString();
                  _notesCtrl.clear();
                  _periodType = AppConstants.periodMonthly;
                  _selectedMonth = DateTime.now();
                  _paymentMethod = AppConstants.paymentCash;
                }),
                child: const Text('Nouveau paiement'),
              ),
            ),
            const SizedBox(height: AppConstants.spaceSM),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Retour au tableau de bord'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: AppConstants.spaceXS),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textGray,
      ),
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color color;
  const _MemberAvatar({
    required this.name,
    this.size = 36,
    this.color = AppColors.primaryLight,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}
