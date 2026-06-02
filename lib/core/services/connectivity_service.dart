import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams whether the device currently has a network interface available.
///
/// connectivity_plus reports interface availability (wifi/mobile/none), not
/// true internet reachability — that's fine for the offline banner; Firestore
/// handles the actual queue/sync regardless of what this reports.
///
/// On Android, connectivity_plus can emit a spurious/transient `none` (or an
/// empty list, which also reads as offline) and then go quiet — the OS never
/// fires a corrective event because the interface never really changed. With a
/// pure event stream that would latch the offline banner on forever (only an
/// app restart re-ran the one-shot check). So we merge the change stream with a
/// periodic re-check and only surface distinct values: a stuck/false offline
/// now self-heals within the poll interval.
final connectivityProvider = StreamProvider<bool>((ref) {
  final connectivity = Connectivity();

  bool isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  final controller = StreamController<bool>();
  bool? last;

  void emit(bool online) {
    if (online != last) {
      last = online;
      controller.add(online);
    }
  }

  Future<void> recheck() async {
    try {
      emit(isOnline(await connectivity.checkConnectivity()));
    } catch (_) {
      // Best-effort; a later event or poll resolves it.
    }
  }

  final sub =
      connectivity.onConnectivityChanged.listen((r) => emit(isOnline(r)));
  final timer = Timer.periodic(const Duration(seconds: 10), (_) => recheck());

  // Seed the current state immediately so consumers don't wait for the timer.
  recheck();

  ref.onDispose(() {
    sub.cancel();
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});
