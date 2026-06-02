import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
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
  String get completeProfileTitle => _t('completeProfileTitle');
  String get completeProfileSubtitle => _t('completeProfileSubtitle');
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
  String get reminders => _t('reminders');
  String get remindersSubtitle => _t('remindersSubtitle');
  String get enableReminders => _t('enableReminders');
  String get reminderFrequency => _t('reminderFrequency');
  String get freqDaily => _t('freqDaily');
  String get freqMonthly => _t('freqMonthly');
  String get freqAnnual => _t('freqAnnual');
  String get nextReminder => _t('nextReminder');
  String get remindersGoalReached => _t('remindersGoalReached');
  String get remindersDisabledHint => _t('remindersDisabledHint');

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
  String get helpFaq => _t('helpFaq');
  String get helpFaqSubtitle => _t('helpFaqSubtitle');
  String get aboutApp => _t('aboutApp');
  String get appVersion => _t('appVersion');
  String get contactUs => _t('contactUs');
  String get contactViaWhatsApp => _t('contactViaWhatsApp');
  String get contactViaEmail => _t('contactViaEmail');
  String get contactWebsite => _t('contactWebsite');
  String get faqCategoryPayments => _t('faqCategoryPayments');
  String get faqCategoryAccount => _t('faqCategoryAccount');
  String get faqCategoryGeneral => _t('faqCategoryGeneral');
  String get reportIssue => _t('reportIssue');
  String get needMoreHelp => _t('needMoreHelp');
  String get needMoreHelpSub => _t('needMoreHelpSub');
  String get contactSupport => _t('contactSupport');
  String get legalSection => _t('legalSection');
  String get faqQ1 => _t('faqQ1');
  String get faqA1 => _t('faqA1');
  String get faqQ2 => _t('faqQ2');
  String get faqA2 => _t('faqA2');
  String get faqQ3 => _t('faqQ3');
  String get faqA3 => _t('faqA3');
  String get faqQ4 => _t('faqQ4');
  String get faqA4 => _t('faqA4');
  String get faqQ5 => _t('faqQ5');
  String get faqA5 => _t('faqA5');
  String get faqQ6 => _t('faqQ6');
  String get faqA6 => _t('faqA6');
  String get faqQ7 => _t('faqQ7');
  String get faqA7 => _t('faqA7');
  String get faqQ8 => _t('faqQ8');
  String get faqA8 => _t('faqA8');

  // ── Payment ────────────────────────────────────────────────
  String get amount => _t('amount');
  String get paymentMethod => _t('paymentMethod');
  String get confirmPayment => _t('confirmPayment');
  String get paymentSuccess => _t('paymentSuccess');
  String get paymentPending => _t('paymentPending');
  String get paymentFailed => _t('paymentFailed');
  String get receipt => _t('receipt');
  String get chooseAmount => _t('chooseAmount');
  String get payments => _t('payments');
  String get chooseMethod => _t('chooseMethod');
  String get mobileMoneyPayment => _t('mobileMoneyPayment');
  String get enterMomoNumber => _t('enterMomoNumber');
  String get payNow => _t('payNow');
  String get confirmOnPhone => _t('confirmOnPhone');
  String get pinPromptMessage => _t('pinPromptMessage');
  String get refreshStatus => _t('refreshStatus');
  String get awaitingPin => _t('awaitingPin');
  String get cancelMobilePayment => _t('cancelMobilePayment');
  String get statusRefreshed => _t('statusRefreshed');

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
  String get errWrongPassword => _t('errWrongPassword');
  String get errUserNotFound => _t('errUserNotFound');
  String get errEmailInUse => _t('errEmailInUse');
  String get errWeakPassword => _t('errWeakPassword');
  String get errTooManyRequests => _t('errTooManyRequests');
  String get errInvalidOtp => _t('errInvalidOtp');
  String get errUserDisabled => _t('errUserDisabled');
  String get errInvalidCredential => _t('errInvalidCredential');

  // ── Auth — reset password & onboarding ─────────────────────
  String get resetPasswordTitle => _t('resetPasswordTitle');
  String get resetPasswordHint => _t('resetPasswordHint');
  String get sendResetLink => _t('sendResetLink');
  String get resetEmailSent => _t('resetEmailSent');
  String get appleComingSoon => _t('appleComingSoon');
  String get preferencesEditableLater => _t('preferencesEditableLater');

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
  String get approvePayment => _t('approvePayment');
  String get proofOfTransfer => _t('proofOfTransfer');

  // ── Bank Transfer ──────────────────────────────────────────
  String get bankTransferTitle => _t('bankTransferTitle');
  String get bankTransferInstructions => _t('bankTransferInstructions');
  String get bankNameLabel => _t('bankNameLabel');
  String get accountNumberLabel => _t('accountNumberLabel');
  String get accountHolderLabel => _t('accountHolderLabel');
  String get attachProof => _t('attachProof');
  String get proofAttached => _t('proofAttached');
  String get proofRequired => _t('proofRequired');
  String get confirmContributionBtn => _t('confirmContributionBtn');
  String get bankDetailsTitle => _t('bankDetailsTitle');
  String get bankDetailsSubtitle => _t('bankDetailsSubtitle');
  String get instructionsOptional => _t('instructionsOptional');
  String get fillRequiredFields => _t('fillRequiredFields');
  String get savedSuccessfully => _t('savedSuccessfully');
  String bulkStep1Label(int n) => _t('bulkStep1Label').replaceAll('{n}', '$n');
  String bulkStep2Label(int n) => _t('bulkStep2Label').replaceAll('{n}', '$n');
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

  // ── Admin management ───────────────────────────────────────
  String get manageAdmins => _t('manageAdmins');
  String get manageAdminsSubtitle => _t('manageAdminsSubtitle');
  String get addAdmin => _t('addAdmin');
  String get promoteAction => _t('promoteAction');
  String get demoteAction => _t('demoteAction');
  String get noAdminsFound => _t('noAdminsFound');
  String get currentAdmins => _t('currentAdmins');
  String get superAdminOnly => _t('superAdminOnly');
  String get cannotRemoveLastSuperAdmin => _t('cannotRemoveLastSuperAdmin');
  String get selectUserToPromote => _t('selectUserToPromote');

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
  String get walletTab => _t('walletTab');
  String get initWallets => _t('initWallets');
  String get walletsReady => _t('walletsReady');
  String get recalcRegionTotals => _t('recalcRegionTotals');
  String get regionTotalsUpdated => _t('regionTotalsUpdated');
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
  String backfillDone(int created, int skipped, int failed) =>
      _t('backfillDone')
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

  // ── Dashboard misc (FR/EN/AR sweep) ──────────────────────
  String get contribute => _t('contribute');
  String get viewAsMember => _t('viewAsMember');
  String get chartLegendNormal => _t('chartLegendNormal');
  String get chartLegendToday => _t('chartLegendToday');
  String get chartLegendRecord => _t('chartLegendRecord');
  String get syncCounters => _t('syncCounters');
  String get totalContributedLabel => _t('totalContributedLabel');
  String get sessionAddPaymentsHint => _t('sessionAddPaymentsHint');
  String get newBadge => _t('newBadge');
  String get targetMonth => _t('targetMonth');

  // ── Focal dashboard widgets ──────────────────────────────
  String get todayCollected => _t('todayCollected');
  String get todayContribCount => _t('todayContribCount');
  String get todayNewMembers => _t('todayNewMembers');

  // ── Admin dashboard widgets ──────────────────────────────
  String get awaitingFirstValidator => _t('awaitingFirstValidator');
  String get awaitingSecondValidator => _t('awaitingSecondValidator');
  String get topFocalOfficers => _t('topFocalOfficers');
  String get paymentMethodDistribution => _t('paymentMethodDistribution');
  String get noFocalActivity => _t('noFocalActivity');
  String get noPaymentsThisMonth => _t('noPaymentsThisMonth');

  // ── Audit (super-admin only) ─────────────────────────────
  String get auditMatricules => _t('auditMatricules');
  String get refresh => _t('refresh');
  String get auditMembersTotal => _t('auditMembersTotal');
  String get auditMissingMatricule => _t('auditMissingMatricule');
  String get auditMalformedMatricule => _t('auditMalformedMatricule');
  String get auditDuplicateMatricule => _t('auditDuplicateMatricule');
  String auditOrphanContributions(int n) =>
      _t('auditOrphanContributions').replaceAll('{n}', '$n');
  String get auditAllClean => _t('auditAllClean');
  String get auditIssuesDetected => _t('auditIssuesDetected');
  String get auditFailed => _t('auditFailed');
  String get repairMemberNumbers => _t('repairMemberNumbers');
  String get repairMemberNumbersDesc => _t('repairMemberNumbersDesc');
  String get repairConfirmTitle => _t('repairConfirmTitle');
  String get repairConfirmMsg => _t('repairConfirmMsg');
  String repairResult(int repaired) =>
      _t('repairResult').replaceAll('{repaired}', '$repaired');
  String get repairNoneNeeded => _t('repairNoneNeeded');
  String get repairError => _t('repairError');

  // ── Analytics screen ─────────────────────────────────────
  String get analyticsTitle => _t('analyticsTitle');
  String get analyticsSubtitle => _t('analyticsSubtitle');
  String get periodToday => _t('periodToday');
  String get periodLast7d => _t('periodLast7d');
  String get periodLast30d => _t('periodLast30d');
  String get periodThisMonth => _t('periodThisMonth');
  String get periodThisYear => _t('periodThisYear');
  String get periodCustom => _t('periodCustom');
  String get kpiTotalRevenue => _t('kpiTotalRevenue');
  String get kpiTxCount => _t('kpiTxCount');
  String get kpiAvgPayment => _t('kpiAvgPayment');
  String get kpiActiveContributors => _t('kpiActiveContributors');
  String get revenueOverTime => _t('revenueOverTime');
  String get paymentMethodBreakdown => _t('paymentMethodBreakdown');
  String get regionalRevenue => _t('regionalRevenue');
  String get topContributorsTitle => _t('topContributorsTitle');
  String get exportCsv => _t('exportCsv');
  String get exportPdf => _t('exportPdf');
  String get noChartData => _t('noChartData');
  String get selectDateRange => _t('selectDateRange');
  String get exportSuccess => _t('exportSuccess');
  String get exportError => _t('exportError');

  // ── Validation short labels & per-screen fixes ───────────
  String get firstValidationShort => _t('firstValidationShort');
  String get secondValidationShort => _t('secondValidationShort');
  String get firstValidationRecorded => _t('firstValidationRecorded');
  String get secondValidationRecorded => _t('secondValidationRecorded');
  String get validateReportTitle => _t('validateReportTitle');
  String validateReportBody(String name) =>
      _t('validateReportBody').replaceAll('{name}', name);
  String validateReportConfirmBody(String count, String amount) =>
      _t('validateReportConfirmBody')
          .replaceAll('{count}', count)
          .replaceAll('{amount}', amount);
  String reportConfirmedMessage(String count, String amount) =>
      _t('reportConfirmedMessage')
          .replaceAll('{count}', count)
          .replaceAll('{amount}', amount);
  String get rejectReportTitle => _t('rejectReportTitle');
  String get enterRejectReasonShort => _t('enterRejectReasonShort');
  String get focalReportsHeaderTitle => _t('focalReportsHeaderTitle');
  String get focalReportsHeaderSubtitle => _t('focalReportsHeaderSubtitle');
  String get pendingFilter => _t('pendingFilter');
  String get validatedFilter => _t('validatedFilter');
  String get rejectedFilter => _t('rejectedFilter');
  String get noFocalReports => _t('noFocalReports');
  String membersCount(int n) => _t('membersCount').replaceAll('{n}', '$n');
  String newMembersCount(int n) =>
      _t('newMembersCount').replaceAll('{n}', '$n');
  String get totalLabel => _t('totalLabel');
  String memberStatusUpdated(String name) =>
      _t('memberStatusUpdated').replaceAll('{name}', name);
  String memberRoleUpdated(String name) =>
      _t('memberRoleUpdated').replaceAll('{name}', name);
  String syncCountersResult(int members, String amount) =>
      _t('syncCountersResult')
          .replaceAll('{members}', '$members')
          .replaceAll('{amount}', amount);
  String get syncCountersError => _t('syncCountersError');
  String get yearLabel => _t('yearLabel');
  String get membersTab => _t('membersTab');

  // ── Send notification sheet ──────────────────────────────
  String get sendNotificationTitle => _t('sendNotificationTitle');
  String get targetActiveMembers => _t('targetActiveMembers');
  String get targetFocal => _t('targetFocal');
  String get targetAdmins => _t('targetAdmins');
  String get recipientsLabel => _t('recipientsLabel');
  String get titleLabel => _t('titleLabel');
  String get messageLabel => _t('messageLabel');
  String get titlePlaceholder => _t('titlePlaceholder');
  String get messagePlaceholder => _t('messagePlaceholder');
  String get titleRequired => _t('titleRequired');
  String get messageRequired => _t('messageRequired');
  String get noRecipientsFound => _t('noRecipientsFound');
  String notificationsSent(int n) =>
      _t('notificationsSent').replaceAll('{n}', '$n');
  String get sendingInProgress => _t('sendingInProgress');
  String get sendError => _t('sendError');
  String get sendBtn => _t('sendBtn');

  // ── Localized label helpers ──────────────────────────────
  // Replace AppUtils.xxxLabel(...) in UI; AppUtils helpers stay for
  // non-UI use (WhatsApp report text, logs).

  String paymentMethodName(String method) {
    switch (method) {
      case AppConstants.paymentMtnMomo:
        return mtnMomo;
      case AppConstants.paymentOrangeMoney:
        return orangeMoney;
      case AppConstants.paymentCash:
        return cash;
      case AppConstants.paymentBankTransfer:
        return bankTransfer;
      default:
        return method;
    }
  }

  String statusName(String status) {
    switch (status) {
      case AppConstants.statusConfirmed:
        return confirmed;
      case AppConstants.statusPending:
        return pending;
      case AppConstants.statusFailed:
        return failed;
      case AppConstants.statusRefunded:
        return refunded;
      case AppConstants.userStatusActive:
        return active;
      case AppConstants.userStatusInactive:
        return inactive;
      case AppConstants.userStatusSuspended:
        return suspended;
      default:
        return status;
    }
  }

  String roleName(String role) {
    switch (role) {
      case AppConstants.roleMember:
        return member;
      case AppConstants.roleFocal:
        return focal;
      case AppConstants.roleAdmin:
        return admin;
      case AppConstants.roleSuperAdmin:
        return superAdmin;
      default:
        return role;
    }
  }

  String periodTypeName(String type) {
    switch (type) {
      case AppConstants.periodDaily:
        return daily;
      case AppConstants.periodMonthly:
        return monthly;
      case AppConstants.periodAnnual:
        return annual;
      case AppConstants.periodCustom:
        return custom;
      default:
        return type;
    }
  }

  List<String> get monthNames => [
        january,
        february,
        march,
        april,
        may,
        june,
        july,
        august,
        september,
        october,
        november,
        december,
      ];

  // ── Events ──────────────────────────────────────────────────
  String get events => _t('events');
  String get upcomingEvents => _t('upcomingEvents');
  String get pastEvents => _t('pastEvents');
  String get noEvents => _t('noEvents');
  String get eventDate => _t('eventDate');
  String get eventTime => _t('eventTime');
  String get eventLocation => _t('eventLocation');
  String get eventDescription => _t('eventDescription');
  String get eventTitleLabel => _t('eventTitleLabel');
  String get createEvent => _t('createEvent');
  String get editEvent => _t('editEvent');
  String get deleteEvent => _t('deleteEvent');
  String get deleteEventConfirm => _t('deleteEventConfirm');
  String get publishEvent => _t('publishEvent');
  String get unpublishEvent => _t('unpublishEvent');
  String get eventDraft => _t('eventDraft');
  String get eventPublished => _t('eventPublished');
  String get eventCancelled => _t('eventCancelled');
  String get addCoverImage => _t('addCoverImage');
  String get changeCoverImage => _t('changeCoverImage');
  String get eventSaved => _t('eventSaved');
  String get eventDeleted => _t('eventDeleted');
  String get manageEvents => _t('manageEvents');
  String get eventEndDate => _t('eventEndDate');
  String get eventOrganizer => _t('eventOrganizer');
  String get eventCategory => _t('eventCategory');
  String get eventPhotos => _t('eventPhotos');
  String get addPhotos => _t('addPhotos');
  String get maxPhotosReached => _t('maxPhotosReached');
  String get shareEvent => _t('shareEvent');
  String get joinUmmahCta => _t('joinUmmahCta');
  String get catGeneral => _t('catGeneral');
  String get catFundraiser => _t('catFundraiser');
  String get catMeeting => _t('catMeeting');
  String get catReligious => _t('catReligious');
  String get catCommunity => _t('catCommunity');

  // ── Connectivity / offline ──────────────────────────────────
  String get offlineBannerMessage => _t('offlineBannerMessage');
  String get syncingMessage => _t('syncingMessage');
  String get syncedMessage => _t('syncedMessage');
  String get receiptPendingSync => _t('receiptPendingSync');

  String categoryLabel(String key) {
    switch (key) {
      case 'fundraiser':
        return catFundraiser;
      case 'meeting':
        return catMeeting;
      case 'religious':
        return catReligious;
      case 'community':
        return catCommunity;
      case 'general':
      default:
        return catGeneral;
    }
  }
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
