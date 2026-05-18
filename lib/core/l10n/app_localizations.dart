import 'package:flutter/material.dart';
import 'translations/fr.dart';
import 'translations/en.dart';
import 'translations/ar.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  Map<String, String> get _map {
    switch (locale.languageCode) {
      case 'en':
        return EnTranslations.translations;
      case 'ar':
        return ArTranslations.translations;
      case 'fr':
      default:
        return FrTranslations.translations;
    }
  }

  String _t(String key) => _map[key] ?? FrTranslations.translations[key] ?? key;

  // ── App ────────────────────────────────────────────────────
  String get appName => _t('appName');
  String get orgName => _t('orgName');
  String get tagline => _t('tagline');
  String get devBy => _t('devBy');
  String get officialPlatform => _t('officialPlatform');
  String get developedBy => _t('developedBy');
  String get connexion => _t('connexion');
  String get inscription => _t('inscription');
  String get accessYourAccount => _t('accessYourAccount');
  String get mobileAuth => _t('mobileAuth');
  String get sendOtp => _t('sendOtp');
  String get verifyOtp => _t('verifyOtp');
  String get enterOtpCode => _t('enterOtpCode');
  String get resendCode => _t('resendCode');
  String get orContinueWith => _t('orContinueWith');
  String get continueWithGoogle => _t('continueWithGoogle');
  String get continueWithPhone => _t('continueWithPhone');
  String get continueWithApple => _t('continueWithApple');
  String get quickSignup => _t('quickSignup');
  String get orRegisterWithEmail => _t('orRegisterWithEmail');
  String get useEmail => _t('useEmail');
  String get firstName => _t('firstName');
  String get lastName => _t('lastName');
  String get region => _t('region');
  String get department => _t('department');
  String get city => _t('city');
  String get quarter => _t('quarter');
  String get cityQuarter => _t('cityQuarter');
  String get emailRecommended => _t('emailRecommended');
  String get continueBtn => _t('continueBtn');
  String get step1of3 => _t('step1of3');
  String get step2of3 => _t('step2of3');
  String get step3of3 => _t('step3of3');
  String get createMyAccount => _t('createMyAccount');
  String get preferredFrequency => _t('preferredFrequency');
  String get preferredPayment => _t('preferredPayment');
  String get chooseLanguage => _t('chooseLanguage');
  String get activeMonths => _t('activeMonths');
  String get thisMonth => _t('thisMonth');
  String get delays => _t('delays');
  String get memberActiveStatus => _t('memberActiveStatus');
  String get memberLateStatus => _t('memberLateStatus');
  String get paymentHistory => _t('paymentHistory');
  String get viewAll => _t('viewAll');
  String get myReceipts => _t('myReceipts');
  String get sponsor => _t('sponsor');
  String get home => _t('home');
  String get alerts => _t('alerts');
  String get annualObjective => _t('annualObjective');
  String get platformProgressCard => _t('platformProgressCard');
  String get since => _t('since');
  String get paidSuffix => _t('paidSuffix');
  String get remainingSuffix => _t('remainingSuffix');
  String get annualGoalReached => _t('annualGoalReached');
  String get superContributor => _t('superContributor');
  String get fcfaToContribute => _t('fcfaToContribute');
  String get noPaymentYet => _t('noPaymentYet');

  // ── Profile Screen ────────────────────────────────────────
  String get editProfile => _t('editProfile');
  String get personalInfo => _t('personalInfo');
  String get membershipStatus => _t('membershipStatus');
  String get currentLevel => _t('currentLevel');
  String get paymentMethods => _t('paymentMethods');
  String get addPaymentMethod => _t('addPaymentMethod');
  String get pushNotifications => _t('pushNotifications');
  String get privacyPolicy => _t('privacyPolicy');
  String get profileUpdated => _t('profileUpdated');
  String get logoutConfirmTitle => _t('logoutConfirmTitle');
  String get logoutConfirmMsg => _t('logoutConfirmMsg');
  String get memberActive => _t('memberActive');
  String get autoRenewal => _t('autoRenewal');
  String get fullName => _t('fullName');
  String get editInfo => _t('editInfo');
  String get remindMember => _t('remindMember');
  String get callAction => _t('callAction');
  String get smsAction => _t('smsAction');
  String get reminderMessage => _t('reminderMessage');
  String get sendSmsReminder => _t('sendSmsReminder');
  String get noPhoneNumber => _t('noPhoneNumber');
  String get launchError => _t('launchError');
  String get languageDisplay => _t('languageDisplay');
  String get saveChanges => _t('saveChanges');
  String get memberSinceLabel => _t('memberSinceLabel');

  // ── Payment Screen ─────────────────────────────────────────
  String get makePayment => _t('makePayment');
  String get customAmount => _t('customAmount');
  String get enterAmount => _t('enterAmount');
  String get viaUssd => _t('viaUssd');
  String get cashToResponsible => _t('cashToResponsible');
  String get securePaymentBadge => _t('securePaymentBadge');
  String get totalToPay => _t('totalToPay');
  String get backToDashboard => _t('backToDashboard');
  String get paymentDone => _t('paymentDone');
  String get requestRegistered => _t('requestRegistered');
  String get thanksContribution => _t('thanksContribution');
  String get composeUssd => _t('composeUssd');
  String get enterPin => _t('enterPin');
  String get wrongPin => _t('wrongPin');
  String get codeCopied => _t('codeCopied');
  String get periodLabel => _t('periodLabel');
  String get modeLabel => _t('modeLabel');
  String get popularBadge => _t('popularBadge');
  String get confirmRequest => _t('confirmRequest');
  String get selectAnAmount => _t('selectAnAmount');
  String get iHavePaid => _t('iHavePaid');
  String get ussdSimulation => _t('ussdSimulation');
  String get pendingValidationMsg => _t('pendingValidationMsg');

  // ── Auth ───────────────────────────────────────────────────
  String get login => _t('login');
  String get signup => _t('signup');
  String get email => _t('email');
  String get password => _t('password');
  String get phone => _t('phone');
  String get confirmPassword => _t('confirmPassword');
  String get forgotPassword => _t('forgotPassword');
  String get createAccount => _t('createAccount');
  String get alreadyMember => _t('alreadyMember');
  String get notMember => _t('notMember');

  // ── Navigation ─────────────────────────────────────────────
  String get dashboard => _t('dashboard');
  String get payment => _t('payment');
  String get profile => _t('profile');
  String get notifications => _t('notifications');
  String get admin => _t('admin');
  String get focal => _t('focal');
  String get settings => _t('settings');
  String get help => _t('help');
  String get logout => _t('logout');

  // ── Payment ────────────────────────────────────────────────
  String get amount => _t('amount');
  String get paymentMethod => _t('paymentMethod');
  String get confirmPayment => _t('confirmPayment');
  String get paymentSuccess => _t('paymentSuccess');
  String get paymentPending => _t('paymentPending');
  String get paymentFailed => _t('paymentFailed');
  String get receipt => _t('receipt');
  String get chooseAmount => _t('chooseAmount');
  String get chooseMethod => _t('chooseMethod');

  // ── Contribution Types ─────────────────────────────────────
  String get daily => _t('daily');
  String get monthly => _t('monthly');
  String get annual => _t('annual');
  String get custom => _t('custom');

  // ── Payment Methods ────────────────────────────────────────
  String get mtnMomo => _t('mtnMomo');
  String get orangeMoney => _t('orangeMoney');
  String get cash => _t('cash');
  String get bankTransfer => _t('bankTransfer');

  // ── Status ─────────────────────────────────────────────────
  String get active => _t('active');
  String get inactive => _t('inactive');
  String get confirmed => _t('confirmed');
  String get pending => _t('pending');
  String get failed => _t('failed');
  String get suspended => _t('suspended');
  String get refunded => _t('refunded');

  // ── Roles ──────────────────────────────────────────────────
  String get member => _t('member');
  String get superAdmin => _t('superAdmin');

  // ── Common ─────────────────────────────────────────────────
  String get save => _t('save');
  String get cancel => _t('cancel');
  String get confirm => _t('confirm');
  String get back => _t('back');
  String get loading => _t('loading');
  String get error => _t('error');
  String get success => _t('success');
  String get retry => _t('retry');
  String get search => _t('search');
  String get filter => _t('filter');
  String get export => _t('export');
  String get submit => _t('submit');
  String get validate => _t('validate');
  String get reject => _t('reject');
  String get close => _t('close');
  String get yes => _t('yes');
  String get no => _t('no');
  String get required => _t('required');
  String get optional => _t('optional');

  // ── Errors ─────────────────────────────────────────────────
  String get fieldRequired => _t('fieldRequired');
  String get invalidEmail => _t('invalidEmail');
  String get invalidPhone => _t('invalidPhone');
  String get passwordTooShort => _t('passwordTooShort');
  String get passwordMismatch => _t('passwordMismatch');
  String get networkError => _t('networkError');
  String get unknownError => _t('unknownError');

  // ── Member ─────────────────────────────────────────────────
  String get memberNumber => _t('memberNumber');
  String get totalContributed => _t('totalContributed');
  String get annualGoal => _t('annualGoal');
  String get monthlyStatus => _t('monthlyStatus');
  String get joinDate => _t('joinDate');
  String get memberSince => _t('memberSince');
  String get activeStatus => _t('activeStatus');

  // ── Payments Management ────────────────────────────────────
  String get paymentsManagement => _t('paymentsManagement');
  String get pendingTab => _t('pendingTab');
  String get recentTab => _t('recentTab');
  String get rejectedTab => _t('rejectedTab');
  String get firstValidation => _t('firstValidation');
  String get secondValidation => _t('secondValidation');
  String get rejectReason => _t('rejectReason');
  String get enterRejectReason => _t('enterRejectReason');
  String get noPendingPayments => _t('noPendingPayments');
  String get noPayments => _t('noPayments');
  String get paymentDetail => _t('paymentDetail');
  String get receiptNo => _t('receiptNo');
  String get noRejectedPayments => _t('noRejectedPayments');
  String get paymentRejected => _t('paymentRejected');
  String get bulkValidationTitle => _t('bulkValidationTitle');
  String get validateAll => _t('validateAll');
  String get individualPayments => _t('individualPayments');
  String get focalSession => _t('focalSession');
  String get submissionDate => _t('submissionDate');
  String get confirmedOn => _t('confirmedOn');
  String get validationTrace => _t('validationTrace');
  String bulkStep1Label(int n) =>
      _t('bulkStep1Label').replaceAll('{n}', '$n');
  String bulkStep2Label(int n) =>
      _t('bulkStep2Label').replaceAll('{n}', '$n');
  String bulkStep1Detail(int n) =>
      _t('bulkStep1Detail').replaceAll('{n}', '$n');
  String bulkStep2Detail(int n) =>
      _t('bulkStep2Detail').replaceAll('{n}', '$n');
  String paymentsValidated(int n) =>
      _t('paymentsValidated').replaceAll('{n}', '$n');

  // ── Members Management ─────────────────────────────────────
  String get membersManagement => _t('membersManagement');
  String get searchMembers => _t('searchMembers');
  String get noMembersFound => _t('noMembersFound');
  String get memberDetail => _t('memberDetail');
  String get suspendAction => _t('suspendAction');
  String get activateAction => _t('activateAction');
  String get deactivateAction => _t('deactivateAction');
  String get changeRoleAction => _t('changeRoleAction');
  String get allFilter => _t('allFilter');
  String get activeFilter => _t('activeFilter');
  String get suspendedFilter => _t('suspendedFilter');
  String get inactiveFilter => _t('inactiveFilter');
  String get confirmStatusChange => _t('confirmStatusChange');
  String get confirmRoleChange => _t('confirmRoleChange');

  // ── Admin ──────────────────────────────────────────────────
  String get totalMembers => _t('totalMembers');
  String get todayCollection => _t('todayCollection');
  String get pendingValidation => _t('pendingValidation');
  String get newMembers => _t('newMembers');
  String get manualPayment => _t('manualPayment');
  String get validatePayment => _t('validatePayment');
  String get rejectPayment => _t('rejectPayment');
  String get adminDashboardTitle => _t('adminDashboardTitle');
  String get adminBadge => _t('adminBadge');
  String get activeMembers => _t('activeMembers');
  String get lateMembers => _t('lateMembers');
  String get newMembersToday => _t('newMembersToday');
  String get chartTitle => _t('chartTitle');
  String get recentPayments => _t('recentPayments');
  String get quickActionsTitle => _t('quickActionsTitle');
  String get manageMembers => _t('manageMembers');
  String get sendNotificationAction => _t('sendNotificationAction');
  String get vsYesterday => _t('vsYesterday');
  String get platformVision => _t('platformVision');
  String get platformVisionSub => _t('platformVisionSub');
  String get membersGoal => _t('membersGoal');
  String get annualRevenueGoal => _t('annualRevenueGoal');
  String get targetLabel => _t('targetLabel');
  String get reachedLabel => _t('reachedLabel');

  // ── Focal ──────────────────────────────────────────────────
  String get focalDashboardTitle => _t('focalDashboardTitle');
  String get focalBadge => _t('focalBadge');
  String get focalZoneLabel => _t('focalZoneLabel');
  String get myReports => _t('myReports');
  String get noReports => _t('noReports');
  String get newReport => _t('newReport');
  String get draftStatus => _t('draftStatus');
  String get submittedStatus => _t('submittedStatus');
  String get validatedStatus => _t('validatedStatus');
  String get rejectedStatus => _t('rejectedStatus');
  String get totalCollectedLabel => _t('totalCollectedLabel');
  String get membersServedLabel => _t('membersServedLabel');
  String get newMembersLabel => _t('newMembersLabel');
  String get shareWhatsApp => _t('shareWhatsApp');
  String get locationLabel => _t('locationLabel');
  String get reportDateLabel => _t('reportDateLabel');
  String get createDraft => _t('createDraft');
  String get submitConfirm => _t('submitConfirm');
  String get submitConfirmBody => _t('submitConfirmBody');
  String get reportCreated => _t('reportCreated');
  String get reportSubmitted => _t('reportSubmitted');
  String get thisMonthSessions => _t('thisMonthSessions');
  String get copiedToClipboard => _t('copiedToClipboard');
  String get notesOptional => _t('notesOptional');
  String get finalizeSession => _t('finalizeSession');
  String get sessionSaved => _t('sessionSaved');
  String get searchMember => _t('searchMember');
  String get memberNotFound => _t('memberNotFound');
  String get discardSession => _t('discardSession');
  String get discardSessionBody => _t('discardSessionBody');
  String get discard => _t('discard');
  String get noSessionPayments => _t('noSessionPayments');
  String get myMemberSpace => _t('myMemberSpace');
  String get myMemberSpaceSub => _t('myMemberSpaceSub');
  String get memberRegistered => _t('memberRegistered');
  String get memberNumberAssigned => _t('memberNumberAssigned');
  String get copyMemberNumber => _t('copyMemberNumber');
  String get myMembers => _t('myMembers');
  String get noMembersRegistered => _t('noMembersRegistered');
  String get notificationSent => _t('notificationSent');
  String get notifTitle => _t('notifTitle');
  String get notifMessage => _t('notifMessage');
  String get sendNotifAction => _t('sendNotifAction');
  String get lastPayment => _t('lastPayment');
  String get contributionsTab => _t('contributionsTab');
  String get paymentRecorded => _t('paymentRecorded');
  String get chooseFrequency => _t('chooseFrequency');
  String get progressionLabel => _t('progressionLabel');
  String get contributionHistory => _t('contributionHistory');
  String get startSession => _t('startSession');
  String get endSession => _t('endSession');
  String get recordPayment => _t('recordPayment');
  String get registerMember => _t('registerMember');
  String get generateReport => _t('generateReport');
  String get submitReport => _t('submitReport');
  String get sessionSummary => _t('sessionSummary');

  // ── Notifications ──────────────────────────────────────────
  String get noNotifications => _t('noNotifications');
  String get noNotificationsBody => _t('noNotificationsBody');
  String get markAllRead => _t('markAllRead');
  String get newPayment => _t('newPayment');
  String get paymentReminder => _t('paymentReminder');
  String get welcome => _t('welcome');
  String get milestone => _t('milestone');
  String get filterAll => _t('filterAll');
  String get filterUnread => _t('filterUnread');
  String get filterPayments => _t('filterPayments');
  String get filterAlerts => _t('filterAlerts');
  String get filterSystem => _t('filterSystem');
  String get todayLabel => _t('todayLabel');
  String get yesterdayLabel => _t('yesterdayLabel');
  String get thisWeekLabel => _t('thisWeekLabel');
  String get olderLabel => _t('olderLabel');

  // ── Treasury / Wallet ─────────────────────────────────────
  String get treasuryTitle => _t('treasuryTitle');
  String get transparencyTitle => _t('transparencyTitle');
  String get adminWalletTitle => _t('adminWalletTitle');
  String get walletAccounts => _t('walletAccounts');
  String get walletBalance => _t('walletBalance');
  String get walletTotalBalance => _t('walletTotalBalance');
  String get walletNoAccounts => _t('walletNoAccounts');
  String get walletNoTransactions => _t('walletNoTransactions');
  String get walletTypeMobileMoney => _t('walletTypeMobileMoney');
  String get walletTypeBank => _t('walletTypeBank');
  String get walletTypeCash => _t('walletTypeCash');
  String get walletTypeOther => _t('walletTypeOther');
  String get txKindInflow => _t('txKindInflow');
  String get txKindOutflow => _t('txKindOutflow');
  String get txKindTransferIn => _t('txKindTransferIn');
  String get txKindTransferOut => _t('txKindTransferOut');
  String get walletAccountName => _t('walletAccountName');
  String get walletAccountType => _t('walletAccountType');
  String get walletAccountCurrency => _t('walletAccountCurrency');
  String get walletOpeningBalance => _t('walletOpeningBalance');
  String get walletColor => _t('walletColor');
  String get addWalletAccount => _t('addWalletAccount');
  String get editWalletAccount => _t('editWalletAccount');
  String get archiveAccount => _t('archiveAccount');
  String get archiveAccountConfirm => _t('archiveAccountConfirm');
  String get archiveAccountBody => _t('archiveAccountBody');
  String get accountArchived => _t('accountArchived');
  String get walletAccountCreated => _t('walletAccountCreated');
  String get walletAccountUpdated => _t('walletAccountUpdated');
  String get addMovement => _t('addMovement');
  String get editMovement => _t('editMovement');
  String get movementKind => _t('movementKind');
  String get movementAmount => _t('movementAmount');
  String get movementDate => _t('movementDate');
  String get movementCategory => _t('movementCategory');
  String get movementNote => _t('movementNote');
  String get movementDeleted => _t('movementDeleted');
  String get movementSaved => _t('movementSaved');
  String get deleteMovement => _t('deleteMovement');
  String get deleteMovementConfirm => _t('deleteMovementConfirm');
  String get deleteMovementBody => _t('deleteMovementBody');
  String get transferTitle => _t('transferTitle');
  String get transferFrom => _t('transferFrom');
  String get transferTo => _t('transferTo');
  String get transferNote => _t('transferNote');
  String get transferExecuted => _t('transferExecuted');
  String get sameAccountError => _t('sameAccountError');
  String get paymentMethodMapping => _t('paymentMethodMapping');
  String get mappingHint => _t('mappingHint');
  String get inflowLabel => _t('inflowLabel');
  String get outflowLabel => _t('outflowLabel');
  String get walletLastUpdate => _t('walletLastUpdate');
  String get monthlyChart => _t('monthlyChart');
  String get noData => _t('noData');
  String get filterDateFrom => _t('filterDateFrom');
  String get filterDateTo => _t('filterDateTo');
  String get loadMore => _t('loadMore');
  String get walletRegion => _t('walletRegion');
  String get walletGlobal => _t('walletGlobal');
  String get regionMapping => _t('regionMapping');
  String get regionMappingHint => _t('regionMappingHint');
  String get initRegionalWallets => _t('initRegionalWallets');
  String get regionalWalletsReady => _t('regionalWalletsReady');
  String get byRegion => _t('byRegion');

  // ── Onboarding ─────────────────────────────────────────────
  String get skip => _t('skip');
  String get heroTagline => _t('heroTagline');
  String get heroSubhead => _t('heroSubhead');
  String get heroStatMembersLabel => _t('heroStatMembersLabel');
  String get heroStatDailyLabel => _t('heroStatDailyLabel');
  String get heroStatYearlyLabel => _t('heroStatYearlyLabel');
  String get alreadyHaveAccount => _t('alreadyHaveAccount');
  String get servicesEyebrow => _t('servicesEyebrow');
  String get servicesTitle => _t('servicesTitle');
  String get servicesSubtitle => _t('servicesSubtitle');
  String get serviceFinanceTitle => _t('serviceFinanceTitle');
  String get serviceFinanceDesc => _t('serviceFinanceDesc');
  String get serviceEducationTitle => _t('serviceEducationTitle');
  String get serviceEducationDesc => _t('serviceEducationDesc');
  String get serviceHealthTitle => _t('serviceHealthTitle');
  String get serviceHealthDesc => _t('serviceHealthDesc');
  String get serviceEmploymentTitle => _t('serviceEmploymentTitle');
  String get serviceEmploymentDesc => _t('serviceEmploymentDesc');
  String get serviceSocialTitle => _t('serviceSocialTitle');
  String get serviceSocialDesc => _t('serviceSocialDesc');
  String get serviceInfraTitle => _t('serviceInfraTitle');
  String get serviceInfraDesc => _t('serviceInfraDesc');
  String get howEyebrow => _t('howEyebrow');
  String get howTitle => _t('howTitle');
  String get howStep1Title => _t('howStep1Title');
  String get howStep1Desc => _t('howStep1Desc');
  String get howStep2Title => _t('howStep2Title');
  String get howStep2Desc => _t('howStep2Desc');
  String get howStep3Title => _t('howStep3Title');
  String get howStep3Desc => _t('howStep3Desc');
  String get ctaTitle => _t('ctaTitle');
  String get ctaSubtitle => _t('ctaSubtitle');
  String get joinCmcda => _t('joinCmcda');
  String get alreadyMemberLogin => _t('alreadyMemberLogin');

  String get backfillContributions => _t('backfillContributions');
  String get backfillContributionsHint => _t('backfillContributionsHint');
  String backfillDone(int created, int skipped, int failed) => _t('backfillDone')
      .replaceAll('{created}', '$created')
      .replaceAll('{skipped}', '$skipped')
      .replaceAll('{failed}', '$failed');

  // ── Months ─────────────────────────────────────────────────
  String get january => _t('january');
  String get february => _t('february');
  String get march => _t('march');
  String get april => _t('april');
  String get may => _t('may');
  String get june => _t('june');
  String get july => _t('july');
  String get august => _t('august');
  String get september => _t('september');
  String get october => _t('october');
  String get november => _t('november');
  String get december => _t('december');
  String get focalReportsTitle => _t('focalReportsTitle');

  List<String> get monthNames => [
        january, february, march, april, may, june,
        july, august, september, october, november, december,
      ];
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['fr', 'en', 'ar'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
