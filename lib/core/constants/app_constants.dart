class AppConstants {
  AppConstants._();

  // ── App Identity ────────────────────────────────────────────
  static const String appName = 'CMCDA Platform';
  static const String appVersion = '1.0.0';
  static const String orgName = 'Cameroon Muslim Community Development Association';
  static const String orgNameFr = 'Association Musulmane de Développement Communautaire du Cameroun';
  static const String orgNameAr = 'جمعية التنمية المجتمعية الإسلامية بالكاميرون';
  static const String acronym = 'CMCDA';
  static const String taglineFr = 'Ensemble pour le développement';
  static const String taglineEn = 'Together for development';
  static const String taglineAr = 'معاً من أجل التنمية';
  static const String devCompany = 'WoilaTech';
  static const String devCity = 'Ngaoundéré, Cameroun';

  // ── Contact ─────────────────────────────────────────────────
  static const String contactPhone = '+237 699 000 000';
  static const String contactEmail = 'contact@cmcda.cm';
  static const String contactWebsite = 'https://cmcda.cm';
  static const String orgCity = 'Yaoundé, Cameroun';

  // ── Contribution Amounts (FCFA) ──────────────────────────────
  static const int amountDaily = 100;
  static const int amountMonthly = 3000;
  static const int amountAnnual = 36500;

  // ── Membership ──────────────────────────────────────────────
  static const int targetMembers = 1000000;
  static const int targetAnnualRevenue = amountAnnual * targetMembers; // 36,500,000,000
  static const String memberPrefix = 'CM-'; // legacy prefix (pre-region rollout)
  static const String memberPrefixFallback = 'Cmr'; // used when region is unknown
  static const String receiptPrefix = 'RCP-';
  static const String reportPrefix = 'RPT-';

  // ── Region Member Prefixes ───────────────────────────────────
  // Each region uses the 3-letter abbreviation of its capital city.
  static const Map<String, String> regionMemberPrefixes = {
    'Adamaoua':     'Nde', // Ngaoundéré
    'Centre':       'Yde', // Yaoundé
    'Est':          'Bta', // Bertoua
    'Extrême-Nord': 'Mra', // Maroua
    'Littoral':     'Dla', // Douala
    'Nord':         'Goa', // Garoua
    'Nord-Ouest':   'Bda', // Bamenda
    'Ouest':        'Bfs', // Bafoussam
    'Sud':          'Ebo', // Ebolowa
    'Sud-Ouest':    'Bua', // Buea
  };

  // ── Firestore Collections ────────────────────────────────────
  static const String usersCollection = 'users';
  static const String contributionsCollection = 'contributions';
  static const String focalReportsCollection = 'focal_reports';
  static const String notificationsCollection = 'notifications';
  static const String auditLogsCollection = 'audit_logs';
  static const String countersCollection = 'counters';

  // ── User Roles ───────────────────────────────────────────────
  static const String roleMember = 'member';
  static const String roleFocal = 'focal';
  static const String roleAdmin = 'admin';
  static const String roleSuperAdmin = 'super_admin';

  // ── Payment Methods ──────────────────────────────────────────
  static const String paymentMtnMomo = 'mtn_momo';
  static const String paymentOrangeMoney = 'orange_money';
  static const String paymentCash = 'cash';
  static const String paymentBankTransfer = 'bank_transfer';

  // ── Payment Status ───────────────────────────────────────────
  static const String statusPending = 'pending';
  static const String statusConfirmed = 'confirmed';
  static const String statusFailed = 'failed';
  static const String statusRefunded = 'refunded';

  // ── User Status ──────────────────────────────────────────────
  static const String userStatusActive = 'active';
  static const String userStatusInactive = 'inactive';
  static const String userStatusSuspended = 'suspended';

  // ── Period Types ─────────────────────────────────────────────
  static const String periodDaily = 'daily';
  static const String periodMonthly = 'monthly';
  static const String periodAnnual = 'annual';
  static const String periodCustom = 'custom';

  // ── Mobile Money ─────────────────────────────────────────────
  static const String mtnMomoUssd = '#126*4*162409*';
  static const String orangeMoneyUssd = '#150*47*617601*';

  // ── Banking ──────────────────────────────────────────────────
  static const String bankName = 'Afriland First Bank';
  static const String bankAccount = '0908312170';

  // ── Wallet / Treasury ─────────────────────────────────────────
  static const String walletAccountsCollection = 'wallet_accounts';
  static const String walletTransactionsCollection = 'wallet_transactions';
  static const String walletConfigCollection = 'wallet_config';
  static const String walletSummaryDoc = 'summary';
  static const String walletPaymentMapDoc = 'payment_method_map';
  static const String walletTypeMobileMoney = 'mobile_money';
  static const String walletTypeBank = 'bank';
  static const String walletTypeCash = 'cash';
  static const String walletTypeOther = 'other';
  static const List<String> walletAccountTypes = [
    'mobile_money', 'bank', 'cash', 'other'
  ];
  static const String txKindInflow = 'inflow';
  static const String txKindOutflow = 'outflow';
  static const String txKindTransferIn = 'transfer_in';
  static const String txKindTransferOut = 'transfer_out';
  static const List<String> walletColorPalette = [
    '#16a34a', '#0ea5e9', '#f59e0b', '#dc2626', '#7c3aed', '#0f766e',
  ];
  static const String defaultCurrency = 'XAF';
  static const String walletCategoryContributions = 'Contributions';

  // One distinct color per Cameroon region, used for auto-seeded regional wallets
  static const Map<String, String> regionWalletColors = {
    'Adamaoua':     '#16a34a',
    'Centre':       '#0ea5e9',
    'Est':          '#f59e0b',
    'Extrême-Nord': '#dc2626',
    'Littoral':     '#7c3aed',
    'Nord':         '#0f766e',
    'Nord-Ouest':   '#ea580c',
    'Ouest':        '#8b5cf6',
    'Sud':          '#059669',
    'Sud-Ouest':    '#0284c7',
  };

  // ── Supported Locales ─────────────────────────────────────────
  static const List<String> supportedLocales = ['fr', 'en', 'ar'];
  static const String defaultLocale = 'fr';

  // ── Cameroon Regions ─────────────────────────────────────────
  static const List<String> cameroonRegions = [
    'Adamaoua',
    'Centre',
    'Est',
    'Extrême-Nord',
    'Littoral',
    'Nord',
    'Nord-Ouest',
    'Ouest',
    'Sud',
    'Sud-Ouest',
  ];

  // ── Web Push (FCM VAPID key) ──────────────────────────────────
  // Fill in after enabling Web Push in Firebase Console →
  // Project Settings → Cloud Messaging → Web Push certificates → Key pair.
  static const String webVapidKey = '';

  // ── Apple Sign-In ─────────────────────────────────────────────
  // Service ID (not App ID) from Apple Developer Console.
  // Steps: developer.apple.com → Identifiers → Services IDs → register one,
  // enable Sign-In with Apple, set redirect URL to appleRedirectUri below,
  // then enable Apple provider in Firebase Console → Authentication.
  static const String appleServiceId = ''; // TODO: fill after Apple Developer setup
  static const String appleRedirectUri =
      'https://cmcda-2f485.firebaseapp.com/__/auth/handler';

  // ── Spacing ──────────────────────────────────────────────────
  static const double spaceXS = 4.0;
  static const double spaceSM = 8.0;
  static const double spaceMD = 16.0;
  static const double spaceLG = 24.0;
  static const double spaceXL = 32.0;
  static const double spaceXXL = 48.0;

  // ── Border Radius ─────────────────────────────────────────────
  static const double radiusSM = 8.0;
  static const double radiusMD = 12.0;
  static const double radiusLG = 16.0;
  static const double radiusXL = 24.0;
  static const double radiusFull = 100.0;
}
