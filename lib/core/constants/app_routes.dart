class AppRoutes {
  AppRoutes._();

  // ── Public ───────────────────────────────────────────────────
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signup = '/signup';

  // ── Member ───────────────────────────────────────────────────
  static const String dashboard = '/dashboard';
  static const String payment = '/pay';
  static const String receipts = '/receipts';
  static const String profile = '/profile';
  static const String notifications = '/notifications';

  // ── Admin ────────────────────────────────────────────────────
  static const String admin = '/admin';
  static const String adminMembers = '/admin/members';
  static const String adminPayments = '/admin/payments';
  static const String adminManualPayment = '/admin/manual-payment';
  static const String adminFocalReports = '/admin/focal-reports';
  static const String adminAnalytics = '/admin/analytics';
  static const String adminSettings = '/admin/settings';

  // ── Focal ────────────────────────────────────────────────────
  static const String focal = '/focal';
  static const String focalReports = '/focal/reports';
  static const String focalMembers = '/focal/members';
  static const String focalNotifications = '/focal/notifications';
  static const String focalProfile = '/focal/profile';
  static const String focalSession = '/focal/session';
  static const String focalReport = '/focal/report';

  // ── Treasury ─────────────────────────────────────────────────
  static const String transparency = '/treasury';
  static const String adminWallet = '/admin/treasury';
  static const String adminWalletAccount = '/admin/treasury/:accountId';

  // ── Common ───────────────────────────────────────────────────
  static const String settings = '/settings';
  static const String help = '/help';
  static const String about = '/about';
}
