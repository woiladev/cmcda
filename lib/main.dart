import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'core/l10n/app_localizations.dart';
import 'core/services/language_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/router_service.dart';
import 'core/theme/app_theme.dart';
import 'presentation/widgets/common/connectivity_banner.dart';

// Must be a top-level function; runs in a separate isolate when the app is
// terminated and a push notification arrives
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Offline-first: persist the Firestore cache so reads work with no network
  // and writes queue locally and sync on reconnect. Must be set before any
  // other Firestore use. Unlimited cache so a field session's data survives.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Route all Flutter framework errors to Crashlytics.
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Route errors from the Dart async zone (Platform thread) to Crashlytics.
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // Register before runApp so the background isolate is ready immediately.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService.instance.initialize();

  // Load locale data for date/number formatting in fr/en/ar.
  await initializeDateFormatting();

  runApp(const ProviderScope(child: CMCDAApp()));
}

class CMCDAApp extends ConsumerWidget {
  const CMCDAApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final languageState = ref.watch(languageProvider);
    final isRTL = ref.watch(isRTLProvider);

    return MaterialApp.router(
      title: 'CMCDA Platform',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,

      // ── Localization ─────────────────────────────────────
      locale: languageState.locale,
      supportedLocales: const [
        Locale('fr'),
        Locale('en'),
        Locale('ar'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // ── RTL/LTR Directionality ───────────────────────────
      builder: (context, child) {
        return Directionality(
          textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
          child: ConnectivityBanner(child: child!),
        );
      },
    );
  }
}
