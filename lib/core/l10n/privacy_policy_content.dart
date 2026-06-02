// Privacy policy long-form content, kept out of the flat translation maps
// because the legal text is multi-paragraph per section.

class PrivacySection {
  final String heading;
  final String body;
  const PrivacySection({required this.heading, required this.body});
}

const String privacyPolicyLastUpdated = '2026-05-23';

const Map<String, List<PrivacySection>> privacyPolicySections = {
  // ── French (default / fallback) ──────────────────────────────
  'fr': [
    PrivacySection(
      heading: 'Introduction',
      body:
          "La présente politique de confidentialité décrit comment CMCDA "
          "(Association Musulmane de Développement Communautaire du Cameroun), "
          "via l'application CMCDA Platform développée par WoilaTech (Ngaoundéré, "
          "Cameroun), collecte, utilise et protège vos données personnelles. "
          "En utilisant l'application, vous acceptez les pratiques décrites ci-dessous.",
    ),
    PrivacySection(
      heading: 'Données que nous collectons',
      body:
          "• Identité et contact : prénom, nom, numéro de téléphone, adresse e-mail, "
          "région, département, ville et quartier.\n"
          "• Compte : numéro de membre (ex. CM-000001), rôle, statut et total des "
          "cotisations.\n"
          "• Paiements : enregistrements de cotisations (montant, méthode, période, "
          "statut) et, pour les virements bancaires, l'image justificative que vous "
          "téléversez.\n"
          "• Données techniques : jeton de notification (FCM) de votre appareil et "
          "langue préférée.",
    ),
    PrivacySection(
      heading: 'Comment nous utilisons vos données',
      body:
          "Nous utilisons vos données pour : créer et gérer votre compte de membre, "
          "enregistrer et valider vos cotisations, émettre des reçus, vous envoyer des "
          "notifications (rappels et confirmations de paiement), produire des rapports "
          "internes et assurer la conformité de l'association. Nous ne vendons jamais "
          "vos données.",
    ),
    PrivacySection(
      heading: 'Partage des données',
      body:
          "Vos données ne sont accessibles qu'aux administrateurs et responsables "
          "habilités de CMCDA, dans la limite de leurs fonctions. Elles sont traitées "
          "par Google Firebase, notre prestataire d'infrastructure. Nous ne partageons "
          "pas vos données avec des tiers à des fins commerciales.",
    ),
    PrivacySection(
      heading: 'Stockage et sécurité',
      body:
          "Vos données sont hébergées sur Google Firebase (Authentication, Cloud "
          "Firestore, Cloud Storage, Cloud Messaging et Cloud Functions). Les images "
          "justificatives de virement sont stockées de manière sécurisée et ne sont "
          "lisibles que par vous et le personnel habilité. L'accès est contrôlé par des "
          "règles de sécurité et l'authentification Firebase.",
    ),
    PrivacySection(
      heading: 'Conservation des données',
      body:
          "Nous conservons vos données aussi longtemps que votre compte est actif ou "
          "que cela est nécessaire pour assurer le suivi des cotisations et respecter "
          "nos obligations. Vous pouvez demander la suppression de votre compte à tout "
          "moment.",
    ),
    PrivacySection(
      heading: 'Vos droits',
      body:
          "Vous avez le droit d'accéder à vos données, de les corriger, de demander "
          "leur suppression et de vous opposer à certains traitements. Pour exercer ces "
          "droits, contactez-nous aux coordonnées indiquées ci-dessous.",
    ),
    PrivacySection(
      heading: 'Notifications push',
      body:
          "Avec votre accord, nous envoyons des notifications via Firebase Cloud "
          "Messaging (rappels de cotisation, confirmations de paiement). Vous pouvez "
          "les désactiver depuis les paramètres de l'application ou de votre appareil.",
    ),
    PrivacySection(
      heading: 'Suppression de compte',
      body:
          "Pour supprimer votre compte et les données associées, envoyez une demande à "
          "contact@cmcda.cm depuis l'adresse e-mail liée à votre compte, ou contactez "
          "un administrateur. Certaines données de cotisation peuvent être conservées "
          "de manière anonymisée pour les besoins comptables de l'association.",
    ),
    PrivacySection(
      heading: 'Contact',
      body:
          "CMCDA — WoilaTech, Ngaoundéré, Cameroun\n"
          "E-mail : contact@cmcda.cm\n"
          "Téléphone : +237 699 000 000\n"
          "Site web : https://cmcda.cm",
    ),
  ],

  // ── English ──────────────────────────────────────────────────
  'en': [
    PrivacySection(
      heading: 'Introduction',
      body:
          "This privacy policy explains how CMCDA (Cameroon Muslim Community "
          "Development Association), through the CMCDA Platform app developed by "
          "WoilaTech (Ngaoundéré, Cameroon), collects, uses and protects your personal "
          "data. By using the app, you agree to the practices described below.",
    ),
    PrivacySection(
      heading: 'Data we collect',
      body:
          "• Identity and contact: first name, last name, phone number, email address, "
          "region, department, city and neighbourhood.\n"
          "• Account: member number (e.g. CM-000001), role, status and total "
          "contributions.\n"
          "• Payments: contribution records (amount, method, period, status) and, for "
          "bank transfers, the proof-of-transfer image you upload.\n"
          "• Technical data: your device's notification token (FCM) and preferred "
          "language.",
    ),
    PrivacySection(
      heading: 'How we use your data',
      body:
          "We use your data to: create and manage your member account, record and "
          "validate your contributions, issue receipts, send you notifications "
          "(reminders and payment confirmations), produce internal reports and meet the "
          "association's compliance needs. We never sell your data.",
    ),
    PrivacySection(
      heading: 'Data sharing',
      body:
          "Your data is only accessible to authorised CMCDA administrators and officers, "
          "within the scope of their duties. It is processed by Google Firebase, our "
          "infrastructure provider. We do not share your data with third parties for "
          "commercial purposes.",
    ),
    PrivacySection(
      heading: 'Storage and security',
      body:
          "Your data is hosted on Google Firebase (Authentication, Cloud Firestore, "
          "Cloud Storage, Cloud Messaging and Cloud Functions). Proof-of-transfer images "
          "are stored securely and are readable only by you and authorised staff. Access "
          "is controlled by security rules and Firebase authentication.",
    ),
    PrivacySection(
      heading: 'Data retention',
      body:
          "We keep your data for as long as your account is active or as needed to track "
          "contributions and meet our obligations. You can request deletion of your "
          "account at any time.",
    ),
    PrivacySection(
      heading: 'Your rights',
      body:
          "You have the right to access your data, correct it, request its deletion and "
          "object to certain processing. To exercise these rights, contact us using the "
          "details below.",
    ),
    PrivacySection(
      heading: 'Push notifications',
      body:
          "With your consent, we send notifications via Firebase Cloud Messaging "
          "(contribution reminders, payment confirmations). You can disable them from "
          "the app settings or your device settings.",
    ),
    PrivacySection(
      heading: 'Account deletion',
      body:
          "To delete your account and associated data, send a request to "
          "contact@cmcda.cm from the email address linked to your account, or contact an "
          "administrator. Some contribution data may be retained in anonymised form for "
          "the association's accounting purposes.",
    ),
    PrivacySection(
      heading: 'Contact',
      body:
          "CMCDA — WoilaTech, Ngaoundéré, Cameroon\n"
          "Email: contact@cmcda.cm\n"
          "Phone: +237 699 000 000\n"
          "Website: https://cmcda.cm",
    ),
  ],

  // ── Arabic ───────────────────────────────────────────────────
  'ar': [
    PrivacySection(
      heading: 'مقدمة',
      body:
          "توضح سياسة الخصوصية هذه كيفية قيام جمعية التنمية المجتمعية الإسلامية "
          "بالكاميرون (CMCDA)، عبر تطبيق CMCDA Platform الذي طورته شركة WoilaTech "
          "(نغاونديري، الكاميرون)، بجمع بياناتك الشخصية واستخدامها وحمايتها. "
          "باستخدامك للتطبيق، فإنك توافق على الممارسات الموضحة أدناه.",
    ),
    PrivacySection(
      heading: 'البيانات التي نجمعها',
      body:
          "• الهوية والتواصل: الاسم الأول، اسم العائلة، رقم الهاتف، البريد الإلكتروني، "
          "المنطقة، المقاطعة، المدينة والحي.\n"
          "• الحساب: رقم العضوية (مثل CM-000001)، الدور، الحالة وإجمالي المساهمات.\n"
          "• المدفوعات: سجلات المساهمات (المبلغ، الطريقة، الفترة، الحالة)، وبالنسبة "
          "للتحويلات البنكية صورة إثبات التحويل التي ترفعها.\n"
          "• البيانات التقنية: رمز الإشعارات (FCM) الخاص بجهازك واللغة المفضلة.",
    ),
    PrivacySection(
      heading: 'كيف نستخدم بياناتك',
      body:
          "نستخدم بياناتك من أجل: إنشاء حساب العضوية وإدارته، تسجيل مساهماتك والتحقق "
          "منها، إصدار الإيصالات، إرسال الإشعارات إليك (التذكيرات وتأكيدات الدفع)، "
          "إعداد التقارير الداخلية وضمان امتثال الجمعية. نحن لا نبيع بياناتك أبدًا.",
    ),
    PrivacySection(
      heading: 'مشاركة البيانات',
      body:
          "لا يمكن الوصول إلى بياناتك إلا للمسؤولين والموظفين المخولين في CMCDA ضمن "
          "نطاق مهامهم. تتم معالجتها بواسطة Google Firebase، مزود البنية التحتية لدينا. "
          "نحن لا نشارك بياناتك مع أطراف ثالثة لأغراض تجارية.",
    ),
    PrivacySection(
      heading: 'التخزين والأمان',
      body:
          "تُستضاف بياناتك على Google Firebase (المصادقة، Cloud Firestore، Cloud "
          "Storage، Cloud Messaging وCloud Functions). تُخزَّن صور إثبات التحويل بشكل "
          "آمن ولا يمكن قراءتها إلا من قبلك ومن قبل الموظفين المخولين. يتم التحكم في "
          "الوصول عبر قواعد الأمان ومصادقة Firebase.",
    ),
    PrivacySection(
      heading: 'الاحتفاظ بالبيانات',
      body:
          "نحتفظ ببياناتك طالما كان حسابك نشطًا أو حسب الحاجة لتتبع المساهمات والوفاء "
          "بالتزاماتنا. يمكنك طلب حذف حسابك في أي وقت.",
    ),
    PrivacySection(
      heading: 'حقوقك',
      body:
          "يحق لك الوصول إلى بياناتك وتصحيحها وطلب حذفها والاعتراض على بعض عمليات "
          "المعالجة. لممارسة هذه الحقوق، يرجى التواصل معنا عبر البيانات الموضحة أدناه.",
    ),
    PrivacySection(
      heading: 'الإشعارات',
      body:
          "بموافقتك، نرسل إشعارات عبر Firebase Cloud Messaging (تذكيرات المساهمة، "
          "تأكيدات الدفع). يمكنك تعطيلها من إعدادات التطبيق أو إعدادات جهازك.",
    ),
    PrivacySection(
      heading: 'حذف الحساب',
      body:
          "لحذف حسابك والبيانات المرتبطة به، أرسل طلبًا إلى contact@cmcda.cm من عنوان "
          "البريد الإلكتروني المرتبط بحسابك، أو تواصل مع أحد المسؤولين. قد يتم الاحتفاظ "
          "ببعض بيانات المساهمات بشكل مجهول الهوية لأغراض محاسبية للجمعية.",
    ),
    PrivacySection(
      heading: 'التواصل',
      body:
          "CMCDA — WoilaTech، نغاونديري، الكاميرون\n"
          "البريد الإلكتروني: contact@cmcda.cm\n"
          "الهاتف: +237 699 000 000\n"
          "الموقع الإلكتروني: https://cmcda.cm",
    ),
  ],
};
