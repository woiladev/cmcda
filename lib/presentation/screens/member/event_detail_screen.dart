import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/event_model.dart';
import '../../widgets/common/fullscreen_gallery.dart';
import 'events_screen.dart';

class EventDetailScreen extends ConsumerWidget {
  final String eventId;
  const EventDetailScreen({required this.eventId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final eventAsync = ref.watch(eventByIdProvider(eventId));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: eventAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _NotFound(l: l),
        data: (event) {
          if (event == null) return _NotFound(l: l);
          return _Body(event: event, l: l);
        },
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  final AppLocalizations l;
  const _NotFound({required this.l});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Center(child: Text(l.noEvents)),
          const _BackButton(),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final EventModel event;
  final AppLocalizations l;
  const _Body({required this.event, required this.l});

  @override
  Widget build(BuildContext context) {
    final date = event.eventDate.toDate();
    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Gallery(event: event)),
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -AppConstants.spaceLG),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(AppConstants.radiusXL)),
                  ),
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.spaceLG,
                    AppConstants.spaceLG,
                    AppConstants.spaceLG,
                    120,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _CategoryChip(label: l.categoryLabel(event.category)),
                          const Spacer(),
                          if (event.isPast)
                            _Pill(
                              text: l.pastEvents,
                              color: AppColors.textGray,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppConstants.spaceMD),
                      Text(
                        event.title,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spaceLG),
                      _InfoTile(
                        icon: Icons.calendar_today_rounded,
                        label: l.eventDate,
                        value: AppUtils.formatDate(date),
                      ),
                      _InfoTile(
                        icon: Icons.schedule_rounded,
                        label: l.eventTime,
                        value: event.endDate != null
                            ? '${DateFormat('HH:mm').format(date)} — ${DateFormat('HH:mm').format(event.endDate!.toDate())}'
                            : DateFormat('HH:mm').format(date),
                      ),
                      if (event.location.isNotEmpty)
                        _InfoTile(
                          icon: Icons.place_rounded,
                          label: l.eventLocation,
                          value: event.location,
                        ),
                      if (event.organizer.isNotEmpty)
                        _InfoTile(
                          icon: Icons.groups_rounded,
                          label: l.eventOrganizer,
                          value: event.organizer,
                        ),
                      if (event.description.isNotEmpty) ...[
                        const SizedBox(height: AppConstants.spaceMD),
                        Text(
                          l.eventDescription,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textGray,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          event.description,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            height: 1.6,
                            color: AppColors.textMid,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SafeArea(child: _BackButton()),
        _ShareBar(
            label: l.shareEvent, onShare: () => shareEventMessage(event, l)),
      ],
    );
  }
}

class _Gallery extends StatefulWidget {
  final EventModel event;
  const _Gallery({required this.event});

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.event.imageUrls;
    if (images.isEmpty) {
      return Container(
        height: 240,
        width: double.infinity,
        color: AppColors.primary.withValues(alpha: 0.08),
        child: const Icon(Icons.event_rounded,
            size: 64, color: AppColors.primaryLight),
      );
    }

    return SizedBox(
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () =>
                  FullscreenGallery.open(context, images, initialIndex: i),
              child: Hero(
                tag: 'event-img-$i-${images[i]}',
                child: CachedNetworkImage(
                  imageUrl: images[i],
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                      color: AppColors.primary.withValues(alpha: 0.06)),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    child: const Icon(Icons.broken_image_rounded,
                        size: 44, color: AppColors.textGray),
                  ),
                ),
              ),
            ),
          ),
          // Bottom gradient for the rounded sheet transition.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 80,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      AppColors.bg.withValues(alpha: 0.6),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (images.length > 1)
            Positioned(
              bottom: AppConstants.spaceLG + 6,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  images.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? AppColors.white
                          : Colors.white.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              ),
            ),
          if (images.length > 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.photo_library_rounded,
                        color: Colors.white, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      '${images.length}',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: Colors.black.withValues(alpha: 0.4),
          shape: const CircleBorder(),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

class _ShareBar extends StatelessWidget {
  final String label;
  final VoidCallback onShare;
  const _ShareBar({required this.label, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          AppConstants.spaceLG,
          AppConstants.spaceMD,
          AppConstants.spaceLG,
          AppConstants.spaceMD + MediaQuery.of(context).padding.bottom,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: const Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: AppColors.textDark.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.share_rounded, size: 20),
            label: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  const _CategoryChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceSM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppConstants.radiusMD),
            ),
            child: Icon(icon, size: 19, color: AppColors.primary),
          ),
          const SizedBox(width: AppConstants.spaceMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textGray,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
