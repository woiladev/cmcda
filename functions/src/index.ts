import * as admin from 'firebase-admin';
import { onDocumentWritten, onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { v4 as uuidv4 } from 'uuid';

admin.initializeApp();
const db = admin.firestore();

// ── Collection / doc constants ────────────────────────────────────
const COL_NOTIFICATIONS = 'notifications';
const COL_ACCOUNTS     = 'wallet_accounts';
const COL_TRANSACTIONS = 'wallet_transactions';
const COL_CONFIG       = 'wallet_config';
const COL_USERS        = 'users';
const COL_CONTRIBUTIONS = 'contributions';
const DOC_SUMMARY      = 'summary';
const DOC_PAYMENT_MAP  = 'payment_method_map';

// Ten Cameroon regions with their accent colour for seeding
const REGIONS: { name: string; color: string }[] = [
  { name: 'Adamaoua',     color: '#16a34a' },
  { name: 'Centre',       color: '#0ea5e9' },
  { name: 'Est',          color: '#f59e0b' },
  { name: 'Extrême-Nord', color: '#dc2626' },
  { name: 'Littoral',     color: '#7c3aed' },
  { name: 'Nord',         color: '#0f766e' },
  { name: 'Nord-Ouest',   color: '#ea580c' },
  { name: 'Ouest',        color: '#8b5cf6' },
  { name: 'Sud',          color: '#059669' },
  { name: 'Sud-Ouest',    color: '#0284c7' },
];

// ── Helpers ───────────────────────────────────────────────────────

type TxKind = 'inflow' | 'outflow' | 'transfer_in' | 'transfer_out';

function isInflow(kind: TxKind): boolean {
  return kind === 'inflow' || kind === 'transfer_in';
}

/**
 * Recomputes current_balance for one account by summing all its transactions
 * from opening_balance.
 */
async function recomputeAccountBalance(accountId: string): Promise<void> {
  const [accountDoc, txsSnap] = await Promise.all([
    db.collection(COL_ACCOUNTS).doc(accountId).get(),
    db.collection(COL_TRANSACTIONS).where('account_id', '==', accountId).get(),
  ]);

  if (!accountDoc.exists) return;

  const openingBalance = (accountDoc.data()?.opening_balance as number) ?? 0;
  let balance = openingBalance;

  for (const tx of txsSnap.docs) {
    const d = tx.data();
    const kind = d.kind as TxKind;
    const amount = (d.amount as number) ?? 0;
    balance += isInflow(kind) ? amount : -amount;
  }

  await accountDoc.ref.update({
    current_balance: balance,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Rebuilds wallet_config/summary:
 *   - total_balance
 *   - accounts[] (includes region field)
 *   - monthly[]  (last 12 calendar months, inflow + outflow)
 */
async function rebuildSummary(): Promise<void> {
  const accountsSnap = await db
    .collection(COL_ACCOUNTS)
    .where('archived', '==', false)
    .get();

  let totalBalance = 0;
  const accounts: object[] = [];

  for (const acc of accountsSnap.docs) {
    const d = acc.data();
    const bal = (d.current_balance as number) ?? 0;
    totalBalance += bal;
    accounts.push({
      id: acc.id,
      name: d.name,
      type: d.type,
      color: d.color,
      currency: (d.currency as string) ?? 'XAF',
      balance: bal,
      region: (d.region as string) ?? null,
    });
  }

  // Aggregate last 12 calendar months in a single query
  const now = new Date();
  const twelveMonthsAgo = new Date(now.getFullYear(), now.getMonth() - 11, 1);

  const txsSnap = await db
    .collection(COL_TRANSACTIONS)
    .where(
      'occurred_at',
      '>=',
      admin.firestore.Timestamp.fromDate(twelveMonthsAgo),
    )
    .get();

  const monthMap = new Map<string, { inflow: number; outflow: number }>();
  for (let i = 11; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    monthMap.set(key, { inflow: 0, outflow: 0 });
  }

  for (const tx of txsSnap.docs) {
    const d = tx.data();
    const ts = d.occurred_at as admin.firestore.Timestamp;
    if (!ts) continue;
    const date = ts.toDate();
    const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
    const bucket = monthMap.get(key);
    if (!bucket) continue;
    const kind = d.kind as TxKind;
    const amount = (d.amount as number) ?? 0;
    if (isInflow(kind)) {
      bucket.inflow += amount;
    } else {
      bucket.outflow += amount;
    }
  }

  const monthly = Array.from(monthMap.entries()).map(([month, v]) => ({
    month,
    inflow: v.inflow,
    outflow: v.outflow,
  }));

  await db.collection(COL_CONFIG).doc(DOC_SUMMARY).set({
    total_balance: totalBalance,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    accounts,
    monthly,
  });
}

// ── 1. onWalletAccountWrite ───────────────────────────────────────────
// Triggers whenever a wallet_account doc is created, updated, or deleted.
// Rebuilds the summary so the transparency screen stays in sync with the
// current account list (e.g. after seeding regional wallets).

export const onWalletAccountWrite = onDocumentWritten(
  { document: `${COL_ACCOUNTS}/{accountId}`, region: 'europe-west1' },
  async (_event) => {
    await rebuildSummary();
  },
);

// ── 2. onWalletTxWrite ─────────────────────────────────────────────
// Triggers on every create / update / delete of a wallet_transactions doc.
// Recomputes the balance of every impacted account then rebuilds the summary.

export const onWalletTxWrite = onDocumentWritten(
  { document: `${COL_TRANSACTIONS}/{txId}`, region: 'europe-west1' },
  async (event) => {
    const before = event.data?.before.data();
    const after  = event.data?.after.data();

    const accountIds = new Set<string>();
    if (before?.account_id) accountIds.add(before.account_id as string);
    if (after?.account_id)  accountIds.add(after.account_id as string);

    if (accountIds.size === 0) return;

    await Promise.all([...accountIds].map(recomputeAccountBalance));
    await rebuildSummary();
  },
);

// ── 2. onContributionConfirmed ─────────────────────────────────────
// When a contribution's status changes to 'confirmed':
//   1. Fetches the member's region from their user doc.
//   2. Looks up payment_method_map[region] to find the regional account.
//   3. Creates an inflow wallet_transaction linked to the contribution.
// On un-confirm (cancel / fail / delete): removes the linked transaction.

export const onContributionConfirmed = onDocumentWritten(
  { document: `${COL_CONTRIBUTIONS}/{contribId}`, region: 'europe-west1' },
  async (event) => {
    const contribId  = event.params.contribId;
    const before     = event.data?.before.data();
    const after      = event.data?.after.data();

    const wasConfirmed = before?.status === 'confirmed';
    const isConfirmed  = after?.status  === 'confirmed';

    // No status change and document still exists — skip (e.g. notes/validatedBy update)
    if (wasConfirmed === isConfirmed && after !== undefined) return;

    // ── Becoming confirmed ───────────────────────────────────────
    if (isConfirmed && !wasConfirmed && after) {
      const memberId = (after.memberId as string) ?? '';
      const amount   = (after.amount   as number) ?? 0;

      if (!memberId) {
        console.warn(`[onContributionConfirmed] Contribution ${contribId} has no memberId.`);
        return;
      }

      // Resolve member's region
      const userDoc = await db.collection(COL_USERS).doc(memberId).get();
      const region  = (userDoc.data()?.region as string) ?? '';

      if (!region) {
        console.warn(
          `[onContributionConfirmed] Member ${memberId} has no region set. ` +
          `Cannot route contribution ${contribId} to a regional wallet.`,
        );
        return;
      }

      // Look up which account this region maps to
      const mapDoc    = await db.collection(COL_CONFIG).doc(DOC_PAYMENT_MAP).get();
      const accountId = (mapDoc.data()?.[region] as string) ?? null;

      if (!accountId) {
        console.warn(
          `[onContributionConfirmed] No account mapped for region "${region}". ` +
          `Skipping wallet tx for contribution ${contribId}.`,
        );
        return;
      }

      await db.collection(COL_TRANSACTIONS).add({
        account_id:        accountId,
        kind:              'inflow',
        amount,
        category:          'Contributions',
        note:              `Contribution ${contribId}`,
        occurred_at:       after.confirmedAt ?? admin.firestore.FieldValue.serverTimestamp(),
        contribution_id:   contribId,
        transfer_group_id: null,
        created_by:        memberId,
        created_at:        admin.firestore.FieldValue.serverTimestamp(),
      });

      return;
    }

    // ── Was confirmed but no longer ──────────────────────────────
    if (wasConfirmed && !isConfirmed) {
      const snap = await db
        .collection(COL_TRANSACTIONS)
        .where('contribution_id', '==', contribId)
        .get();

      const batch = db.batch();
      snap.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
    }
  },
);

// ── 3. createTransfer ─────────────────────────────────────────────
// Callable: { from, to, amount, note? }
// Creates transfer_out + transfer_in sharing a transfer_group_id atomically.

interface TransferRequest {
  from:   string;
  to:     string;
  amount: number;
  note?:  string;
}

export const createTransfer = onCall<TransferRequest>(
  { region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    const role = request.auth.token.role as string | undefined;
    if (role !== 'admin' && role !== 'super_admin') {
      throw new HttpsError('permission-denied', 'Admin role required.');
    }

    const { from, to, amount, note } = request.data;

    if (!from || !to || !amount) {
      throw new HttpsError('invalid-argument', 'from, to, and amount are required.');
    }
    if (from === to) {
      throw new HttpsError('invalid-argument', 'Source and destination must differ.');
    }
    if (!Number.isInteger(amount) || amount <= 0) {
      throw new HttpsError('invalid-argument', 'amount must be a positive integer.');
    }

    const transferGroupId = uuidv4();
    const uid = request.auth.uid;
    const now = admin.firestore.FieldValue.serverTimestamp();

    await db.runTransaction(async (txn) => {
      const fromRef = db.collection(COL_ACCOUNTS).doc(from);
      const toRef   = db.collection(COL_ACCOUNTS).doc(to);

      const [fromDoc, toDoc] = await Promise.all([txn.get(fromRef), txn.get(toRef)]);

      if (!fromDoc.exists) throw new HttpsError('not-found', `Source account ${from} not found.`);
      if (!toDoc.exists)   throw new HttpsError('not-found', `Destination account ${to} not found.`);
      if (fromDoc.data()?.archived) throw new HttpsError('failed-precondition', 'Source account is archived.');
      if (toDoc.data()?.archived)   throw new HttpsError('failed-precondition', 'Destination account is archived.');

      const outRef = db.collection(COL_TRANSACTIONS).doc();
      const inRef  = db.collection(COL_TRANSACTIONS).doc();

      txn.set(outRef, {
        account_id: from, kind: 'transfer_out', amount,
        category: null, note: note ?? null, occurred_at: now,
        contribution_id: null, transfer_group_id: transferGroupId,
        created_by: uid, created_at: now,
      });
      txn.set(inRef, {
        account_id: to, kind: 'transfer_in', amount,
        category: null, note: note ?? null, occurred_at: now,
        contribution_id: null, transfer_group_id: transferGroupId,
        created_by: uid, created_at: now,
      });
    });

    return { transferGroupId };
  },
);

// ── 4. seedRegionalWallets ────────────────────────────────────────
// Callable (admin only): idempotently creates one wallet_account per
// Cameroon region and sets payment_method_map to { region → accountId }.
// Safe to call multiple times — existing regional accounts are reused.

export const seedRegionalWallets = onCall(
  { region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    const role = request.auth.token.role as string | undefined;
    if (role !== 'admin' && role !== 'super_admin') {
      throw new HttpsError('permission-denied', 'Admin role required.');
    }

    const uid = request.auth.uid;
    const now = admin.firestore.FieldValue.serverTimestamp();
    const paymentMap: Record<string, string> = {};
    let created = 0;
    let reused  = 0;

    for (const r of REGIONS) {
      const existing = await db
        .collection(COL_ACCOUNTS)
        .where('region', '==', r.name)
        .limit(1)
        .get();

      let accountId: string;
      if (!existing.empty) {
        accountId = existing.docs[0].id;
        reused++;
      } else {
        const ref = await db.collection(COL_ACCOUNTS).add({
          name:            `Trésorerie – ${r.name}`,
          type:            'other',
          currency:        'XAF',
          opening_balance: 0,
          current_balance: 0,
          color:           r.color,
          region:          r.name,
          archived:        false,
          created_by:      uid,
          created_at:      now,
          updated_at:      now,
        });
        accountId = ref.id;
        created++;
      }

      paymentMap[r.name] = accountId;
    }

    await db.collection(COL_CONFIG).doc(DOC_PAYMENT_MAP).set(paymentMap);

    // Trigger a summary rebuild
    await rebuildSummary();

    return { created, reused, regions: Object.keys(paymentMap).length };
  },
);

// ── 5. backfillConfirmedContributions ─────────────────────────
// Callable (admin only): scans all confirmed contributions and creates
// missing wallet_transactions for any that were confirmed before the
// onContributionConfirmed trigger was deployed.
// Idempotent — skips contributions that already have a linked transaction.

export const backfillConfirmedContributions = onCall(
  { region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    const role = request.auth.token.role as string | undefined;
    if (role !== 'admin' && role !== 'super_admin') {
      throw new HttpsError('permission-denied', 'Admin role required.');
    }

    // Load payment map once
    const mapDoc = await db.collection(COL_CONFIG).doc(DOC_PAYMENT_MAP).get();
    const paymentMap = (mapDoc.data() ?? {}) as Record<string, string>;

    if (Object.keys(paymentMap).length === 0) {
      throw new HttpsError(
        'failed-precondition',
        'Payment map is empty. Seed regional wallets first.',
      );
    }

    // Fetch all confirmed contributions
    const confirmedSnap = await db
      .collection(COL_CONTRIBUTIONS)
      .where('status', '==', 'confirmed')
      .get();

    // Fetch all existing contribution-linked transactions in one query
    const existingTxSnap = await db
      .collection(COL_TRANSACTIONS)
      .where('contribution_id', '!=', null)
      .get();

    const alreadyLinked = new Set<string>(
      existingTxSnap.docs
        .map((d) => d.data().contribution_id as string | null)
        .filter((id): id is string => !!id),
    );

    let created = 0;
    let skipped = 0;
    let failed  = 0;

    for (const contrib of confirmedSnap.docs) {
      const contribId = contrib.id;

      // Skip if a wallet transaction already exists for this contribution
      if (alreadyLinked.has(contribId)) {
        skipped++;
        continue;
      }

      const d        = contrib.data();
      const memberId = (d.memberId as string) ?? '';
      const amount   = (d.amount   as number) ?? 0;

      if (!memberId) { failed++; continue; }

      // Resolve member region
      const userDoc = await db.collection(COL_USERS).doc(memberId).get();
      const region  = (userDoc.data()?.region as string) ?? '';

      if (!region) { failed++; continue; }

      const accountId = paymentMap[region] ?? null;
      if (!accountId) { failed++; continue; }

      await db.collection(COL_TRANSACTIONS).add({
        account_id:        accountId,
        kind:              'inflow',
        amount,
        category:          'Contributions',
        note:              `Contribution ${contribId}`,
        occurred_at:       d.confirmedAt ?? admin.firestore.FieldValue.serverTimestamp(),
        contribution_id:   contribId,
        transfer_group_id: null,
        created_by:        memberId,
        created_at:        admin.firestore.FieldValue.serverTimestamp(),
      });

      created++;
    }

    // Rebuild summary once at the end
    if (created > 0) await rebuildSummary();

    return { created, skipped, failed, total: confirmedSnap.size };
  },
);

// ── 6. onNotificationCreate ───────────────────────────────────────
// Triggers when a new doc is created in the `notifications` collection.
// Reads the target user's FCM token from Firestore and sends a push via
// the Firebase Admin Messaging SDK.

export const onNotificationCreate = onDocumentCreated(
  { document: `${COL_NOTIFICATIONS}/{notifId}`, region: 'europe-west1' },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const userId = data.userId as string;
    const title  = data.title  as string;
    const body   = data.body   as string;
    const type   = (data.type  as string) ?? '';

    if (!userId || !title || !body) return;

    // Fetch the user's FCM token
    const userDoc  = await db.collection(COL_USERS).doc(userId).get();
    const fcmToken = userDoc.data()?.fcmToken as string | undefined;

    if (!fcmToken) {
      console.log(`[onNotificationCreate] No FCM token for user ${userId}, skipping push.`);
      return;
    }

    // FCM data payload values must all be strings
    const extraData: Record<string, string> = { type, notifId: event.data!.id };
    const payload = data.data as Record<string, unknown> | undefined;
    if (payload && typeof payload === 'object') {
      for (const [k, v] of Object.entries(payload)) {
        extraData[k] = String(v);
      }
    }

    try {
      await admin.messaging().send({
        token: fcmToken,
        notification: { title, body },
        data: extraData,
        android: {
          priority: 'high',
          notification: {
            channelId: 'cmcda_high_importance',
            clickAction: 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
        apns: {
          payload: {
            aps: { sound: 'default', badge: 1 },
          },
        },
      });
      console.log(`[onNotificationCreate] Push sent to user ${userId}.`);
    } catch (err) {
      console.error(`[onNotificationCreate] Failed for user ${userId}:`, err);
    }
  },
);
