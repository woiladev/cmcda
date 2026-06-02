import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';

enum _Phase { hidden, offline, syncing, synced }

/// Wraps the app and shows a thin bottom strip when the device is offline,
/// then a brief "syncing…/synced" confirmation once the connection returns and
/// Firestore finishes flushing its queued writes.
class ConnectivityBanner extends ConsumerStatefulWidget {
  final Widget child;
  const ConnectivityBanner({super.key, required this.child});

  @override
  ConsumerState<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends ConsumerState<ConnectivityBanner> {
  _Phase _phase = _Phase.hidden;

  void _onConnectivityChange(bool online) {
    if (!online) {
      if (_phase != _Phase.offline) setState(() => _phase = _Phase.offline);
      return;
    }
    // Back online. Only surface a sync confirmation if we were offline; on a
    // cold start that begins online we stay hidden.
    if (_phase == _Phase.offline) {
      setState(() => _phase = _Phase.syncing);
      FirebaseFirestore.instance.waitForPendingWrites().then((_) {
        if (!mounted || _phase != _Phase.syncing) return;
        setState(() => _phase = _Phase.synced);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _phase == _Phase.synced) {
            setState(() => _phase = _Phase.hidden);
          }
        });
      });
    } else if (_phase != _Phase.hidden) {
      setState(() => _phase = _Phase.hidden);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
      final online = next.valueOrNull;
      if (online != null) _onConnectivityChange(online);
    });

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _Strip(phase: _phase),
        ),
      ],
    );
  }
}

class _Strip extends StatelessWidget {
  final _Phase phase;
  const _Strip({required this.phase});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    final (String text, IconData icon, Color color, bool spin) = switch (phase) {
      _Phase.offline => (l.offlineBannerMessage, Icons.cloud_off_rounded,
          AppColors.textDark, false),
      _Phase.syncing =>
        (l.syncingMessage, Icons.sync_rounded, AppColors.primary, true),
      _Phase.synced =>
        (l.syncedMessage, Icons.cloud_done_rounded, AppColors.success, false),
      _Phase.hidden => ('', Icons.cloud_off_rounded, AppColors.textDark, false),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) => SizeTransition(
        sizeFactor: anim,
        axisAlignment: -1,
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: phase == _Phase.hidden
          ? const SizedBox.shrink(key: ValueKey('hidden'))
          : Material(
              key: ValueKey(phase),
              color: color,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (spin)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      else
                        Icon(icon, size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
