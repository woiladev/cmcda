import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../constants/app_routes.dart';
import '../services/notification_service.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../presentation/screens/auth/splash_screen.dart';
import '../../presentation/screens/auth/onboarding_screen.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/complete_profile_screen.dart';
import '../../presentation/screens/member/member_dashboard_screen.dart';
import '../../presentation/screens/member/member_shell.dart';
import '../../presentation/screens/member/payment_screen.dart';
import '../../presentation/screens/member/profile_screen.dart';
import '../../presentation/screens/member/notifications_screen.dart';
import '../../presentation/screens/member/reminder_settings_screen.dart';
import '../../presentation/screens/member/events_screen.dart';
import '../../presentation/screens/member/event_detail_screen.dart';
import '../../presentation/screens/admin/admin_dashboard_screen.dart';
import '../../presentation/screens/admin/admin_members_screen.dart';
import '../../presentation/screens/admin/admin_payments_screen.dart';
import '../../presentation/screens/admin/admin_shell.dart';
import '../../presentation/screens/admin/admin_settings_screen.dart';
import '../../presentation/screens/focal/focal_dashboard_screen.dart';
import '../../presentation/screens/focal/focal_members_screen.dart';
import '../../presentation/screens/focal/focal_payments_screen.dart';
import '../../presentation/screens/focal/focal_profile_screen.dart';
import '../../presentation/screens/focal/focal_reports_screen.dart';
import '../../presentation/screens/focal/focal_session_screen.dart';
import '../../presentation/screens/focal/focal_shell.dart';
import '../../presentation/screens/member/receipts_screen.dart';
import '../../presentation/screens/member/transparency_screen.dart';
import '../../presentation/screens/admin/admin_wallet_screen.dart';
import '../../presentation/screens/admin/admin_wallet_account_screen.dart';
import '../../presentation/screens/admin/admin_manual_payment_screen.dart';
import '../../presentation/screens/admin/admin_focal_reports_screen.dart';
import '../../presentation/screens/admin/admin_audit_screen.dart';
import '../../presentation/screens/admin/admin_team_screen.dart';
import '../../presentation/screens/admin/admin_bank_details_screen.dart';
import '../../presentation/screens/admin/admin_analytics_screen.dart';
import '../../presentation/screens/focal/focal_report_detail_screen.dart';
import '../../presentation/screens/admin/admin_events_screen.dart';
import '../../presentation/screens/admin/admin_event_form_screen.dart';
import '../../presentation/screens/common/privacy_policy_screen.dart';
import '../../presentation/screens/common/help_screen.dart';
import '../../presentation/screens/common/about_screen.dart';
import '../../data/models/event_model.dart';

// ── Auth State Providers ──────────────────────────────────────

final _authRepo = AuthRepository();

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final currentUserProfileProvider = StreamProvider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) =>
        user != null ? _authRepo.userStream(user.uid) : Stream.value(null),
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
  );
});

// ── View Mode Provider ────────────────────────────────────────
// Tracks whether an admin is intentionally browsing the member view.
// Resets to false on app restart (session-only).
final viewingAsMemberProvider = StateProvider<bool>((ref) => false);

// Increments each time the Pay tab is entered from a different tab.
// PaymentScreen listens to this to reset its success state.
final paymentTabActivationProvider = StateProvider<int>((ref) => 0);

// ── Router Notifier (bridges Riverpod → GoRouter refresh) ────

class _RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  _RouterNotifier(this._ref) {
    _ref.listen(authStateProvider, (_, __) => notifyListeners());
    _ref.listen(currentUserProfileProvider, (_, __) => notifyListeners());
    _ref.listen(viewingAsMemberProvider, (_, __) => notifyListeners());
  }
}

// ── Root navigator key ────────────────────────────────────────
// Shared with NotificationService so push-notification taps can navigate
// without needing a BuildContext.
final _rootNavigatorKey = NotificationService.instance.navigatorKey;

