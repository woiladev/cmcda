import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/event_model.dart';
import '../../../data/repositories/event_repository.dart';

// ── Providers ─────────────────────────────────────────────────
final eventRepositoryProvider =
    Provider<EventRepository>((_) => EventRepository());

final publishedEventsProvider =
    StreamProvider.autoDispose<List<EventModel>>((ref) {
  return ref.watch(eventRepositoryProvider).streamPublished();
});

final allEventsProvider = StreamProvider.autoDispose<List<EventModel>>((ref) {
  return ref.watch(eventRepositoryProvider).streamAll();
});

final eventByIdProvider =
    StreamProvider.autoDispose.family<EventModel?, String>((ref, id) {
  return ref.watch(eventRepositoryProvider).streamOne(id);
});

/// Builds a rich, shareable message for an event — including the CMCDA vision
/// and a call to the Ummah — and opens the system share sheet.
void shareEventMessage(EventModel event, AppLocalizations l) {
  final date = event.eventDate.toDate();
  final buf = StringBuffer()
    ..writeln('🌙 ${event.title}')
    ..writeln(
        '📅 ${AppUtils.formatDate(date)} • ${DateFormat('HH:mm').format(date)}');
  if (event.location.isNotEmpty) buf.writeln('📍 ${event.location}');
  buf.writeln();
  if (event.description.isNotEmpty) buf.writeln(event.description);
  buf
    ..writeln()
    ..writeln('—' * 16)
    ..writeln('${AppConstants.orgNameFr} (${AppConstants.acronym})')
    ..writeln(AppConstants.taglineFr)
    ..writeln(l.joinUmmahCta)
    ..writeln('🔗 ${AppConstants.contactWebsite}');
  Share.share(buf.toString(), subject: event.title);
}

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final eventsAsync = ref.watch(publishedEventsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(title: l.events),
            Expanded(
              child: eventsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                  child: Text(l.noEvents,
                      style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textGray)),
                ),
                data: (events) {
                  if (events.isEmpty) return _EmptyState(label: l.noEvents);
                  final upcoming =
                      events.where((e) => !e.isPast).toList().reversed.toList();
                  final past = events.where((e) => e.isPast).toList();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.spaceLG,
                      AppConstants.spaceMD,
                      AppConstants.spaceLG,
                      AppConstants.spaceXL,
                    ),
                    children: [
                      if (upcoming.isNotEmpty) ...[
                        _SectionLabel(text: l.upcomingEvents),
                        ...upcoming.map((e) => _EventCard(event: e)),
                      ],
                      if (past.isNotEmpty) ...[
                        const SizedBox(height: AppConstants.spaceMD),
                        _SectionLabel(text: l.pastEvents),
                        ...past.map((e) => _EventCard(event: e, dimmed: true)),
                      ],
                    ],
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

class _Header extends StatelessWidget {
  final String title;
  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceLG,
        AppConstants.spaceMD,
        AppConstants.spaceLG,
        AppConstants.spaceSM,
      ),
      child: Row(
        children: [
          const Icon(Icons.event_rounded, color: AppColors.primary, size: 26),
          const SizedBox(width: AppConstants.spaceSM),
          Text(
            title,
            style: GoogleFonts.playfairDisplay(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceSM, top: 4),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: AppColors.textGray,
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final EventModel event;
  final bool dimmed;
  const _EventCard({required this.event, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.7 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppConstants.spaceMD),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppConstants.radiusLG),
            onTap: () => context.push(AppRoutes.eventDetail, extra: event.id),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.radiusLG),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      _CoverImage(url: event.coverImage, height: 150),
                      Positioned(
                        top: AppConstants.spaceSM,
                        left: AppConstants.spaceSM,
                        child: _OverlayChip(
                          text: AppLocalizations.of(context)
                              .categoryLabel(event.category),
                        ),
                      ),
                      if (event.imageUrls.length > 1)
                        Positioned(
                          top: AppConstants.spaceSM,
                          right: AppConstants.spaceSM,
                          child: _OverlayChip(
                            icon: Icons.photo_library_rounded,
                            text: '${event.imageUrls.length}',
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppConstants.spaceMD),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                event.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(Icons.share_rounded,
                                  size: 20, color: AppColors.primary),
                              onPressed: () => shareEventMessage(
                                  event, AppLocalizations.of(context)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _MetaRow(
                          icon: Icons.calendar_today_rounded,
                          text: AppUtils.formatDate(event.eventDate.toDate()),
                        ),
                        if (event.location.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _MetaRow(
                            icon: Icons.place_rounded,
                            text: event.location,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textGray),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppColors.textMid,
            ),
          ),
        ),
      ],
    );
  }
}

class _OverlayChip extends StatelessWidget {
  final String text;
  final IconData? icon;
  const _OverlayChip({required this.text, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            icon == null ? text.toUpperCase() : text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: icon == null ? 0.4 : 0,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  final String? url;
  final double height;
  const _CoverImage({required this.url, required this.height});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        height: height,
        width: double.infinity,
        color: AppColors.primary.withValues(alpha: 0.08),
        child: const Icon(Icons.event_rounded,
            size: 44, color: AppColors.primaryLight),
      );
    }
    return CachedNetworkImage(
      imageUrl: url!,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        height: height,
        color: AppColors.primary.withValues(alpha: 0.06),
      ),
      errorWidget: (_, __, ___) => Container(
        height: height,
        width: double.infinity,
        color: AppColors.primary.withValues(alpha: 0.08),
        child: const Icon(Icons.broken_image_rounded,
            size: 40, color: AppColors.textGray),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String label;
  const _EmptyState({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_busy_rounded,
              size: 56, color: AppColors.textLight),
          const SizedBox(height: AppConstants.spaceMD),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              color: AppColors.textGray,
            ),
          ),
        ],
      ),
    );
  }
}
