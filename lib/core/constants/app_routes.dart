class AppRoutes {
  AppRoutes._();

  // ── Public ───────────────────────────────────────────────────
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String completeProfile = '/complete-profile';

  // ── Member ───────────────────────────────────────────────────
  static const String dashboard = '/dashboard';
  static const String payment = '/pay';
  static const String receipts = '/receipts';
  static const String profile = '/profile';
  static const String notifications = '/notifications';
  static const String reminders = '/reminders';
  static const String events = '/events';
  static const String eventDetail = '/events/detail';

  // ── Admin ────────────────────────────────────────────────────
  static const String admin = '/admin';
  static const String adminMembers = '/admin/members';
  static const String adminPayments = '/admin/payments';
  static const String adminManualPayment = '/admin/manual-payment';
  static const String adminFocalReports = '/admin/focal-reports';
  static const String adminAnalytics = '/admin/analytics';
  static const String adminSettings = '/admin/settings';
  static const String adminAudit = '/admin/audit';
  static const String adminTeam = '/admin/team';
  static const String adminBankDetails = '/admin/bank-details';
  static const String adminEvents = '/admin/events';
  static const String adminEventForm = '/admin/event-form';

  // ── Focal ────────────────────────────────────────────────────
  static const String focal = '/focal';
  static const String focalReports = '/focal/reports';
  static const String focalMembers = '/focal/members';
  static const String focalPayments = '/focal/payments';
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
  static const String privacyPolicy = '/privacy';
}
