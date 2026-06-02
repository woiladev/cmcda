import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/router_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/event_model.dart';
import '../member/events_screen.dart';

class AdminEventFormScreen extends ConsumerStatefulWidget {
  final EventModel? event;
  const AdminEventFormScreen({this.event, super.key});

  @override
  ConsumerState<AdminEventFormScreen> createState() =>
      _AdminEventFormScreenState();
}

class _AdminEventFormScreenState extends ConsumerState<AdminEventFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _organizer;
  late final TextEditingController _description;

  String? _region;
  late DateTime _date;
  DateTime? _endDate;
  late String _status;
  late String _category;

  // Existing remote images kept, plus newly picked local files. Combined ≤ 5.
  final List<String> _existingUrls = [];
  final List<XFile> _newImages = [];
  bool _saving = false;

  bool get _isEdit => widget.event != null;
  int get _imageCount => _existingUrls.length + _newImages.length;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _title = TextEditingController(text: e?.title ?? '');
    _region = AppConstants.cameroonRegions.contains(e?.location)
        ? e!.location
        : null;
    _organizer = TextEditingController(text: e?.organizer ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _date =
        e?.eventDate.toDate() ?? DateTime.now().add(const Duration(days: 1));
    _endDate = e?.endDate?.toDate();
    _status = e?.status ?? EventModel.statusDraft;
    _category = e?.category ?? EventModel.categoryGeneral;
    if (e != null) _existingUrls.addAll(e.imageUrls);
  }

  @override
  void dispose() {
    _title.dispose();
    _organizer.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remaining = EventModel.maxImages - _imageCount;
    if (remaining <= 0) {
      _toast(AppLocalizations.of(context).maxPhotosReached);
      return;
    }
    final picked = await ImagePicker().pickMultiImage(limit: remaining);
    if (picked.isEmpty) return;
    setState(() => _newImages.addAll(picked.take(remaining)));
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickDate({required bool isEnd}) async {
    final base = isEnd ? (_endDate ?? _date) : _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    final updated =
        DateTime(picked.year, picked.month, picked.day, base.hour, base.minute);
    setState(() => isEnd ? _endDate = updated : _date = updated);
  }

  Future<void> _pickTime({required bool isEnd}) async {
    final base = isEnd ? (_endDate ?? _date) : _date;
    final picked = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (picked == null) return;
    final updated =
        DateTime(base.year, base.month, base.day, picked.hour, picked.minute);
    setState(() => isEnd ? _endDate = updated : _date = updated);
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    final profile = ref.read(currentUserProfileProvider).valueOrNull;
    if (profile == null) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(eventRepositoryProvider);
      final uploaded = await repo.uploadImages(_newImages, profile.id);
      final imageUrls = [..._existingUrls, ...uploaded];

      if (_isEdit) {
        await repo.updateEvent(widget.event!.id, {
          'title': _title.text.trim(),
          'location': _region ?? '',
          'organizer': _organizer.text.trim(),
          'description': _description.text.trim(),
          'eventDate': _date,
          'endDate': _endDate ?? FieldValue.delete(),
          'category': _category,
          'status': _status,
          'imageUrls': imageUrls,
        });
      } else {
        await repo.createEvent(
          title: _title.text.trim(),
          location: _region ?? '',
          organizer: _organizer.text.trim(),
          description: _description.text.trim(),
          eventDate: _date,
          endDate: _endDate,
          category: _category,
          imageUrls: imageUrls,
          status: _status,
          createdBy: profile.id,
          createdByName: profile.fullName,
        );
      }

      if (mounted) {
        _toast(l.eventSaved);
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        title: Text(
          _isEdit ? l.editEvent : l.createEvent,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppConstants.spaceLG),
          children: [
            _SectionLabel(text: '${l.eventPhotos}  ($_imageCount/5)'),
            const SizedBox(height: AppConstants.spaceSM),
            _ImageGrid(
              existingUrls: _existingUrls,
              newImages: _newImages,
              canAdd: _imageCount < EventModel.maxImages,
              addLabel: l.addPhotos,
              onAdd: _pickImages,
              onRemoveExisting: (i) =>
                  setState(() => _existingUrls.removeAt(i)),
              onRemoveNew: (i) => setState(() => _newImages.removeAt(i)),
            ),
            const SizedBox(height: AppConstants.spaceLG),
            _Field(
              controller: _title,
              label: l.eventTitleLabel,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l.fieldRequired : null,
            ),
            const SizedBox(height: AppConstants.spaceMD),
            _SectionLabel(text: l.eventCategory),
            const SizedBox(height: AppConstants.spaceSM),
            _CategorySelector(
              selected: _category,
              labelOf: l.categoryLabel,
              onChanged: (c) => setState(() => _category = c),
            ),
            const SizedBox(height: AppConstants.spaceMD),
            DropdownButtonFormField<String>(
              initialValue: _region,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l.eventLocation,
                prefixIcon: const Icon(Icons.location_on_outlined),
              ),
              items: AppConstants.cameroonRegions
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (v) => setState(() => _region = v),
            ),
            const SizedBox(height: AppConstants.spaceMD),
            _Field(controller: _organizer, label: l.eventOrganizer),
            const SizedBox(height: AppConstants.spaceMD),
            _Field(
              controller: _description,
              label: l.eventDescription,
              maxLines: 4,
            ),
            const SizedBox(height: AppConstants.spaceMD),
            Row(
              children: [
                Expanded(
                  child: _PickerTile(
                    icon: Icons.calendar_today_rounded,
                    label: l.eventDate,
                    value: DateFormat('dd/MM/yyyy').format(_date),
                    onTap: () => _pickDate(isEnd: false),
                  ),
                ),
                const SizedBox(width: AppConstants.spaceMD),
                Expanded(
                  child: _PickerTile(
                    icon: Icons.schedule_rounded,
                    label: l.eventTime,
                    value: DateFormat('HH:mm').format(_date),
                    onTap: () => _pickTime(isEnd: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceMD),
            _EndDateRow(
              label: l.eventEndDate,
              endDate: _endDate,
              onEnable: () => setState(
                  () => _endDate = _date.add(const Duration(hours: 2))),
              onClear: () => setState(() => _endDate = null),
              onPickDate: () => _pickDate(isEnd: true),
              onPickTime: () => _pickTime(isEnd: true),
            ),
            const SizedBox(height: AppConstants.spaceLG),
            _StatusSelector(
              status: _status,
              l: l,
              onChanged: (s) => setState(() => _status = s),
            ),
            const SizedBox(height: AppConstants.spaceXL),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.white),
                      )
                    : Text(l.save,
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: AppColors.textGray,
      ),
    );
  }
}

class _ImageGrid extends StatelessWidget {
  final List<String> existingUrls;
  final List<XFile> newImages;
  final bool canAdd;
  final String addLabel;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemoveExisting;
  final ValueChanged<int> onRemoveNew;

  const _ImageGrid({
    required this.existingUrls,
    required this.newImages,
    required this.canAdd,
    required this.addLabel,
    required this.onAdd,
    required this.onRemoveExisting,
    required this.onRemoveNew,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      for (int i = 0; i < existingUrls.length; i++)
        _Thumb(
          image: CachedNetworkImage(
            imageUrl: existingUrls[i],
            width: 92,
            height: 92,
            fit: BoxFit.cover,
            placeholder: (_, __) =>
                Container(color: AppColors.primary.withValues(alpha: 0.06)),
            errorWidget: (_, __, ___) => Container(
              color: AppColors.primary.withValues(alpha: 0.08),
              child: const Icon(Icons.broken_image_rounded,
                  size: 24, color: AppColors.textGray),
            ),
          ),
          onRemove: () => onRemoveExisting(i),
        ),
      for (int i = 0; i < newImages.length; i++)
        _Thumb(
          image: Image.file(File(newImages[i].path),
              width: 92, height: 92, fit: BoxFit.cover),
          onRemove: () => onRemoveNew(i),
        ),
      if (canAdd) _AddTile(label: addLabel, onTap: onAdd),
    ];

    return Wrap(
      spacing: AppConstants.spaceSM,
      runSpacing: AppConstants.spaceSM,
      children: tiles,
    );
  }
}

class _Thumb extends StatelessWidget {
  final Widget image;
  final VoidCallback onRemove;
  const _Thumb({required this.image, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            child: image,
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    size: 15, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
              style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_rounded,
                color: AppColors.primary, size: 22),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  final String selected;
  final String Function(String) labelOf;
  final ValueChanged<String> onChanged;
  const _CategorySelector({
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppConstants.spaceSM,
      runSpacing: AppConstants.spaceSM,
      children: EventModel.categories.map((c) {
        final isSel = c == selected;
        return GestureDetector(
          onTap: () => onChanged(c),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSel ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              border: Border.all(
                  color: isSel ? AppColors.primary : AppColors.border),
            ),
            child: Text(
              labelOf(c),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSel ? AppColors.white : AppColors.textMid,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _EndDateRow extends StatelessWidget {
  final String label;
  final DateTime? endDate;
  final VoidCallback onEnable;
  final VoidCallback onClear;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

  const _EndDateRow({
    required this.label,
    required this.endDate,
    required this.onEnable,
    required this.onClear,
    required this.onPickDate,
    required this.onPickTime,
  });

  @override
  Widget build(BuildContext context) {
    if (endDate == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onEnable,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(label,
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: _PickerTile(
            icon: Icons.event_available_rounded,
            label: label,
            value: DateFormat('dd/MM/yyyy').format(endDate!),
            onTap: onPickDate,
          ),
        ),
        const SizedBox(width: AppConstants.spaceSM),
        Expanded(
          child: _PickerTile(
            icon: Icons.schedule_rounded,
            label: label,
            value: DateFormat('HH:mm').format(endDate!),
            onTap: onPickTime,
          ),
        ),
        IconButton(
          onPressed: onClear,
          icon: const Icon(Icons.close_rounded, color: AppColors.textGray),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final String? Function(String?)? validator;
  const _Field({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceMD, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: AppConstants.spaceSM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: AppColors.textGray)),
                  Text(value,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusSelector extends StatelessWidget {
  final String status;
  final AppLocalizations l;
  final ValueChanged<String> onChanged;
  const _StatusSelector({
    required this.status,
    required this.l,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      (EventModel.statusDraft, l.eventDraft),
      (EventModel.statusPublished, l.eventPublished),
    ];
    return Row(
      children: options.map((o) {
        final selected = status == o.$1;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: AppConstants.spaceSM),
            child: GestureDetector(
              onTap: () => onChanged(o.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                  border: Border.all(
                      color: selected ? AppColors.primary : AppColors.border),
                ),
                child: Text(
                  o.$2,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.white : AppColors.textMid,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
