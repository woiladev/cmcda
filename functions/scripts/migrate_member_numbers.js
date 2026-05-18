/**
 * One-time migration: reassign CM-XXXXXX member numbers to region-based prefixes.
 * Run from the functions/ folder:
 *   node scripts/migrate_member_numbers.js
 *
 * Uses Application Default Credentials (Firebase CLI login is enough).
 */

const admin = require('firebase-admin');

const serviceAccount = require('c:/Users/USER PRO/Downloads/cmcda-2f485-firebase-adminsdk-fbsvc-67c2839bfa.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'cmcda-2f485',
});
const db = admin.firestore();

// Must mirror AppConstants.regionMemberPrefixes in app_constants.dart
const REGION_PREFIXES = {
  'Adamaoua':     'Nde',
  'Centre':       'Yde',
  'Est':          'Bta',
  'Extrême-Nord': 'Mra',
  'Littoral':     'Dla',
  'Nord':         'Goa',
  'Nord-Ouest':   'Bda',
  'Ouest':        'Bfs',
  'Sud':          'Ebo',
  'Sud-Ouest':    'Bua',
};
const FALLBACK_PREFIX = 'Cmr';

function prefixForRegion(region) {
  return REGION_PREFIXES[region] || FALLBACK_PREFIX;
}

function formatNumber(n) {
  return n.toString().padStart(6, '0');
}

async function migrate() {
  // 1. Load all users and filter for the old CM- format in code
  const snapshot = await db.collection('users').get();
  const oldUsers = snapshot.docs.filter(
    (d) => typeof d.data().memberNumber === 'string' && d.data().memberNumber.startsWith('CM-')
  );

  if (oldUsers.length === 0) {
    console.log('No CM- users found. Nothing to migrate.');
    return;
  }

  console.log(`Found ${oldUsers.length} user(s) to migrate.\n`);

  // 2. Group users by their region prefix so we can assign sequential numbers
  const groups = {};
  for (const doc of oldUsers) {
    const region = doc.data().region || '';
    const prefix = prefixForRegion(region);
    if (!groups[prefix]) groups[prefix] = [];
    groups[prefix].push(doc);
  }

  // 3. For each prefix group, read the current counter then assign numbers
  for (const [prefix, docs] of Object.entries(groups)) {
    const counterRef = db.collection('counters').doc(`members_${prefix}`);

    const pending = [];

    await db.runTransaction(async (tx) => {
      const counterSnap = await tx.get(counterRef);
      let count = (counterSnap.data() && counterSnap.data().count) ? counterSnap.data().count : 0;

      for (const doc of docs) {
        count += 1;
        const newNumber = `${prefix}-${formatNumber(count)}`;
        pending.push({ old: doc.data().memberNumber, new: newNumber, uid: doc.ref.id });
        tx.update(doc.ref, {
          memberNumber: newNumber,
          updatedAt: admin.firestore.Timestamp.now(),
        });
      }

      tx.set(counterRef, { count }, { merge: true });
    });

    for (const u of pending) {
      console.log(`  ${u.old}  ->  ${u.new}  (uid: ${u.uid})`);
    }
    console.log(`[OK] ${docs.length} user(s) updated for prefix [${prefix}].\n`);
  }

  console.log('Migration complete.');
}

migrate().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});
