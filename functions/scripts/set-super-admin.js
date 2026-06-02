/**
 * One-off bootstrap: grant the super_admin role to a user.
 * Run from the functions/ folder:
 *   node scripts/set-super-admin.js <uid-or-email>
 *
 * Sets BOTH the `role` custom claim and the Firestore users/{uid}.role field,
 * so the in-app setUserRole Cloud Function (which requires an existing
 * super_admin to call it) can take over from here.
 *
 * Uses the same service-account key as migrate_member_numbers.js.
 */

const admin = require('firebase-admin');

const serviceAccount = require('c:/Users/USER PRO/Downloads/cmcda-2f485-firebase-adminsdk-fbsvc-67c2839bfa.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'cmcda-2f485',
});
const db = admin.firestore();
const auth = admin.auth();

async function resolveUid(arg) {
  if (arg.includes('@')) {
    const user = await auth.getUserByEmail(arg);
    return user.uid;
  }
  return arg;
}

async function main() {
  const arg = process.argv[2];
  if (!arg) {
    console.error('Usage: node scripts/set-super-admin.js <uid-or-email>');
    process.exit(1);
  }

  const uid = await resolveUid(arg);

  await auth.setCustomUserClaims(uid, { role: 'super_admin' });
  await db.collection('users').doc(uid).set(
    { role: 'super_admin', updatedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true },
  );

  console.log(`✓ ${uid} is now super_admin (claim + Firestore doc updated).`);
  console.log('  The user must sign out and back in for the new claim to take effect.');
  process.exit(0);
}

main().catch((e) => {
  console.error('Failed:', e);
  process.exit(1);
});
