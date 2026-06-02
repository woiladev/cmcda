import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/event_model.dart';
import '../member/events_screen.dart';

class AdminEventsScreen extends ConsumerWidget {
  const AdminEventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final eventsAsync = ref.watch(allEventsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        title: Text(
          l.manageEvents,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        onPressed: () => context.push(AppRoutes.adminEventForm),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.createEvent,
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('$e')),
        data: (events) {
          if (events.isEmpty) {
            return Center(
              child: Text(l.noEvents,
                  style:
                      GoogleFonts.plusJakartaSans(color: AppColors.textGray)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceLG,
              AppConstants.spaceMD,
              AppConstants.spaceLG,
              100,
            ),
            itemCount: events.length,
            itemBuilder: (_, i) =>
                _AdminEventCard(event: events[i], l: l, ref: ref),
          );
        },
      ),
    );
  }
}

class _AdminEventCard extends StatelessWidget {
  final EventModel event;
  final AppLocalizations l;
  final WidgetRef ref;
  const _AdminEventCard({
    required this.event,
    required this.l,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceMD),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          onTap: () => context.push(AppRoutes.adminEventForm, extra: event),
          child: Container(
            padding: const EdgeInsets.all(AppConstants.spaceMD),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppConstants.radiusLG),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: (event.coverImage != null &&
                            event.coverImage!.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: event.coverImage!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Icon(
                                Icons.event_rounded,
                                color: AppColors.primaryLight),
                          )
                        : Container(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            child: const Icon(Icons.event_rounded,
                                color: AppColors.primaryLight),
                          ),
                  ),
                ),
                const SizedBox(width: AppConstants.spaceMD),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppUtils.formatDate(event.eventDate.toDate()),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppColors.textGray,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _StatusBadge(event: event, l: l),
                    ],
                  ),
                ),
                _ActionMenu(event: event, l: l, ref: ref),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final EventModel event;
  final AppLocalizations l;
  const _StatusBadge({required this.event, required this.l});

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;
    if (event.isPublished) {
      color = AppColors.success;
      label = l.eventPublished;
    } else if (event.isCancelled) {
      color = AppColors.error;
      label = l.eventCancelled;
    } else {
      color = AppColors.warning;
      label = l.eventDraft;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ActionMenu extends StatelessWidget {
  final EventModel event;
  final AppLocalizations l;
  final WidgetRef ref;
  const _ActionMenu({
    required this.event,
    required this.l,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(eventRepositoryProvider);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textGray),
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            context.push(AppRoutes.adminEventForm, extra: event);
            break;
          case 'publish':
            await repo
                .updateEvent(event.id, {'status': EventModel.statusPublished});
            break;
          case 'unpublish':
            await repo
                .updateEvent(event.id, {'status': EventModel.statusDraft});
            break;
          case 'delete':
            final ok = await _confirmDelete(context, l);
            if (ok == true) {
              await repo.deleteEvent(event.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.eventDeleted)),
                );
              }
            }
            break;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'edit', child: Text(l.editEvent)),
        if (event.isPublished)
          PopupMenuItem(value: 'unpublish', child: Text(l.unpublishEvent))
        else
          PopupMenuItem(value: 'publish', child: Text(l.publishEvent)),
        PopupMenuItem(
          value: 'delete',
          child: Text(l.deleteEvent,
              style: const TextStyle(color: AppColors.error)),
        ),
      ],
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, AppLocalizations l) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteEvent),
        content: Text(l.deleteEventConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.deleteEvent,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