// ── Router Provider ───────────────────────────────────────────

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: notifier,
    redirect: (BuildContext context, GoRouterState state) {
      final authAsync = ref.read(authStateProvider);
      final profileAsync = ref.read(currentUserProfileProvider);

      // Still loading auth — stay put
      if (authAsync.isLoading) return null;

      final user = authAsync.valueOrNull;
      final isLoggedIn = user != null;
      final location = state.matchedLocation;

      // Splash controls its own navigation timing — never auto-redirect from it
      if (location == AppRoutes.splash) return null;

      final publicRoutes = {
        AppRoutes.login,
        AppRoutes.signup,
        AppRoutes.onboarding,
      };

      if (!isLoggedIn) {
        return publicRoutes.contains(location) ? null : AppRoutes.login;
      }

      // User is authenticated — wait for Firestore profile stream
      if (profileAsync.isLoading || profileAsync.hasError) return null;

      final profile = profileAsync.valueOrNull;

      // No Firestore doc yet — new social/phone user needs to complete profile
      if (profile == null) {
        return location == AppRoutes.completeProfile
            ? null
            : AppRoutes.completeProfile;
      }

      // Profile exists — redirect away from complete-profile or public routes
      if (location == AppRoutes.completeProfile ||
          publicRoutes.contains(location)) {
        final role = profile.role;
        if (role == AppConstants.roleAdmin ||
            role == AppConstants.roleSuperAdmin) {
          return AppRoutes.admin;
        }
        if (role == AppConstants.roleFocal) return AppRoutes.focal;
        return AppRoutes.dashboard;
      }

      // Super-admin-only routes
      if ((location == AppRoutes.adminAudit ||
              location == AppRoutes.adminTeam ||
              location == AppRoutes.adminBankDetails) &&
          profile.role != AppConstants.roleSuperAdmin) {
        return AppRoutes.admin;
      }

      return null;
    },
    errorBuilder: (context, state) => _ErrorPage(error: state.error),
    routes: [
      // ── Public ──────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (_, __) => const LoginScreen(startOnSignup: true),
      ),
      GoRoute(
        path: AppRoutes.completeProfile,
        builder: (_, __) => const CompleteProfileScreen(),
      ),

      // ── Member shell (persistent nav bar across 4 tabs) ─────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MemberShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.dashboard,
              builder: (_, __) => const MemberDashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.payment,
              builder: (_, __) => const PaymentScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.events,
              builder: (_, __) => const EventsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.notifications,
              builder: (_, __) => const NotificationsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.profile,
              builder: (_, __) => const ProfileScreen(),
            ),
          ]),
        ],
      ),
      GoRoute(
        path: AppRoutes.receipts,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const ReceiptsScreen(),
      ),
      GoRoute(
        path: AppRoutes.reminders,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const ReminderSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.eventDetail,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) =>
            EventDetailScreen(eventId: state.extra as String),
      ),

      // ── Admin shell (persistent nav bar across 4 tabs) ──────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AdminShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.admin,
              builder: (_, __) => const AdminDashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.adminMembers,
              builder: (_, __) => const AdminMembersScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.adminPayments,
              builder: (_, __) => const AdminPaymentsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.adminWallet,
              builder: (_, __) => const AdminWalletScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.adminSettings,
              builder: (_, __) => const AdminSettingsScreen(),
            ),
          ]),
        ],
      ),
      // These push above the shell (full-screen, no nav bar)
      GoRoute(
        path: AppRoutes.adminManualPayment,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AdminManualPaymentScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminFocalReports,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AdminFocalReportsScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminTeam,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AdminTeamScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminAudit,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AdminAuditScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminBankDetails,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AdminBankDetailsScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminAnalytics,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AdminAnalyticsScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminEvents,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AdminEventsScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminEventForm,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) =>
            AdminEventFormScreen(event: state.extra as EventModel?),
      ),

      // ── Focal shell (persistent nav bar across 5 tabs) ──────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            FocalShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.focal,
              builder: (_, __) => const FocalDashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.focalMembers,
              builder: (_, __) => const FocalMembersScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.focalPayments,
              builder: (_, __) => const FocalPaymentsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.focalNotifications,
              builder: (_, __) => const NotificationsScreen(
                themeColor: Color(0xFF26A8F3),
                themeColorDark: Color(0xFF0A5F8C),
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.focalProfile,
              builder: (_, __) => const FocalProfileScreen(),
            ),
          ]),
        ],
      ),
      GoRoute(
        path: AppRoutes.focalReports,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const FocalReportsScreen(),
      ),
      GoRoute(
        path: AppRoutes.focalSession,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const FocalSessionScreen(),
      ),
      GoRoute(
        path: AppRoutes.focalReport,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => FocalReportDetailScreen(
          reportId: state.extra as String,
        ),
      ),

      // ── Treasury (member transparency) ──────────────────────
      GoRoute(
        path: AppRoutes.transparency,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const TransparencyScreen(),
      ),

      // ── Treasury (admin) ─────────────────────────────────────
      // adminWallet is a shell branch (Wallet tab); only the account detail
      // is a root push route here.
      GoRoute(
        path: AppRoutes.adminWalletAccount,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => AdminWalletAccountScreen(
          accountId: state.pathParameters['accountId']!,
        ),
      ),

      // ── Common ───────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.help,
        builder: (_, __) => const HelpScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (_, __) => const AboutScreen(),
      ),
      GoRoute(
        path: AppRoutes.privacyPolicy,
        builder: (_, __) => const PrivacyPolicyScreen(),
      ),
    ],
  );
});

// ── Error Page ────────────────────────────────────────────────

class _ErrorPage extends StatelessWidget {
  final Exception? error;
  const _ErrorPage({this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page introuvable')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              error?.toString() ?? 'Cette page n\'existe pas.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.splash),
              child: const Text('Retour à l\'accueil'),
            ),
          ],
        ),
      ),
    );
  }
}
