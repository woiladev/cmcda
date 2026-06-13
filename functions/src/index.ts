import * as admin from 'firebase-admin';
import { onDocumentWritten, onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onCall, onRequest, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineSecret } from 'firebase-functions/params';
import { v4 as uuidv4 } from 'uuid';
import { createVerify, createHash } from 'crypto';

admin.initializeApp();
const db = admin.firestore();

// ── Collection / doc constants ────────────────────────────────────
const COL_NOTIFICATIONS = 'notifications';
const COL_ACCOUNTS     = 'wallet_accounts';
const COL_TRANSACTIONS = 'wallet_transactions';
const COL_CONFIG       = 'wallet_config';
const COL_USERS        = 'users';
const COL_CONTRIBUTIONS = 'contributions';
const COL_REMINDER_PLANS = 'reminder_plans';
const DOC_SUMMARY      = 'summary';
const DOC_REGION_MAP   = 'region_account_map';
const DOC_REGION_TOTALS = 'region_totals';

// Annual contribution target (FCFA) — reminders stop once a member reaches it.
const ANNUAL_TARGET = 36500;
const CADENCE_AMOUNT: Record<string, number> = {
  daily: 100,
  weekly: 700,
  monthly: 3000,
  annual: 36500,
};

// Bucket key for confirmed contributions that can be attributed to no region
// (member and recorder both have none). Kept in sync with
// AppConstants.walletOtherRegionKey on the client.
const OTHER_REGION = 'Autres';

// The 10 Cameroon region treasury wallets, plus an "Autres" catch-all for
// confirmed contributions that resolve to no region. Confirmed contributions
// are routed to the wallet for their region (member → recorder → Autres), so
// each wallet's ledger holds every contribution collected in that region and
// its total_received is that region's running tally. Colors mirror
// AppConstants.regionWalletColors on the client. The Autres wallet keeps the
// invariant that the wallets sum to the gross collected — without it,
// unattributed contributions would have no ledger to land in.
const REGION_WALLETS: { region: string; name: string; color: string }[] = [
  { region: 'Adamaoua',     name: 'Adamaoua',     color: '#16a34a' },
  { region: 'Centre',       name: 'Centre',       color: '#0ea5e9' },
  { region: 'Est',          name: 'Est',          color: '#f59e0b' },
  { region: 'Extrême-Nord', name: 'Extrême-Nord', color: '#dc2626' },
  { region: 'Littoral',     name: 'Littoral',     color: '#7c3aed' },
  { region: 'Nord',         name: 'Nord',         color: '#0f766e' },
  { region: 'Nord-Ouest',   name: 'Nord-Ouest',   color: '#ea580c' },
  { region: 'Ouest',        name: 'Ouest',        color: '#8b5cf6' },
  { region: 'Sud',          name: 'Sud',          color: '#059669' },
  { region: 'Sud-Ouest',    name: 'Sud-Ouest',    color: '#0284c7' },
  { region: OTHER_REGION,   name: 'Autres',       color: '#64748b' },
];

// ── Helpers ───────────────────────────────────────────────────────

type TxKind = 'inflow' | 'outflow' | 'transfer_in' | 'transfer_out';

function isInflow(kind: TxKind): boolean {
  return kind === 'inflow' || kind === 'transfer_in';
}

// Formats an integer FCFA amount, e.g. "3 000 FCFA" (matches AppUtils.formatAmount).
function formatFcfa(amount: number): string {
  return `${amount.toLocaleString('fr-FR')} FCFA`;
}

// Creates a notification doc; onNotificationCreate turns it into an FCM push.
async function createNotification(params: {
  userId: string;
  type:   string;
  title:  string;
  body:   string;
  data?:  Record<string, unknown>;
}): Promise<void> {
  if (!params.userId) return;
  await db.collection(COL_NOTIFICATIONS).add({
    userId:    params.userId,
    type:      params.type,
    title:     params.title,
    body:      params.body,
    read:      false,
    data:      params.data ?? {},
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Authorizes the caller as super_admin and returns their uid.
 * Prefers the `role` custom claim; falls back to the caller's Firestore user
 * doc to cover the bootstrap window before claims are populated.
 */
async function assertSuperAdmin(request: CallableRequest): Promise<string> {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be signed in.');
  }
  const claimRole = request.auth.token.role as string | undefined;
  if (claimRole === 'super_admin') return request.auth.uid;

  const snap = await db.collection(COL_USERS).doc(request.auth.uid).get();
  const docRole = snap.data()?.role as string | undefined;
  if (docRole === 'super_admin') return request.auth.uid;

  throw new HttpsError('permission-denied', 'Super admin role required.');
}

/** Reads a member's region from their user doc. '' when unknown. */
async function getMemberRegion(memberId: string): Promise<string> {
  if (!memberId) return '';
  const userDoc = await db.collection(COL_USERS).doc(memberId).get();
  return (userDoc.data()?.region as string) ?? '';
}

/**
 * Resolves the region a confirmed contribution should be attributed to so the
 * treasury total stays complete: the member's own region, else the recorder's
 * region (focal officer / admin who logged it), else the OTHER_REGION bucket.
 * Never returns '' — every confirmed contribution lands somewhere.
 */
async function resolveContribRegion(
  memberId: string,
  recordedBy: string,
): Promise<string> {
  const member = await getMemberRegion(memberId);
  if (member) return member;
  const recorder = recordedBy ? await getMemberRegion(recordedBy) : '';
  return recorder || OTHER_REGION;
}

/** Adjusts wallet_config/region_totals[region] by [delta]. No-op if unknown. */
async function bumpRegionTotalForRegion(
  region: string,
  delta: number,
): Promise<void> {
  if (!region || delta === 0) return;
  await db.collection(COL_CONFIG).doc(DOC_REGION_TOTALS).set(
    {
      [region]: admin.firestore.FieldValue.increment(delta),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
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
  // Gross money received THROUGH this wallet: direct inflows only (confirmed
  // contributions + manual inflow movements). Excludes transfer_in (internal
  // moves) and is never reduced by outflows, so it reflects total received.
  let received = 0;

  for (const tx of txsSnap.docs) {
    const d = tx.data();
    const kind = d.kind as TxKind;
    const amount = (d.amount as number) ?? 0;
    balance += isInflow(kind) ? amount : -amount;
    if (kind === 'inflow') received += amount;
  }

  await accountDoc.ref.update({
    current_balance: balance,
    total_received: received,
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
    // Gross received via this method; fall back to balance for accounts not yet
    // recomputed since this field was added.
    const received = (d.total_received as number) ?? bal;
    totalBalance += bal;
    accounts.push({
      id: acc.id,
      name: d.name,
      type: d.type,
      color: d.color,
      currency: (d.currency as string) ?? 'XAF',
      balance: bal,
      received,
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

    // ── Becoming failed (rejected) ───────────────────────────────
    // Notify the member when their payment is rejected. Handled before the
    // confirmed-only early return below, which would otherwise skip this edge.
    const wasFailed = before?.status === 'failed';
    const isFailed  = after?.status  === 'failed';
    if (isFailed && !wasFailed && after) {
      const reason = (after.notes as string) ?? '';
      await createNotification({
        userId: (after.memberId as string) ?? '',
        type:   'payment_rejected',
        title:  'Paiement rejeté',
        body:   `Votre contribution de ${formatFcfa((after.amount as number) ?? 0)} a été rejetée.` +
                (reason ? ` Motif : ${reason}` : ''),
        data:   { reason },
      });
    }

    // No status change and document still exists — skip (e.g. notes/validatedBy update)
    if (wasConfirmed === isConfirmed && after !== undefined) return;

    // ── Becoming confirmed ───────────────────────────────────────
    if (isConfirmed && !wasConfirmed && after) {
      const memberId   = (after.memberId   as string) ?? '';
      const amount     = (after.amount     as number) ?? 0;
      const recordedBy = (after.recordedBy as string) ?? '';

      // The member's OWN region drives the matricule prefix — it must reflect
      // who paid, never a fallback.
      const memberRegion = await getMemberRegion(memberId);

      // Routing region for the treasury aggregate + wallet: member's region,
      // else the recorder's, else the "Autres" bucket. Guarantees every
      // confirmed contribution is counted (incl. focal-collected cash for
      // unregistered members).
      const region = memberRegion ||
        (recordedBy ? await getMemberRegion(recordedBy) : '') ||
        OTHER_REGION;

      // First confirmed contribution → issue the matricule and activate the
      // member (no-op if they already have a number).
      const matricule = await assignMatriculeOnFirstContribution(memberId, memberRegion);
      // Backfill this contribution's denormalised memberNumber if it was created
      // before the matricule existed (self-signup member's first payment).
      if (matricule && !((after.memberNumber as string) ?? '').trim()) {
        await event.data!.after.ref.update({ memberNumber: matricule });
      }

      // Per-region transparency aggregate — always runs (region never empty).
      await bumpRegionTotalForRegion(region, amount);

      // Notify the member their contribution is confirmed (covers mobile-money
      // auto-confirm AND admin dual-validation — both flip status to confirmed).
      const receiptNumber = (after.receiptNumber as string) ?? '';
      await createNotification({
        userId: memberId,
        type:   'payment_confirmed',
        title:  'Paiement confirmé',
        body:   `Votre contribution de ${formatFcfa(amount)} a été confirmée.` +
                (receiptNumber ? ` Reçu n° ${receiptNumber}.` : ''),
        data:   { amount: String(amount), receiptNumber },
      });

      // Route to this region's wallet: region_account_map[region]. `region`
      // was resolved above (member → recorder → Autres), so once
      // seedRegionWallets has run there is always a wallet to land in.
      const mapDoc    = await db.collection(COL_CONFIG).doc(DOC_REGION_MAP).get();
      const accountId = (mapDoc.data()?.[region] as string) ?? null;

      if (!accountId) {
        console.warn(
          `[onContributionConfirmed] No wallet mapped for region "${region}". ` +
          `Run "Initialize wallets". Skipping wallet tx for contribution ${contribId}.`,
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
        created_by:        memberId || (after.recordedBy as string) || 'system',
        created_at:        admin.firestore.FieldValue.serverTimestamp(),
      });

      return;
    }

    // ── Was confirmed but no longer ──────────────────────────────
    if (wasConfirmed && !isConfirmed) {
      // Reverse the per-region aggregate, resolving the same bucket the
      // confirmation credited (member region → recorder region → Autres).
      const reverseRegion = await resolveContribRegion(
        (before?.memberId as string) ?? '',
        (before?.recordedBy as string) ?? '',
      );
      await bumpRegionTotalForRegion(
        reverseRegion,
        -((before?.amount as number) ?? 0),
      );

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

// ── 2b. onContributionCreated ──────────────────────────────────────
// Assigns the sequential receipt number (RCP-000001) server-side. The client
// creates contributions with an empty receiptNumber so the write succeeds
// offline (no transaction needed on-device); this trigger fills in the number
// atomically when the doc lands — whether created online or synced from an
// offline device. Idempotent: skips docs that already have a receiptNumber.

export const onContributionCreated = onDocumentCreated(
  { document: `${COL_CONTRIBUTIONS}/{contribId}`, region: 'europe-west1' },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const existing = (snap.data()?.receiptNumber as string) ?? '';
    if (existing) return; // already numbered (e.g. legacy / retry)

    const counterRef = db.collection('counters').doc('receipts');
    const receiptNumber = await db.runTransaction(async (tx) => {
      const counter = await tx.get(counterRef);
      const next = ((counter.data()?.count as number) ?? 0) + 1;
      tx.set(counterRef, { count: next }, { merge: true });
      return `RCP-${String(next).padStart(6, '0')}`;
    });

    await snap.ref.update({ receiptNumber });
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
    const uid = await assertSuperAdmin(request);

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

// ── setUserRole ───────────────────────────────────────────────────
// Callable (super_admin only): assigns a role to a user. Keeps the custom
// claim and the Firestore user doc in sync, and writes an audit log entry.
// Refuses to demote the last remaining super_admin.

const VALID_ROLES = ['member', 'focal', 'admin', 'super_admin'];
const ROLE_LABELS_FR: Record<string, string> = {
  member:      'Membre',
  focal:       'Point focal',
  admin:       'Administrateur',
  super_admin: 'Super administrateur',
};

interface SetUserRoleRequest {
  uid:  string;
  role: string;
}

export const setUserRole = onCall<SetUserRoleRequest>(
  { region: 'europe-west1' },
  async (request) => {
    const callerUid = await assertSuperAdmin(request);

    const { uid, role } = request.data;
    if (!uid || !role) {
      throw new HttpsError('invalid-argument', 'uid and role are required.');
    }
    if (!VALID_ROLES.includes(role)) {
      throw new HttpsError('invalid-argument', `Invalid role: ${role}.`);
    }

    const userRef = db.collection(COL_USERS).doc(uid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new HttpsError('not-found', `User ${uid} not found.`);
    }
    const previousRole = userSnap.data()?.role as string | undefined;

    // Guard: never leave the platform without a super_admin.
    if (previousRole === 'super_admin' && role !== 'super_admin') {
      const supers = await db
        .collection(COL_USERS)
        .where('role', '==', 'super_admin')
        .get();
      if (supers.size <= 1) {
        throw new HttpsError(
          'failed-precondition',
          'Cannot remove the last super admin.',
        );
      }
    }

    // Keep custom claim and user doc in sync.
    await admin.auth().setCustomUserClaims(uid, { role });
    await userRef.update({
      role,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await db.collection('audit_logs').add({
      action:    'role_change',
      actorUid:  callerUid,
      targetUid: uid,
      fromRole:  previousRole ?? null,
      toRole:    role,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Notify the user of their new role (skip no-op reassignments).
    if (role !== previousRole) {
      await createNotification({
        userId: uid,
        type:   'role_change',
        title:  'Votre rôle a changé',
        body:   `Votre rôle est désormais : ${ROLE_LABELS_FR[role] ?? role}.`,
        data:   { role },
      });
    }

    return { uid, role };
  },
);

// ── repairMemberNumbers ───────────────────────────────────────────
// Callable (super_admin only): repairs the matricule (memberNumber) namespace.
//
// Why this exists: matricules are `<regionPrefix>-<6 digits>`, where the number
// is a position drawn from counters/members.count. That sequence stayed unique
// only while the counter moved forward. A past "Sync counters" reset the counter
// to the live member-doc count, moving it *backward* below the highest number
// already issued, so later signups re-used numbers → duplicates. memberNumber is
// write-protected for every client by the Firestore rules, so the fix has to run
// here with the Admin SDK.
//
// What it does (idempotent): keeps the OLDEST holder of each number, reassigns
// anyone with an empty/unparseable or duplicate matricule a fresh number above
// the current high-water mark, then reseeds counters/members.count to that mark
// so future generateMemberNumber() calls never collide again.

const REGION_MEMBER_PREFIXES: Record<string, string> = {
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
const MEMBER_PREFIX_FALLBACK = 'Cmr';

/**
 * On a member's first confirmed contribution, issues their matricule and flips
 * their status to 'active'. Self-signup members are created with an empty
 * memberNumber and 'inactive' status; this is where they get activated.
 *
 * No-op when the member already has a memberNumber (so it never re-issues for
 * members onboarded by a focal officer, nor on later contributions). Runs in a
 * single transaction over the user doc + counters/members so two contributions
 * confirmed at nearly the same time can't double-issue a number.
 */
async function assignMatriculeOnFirstContribution(
  memberId: string,
  region: string,
): Promise<string> {
  if (!memberId) return '';
  return db.runTransaction(async (tx) => {
    const userRef  = db.collection(COL_USERS).doc(memberId);
    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) return '';

    const existing = ((userSnap.data()?.memberNumber as string) ?? '').trim();
    if (existing !== '') return existing; // already has a matricule

    const counterRef  = db.collection('counters').doc('members');
    const counterSnap = await tx.get(counterRef);
    const next   = ((counterSnap.data()?.count as number) ?? 0) + 1;
    const prefix = REGION_MEMBER_PREFIXES[region] ?? MEMBER_PREFIX_FALLBACK;
    const matricule = `${prefix}-${String(next).padStart(6, '0')}`;

    tx.set(counterRef, { count: next }, { merge: true });
    tx.update(userRef, {
      memberNumber: matricule,
      status:       'active',
      updatedAt:    admin.firestore.FieldValue.serverTimestamp(),
    });
    return matricule;
  });
}

// Extracts the numeric sequence from a matricule like "Yde-000012" → 12.
// Returns NaN when the string has no usable digits.
function parseMatriculeSeq(raw: string): number {
  if (!raw) return NaN;
  const tail = raw.includes('-') ? raw.slice(raw.indexOf('-') + 1) : raw;
  const digits = tail.replace(/[^0-9]/g, '');
  return digits === '' ? NaN : parseInt(digits, 10);
}

export const repairMemberNumbers = onCall(
  { region: 'europe-west1' },
  async (request) => {
    const callerUid = await assertSuperAdmin(request);

    const usersSnap = await db.collection(COL_USERS).get();

    // Oldest first, so the earliest holder of a number keeps it.
    const users = usersSnap.docs.slice().sort((a, b) => {
      const ta = (a.data().createdAt as admin.firestore.Timestamp | undefined)?.toMillis() ?? 0;
      const tb = (b.data().createdAt as admin.firestore.Timestamp | undefined)?.toMillis() ?? 0;
      return ta - tb;
    });

    // High-water mark across every parseable number currently in use.
    let maxSeq = 0;
    for (const doc of users) {
      const seq = parseMatriculeSeq((doc.data().memberNumber as string) ?? '');
      if (!Number.isNaN(seq) && seq > maxSeq) maxSeq = seq;
    }

    const claimed = new Set<number>();
    const changes: { id: string; from: string; to: string }[] = [];

    for (const doc of users) {
      const region = (doc.data().region as string) ?? '';
      const current = ((doc.data().memberNumber as string) ?? '').trim();
      const seq = parseMatriculeSeq(current);

      // Members only earn a matricule once their first contribution is confirmed
      // (status flips to 'active'); staff always have one. A legitimately-empty,
      // not-yet-active member must be left alone — issuing a number here would
      // wrongly "activate" them before they have paid.
      const status = (doc.data().status as string) ?? 'inactive';
      const userRole = (doc.data().role as string) ?? 'member';
      const isStaff = userRole === 'focal' || userRole === 'admin' ||
                      userRole === 'super_admin';
      const shouldHaveMatricule = isStaff || status === 'active';
      if (current === '' && !shouldHaveMatricule) continue;

      const needsNew = current === '' || Number.isNaN(seq) || claimed.has(seq);
      if (!needsNew) {
        claimed.add(seq);
        continue;
      }

      const prefix = REGION_MEMBER_PREFIXES[region] ?? MEMBER_PREFIX_FALLBACK;
      maxSeq += 1;
      claimed.add(maxSeq);
      const next = `${prefix}-${String(maxSeq).padStart(6, '0')}`;
      changes.push({ id: doc.id, from: current, to: next });
    }

    // Apply reassignments in chunks (Firestore batches cap at 500 writes).
    for (let i = 0; i < changes.length; i += 450) {
      const batch = db.batch();
      for (const c of changes.slice(i, i + 450)) {
        batch.update(db.collection(COL_USERS).doc(c.id), {
          memberNumber: c.to,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    // Reseed the sequence to the high-water mark so the next issued matricule
    // (maxSeq + 1) is guaranteed unused.
    await db.collection('counters').doc('members').set(
      { count: maxSeq },
      { merge: true },
    );

    await db.collection('audit_logs').add({
      action:    'matricule_repair',
      actorUid:  callerUid,
      scanned:   users.length,
      repaired:  changes.length,
      counter:   maxSeq,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { scanned: users.length, repaired: changes.length, counter: maxSeq };
  },
);

// ── validateFocalReport ───────────────────────────────────────────
// Callable (super_admin only): accepting a focal report confirms ALL of its
// still-pending cash contributions in one action. Each confirmation triggers
// onContributionConfirmed, which credits the regional wallet. Mirrors the
// per-payment dual-validation effects (member totals + platform counter).

const COL_FOCAL_REPORTS = 'focal_reports';

interface FocalReportActionRequest {
  reportId: string;
  reason?:  string;
}

export const validateFocalReport = onCall<FocalReportActionRequest>(
  { region: 'europe-west1' },
  async (request) => {
    const callerUid = await assertSuperAdmin(request);

    const { reportId } = request.data;
    if (!reportId) {
      throw new HttpsError('invalid-argument', 'reportId is required.');
    }

    const reportRef = db.collection(COL_FOCAL_REPORTS).doc(reportId);
    const reportSnap = await reportRef.get();
    if (!reportSnap.exists) {
      throw new HttpsError('not-found', `Report ${reportId} not found.`);
    }
    if (reportSnap.data()?.status === 'validated') {
      throw new HttpsError('failed-precondition', 'Report already validated.');
    }

    // Linked contributions still awaiting confirmation. Query by focalReportId
    // (single-field, auto-indexed) and filter status in code to avoid a
    // composite index.
    const linkedSnap = await db
      .collection(COL_CONTRIBUTIONS)
      .where('focalReportId', '==', reportId)
      .get();
    const pending = linkedSnap.docs.filter(
      (d) => d.data().status === 'pending',
    );

    const now = admin.firestore.FieldValue.serverTimestamp();
    const memberIncrements = new Map<string, number>();
    let total = 0;

    // Chunk writes to stay under the 500-op batch limit.
    const CHUNK = 200;
    for (let i = 0; i < pending.length; i += CHUNK) {
      const batch = db.batch();
      for (const doc of pending.slice(i, i + CHUNK)) {
        const data = doc.data();
        const amount = (data.amount as number) ?? 0;
        const memberId = (data.memberId as string) ?? '';
        batch.update(doc.ref, {
          status: 'confirmed',
          confirmedAt: now,
          validatedBy: callerUid,
          secondValidatorId: callerUid,
        });
        total += amount;
        if (memberId && amount > 0) {
          memberIncrements.set(
            memberId,
            (memberIncrements.get(memberId) ?? 0) + amount,
          );
        }
      }
      await batch.commit();
    }

    // Member totals + platform counter (separate pass; small cardinality).
    const totalsBatch = db.batch();
    for (const [memberId, amount] of memberIncrements) {
      totalsBatch.update(db.collection(COL_USERS).doc(memberId), {
        totalContributed: admin.firestore.FieldValue.increment(amount),
      });
    }
    if (total > 0) {
      totalsBatch.set(
        db.collection('counters').doc('platform'),
        { totalContributed: admin.firestore.FieldValue.increment(total) },
        { merge: true },
      );
    }
    totalsBatch.update(reportRef, {
      status: 'validated',
      validatedBy: callerUid,
    });
    await totalsBatch.commit();

    await db.collection('audit_logs').add({
      action:    'focal_report_validated',
      actorUid:  callerUid,
      reportId,
      confirmed: pending.length,
      total,
      createdAt: now,
    });

    // Notify the focal officer that their report was accepted. The members
    // whose contributions were confirmed are notified automatically via
    // onContributionConfirmed (status flipped to confirmed above).
    await createNotification({
      userId: (reportSnap.data()?.focalId as string) ?? '',
      type:   'focal_report',
      title:  'Rapport validé',
      body:   `Votre rapport de session a été validé. ${pending.length} contribution(s) confirmée(s).`,
      data:   { reportId },
    });

    return { confirmed: pending.length, total };
  },
);

// ── rejectFocalReport ─────────────────────────────────────────────
// Callable (super_admin only): rejects a report and fails its still-pending
// contributions so they leave the pending queue (no wallet credit).

export const rejectFocalReport = onCall<FocalReportActionRequest>(
  { region: 'europe-west1' },
  async (request) => {
    const callerUid = await assertSuperAdmin(request);

    const { reportId, reason } = request.data;
    if (!reportId) {
      throw new HttpsError('invalid-argument', 'reportId is required.');
    }

    const reportRef = db.collection(COL_FOCAL_REPORTS).doc(reportId);
    const reportSnap = await reportRef.get();
    if (!reportSnap.exists) {
      throw new HttpsError('not-found', `Report ${reportId} not found.`);
    }

    const linkedSnap = await db
      .collection(COL_CONTRIBUTIONS)
      .where('focalReportId', '==', reportId)
      .get();
    const pending = linkedSnap.docs.filter(
      (d) => d.data().status === 'pending',
    );

    const now = admin.firestore.FieldValue.serverTimestamp();
    const CHUNK = 400;
    for (let i = 0; i < pending.length; i += CHUNK) {
      const batch = db.batch();
      for (const doc of pending.slice(i, i + CHUNK)) {
        batch.update(doc.ref, {
          status: 'failed',
          notes: reason ?? null,
        });
      }
      await batch.commit();
    }

    await reportRef.update({
      status: 'rejected',
      validatedBy: callerUid,
      notes: reason ?? null,
    });

    await db.collection('audit_logs').add({
      action:   'focal_report_rejected',
      actorUid: callerUid,
      reportId,
      failed:   pending.length,
      createdAt: now,
    });

    // Notify the focal officer that their report was rejected.
    await createNotification({
      userId: (reportSnap.data()?.focalId as string) ?? '',
      type:   'focal_report',
      title:  'Rapport rejeté',
      body:   `Votre rapport de session a été rejeté.` + (reason ? ` Motif : ${reason}` : ''),
      data:   { reportId, reason: reason ?? '' },
    });

    return { failed: pending.length };
  },
);

// ── onFocalReportSubmitted ────────────────────────────────────────
// When a focal officer submits a report (status draft → submitted), notify
// every admin / super_admin so they can review it. Each notification doc is
// turned into an FCM push by onNotificationCreate.

export const onFocalReportSubmitted = onDocumentWritten(
  { document: `${COL_FOCAL_REPORTS}/{reportId}`, region: 'europe-west1' },
  async (event) => {
    const before = event.data?.before.data();
    const after  = event.data?.after.data();
    if (!after) return;

    const becameSubmitted =
      before?.status !== 'submitted' && after.status === 'submitted';
    if (!becameSubmitted) return;

    const reportId  = event.params.reportId;
    const focalName = (after.focalName as string) ?? '';
    const location  = (after.location as string) ?? '';
    const total     = (after.totalCollected as number) ?? 0;
    const members   = (after.membersServed as number) ?? 0;

    const admins = await db
      .collection(COL_USERS)
      .where('role', 'in', ['admin', 'super_admin'])
      .get();

    await Promise.all(
      admins.docs.map((doc) =>
        createNotification({
          userId: doc.id,
          type:   'focal_report',
          title:  'Nouveau rapport de session',
          body:   `${focalName} a soumis un rapport${location ? ` (${location})` : ''} : ` +
                  `${members} membre(s), ${formatFcfa(total)}.`,
          data:   { reportId },
        }),
      ),
    );
  },
);

// ── 4. seedRegionWallets ──────────────────────────────────────────
// Callable (super_admin only): idempotently creates one wallet_account per
// Cameroon region (+ an "Autres" catch-all) and sets the region → accountId map
// (wallet_config/region_account_map). Confirmed contributions are routed to the
// wallet for their region, so each wallet's ledger holds every contribution
// collected in that region and starts at 0 until money arrives. Reused wallets
// are un-archived; any other active account (e.g. legacy payment-method wallets)
// is archived so the accounts list shows only the region wallets. Wallets are
// keyed by the `region` field — safe to call multiple times.

export const seedRegionWallets = onCall(
  { region: 'europe-west1' },
  async (request) => {
    const uid = await assertSuperAdmin(request);
    const now = admin.firestore.FieldValue.serverTimestamp();
    const regionMap: Record<string, string> = {};
    const keepIds = new Set<string>();
    let created = 0;
    let reused  = 0;

    for (const w of REGION_WALLETS) {
      const existing = await db
        .collection(COL_ACCOUNTS)
        .where('region', '==', w.region)
        .limit(1)
        .get();

      let accountId: string;
      if (!existing.empty) {
        accountId = existing.docs[0].id;
        // Re-activate a previously-archived region wallet and refresh its label.
        await existing.docs[0].ref.update({
          archived: false,
          name: w.name,
          type: 'other',
          color: w.color,
          method: null,
          updated_at: now,
        });
        reused++;
      } else {
        const ref = await db.collection(COL_ACCOUNTS).add({
          name:            w.name,
          type:            'other',
          method:          null,
          currency:        'XAF',
          opening_balance: 0,
          current_balance: 0,
          color:           w.color,
          region:          w.region,
          archived:        false,
          created_by:      uid,
          created_at:      now,
          updated_at:      now,
        });
        accountId = ref.id;
        created++;
      }

      regionMap[w.region] = accountId;
      keepIds.add(accountId);
    }

    // Overwrite the routing map with region → account (drops legacy method keys).
    await db.collection(COL_CONFIG).doc(DOC_REGION_MAP).set(regionMap);

    // Archive every other active account (legacy payment-method wallets / other)
    // so only the region wallets remain in the accounts list.
    let archived = 0;
    const allAccounts = await db.collection(COL_ACCOUNTS).get();
    for (const acc of allAccounts.docs) {
      if (keepIds.has(acc.id)) continue;
      if (acc.data().archived === true) continue;
      await acc.ref.update({ archived: true, updated_at: now });
      archived++;
    }

    // Trigger a summary rebuild
    await rebuildSummary();

    return { created, reused, archived, regions: Object.keys(regionMap).length };
  },
);

// ── 5. backfillConfirmedContributions ─────────────────────────
// Callable (super_admin only): reconciles wallet inflows with confirmed
// contributions, routing each to its REGION wallet. To guarantee the region
// wallets equal the sum of confirmed contributions (and to migrate data created
// under the old payment-method routing), it deletes every existing
// contribution-linked wallet_transaction and recreates them by region. Manual
// treasury entries (transfers / adjustments, which have no contribution_id) are
// left untouched.

export const backfillConfirmedContributions = onCall(
  { region: 'europe-west1' },
  async (request) => {
    await assertSuperAdmin(request);

    // Load region → account map once
    const mapDoc = await db.collection(COL_CONFIG).doc(DOC_REGION_MAP).get();
    const regionMap = (mapDoc.data() ?? {}) as Record<string, string>;

    if (Object.keys(regionMap).length === 0) {
      throw new HttpsError(
        'failed-precondition',
        'Region wallet map is empty. Initialize wallets first.',
      );
    }

    // memberId → region, from a single users read — used to route each
    // contribution the same way the live trigger does.
    const usersSnap = await db.collection(COL_USERS).get();
    const regionByMember = new Map<string, string>();
    for (const u of usersSnap.docs) {
      const region = (u.data().region as string) ?? '';
      if (region) regionByMember.set(u.id, region);
    }

    // Delete all auto-generated contribution-linked transactions so they can be
    // recreated on the correct region wallet (drops any left on archived
    // method wallets). Chunked to stay under the 500-op batch limit.
    const existingTxSnap = await db
      .collection(COL_TRANSACTIONS)
      .where('contribution_id', '!=', null)
      .get();
    for (let i = 0; i < existingTxSnap.docs.length; i += 450) {
      const batch = db.batch();
      for (const doc of existingTxSnap.docs.slice(i, i + 450)) {
        batch.delete(doc.ref);
      }
      await batch.commit();
    }

    // Fetch all confirmed contributions
    const confirmedSnap = await db
      .collection(COL_CONTRIBUTIONS)
      .where('status', '==', 'confirmed')
      .get();

    let created = 0;
    const skipped = 0;
    let failed  = 0;

    // Recompute the CMCDA-collected pawaPay balance counter from scratch, per
    // environment. Legacy pawaPay deposits without a stored environment are
    // treated as production.
    const ppCollected: Record<string, number> = { production: 0, sandbox: 0 };

    for (const contrib of confirmedSnap.docs) {
      const contribId = contrib.id;

      const d        = contrib.data();
      const memberId = (d.memberId as string) ?? '';
      const amount   = (d.amount   as number) ?? 0;

      // Tally pawaPay-collected amounts (mobile-money deposits routed through
      // pawaPay carry a depositId).
      const method = (d.paymentMethod as string) ?? '';
      const isPawaPay =
        method === 'mtn_momo' || method === 'orange_money' || !!d.depositId;
      if (isPawaPay) {
        const e = (d.pawaPayEnvironment as string) === 'sandbox'
          ? 'sandbox'
          : 'production';
        ppCollected[e] += amount;
      }

      // Route to the region wallet: member's region → recorder's → Autres.
      const region =
        regionByMember.get(memberId) ||
        regionByMember.get((d.recordedBy as string) ?? '') ||
        OTHER_REGION;
      const accountId = regionMap[region] ?? null;
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
        created_by:        memberId || (d.recordedBy as string) || 'system',
        created_at:        admin.firestore.FieldValue.serverTimestamp(),
      });

      created++;
    }

    // Sum completed payouts per environment, then overwrite the pawaPay counter.
    const ppWithdrawn: Record<string, number> = { production: 0, sandbox: 0 };
    const payoutsSnap = await db
      .collection('payouts')
      .where('status', '==', 'COMPLETED')
      .get();
    for (const p of payoutsSnap.docs) {
      const pd = p.data();
      const e = (pd.environment as string) === 'sandbox'
        ? 'sandbox'
        : 'production';
      ppWithdrawn[e] += (pd.amount as number) ?? 0;
    }
    await db.collection('counters').doc('pawapay').set({
      collected_production: ppCollected.production,
      collected_sandbox: ppCollected.sandbox,
      withdrawn_production: ppWithdrawn.production,
      withdrawn_sandbox: ppWithdrawn.sandbox,
    }, { merge: true });

    // Rebuild summary once at the end (always — txs may have been deleted even
    // when nothing new was created).
    await rebuildSummary();

    return { created, skipped, failed, total: confirmedSnap.size };
  },
);

// ── backfillRegionTotals ──────────────────────────────────────────
// Callable (super_admin only): recomputes wallet_config/region_totals by
// summing every confirmed contribution into its region. Mirrors the live
// onContributionConfirmed routing exactly: member's region → recorder's region
// → OTHER_REGION bucket, so the recomputed total equals the gross collected.
// Idempotent — overwrites the doc with the freshly computed map.

export const backfillRegionTotals = onCall(
  { region: 'europe-west1' },
  async (request) => {
    await assertSuperAdmin(request);

    // memberId → region, from a single users read.
    const usersSnap = await db.collection(COL_USERS).get();
    const regionByMember = new Map<string, string>();
    for (const u of usersSnap.docs) {
      const region = (u.data().region as string) ?? '';
      if (region) regionByMember.set(u.id, region);
    }

    const confirmedSnap = await db
      .collection(COL_CONTRIBUTIONS)
      .where('status', '==', 'confirmed')
      .get();

    const totals: Record<string, number> = {};
    let total = 0;
    for (const c of confirmedSnap.docs) {
      const d = c.data();
      // member's region → recorder's region → Autres (the regionByMember map
      // covers recorders too, since they are users with regions).
      const region =
        regionByMember.get((d.memberId as string) ?? '') ||
        regionByMember.get((d.recordedBy as string) ?? '') ||
        OTHER_REGION;
      const amount = (d.amount as number) ?? 0;
      totals[region] = (totals[region] ?? 0) + amount;
      total += amount;
    }

    await db.collection(COL_CONFIG).doc(DOC_REGION_TOTALS).set({
      ...totals,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { regions: Object.keys(totals).length, total };
  },
);

// ── onUserWelcome ─────────────────────────────────────────────────
// Sends a one-time welcome notification once a user has a usable profile
// (region filled). Email/password signups arrive complete at creation;
// Google sign-in creates a minimal profile (empty region) first and completes
// it on onboarding (an update). A single onDocumentWritten trigger covers both,
// guarded by a `welcomedAt` marker so the welcome fires exactly once.

export const onUserWelcome = onDocumentWritten(
  { document: `${COL_USERS}/{uid}`, region: 'europe-west1' },
  async (event) => {
    const before = event.data?.before?.data() ?? {};
    const after  = event.data?.after.data();
    if (!after) return; // deletion

    // Only fire when region is set for the first time (empty → non-empty).
    // This prevents retriggering on subsequent profile edits or FCM token saves.
    const regionJustSet = !before.region && !!after.region;
    if (!regionJustSet) return;

    // Atomic check-and-set: prevents duplicate welcomes when Cloud Functions
    // delivers the same event more than once (at-least-once semantics).
    let shouldWelcome = false;
    await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(event.data!.after.ref);
      if (snap.data()?.welcomedAt) return;
      tx.update(event.data!.after.ref, {
        welcomedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      shouldWelcome = true;
    });
    if (!shouldWelcome) return;

    await createNotification({
      userId: event.params.uid,
      type:   'welcome',
      title:  'Bienvenue dans la CMCDA',
      body:   `Bienvenue ${(after.firstName as string) ?? ''} ! Votre adhésion a été enregistrée avec succès.`,
    });
  },
);

// ── 6. onNotificationCreate ───────────────────────────────────────
// Triggers when a new doc is created in the `notifications` collection.
// Reads the target user's FCM tokens from Firestore and pushes to every
// registered device, pruning any tokens FCM reports as unregistered.

// Reads the multi-device token array, falling back to the legacy single
// `fcmToken` string for user docs written before the array migration.
function readTokens(userData: admin.firestore.DocumentData | undefined): string[] {
  const raw = userData?.fcmTokens;
  if (Array.isArray(raw)) {
    return raw.filter((t): t is string => typeof t === 'string' && t.length > 0);
  }
  const legacy = userData?.fcmToken;
  return typeof legacy === 'string' && legacy.length > 0 ? [legacy] : [];
}

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

    const userRef = db.collection(COL_USERS).doc(userId);
    const tokens  = readTokens((await userRef.get()).data());

    if (tokens.length === 0) {
      console.log(`[onNotificationCreate] No FCM tokens for user ${userId}, skipping push.`);
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
      const res = await admin.messaging().sendEachForMulticast({
        tokens,
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

      // Prune tokens FCM reports as permanently invalid so dead devices stop
      // being retried (and the array doesn't grow unbounded).
      const stale: string[] = [];
      res.responses.forEach((r, i) => {
        const code = r.error?.code;
        if (code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token' ||
            code === 'messaging/invalid-argument') {
          stale.push(tokens[i]);
        }
      });
      if (stale.length > 0) {
        await userRef.update({
          fcmTokens: admin.firestore.FieldValue.arrayRemove(...stale),
        });
      }

      console.log(
        `[onNotificationCreate] user ${userId}: success=${res.successCount} ` +
        `failure=${res.failureCount} pruned=${stale.length}.`,
      );
    } catch (err) {
      console.error(`[onNotificationCreate] Failed for user ${userId}:`, err);
    }
  },
);

// ── 7. sendContributionReminders ──────────────────────────────────
// Scheduled daily. Walks every active reminder plan whose nextReminderAt is
// due, and — unless the member already reached the annual target this calendar
// year — creates a payment_reminder notification (which onNotificationCreate
// turns into an FCM push) and advances nextReminderAt by the plan's cadence.

function addDays(d: Date, n: number): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n,
    d.getHours(), d.getMinutes(), d.getSeconds());
}
function addMonths(d: Date, n: number): Date {
  return new Date(d.getFullYear(), d.getMonth() + n, d.getDate(),
    d.getHours(), d.getMinutes(), d.getSeconds());
}
function addYears(d: Date, n: number): Date {
  return new Date(d.getFullYear() + n, d.getMonth(), d.getDate(),
    d.getHours(), d.getMinutes(), d.getSeconds());
}
function nextCadence(from: Date, frequency: string): Date {
  switch (frequency) {
    case 'daily':  return addDays(from, 1);
    case 'weekly': return addDays(from, 7);
    case 'annual': return addYears(from, 1);
    case 'monthly':
    default:       return addMonths(from, 1);
  }
}

export const sendContributionReminders = onSchedule(
  { schedule: 'every day 09:00', timeZone: 'Africa/Douala', region: 'europe-west1' },
  async () => {
    const now = new Date();
    const nowTs = admin.firestore.Timestamp.fromDate(now);
    const startOfYear = new Date(now.getFullYear(), 0, 1);
    const startOfNextYear = new Date(now.getFullYear() + 1, 0, 1);

    const dueSnap = await db
      .collection(COL_REMINDER_PLANS)
      .where('active', '==', true)
      .where('nextReminderAt', '<=', nowTs)
      .get();

    let sent = 0;
    let skipped = 0;

    for (const planDoc of dueSnap.docs) {
      const plan = planDoc.data();
      const memberId = (plan.memberId as string) ?? planDoc.id;
      const frequency = (plan.frequency as string) ?? 'monthly';

      // Member must exist and be active
      const userDoc = await db.collection(COL_USERS).doc(memberId).get();
      if (!userDoc.exists || userDoc.data()?.status !== 'active') {
        skipped++;
        continue;
      }

      // Confirmed contributions for the current calendar year
      const contribSnap = await db
        .collection(COL_CONTRIBUTIONS)
        .where('memberId', '==', memberId)
        .where('status', '==', 'confirmed')
        .get();

      let yearTotal = 0;
      for (const c of contribSnap.docs) {
        const cd = c.data();
        const ts = (cd.confirmedAt ?? cd.createdAt) as admin.firestore.Timestamp | undefined;
        if (!ts) continue;
        const date = ts.toDate();
        if (date >= startOfYear && date < startOfNextYear) {
          yearTotal += (cd.amount as number) ?? 0;
        }
      }

      // Target reached — pause until next year
      if (yearTotal >= ANNUAL_TARGET) {
        await planDoc.ref.update({
          nextReminderAt: admin.firestore.Timestamp.fromDate(startOfNextYear),
          updatedAt: nowTs,
        });
        skipped++;
        continue;
      }

      const amount = (plan.amount as number) ?? CADENCE_AMOUNT[frequency] ?? CADENCE_AMOUNT.monthly;

      await db.collection(COL_NOTIFICATIONS).add({
        userId: memberId,
        type: 'payment_reminder',
        title: 'Rappel de contribution',
        body: `Rappel : pensez à verser votre contribution de ${amount.toLocaleString('fr-FR')} FCFA.`,
        read: false,
        data: { frequency, amount: String(amount) },
        createdAt: nowTs,
      });

      await planDoc.ref.update({
        lastReminderAt: nowTs,
        nextReminderAt: admin.firestore.Timestamp.fromDate(nextCadence(now, frequency)),
        updatedAt: nowTs,
      });
      sent++;
    }

    console.log(`[sendContributionReminders] sent=${sent} skipped=${skipped} due=${dueSnap.size}`);
  },
);

// ═══════════════════════════════════════════════════════════════════
// pawaPay mobile-money gateway (MTN + Orange Cameroon, currency XAF)
// ═══════════════════════════════════════════════════════════════════
//
// The pawaPay API token is secret, so EVERY pawaPay HTTP call lives here —
// never on the client. Deposits are async (push-USSD): we initiate a deposit,
// the customer approves with their Mobile Money PIN on their phone, and the
// payment resolves to COMPLETED/FAILED later via callback (pawaPayWebhook) or
// polling (checkPawaPayDeposit). Contributions are therefore created `pending`
// and flipped to `confirmed` only once the money is actually collected.

// Two tokens are held server-side: the production token and a sandbox token.
// Which one (and which base URL) is used is decided AT CALL TIME from the
// app_config/payment_config.environment field, so a super admin can flip the
// environment from the admin UI without a redeploy. Every pawaPay function must
// therefore declare BOTH secrets in its `secrets:` array.
const PAWAPAY_API_TOKEN = defineSecret('PAWAPAY_API_TOKEN');
const PAWAPAY_SANDBOX_TOKEN = defineSecret('PAWAPAY_SANDBOX_TOKEN');

const PAWAPAY_PROD_BASE = 'https://api.pawapay.io';
const PAWAPAY_SANDBOX_BASE = 'https://api.sandbox.pawapay.io';

const PAWAPAY_PROVIDER_MTN = 'MTN_MOMO_CMR';
const PAWAPAY_PROVIDER_ORANGE = 'ORANGE_CMR';
const PAWAPAY_CURRENCY = 'XAF';

interface PawaPayEnv {
  baseUrl: string;
  token: string;
  environment: string; // 'production' | 'sandbox'
}

// Resolves the active pawaPay environment from Firestore. Defaults to
// 'production' when the config doc/field is missing (the app is live by
// default). Reads on every pawaPay invocation — one extra Firestore get,
// which is negligible next to the outbound HTTP call.
async function resolvePawaPayEnv(): Promise<PawaPayEnv> {
  let environment = 'production';
  try {
    const snap = await db
      .collection('app_config')
      .doc('payment_config')
      .get();
    const env = snap.data()?.environment as string | undefined;
    if (env === 'sandbox') environment = 'sandbox';
  } catch {
    // On any read failure, stay on production rather than silently testing.
    environment = 'production';
  }
  if (environment === 'sandbox') {
    return {
      baseUrl: PAWAPAY_SANDBOX_BASE,
      token: PAWAPAY_SANDBOX_TOKEN.value(),
      environment,
    };
  }
  return {
    baseUrl: PAWAPAY_PROD_BASE,
    token: PAWAPAY_API_TOKEN.value(),
    environment,
  };
}

interface PawaPayResult {
  ok: boolean;
  status: number;
  body: any;
}

// Calls the pawaPay v2 API with the bearer token for the resolved environment.
// Returns parsed JSON + ok flag rather than throwing, so callers can map
// failures to contribution/payout state.
async function pawaPayFetch(
  env: PawaPayEnv,
  path: string,
  method: 'GET' | 'POST',
  body?: unknown,
): Promise<PawaPayResult> {
  const base = env.baseUrl.replace(/\/+$/, '');
  const res = await fetch(`${base}${path}`, {
    method,
    headers: {
      'Authorization': `Bearer ${env.token}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let parsed: any = null;
  try {
    parsed = await res.json();
  } catch {
    parsed = null;
  }
  return { ok: res.ok, status: res.status, body: parsed };
}

// Normalizes a Cameroon number to pawaPay MSISDN form: digits only, 237 prefix,
// no leading +/00. Accepts "+237 6XX...", "06XX...", "6XX...", "237...".
function toMsisdn(raw: string): string {
  let d = (raw || '').replace(/\D/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  if (d.startsWith('237')) return d;
  if (d.startsWith('0')) d = d.slice(1);
  return `237${d}`;
}

function providerToMethod(provider: string): string {
  return provider === PAWAPAY_PROVIDER_MTN ? 'mtn_momo' : 'orange_money';
}

// ISO year-month period, e.g. "2026-05" (matches AppUtils.getPeriodForDate).
function currentPeriod(): string {
  const now = new Date();
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`;
}

// French fallback text per stable failure token. Stored in `notes` so the admin
// queue and older clients always show a readable reason; the client localizes
// the stable token (pawaPayFailureCode) into fr/en/ar via AppLocalizations.
const PP_FAILURE_FR: Record<string, string> = {
  INSUFFICIENT_BALANCE: 'Solde Mobile Money insuffisant',
  PAYMENT_NOT_APPROVED: 'Paiement non approuvé (code PIN non saisi)',
  PAYER_NOT_FOUND: "Ce numéro n'est pas enregistré chez l'opérateur choisi",
  PAYER_LIMIT_REACHED: 'Limite de transaction Mobile Money atteinte',
  PROVIDER_UNAVAILABLE: 'Opérateur momentanément indisponible',
  AMOUNT_OUT_OF_LIMITS: 'Montant en dehors des limites autorisées',
  INVALID_NUMBER: 'Numéro de téléphone invalide',
  TIMEOUT: 'Délai de paiement expiré',
  NOT_ALLOWED: "Paiement Mobile Money non autorisé pour ce compte — contactez l'opérateur",
  GENERIC: 'Paiement échoué',
};

// Normalizes any pawaPay failureCode / rejectionCode into a stable token the
// client can localize, plus a French fallback message. Matching is substring-
// based so new or provider-specific code spellings still bucket sensibly;
// anything unrecognized falls back to GENERIC.
function normalizePawaPayFailure(
  rawCode?: string | null,
  rawMessage?: string | null,
): { code: string; message: string } {
  const c = (rawCode ?? '').toUpperCase();
  let code = 'GENERIC';
  if (c.includes('INSUFFICIENT') || c.includes('BALANCE')) {
    code = 'INSUFFICIENT_BALANCE';
  } else if (c.includes('NOT_APPROVED') || c.includes('APPROVAL') || c.includes('REJECTED_BY_PAYER')) {
    code = 'PAYMENT_NOT_APPROVED';
  } else if (c.includes('PAYER_NOT_FOUND') || c.includes('NOT_FOUND')) {
    code = 'PAYER_NOT_FOUND';
  } else if (c.includes('LIMIT')) {
    code = 'PAYER_LIMIT_REACHED';
  } else if (c.includes('UNAVAILABLE') || c.includes('NOT_AVAILABLE') || c.includes('TEMPORARILY')) {
    code = 'PROVIDER_UNAVAILABLE';
  } else if (c.includes('AMOUNT')) {
    code = 'AMOUNT_OUT_OF_LIMITS';
  } else if (c.includes('INVALID') && (c.includes('PHONE') || c.includes('PAYER') || c.includes('NUMBER') || c.includes('MSISDN'))) {
    code = 'INVALID_NUMBER';
  } else if (c.includes('TIMEOUT') || c.includes('EXPIRED')) {
    code = 'TIMEOUT';
  }
  const message = PP_FAILURE_FR[code] ?? rawMessage ?? PP_FAILURE_FR.GENERIC;
  return { code, message };
}

/**
 * Reconciles a contribution doc with a pawaPay deposit status payload.
 * Idempotent: no-op once the contribution is already confirmed/failed.
 *
 * On COMPLETED we credit users/{id}.totalContributed and
 * counters/platform.totalContributed here, because (unlike the client
 * createContribution auto-confirm path) the doc was created `pending` and the
 * client never credited it. Flipping status → confirmed then triggers
 * onContributionConfirmed for region totals, the wallet inflow tx, and the
 * "payment confirmed" notification. Returns the resulting contribution status.
 */
async function reconcileDeposit(
  contribRef: admin.firestore.DocumentReference,
  payload: { status?: string; failureReason?: any },
): Promise<string> {
  const snap = await contribRef.get();
  if (!snap.exists) return 'failed';
  const data = snap.data()!;
  const current = (data.status as string) ?? 'pending';
  if (current === 'confirmed' || current === 'failed') return current;

  const ppStatus = (payload.status as string) ?? '';

  if (ppStatus === 'COMPLETED') {
    const memberId = (data.memberId as string) ?? '';
    const amount = (data.amount as number) ?? 0;
    if (memberId && amount > 0) {
      await db.collection(COL_USERS).doc(memberId).update({
        totalContributed: admin.firestore.FieldValue.increment(amount),
      });
      await db.collection('counters').doc('platform').set(
        { totalContributed: admin.firestore.FieldValue.increment(amount) },
        { merge: true },
      );
      // CMCDA-collected pawaPay balance (per environment). This — minus
      // completed payouts — is what the withdraw screen shows as available,
      // NOT the whole pawaPay wallet (which may hold other merchants' funds).
      const e = (data.pawaPayEnvironment as string) === 'sandbox'
        ? 'sandbox'
        : 'production';
      await db.collection('counters').doc('pawapay').set(
        { [`collected_${e}`]: admin.firestore.FieldValue.increment(amount) },
        { merge: true },
      );
    }
    await contribRef.update({
      status: 'confirmed',
      confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
      pawaPayStatus: ppStatus,
    });
    return 'confirmed';
  }

  if (ppStatus === 'FAILED') {
    const { code, message } = normalizePawaPayFailure(
      payload.failureReason?.failureCode,
      payload.failureReason?.failureMessage,
    );
    await contribRef.update({
      status: 'failed',
      notes: message,
      pawaPayFailureCode: code,
      pawaPayStatus: ppStatus,
    });
    return 'failed';
  }

  // ACCEPTED / PROCESSING / IN_RECONCILIATION / DUPLICATE_IGNORED — still pending.
  if (ppStatus) await contribRef.update({ pawaPayStatus: ppStatus });
  return 'pending';
}

// ── Webhook signature verification (RFC-9421) ──────────────────────
//
// pawaPay signs HTTP callbacks using ECDSA-P256-SHA256 per RFC-9421.
// The public key is fetched from /v1/signing-keys and cached for 24 h.
// Verification is skipped when the Signature header is absent (sandbox /
// unconfigured). Once signed callbacks are enabled in the pawaPay
// dashboard, any unsigned or tampered request is rejected with 401.

let _ppKeyCache: { pem: string; keyId: string; fetchedAt: number } | null = null;

async function getPpSigningKey(env: PawaPayEnv): Promise<{ pem: string; keyId: string }> {
  const TTL_MS = 24 * 60 * 60 * 1000;
  if (_ppKeyCache && Date.now() - _ppKeyCache.fetchedAt < TTL_MS) {
    return { pem: _ppKeyCache.pem, keyId: _ppKeyCache.keyId };
  }
  const r = await pawaPayFetch(env, '/v1/signing-keys', 'GET');
  if (!r.ok) throw new Error(`Cannot fetch pawaPay signing key (HTTP ${r.status})`);
  const entries: any[] = Array.isArray(r.body) ? r.body : [r.body];
  const entry = entries[0] ?? {};
  const rawKey: string = entry.publicKey ?? '';
  const keyId: string = entry.keyId ?? '';
  if (!rawKey) throw new Error('pawaPay returned an empty signing key');
  // Convert base64-DER to PEM if not already wrapped.
  const pem = rawKey.includes('BEGIN')
    ? rawKey
    : `-----BEGIN PUBLIC KEY-----\n${rawKey.match(/.{1,64}/g)!.join('\n')}\n-----END PUBLIC KEY-----`;
  _ppKeyCache = { pem, keyId, fetchedAt: Date.now() };
  return { pem, keyId };
}

/**
 * Verifies the RFC-9421 HTTP Message Signature on a pawaPay webhook request.
 * No-op when the Signature header is absent (sandbox / pre-production).
 * Throws with a descriptive message on any verification failure.
 */
async function verifyPawaPayWebhookSignature(
  req: import('express').Request,
  rawBody: Buffer,
  env: PawaPayEnv,
): Promise<void> {
  const sigInput = (req.headers['signature-input'] ?? '') as string;
  const sigHeader = (req.headers['signature'] ?? '') as string;
  if (!sigInput || !sigHeader) return; // No signature — sandbox; allow through.

  // 1. Verify Content-Digest (SHA-512 of raw body) if present.
  const contentDigest = (req.headers['content-digest'] ?? '') as string;
  if (contentDigest) {
    const m = contentDigest.match(/sha-512=:([^:]+):/);
    if (m) {
      const expected = createHash('sha512').update(rawBody).digest('base64');
      if (expected !== m[1]) throw new Error('content-digest mismatch');
    }
  }

  // 2. Parse Signature-Input: sig1=("comp1" "comp2"...);param=val;...
  const siMatch = sigInput.match(/^(\w+)=(\(([^)]*)\)((?:;[^;\s]+(?:=[^\s;]+)?)*))/);
  if (!siMatch) throw new Error('Malformed Signature-Input header');
  const sigLabel = siMatch[1];
  const sigParamsStr = siMatch[2]; // full value after label=, used in @signature-params line
  const compsRaw = siMatch[3];
  const components: string[] = [...compsRaw.matchAll(/"([^"]+)"/g)].map((x) => x[1]);

  // 3. Extract signature bytes for this label. Format: sig1=:base64:
  const sigValMatch = sigHeader.match(new RegExp(`(?:^|,\\s*)${sigLabel}=:([^:]+):`));
  if (!sigValMatch) throw new Error(`Signature label "${sigLabel}" not found in Signature header`);
  const sigBytes = Buffer.from(sigValMatch[1], 'base64');

  // 4. Reconstruct the signature base (RFC-9421 §3.3).
  const reqUrl = new URL(req.url, `https://${req.headers.host ?? 'cloudfunctions.net'}`);
  const lines: string[] = [];
  for (const comp of components) {
    switch (comp) {
      case '@method':
        lines.push(`"@method": ${req.method}`);
        break;
      case '@path':
        lines.push(`"@path": ${reqUrl.pathname}`);
        break;
      case '@authority':
        lines.push(`"@authority": ${req.headers.host ?? ''}`);
        break;
      case '@target-uri':
        lines.push(`"@target-uri": ${reqUrl.href}`);
        break;
      case '@request-target':
        lines.push(`"@request-target": ${req.method.toLowerCase()} ${reqUrl.pathname}`);
        break;
      default: {
        const hval = req.headers[comp.toLowerCase()];
        if (hval !== undefined) {
          lines.push(`"${comp}": ${Array.isArray(hval) ? hval.join(', ') : hval}`);
        }
      }
    }
  }
  lines.push(`"@signature-params": ${sigParamsStr}`);
  const sigBase = lines.join('\n');

  // 5. Verify ECDSA-P256-SHA256. Try DER encoding first, then IEEE P1363 fallback.
  const { pem } = await getPpSigningKey(env);
  const tryVerify = (dsaEncoding?: 'ieee-p1363'): boolean => {
    const v = createVerify('SHA256');
    v.update(sigBase, 'utf8');
    return v.verify(
      dsaEncoding ? { key: pem, format: 'pem', dsaEncoding } : { key: pem, format: 'pem' },
      sigBytes,
    );
  };
  const valid = tryVerify() || tryVerify('ieee-p1363');
  if (!valid) throw new Error('pawaPay webhook signature is invalid');
}

// ── initiatePawaPayDeposit ─────────────────────────────────────────
// Callable: { amount, periodType, phoneNumber, provider }
// Creates the contribution (pending) and initiates the pawaPay deposit.

interface InitiateDepositRequest {
  amount: number;
  periodType: string;
  phoneNumber: string;
  provider: string;
  // Optional: staff (focal/admin) charging a member's MoMo on their behalf.
  // When omitted (or equal to the caller), the deposit is for the caller.
  memberId?: string;
}

export const initiatePawaPayDeposit = onCall<InitiateDepositRequest>(
  { region: 'europe-west1', secrets: [PAWAPAY_API_TOKEN, PAWAPAY_SANDBOX_TOKEN] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    const callerUid = request.auth.uid;
    const { amount, periodType, phoneNumber, provider, memberId: targetMemberId } =
      request.data;

    if (!Number.isInteger(amount) || amount <= 0) {
      throw new HttpsError('invalid-argument', 'amount must be a positive integer.');
    }
    if (provider !== PAWAPAY_PROVIDER_MTN && provider !== PAWAPAY_PROVIDER_ORANGE) {
      throw new HttpsError('invalid-argument', `Unsupported provider: ${provider}.`);
    }
    const msisdn = toMsisdn(phoneNumber);
    if (msisdn.length < 11) {
      throw new HttpsError('invalid-argument', 'Invalid phone number.');
    }

    // Resolve who the contribution is for. A staff member (focal/admin) may
    // charge another member's MoMo on their behalf; everyone else can only
    // pay for themselves. recordedBy always stays the caller for the audit trail.
    let memberId = callerUid;
    if (targetMemberId && targetMemberId !== callerUid) {
      const callerSnap = await db.collection(COL_USERS).doc(callerUid).get();
      const callerRole = (callerSnap.data()?.role as string) ?? 'member';
      const isStaff = ['focal', 'admin', 'super_admin'].includes(callerRole);
      if (!isStaff) {
        throw new HttpsError(
          'permission-denied',
          'Only staff can record a payment for another member.',
        );
      }
      memberId = targetMemberId;
    }

    const userSnap = await db.collection(COL_USERS).doc(memberId).get();
    if (!userSnap.exists) {
      throw new HttpsError('not-found', 'User profile not found.');
    }
    const user = userSnap.data()!;
    if ((user.status as string) === 'suspended') {
      throw new HttpsError('permission-denied', 'Account suspended.');
    }

    const env = await resolvePawaPayEnv();
    const depositId = uuidv4();
    const contribRef = db.collection(COL_CONTRIBUTIONS).doc();

    await contribRef.set({
      memberId,
      memberName: (user.fullName as string) ?? '',
      memberNumber: (user.memberNumber as string) ?? '',
      amount,
      period: currentPeriod(),
      periodType: periodType || 'monthly',
      paymentMethod: providerToMethod(provider),
      status: 'pending',
      receiptNumber: '',
      recordedBy: callerUid,
      validationRequired: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      depositId,
      pawaPayStatus: 'ACCEPTED',
      pawaPayProvider: provider,
      // Which gateway environment this deposit ran against — so the
      // CMCDA-collected balance counter never mixes sandbox with live money.
      pawaPayEnvironment: env.environment,
      payerPhone: msisdn,
    });

    const result = await pawaPayFetch(env, '/v2/deposits', 'POST', {
      depositId,
      amount: String(amount),
      currency: PAWAPAY_CURRENCY,
      payer: {
        type: 'MMO',
        accountDetails: { phoneNumber: msisdn, provider },
      },
    });

    if (!result.ok) {
      const rawCode =
        result.body?.failureReason?.failureCode ??
        result.body?.rejectionReason?.rejectionCode ??
        result.body?.rejectionReason?.failureCode;
      const rawMsg =
        result.body?.message ??
        result.body?.failureReason?.failureMessage ??
        result.body?.rejectionReason?.rejectionMessage;
      const { code, message } = normalizePawaPayFailure(rawCode, rawMsg);
      await contribRef.update({
        status: 'failed',
        notes: message,
        pawaPayFailureCode: code,
        pawaPayStatus: 'FAILED',
      });
      // Surface the stable token in details so the client localizes it.
      throw new HttpsError(
        'internal',
        `Deposit initiation failed: ${rawMsg ?? rawCode ?? result.status}`,
        { failureCode: code },
      );
    }

    return {
      contributionId: contribRef.id,
      depositId,
      status: (result.body?.status as string) ?? 'ACCEPTED',
    };
  },
);

// ── pawaPayWebhook ─────────────────────────────────────────────────
// HTTP endpoint pawaPay POSTs deposit status updates to. Configure this
// function's deployed URL as the callback URL in the pawaPay dashboard.
//
// Signature verification (RFC-9421, ECDSA-P256) is enforced by
// verifyPawaPayWebhookSignature below. It is a no-op only when the Signature
// header is absent (sandbox). PRODUCTION: enable signed callbacks in the
// pawaPay dashboard so every request carries a signature — otherwise a forged
// unsigned body would be accepted.

export const pawaPayWebhook = onRequest(
  { region: 'europe-west1', secrets: [PAWAPAY_API_TOKEN, PAWAPAY_SANDBOX_TOKEN] },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    // Verify RFC-9421 signature when pawaPay sends signed callbacks.
    // Skipped silently in sandbox where the header is absent.
    const rawBody: Buffer =
      (req as any).rawBody ?? Buffer.from(JSON.stringify(req.body ?? {}), 'utf8');
    try {
      const env = await resolvePawaPayEnv();
      await verifyPawaPayWebhookSignature(req, rawBody, env);
    } catch (e) {
      console.warn('[pawaPayWebhook] signature rejected:', (e as Error).message);
      res.status(401).send('Invalid signature');
      return;
    }

    const payload = req.body ?? {};
    const depositId = payload.depositId as string | undefined;
    if (!depositId) {
      res.status(400).send('Missing depositId');
      return;
    }

    try {
      const q = await db
        .collection(COL_CONTRIBUTIONS)
        .where('depositId', '==', depositId)
        .limit(1)
        .get();
      if (q.empty) {
        console.warn(`[pawaPayWebhook] No contribution for depositId ${depositId}.`);
        res.status(200).send('OK');
        return;
      }
      await reconcileDeposit(q.docs[0].ref, payload);
    } catch (e) {
      console.error('[pawaPayWebhook] reconcile error', e);
    }
    // Always 200 so pawaPay does not retry indefinitely on our internal errors.
    res.status(200).send('OK');
  },
);

// ── checkPawaPayDeposit ────────────────────────────────────────────
// Callable poll fallback: { contributionId }. Fetches the live deposit status
// from pawaPay and reconciles it. Used by the client while waiting if no
// callback has arrived yet (and in sandbox where callbacks may be unconfigured).

interface CheckDepositRequest {
  contributionId: string;
}

export const checkPawaPayDeposit = onCall<CheckDepositRequest>(
  { region: 'europe-west1', secrets: [PAWAPAY_API_TOKEN, PAWAPAY_SANDBOX_TOKEN] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    const { contributionId } = request.data;
    if (!contributionId) {
      throw new HttpsError('invalid-argument', 'contributionId is required.');
    }

    const contribRef = db.collection(COL_CONTRIBUTIONS).doc(contributionId);
    const snap = await contribRef.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Contribution not found.');
    }
    const data = snap.data()!;

    // Owner or staff only.
    const callerSnap = await db.collection(COL_USERS).doc(request.auth.uid).get();
    const callerRole = (callerSnap.data()?.role as string) ?? 'member';
    const isStaff = ['focal', 'admin', 'super_admin'].includes(callerRole);
    if (data.memberId !== request.auth.uid && !isStaff) {
      throw new HttpsError('permission-denied', 'Not allowed.');
    }

    const current = (data.status as string) ?? 'pending';
    if (current === 'confirmed' || current === 'failed') {
      return { status: current };
    }

    const depositId = data.depositId as string | undefined;
    if (!depositId) {
      throw new HttpsError('failed-precondition', 'No depositId on contribution.');
    }

    const env = await resolvePawaPayEnv();
    const result = await pawaPayFetch(env, `/v2/deposits/${depositId}`, 'GET');
    if (!result.ok) {
      throw new HttpsError('internal', `pawaPay status check failed (${result.status}).`);
    }
    // GET /v2/deposits/{id} may return the deposit object directly or wrapped.
    const dep = Array.isArray(result.body)
      ? result.body[0]
      : (result.body?.data ?? result.body);
    const status = await reconcileDeposit(contribRef, dep ?? {});
    return { status };
  },
);

// ── predictPawaPayProvider ─────────────────────────────────────────
// Callable: { phoneNumber } → predicted provider for the MSISDN.

interface PredictProviderRequest {
  phoneNumber: string;
}

export const predictPawaPayProvider = onCall<PredictProviderRequest>(
  { region: 'europe-west1', secrets: [PAWAPAY_API_TOKEN, PAWAPAY_SANDBOX_TOKEN] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    const msisdn = toMsisdn(request.data.phoneNumber ?? '');
    if (msisdn.length < 11) {
      throw new HttpsError('invalid-argument', 'Invalid phone number.');
    }
    const env = await resolvePawaPayEnv();
    const result = await pawaPayFetch(env, '/v2/predict-provider', 'POST', {
      phoneNumber: msisdn,
    });
    if (!result.ok) {
      throw new HttpsError('internal', `Provider prediction failed (${result.status}).`);
    }
    return {
      provider: (result.body?.provider as string) ?? '',
      phoneNumber: (result.body?.phoneNumber as string) ?? msisdn,
      country: (result.body?.country as string) ?? 'CMR',
    };
  },
);

// ── cleanStuckPawaPayDeposits ──────────────────────────────────────
// Runs every 2 hours. Finds mobile-money contributions still `pending`
// after 4 hours (the user ignored the USSD PIN prompt, or no callback
// arrived), fetches the live status from pawaPay, and reconciles.
// Any deposit still unresolved past the cutoff is force-marked `failed`
// so the admin pending queue never accumulates ghost entries.

export const cleanStuckPawaPayDeposits = onSchedule(
  { region: 'europe-west1', schedule: 'every 2 hours', secrets: [PAWAPAY_API_TOKEN, PAWAPAY_SANDBOX_TOKEN] },
  async () => {
    const env = await resolvePawaPayEnv();
    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 4 * 60 * 60 * 1000),
    );

    // Uses the existing (status ASC, createdAt ASC) composite index.
    // Mobile-money deposits are identified in-memory by the presence of depositId,
    // avoiding a multi-field inequality that would need a new index.
    const snap = await db
      .collection(COL_CONTRIBUTIONS)
      .where('status', '==', 'pending')
      .where('createdAt', '<', cutoff)
      .orderBy('createdAt', 'asc')
      .get();

    const mobileMoney = snap.docs.filter((d) => !!(d.data().depositId as string | undefined));
    if (mobileMoney.length === 0) {
      console.log('[cleanStuckPawaPayDeposits] nothing to process');
      return;
    }

    let reconciled = 0;
    let forceFailed = 0;

    await Promise.all(
      mobileMoney.map(async (doc) => {
        const depositId = doc.data().depositId as string;
        try {
          const r = await pawaPayFetch(env, `/v2/deposits/${depositId}`, 'GET');
          if (r.ok) {
            const dep = Array.isArray(r.body)
              ? r.body[0]
              : (r.body?.data ?? r.body);
            const result = await reconcileDeposit(doc.ref, dep ?? {});
            if (result !== 'pending') {
              reconciled++;
              return;
            }
          }
        } catch (e) {
          console.warn(`[cleanStuckPawaPayDeposits] pawaPay fetch error for ${depositId}`, e);
        }

        // Still pending after cutoff (or pawaPay returned an error) — force fail.
        await doc.ref.update({
          status: 'failed',
          notes: 'Délai de paiement expiré',
          pawaPayFailureCode: 'TIMEOUT',
          pawaPayStatus: 'FAILED',
        });
        forceFailed++;
      }),
    );

    console.log(
      `[cleanStuckPawaPayDeposits] scanned=${mobileMoney.length} reconciled=${reconciled} forceFailed=${forceFailed}`,
    );
  },
);

// ═══════════════════════════════════════════════════════════════════
// pawaPay payouts (withdrawals) — super-admin only
// ═══════════════════════════════════════════════════════════════════
//
// A payout disburses money FROM the pawaPay wallet balance (the funds CMCDA
// collected via deposits) TO a Mobile Money number. Like deposits, payouts are
// async: we initiate, pawaPay processes, and the final status arrives later.
// v1 reconciles by polling (checkPawaPayPayout) — the admin withdraw screen
// polls after initiating, mirroring the member deposit flow. The `payouts`
// collection is the source of truth (clients cannot write it; rules block it).

const COL_PAYOUTS = 'payouts';

// Reconciles a payouts doc with a pawaPay payout status payload. Idempotent:
// no-op once COMPLETED/FAILED. Mirrors reconcileDeposit but without crediting
// any totals (payouts move money out, not in).
async function reconcilePayout(
  payoutRef: admin.firestore.DocumentReference,
  payload: { status?: string; failureReason?: any },
): Promise<string> {
  const snap = await payoutRef.get();
  if (!snap.exists) return 'FAILED';
  const pdata = snap.data()!;
  const current = (pdata.status as string) ?? 'ACCEPTED';
  if (current === 'COMPLETED' || current === 'FAILED') return current;

  const ppStatus = (payload.status as string) ?? '';

  if (ppStatus === 'COMPLETED') {
    // Debit the CMCDA-collected balance counter for this environment so the
    // withdraw screen's "available" reflects money already taken out.
    const amount = (pdata.amount as number) ?? 0;
    const e = (pdata.environment as string) === 'sandbox'
      ? 'sandbox'
      : 'production';
    if (amount > 0) {
      await db.collection('counters').doc('pawapay').set(
        { [`withdrawn_${e}`]: admin.firestore.FieldValue.increment(amount) },
        { merge: true },
      );
    }
    await payoutRef.update({
      status: 'COMPLETED',
      pawaPayStatus: ppStatus,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return 'COMPLETED';
  }

  if (ppStatus === 'FAILED' || ppStatus === 'REJECTED') {
    const { code, message } = normalizePawaPayFailure(
      payload.failureReason?.failureCode,
      payload.failureReason?.failureMessage,
    );
    await payoutRef.update({
      status: 'FAILED',
      pawaPayStatus: ppStatus,
      pawaPayFailureCode: code,
      notes: message,
    });
    return 'FAILED';
  }

  // ACCEPTED / ENQUEUED / PROCESSING / IN_RECONCILIATION — still in flight.
  if (ppStatus) await payoutRef.update({ pawaPayStatus: ppStatus });
  return 'PENDING';
}

// ── getPawaPayBalance ──────────────────────────────────────────────
// Callable (super-admin): returns the amount CMCDA has collected through THIS
// app via pawaPay (confirmed deposits) minus what's already been withdrawn —
// NOT the whole pawaPay wallet balance, which may hold funds from other apps
// sharing the same pawaPay account. Tracked per environment in
// counters/pawapay (collected_{env} / withdrawn_{env}), maintained server-side
// by reconcileDeposit / reconcilePayout. The live pawaPay wallet balance is
// still returned as `walletBalance` for reference (it caps what can actually be
// disbursed), but the withdraw screen shows `balance`.
export const getPawaPayBalance = onCall(
  { region: 'europe-west1', secrets: [PAWAPAY_API_TOKEN, PAWAPAY_SANDBOX_TOKEN] },
  async (request) => {
    await assertSuperAdmin(request);
    const env = await resolvePawaPayEnv();

    const counterSnap =
      await db.collection('counters').doc('pawapay').get();
    const c = counterSnap.data() ?? {};
    const collected = (c[`collected_${env.environment}`] as number) ?? 0;
    const withdrawn = (c[`withdrawn_${env.environment}`] as number) ?? 0;
    const balance = Math.max(0, collected - withdrawn);

    // Best-effort live wallet balance (upper bound on what can be disbursed).
    let walletBalance: number | null = null;
    try {
      const result = await pawaPayFetch(env, '/v2/wallet-balances', 'GET');
      if (result.ok) {
        const balances: any[] = Array.isArray(result.body?.balances)
          ? result.body.balances
          : [];
        const xaf = balances.find(
          (b) => (b?.currency as string) === PAWAPAY_CURRENCY,
        );
        if (xaf) walletBalance = Math.round(parseFloat(xaf.balance) || 0);
      }
    } catch {
      walletBalance = null;
    }

    return {
      balance,
      collected,
      withdrawn,
      walletBalance,
      currency: PAWAPAY_CURRENCY,
      environment: env.environment,
    };
  },
);

// ── initiatePawaPayPayout ──────────────────────────────────────────
// Callable (super-admin): disburses `amount` XAF to a Mobile Money number.
interface InitiatePayoutRequest {
  amount: number;
  phoneNumber: string;
  provider: string;
  note?: string;
}

export const initiatePawaPayPayout = onCall<InitiatePayoutRequest>(
  { region: 'europe-west1', secrets: [PAWAPAY_API_TOKEN, PAWAPAY_SANDBOX_TOKEN] },
  async (request) => {
    const uid = await assertSuperAdmin(request);
    const { amount, phoneNumber, provider, note } = request.data;

    if (!Number.isInteger(amount) || amount <= 0) {
      throw new HttpsError('invalid-argument', 'amount must be a positive integer.');
    }
    if (provider !== PAWAPAY_PROVIDER_MTN && provider !== PAWAPAY_PROVIDER_ORANGE) {
      throw new HttpsError('invalid-argument', `Unsupported provider: ${provider}.`);
    }
    const msisdn = toMsisdn(phoneNumber);
    if (msisdn.length < 11) {
      throw new HttpsError('invalid-argument', 'Invalid phone number.');
    }

    const env = await resolvePawaPayEnv();
    const payoutId = uuidv4();
    const payoutRef = db.collection(COL_PAYOUTS).doc(payoutId);

    await payoutRef.set({
      payoutId,
      amount,
      currency: PAWAPAY_CURRENCY,
      phoneNumber: msisdn,
      provider,
      note: note ?? null,
      status: 'ACCEPTED',
      pawaPayStatus: 'ACCEPTED',
      environment: env.environment,
      createdBy: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const result = await pawaPayFetch(env, '/v2/payouts', 'POST', {
      payoutId,
      amount: String(amount),
      currency: PAWAPAY_CURRENCY,
      recipient: {
        type: 'MMO',
        accountDetails: { phoneNumber: msisdn, provider },
      },
    });

    if (!result.ok) {
      const rawCode =
        result.body?.failureReason?.failureCode ??
        result.body?.rejectionReason?.rejectionCode ??
        result.body?.rejectionReason?.failureCode;
      const rawMsg =
        result.body?.message ??
        result.body?.failureReason?.failureMessage ??
        result.body?.rejectionReason?.rejectionMessage;
      const { code, message } = normalizePawaPayFailure(rawCode, rawMsg);
      await payoutRef.update({
        status: 'FAILED',
        pawaPayStatus: 'FAILED',
        pawaPayFailureCode: code,
        notes: message,
      });
      throw new HttpsError(
        'internal',
        `Payout initiation failed: ${rawMsg ?? rawCode ?? result.status}`,
        { failureCode: code },
      );
    }

    return {
      payoutId,
      status: (result.body?.status as string) ?? 'ACCEPTED',
    };
  },
);

// ── checkPawaPayPayout ─────────────────────────────────────────────
// Callable (super-admin): polls live payout status and reconciles the doc.
interface CheckPayoutRequest {
  payoutId: string;
}

export const checkPawaPayPayout = onCall<CheckPayoutRequest>(
  { region: 'europe-west1', secrets: [PAWAPAY_API_TOKEN, PAWAPAY_SANDBOX_TOKEN] },
  async (request) => {
    await assertSuperAdmin(request);
    const { payoutId } = request.data;
    if (!payoutId) {
      throw new HttpsError('invalid-argument', 'payoutId is required.');
    }

    const payoutRef = db.collection(COL_PAYOUTS).doc(payoutId);
    const snap = await payoutRef.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Payout not found.');
    }
    const current = (snap.data()?.status as string) ?? 'ACCEPTED';
    if (current === 'COMPLETED' || current === 'FAILED') {
      return { status: current };
    }

    const env = await resolvePawaPayEnv();
    const result = await pawaPayFetch(env, `/v2/payouts/${payoutId}`, 'GET');
    if (!result.ok) {
      throw new HttpsError('internal', `pawaPay payout status check failed (${result.status}).`);
    }
    // GET /v2/payouts/{id} may return the payout object directly or wrapped.
    const payout = Array.isArray(result.body)
      ? result.body[0]
      : (result.body?.data ?? result.body);
    const status = await reconcilePayout(payoutRef, payout ?? {});
    return { status };
  },
);

// ═══════════════════════════════════════════════════════════════════
// MTN MoMo direct Collection API (Cameroon)
// ═══════════════════════════════════════════════════════════════════
//
// Unlike Orange (which still flows through pawaPay), MTN mobile-money deposits
// call MTN's Collection API DIRECTLY:
//   1. POST /collection/token/                     → short-lived bearer token
//   2. POST /collection/v1_0/requesttopay          → push a PIN prompt to payer
//   3. GET  /collection/v1_0/requesttopay/{refId}  → poll SUCCESSFUL/PENDING/FAILED
// Deposits are async (the payer approves with their MoMo PIN), so contributions
// are created `pending` and flipped to confirmed/failed by THREE paths, all
// idempotent through reconcileMtnDeposit:
//   • momoWebhook   — MTN PUTs the final status to our registered callback host
//                     (api.cmcda.org → momoWebhook via the Hosting rewrite). Fast
//                     path, but MTN fires it ONCE with no retry, so it can be lost.
//   • checkMtnMomoDeposit — client polls while the payment sheet is open.
//   • cleanStuckMtnMomoDeposits — hourly sweep of abandoned deposits.
// The webhook is an optimisation layered on top of polling, never a replacement:
// for security it ignores the callback body and re-fetches the authoritative
// status from MTN before reconciling (see momoWebhook).
//
// Environment follows the SAME app_config/payment_config.environment toggle as
// pawaPay. Production → live proxy + XAF; sandbox → MTN sandbox host + EUR. Each
// environment carries its own apiUser / apiKey / subscription-key secret trio.

const MTN_API_USER = defineSecret('MTN_MOMO_API_USER');
const MTN_API_KEY = defineSecret('MTN_MOMO_API_KEY');
const MTN_SUBSCRIPTION_KEY = defineSecret('MTN_MOMO_SUBSCRIPTION_KEY');
const MTN_SANDBOX_API_USER = defineSecret('MTN_MOMO_SANDBOX_API_USER');
const MTN_SANDBOX_API_KEY = defineSecret('MTN_MOMO_SANDBOX_API_KEY');
const MTN_SANDBOX_SUBSCRIPTION_KEY = defineSecret('MTN_MOMO_SANDBOX_SUBSCRIPTION_KEY');

// Every MTN function declares the full secret set — the active environment is
// resolved at call time, so both trios must be available.
const MTN_SECRETS = [
  MTN_API_USER, MTN_API_KEY, MTN_SUBSCRIPTION_KEY,
  MTN_SANDBOX_API_USER, MTN_SANDBOX_API_KEY, MTN_SANDBOX_SUBSCRIPTION_KEY,
];

const MTN_PROD_BASE = 'https://proxy.momoapi.mtn.com';
const MTN_PROD_TARGET = 'mtncameroon';
const MTN_SANDBOX_BASE = 'https://sandbox.momodeveloper.mtn.com';
const MTN_SANDBOX_TARGET = 'sandbox';

// Production callback host registered with the MTN API user (providerCallbackHost
// = api.cmcda.org). When this URL is sent as X-Callback-Url on requesttopay, MTN
// PUTs the final status here ONCE (no retry), so momoWebbook is only a fast-path —
// checkMtnMomoDeposit polling + cleanStuckMtnMomoDeposits remain the safety net.
// Routed to the momoWebhook function via the Firebase Hosting rewrite in
// firebase.json. The host MUST match the registered providerCallbackHost, so it is
// only attached in production (the sandbox API user isn't registered to this host).
const MTN_CALLBACK_URL = 'https://api.cmcda.org/webhook/momo';

interface MtnEnv {
  baseUrl: string;
  target: string;
  currency: string;
  apiUser: string;
  apiKey: string;
  subscriptionKey: string;
  environment: string; // 'production' | 'sandbox'
  // X-Callback-Url to attach to requesttopay (production only; '' = poll-only).
  callbackUrl: string;
}

// Resolves the active MTN environment from app_config/payment_config (shared
// with pawaPay). Defaults to production on a missing field or read failure, so
// the app never silently runs against the sandbox.
async function resolveMtnEnv(): Promise<MtnEnv> {
  let environment = 'production';
  try {
    const snap = await db.collection('app_config').doc('payment_config').get();
    if ((snap.data()?.environment as string) === 'sandbox') environment = 'sandbox';
  } catch {
    environment = 'production';
  }
  if (environment === 'sandbox') {
    return {
      baseUrl: MTN_SANDBOX_BASE,
      target: MTN_SANDBOX_TARGET,
      currency: 'EUR', // MTN sandbox only settles in EUR
      apiUser: MTN_SANDBOX_API_USER.value(),
      apiKey: MTN_SANDBOX_API_KEY.value(),
      subscriptionKey: MTN_SANDBOX_SUBSCRIPTION_KEY.value(),
      environment,
      // Sandbox API user isn't registered to api.cmcda.org — poll-only.
      callbackUrl: '',
    };
  }
  return {
    baseUrl: MTN_PROD_BASE,
    target: MTN_PROD_TARGET,
    currency: 'XAF',
    apiUser: MTN_API_USER.value(),
    apiKey: MTN_API_KEY.value(),
    subscriptionKey: MTN_SUBSCRIPTION_KEY.value(),
    environment,
    callbackUrl: MTN_CALLBACK_URL,
  };
}

// Per-environment access-token cache. MTN tokens live ~1 h; Cloud Functions
// instances are short-lived, so this just avoids a token round-trip on each warm
// invocation. Refreshed 60 s before expiry.
const _mtnTokenCache: Record<string, { token: string; expiresAt: number }> = {};

async function getMtnToken(env: MtnEnv): Promise<string> {
  const cached = _mtnTokenCache[env.environment];
  if (cached && Date.now() < cached.expiresAt) return cached.token;

  const basic = Buffer.from(`${env.apiUser}:${env.apiKey}`).toString('base64');
  const res = await fetch(`${env.baseUrl}/collection/token/`, {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${basic}`,
      'Ocp-Apim-Subscription-Key': env.subscriptionKey,
    },
  });
  if (!res.ok) {
    // MTN's error body carries the real reason (e.g. invalid subscription key,
    // wrong API user/key) — it contains no secrets, so log it for diagnosis.
    const errText = await res.text().catch(() => '');
    console.error(
      `[getMtnToken] token request failed env=${env.environment} ` +
      `target=${env.target} host=${env.baseUrl} HTTP ${res.status}: ${errText}`,
    );
    throw new HttpsError('internal', `MTN token request failed (HTTP ${res.status}).`);
  }
  const body: any = await res.json().catch(() => null);
  const token = body?.access_token as string | undefined;
  if (!token) throw new HttpsError('internal', 'MTN token response had no access_token.');
  const ttlMs = ((body?.expires_in as number) ?? 3600) * 1000;
  _mtnTokenCache[env.environment] = { token, expiresAt: Date.now() + ttlMs - 60_000 };
  return token;
}

interface MtnResult { ok: boolean; status: number; body: any; }

// Calls the MTN Collection API with the bearer token for the resolved
// environment. Returns parsed JSON + ok flag rather than throwing, so callers
// can map failures to contribution state. requesttopay returns 202 with an empty
// body, so a missing/non-JSON body is normal — never treat it as an error.
async function mtnFetch(
  env: MtnEnv,
  token: string,
  path: string,
  method: 'GET' | 'POST',
  referenceId?: string,
  body?: unknown,
  callbackUrl?: string,
): Promise<MtnResult> {
  const headers: Record<string, string> = {
    'Authorization': `Bearer ${token}`,
    'X-Target-Environment': env.target,
    'Ocp-Apim-Subscription-Key': env.subscriptionKey,
    'Content-Type': 'application/json',
  };
  if (referenceId) headers['X-Reference-Id'] = referenceId;
  // When set, MTN PUTs the final status to this URL (host must match the API
  // user's registered providerCallbackHost). Only valid on requesttopay.
  if (callbackUrl) headers['X-Callback-Url'] = callbackUrl;
  const res = await fetch(`${env.baseUrl}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  let parsed: any = null;
  try { parsed = await res.json(); } catch { parsed = null; }
  return { ok: res.ok, status: res.status, body: parsed };
}

// Maps an MTN requesttopay `reason` (a string or { code, message }) onto the
// SAME stable failure tokens pawaPay uses, so the client localizes both gateways
// through the existing AppLocalizations.pawaPayFailure(code). French fallback
// messages reuse PP_FAILURE_FR.
function normalizeMtnFailure(reason: any): { code: string; message: string } {
  const raw = typeof reason === 'string'
    ? reason
    : (reason?.code ?? reason?.message ?? '');
  const c = String(raw).toUpperCase();
  let code = 'GENERIC';
  if (c.includes('NOT_ENOUGH_FUNDS') || c.includes('INSUFFICIENT') || c.includes('LOW_BALANCE')) {
    code = 'INSUFFICIENT_BALANCE';
  } else if (c.includes('APPROVAL_REJECTED') || c.includes('NOT_APPROVED') || c.includes('CANCEL')) {
    code = 'PAYMENT_NOT_APPROVED';
  } else if (c.includes('PAYER_NOT_FOUND') || c.includes('PAYEE_NOT_FOUND') ||
             c.includes('RESOURCE_NOT_FOUND') || c.includes('ACCOUNTHOLDER')) {
    code = 'PAYER_NOT_FOUND';
  } else if (c.includes('LIMIT')) {
    code = 'PAYER_LIMIT_REACHED';
  } else if (c.includes('UNAVAILABLE') || c.includes('INTERNAL_PROCESSING_ERROR') ||
             c.includes('SERVICE')) {
    code = 'PROVIDER_UNAVAILABLE';
  } else if (c.includes('AMOUNT')) {
    code = 'AMOUNT_OUT_OF_LIMITS';
  } else if (c.includes('NOT_ALLOWED') || c.includes('NOTALLOWED')) {
    // MTN refuses the collection at the account level (product not activated for
    // live collections, tier restriction, etc.) — distinct from a user-side
    // rejection. Surface a message that points at the account, not the payer.
    code = 'NOT_ALLOWED';
  } else if (c.includes('INVALID') || c.includes('MSISDN') || c.includes('PARTYID')) {
    code = 'INVALID_NUMBER';
  } else if (c.includes('EXPIRED') || c.includes('TIMEOUT')) {
    code = 'TIMEOUT';
  }
  const message = PP_FAILURE_FR[code] ?? PP_FAILURE_FR.GENERIC;
  return { code, message };
}

/**
 * Reconciles a contribution doc with an MTN requesttopay status payload.
 * Idempotent: no-op once the contribution is already confirmed/failed.
 *
 * Mirrors reconcileDeposit (pawaPay): on SUCCESSFUL we credit
 * users/{id}.totalContributed and counters/platform.totalContributed HERE,
 * because the doc was created `pending` and the client never credited it.
 * Flipping status → confirmed then triggers onContributionConfirmed for region
 * totals, the wallet inflow tx, the matricule, and the "payment confirmed"
 * notification. The MTN-collected balance is tracked per environment in
 * counters/mtnmomo (separate from pawaPay's wallet). Returns the resulting
 * contribution status.
 */
async function reconcileMtnDeposit(
  contribRef: admin.firestore.DocumentReference,
  payload: { status?: string; reason?: any; financialTransactionId?: string },
): Promise<string> {
  const snap = await contribRef.get();
  if (!snap.exists) return 'failed';
  const data = snap.data()!;
  const current = (data.status as string) ?? 'pending';
  if (current === 'confirmed' || current === 'failed') return current;

  const mtnStatus = (payload.status as string) ?? '';

  if (mtnStatus === 'SUCCESSFUL') {
    const memberId = (data.memberId as string) ?? '';
    const amount = (data.amount as number) ?? 0;
    if (memberId && amount > 0) {
      await db.collection(COL_USERS).doc(memberId).update({
        totalContributed: admin.firestore.FieldValue.increment(amount),
      });
      await db.collection('counters').doc('platform').set(
        { totalContributed: admin.firestore.FieldValue.increment(amount) },
        { merge: true },
      );
      const e = (data.mtnEnvironment as string) === 'sandbox' ? 'sandbox' : 'production';
      await db.collection('counters').doc('mtnmomo').set(
        { [`collected_${e}`]: admin.firestore.FieldValue.increment(amount) },
        { merge: true },
      );
    }
    await contribRef.update({
      status: 'confirmed',
      confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
      mtnStatus,
      ...(payload.financialTransactionId
        ? { mtnFinancialTransactionId: payload.financialTransactionId }
        : {}),
    });
    return 'confirmed';
  }

  if (mtnStatus === 'FAILED') {
    const { code, message } = normalizeMtnFailure(payload.reason);
    await contribRef.update({
      status: 'failed',
      notes: message,
      // Reuse the client's localized failure token (see normalizeMtnFailure).
      pawaPayFailureCode: code,
      mtnStatus,
    });
    return 'failed';
  }

  // PENDING (or any non-terminal status) — still awaiting the payer's PIN.
  if (mtnStatus) await contribRef.update({ mtnStatus });
  return 'pending';
}

// ── initiateMtnMomoDeposit ─────────────────────────────────────────
// Callable: { amount, periodType, phoneNumber, memberId? }
// Creates the contribution (pending) and pushes an MTN MoMo PIN prompt to the
// payer. Resolved later by checkMtnMomoDeposit / cleanStuckMtnMomoDeposits.

interface InitiateMtnDepositRequest {
  amount: number;
  periodType: string;
  phoneNumber: string;
  // Optional: staff (focal/admin) charging a member's MoMo on their behalf.
  memberId?: string;
}

export const initiateMtnMomoDeposit = onCall<InitiateMtnDepositRequest>(
  { region: 'europe-west1', secrets: MTN_SECRETS },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    const callerUid = request.auth.uid;
    const { amount, periodType, phoneNumber, memberId: targetMemberId } = request.data;

    if (!Number.isInteger(amount) || amount <= 0) {
      throw new HttpsError('invalid-argument', 'amount must be a positive integer.');
    }
    const msisdn = toMsisdn(phoneNumber);
    if (msisdn.length < 11) {
      throw new HttpsError('invalid-argument', 'Invalid phone number.');
    }

    // Staff (focal/admin) may charge another member's MoMo; everyone else can
    // only pay for themselves. recordedBy always stays the caller.
    let memberId = callerUid;
    if (targetMemberId && targetMemberId !== callerUid) {
      const callerSnap = await db.collection(COL_USERS).doc(callerUid).get();
      const callerRole = (callerSnap.data()?.role as string) ?? 'member';
      if (!['focal', 'admin', 'super_admin'].includes(callerRole)) {
        throw new HttpsError(
          'permission-denied',
          'Only staff can record a payment for another member.',
        );
      }
      memberId = targetMemberId;
    }

    const userSnap = await db.collection(COL_USERS).doc(memberId).get();
    if (!userSnap.exists) {
      throw new HttpsError('not-found', 'User profile not found.');
    }
    const user = userSnap.data()!;
    if ((user.status as string) === 'suspended') {
      throw new HttpsError('permission-denied', 'Account suspended.');
    }

    const env = await resolveMtnEnv();
    const token = await getMtnToken(env);
    const referenceId = uuidv4();
    const contribRef = db.collection(COL_CONTRIBUTIONS).doc();

    await contribRef.set({
      memberId,
      memberName: (user.fullName as string) ?? '',
      memberNumber: (user.memberNumber as string) ?? '',
      amount,
      period: currentPeriod(),
      periodType: periodType || 'monthly',
      paymentMethod: providerToMethod(PAWAPAY_PROVIDER_MTN), // 'mtn_momo'
      status: 'pending',
      receiptNumber: '',
      recordedBy: callerUid,
      validationRequired: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      // MTN-direct markers (parallel to pawaPay's depositId/pawaPayEnvironment).
      mtnReferenceId: referenceId,
      mtnStatus: 'PENDING',
      mtnEnvironment: env.environment,
      pawaPayProvider: PAWAPAY_PROVIDER_MTN, // logical provider tag (MTN)
      payerPhone: msisdn,
    });

    const result = await mtnFetch(
      env, token, '/collection/v1_0/requesttopay', 'POST', referenceId,
      {
        amount: String(amount),
        currency: env.currency,
        externalId: contribRef.id,
        payer: { partyIdType: 'MSISDN', partyId: msisdn },
        payerMessage: 'Contribution CMCDA',
        payeeNote: `Contribution ${contribRef.id}`,
      },
      // Push the final status to momoWebhook (production only). Polling stays the
      // fallback — MTN sends the callback once with no retry.
      env.callbackUrl,
    );

    // 202 Accepted = the PIN prompt was pushed successfully. Anything else is a
    // hard initiation failure (bad number, provider down, limits, …).
    if (!result.ok) {
      // Log MTN's exact rejection (status + body). The body carries the real
      // cause — invalid X-Target-Environment, currency not supported, bad
      // MSISDN, etc. — and contains no secrets.
      console.error(
        `[initiateMtnMomoDeposit] requesttopay rejected env=${env.environment} ` +
        `target=${env.target} currency=${env.currency} msisdn=${msisdn} ` +
        `HTTP ${result.status}: ${JSON.stringify(result.body)}`,
      );
      const { code, message } = normalizeMtnFailure(
        result.body?.code ?? result.body?.message ?? `HTTP_${result.status}`,
      );
      await contribRef.update({
        status: 'failed',
        notes: message,
        pawaPayFailureCode: code,
        mtnStatus: 'FAILED',
      });
      throw new HttpsError(
        'internal',
        `MTN deposit initiation failed (HTTP ${result.status}).`,
        { failureCode: code },
      );
    }

    return { contributionId: contribRef.id, referenceId, status: 'PENDING' };
  },
);

// ── checkMtnMomoDeposit ────────────────────────────────────────────
// Callable poll: { contributionId }. Fetches the live requesttopay status from
// MTN and reconciles it. The client calls this repeatedly while waiting (MTN has
// no inbound webhook), and cleanStuckMtnMomoDeposits sweeps abandoned ones.

interface CheckMtnDepositRequest { contributionId: string; }

export const checkMtnMomoDeposit = onCall<CheckMtnDepositRequest>(
  { region: 'europe-west1', secrets: MTN_SECRETS },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    const { contributionId } = request.data;
    if (!contributionId) {
      throw new HttpsError('invalid-argument', 'contributionId is required.');
    }

    const contribRef = db.collection(COL_CONTRIBUTIONS).doc(contributionId);
    const snap = await contribRef.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Contribution not found.');
    }
    const data = snap.data()!;

    // Owner or staff only.
    const callerSnap = await db.collection(COL_USERS).doc(request.auth.uid).get();
    const callerRole = (callerSnap.data()?.role as string) ?? 'member';
    const isStaff = ['focal', 'admin', 'super_admin'].includes(callerRole);
    if (data.memberId !== request.auth.uid && !isStaff) {
      throw new HttpsError('permission-denied', 'Not allowed.');
    }

    const currentStatus = (data.status as string) ?? 'pending';
    if (currentStatus === 'confirmed' || currentStatus === 'failed') {
      return { status: currentStatus };
    }

    const referenceId = data.mtnReferenceId as string | undefined;
    if (!referenceId) {
      throw new HttpsError('failed-precondition', 'No MTN reference on contribution.');
    }

    const env = await resolveMtnEnv();
    const token = await getMtnToken(env);
    const result = await mtnFetch(
      env, token, `/collection/v1_0/requesttopay/${referenceId}`, 'GET',
    );
    // Log MTN's verbatim status payload (status + reason) — no secrets — so we
    // can see exactly why a deposit resolves to FAILED rather than SUCCESSFUL.
    console.log(
      `[checkMtnMomoDeposit] ref=${referenceId} env=${env.environment} ` +
      `HTTP ${result.status}: ${JSON.stringify(result.body)}`,
    );
    if (!result.ok) {
      throw new HttpsError('internal', `MTN status check failed (HTTP ${result.status}).`);
    }
    const status = await reconcileMtnDeposit(contribRef, result.body ?? {});
    return { status };
  },
);

// ── momoWebhook ────────────────────────────────────────────────────
// HTTP endpoint MTN PUTs the requesttopay result to (X-Callback-Url =
// https://api.cmcda.org/webhook/momo, routed here by the Hosting rewrite). MTN
// fires it ONCE with no retry, so it is purely a fast path — the client poll and
// the hourly sweep still resolve anything that never arrives.
//
// MTN callbacks are NOT signed, so we never trust the request body: we use it
// only to locate the contribution (by externalId = our doc id, or the
// X-Reference-Id header), then re-fetch the AUTHORITATIVE status from MTN with our
// own credentials before reconciling. A forged callback can at most trigger one
// extra status fetch for a real, still-pending deposit — it can never confirm a
// payment that MTN didn't actually settle. Always 200 so MTN doesn't log failures.

export const momoWebhook = onRequest(
  { region: 'europe-west1', secrets: MTN_SECRETS },
  async (req, res) => {
    if (req.method !== 'POST' && req.method !== 'PUT') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    try {
      const payload = (req.body ?? {}) as Record<string, unknown>;
      const externalId = payload.externalId as string | undefined;
      const headerRef =
        (req.header('X-Reference-Id') ?? req.header('x-reference-id')) || undefined;

      // Locate the contribution. externalId is our (unguessable) doc id; fall back
      // to a query on mtnReferenceId if MTN only echoed the reference header.
      let contribRef: admin.firestore.DocumentReference | null = null;
      if (externalId) {
        const ref = db.collection(COL_CONTRIBUTIONS).doc(externalId);
        if ((await ref.get()).exists) contribRef = ref;
      }
      if (!contribRef && headerRef) {
        const q = await db
          .collection(COL_CONTRIBUTIONS)
          .where('mtnReferenceId', '==', headerRef)
          .limit(1)
          .get();
        if (!q.empty) contribRef = q.docs[0].ref;
      }
      if (!contribRef) {
        console.warn(
          `[momoWebhook] no contribution for externalId=${externalId} ref=${headerRef}`,
        );
        res.status(200).send('OK');
        return;
      }

      const data = (await contribRef.get()).data()!;
      const current = (data.status as string) ?? 'pending';
      if (current === 'confirmed' || current === 'failed') {
        res.status(200).send('OK');
        return;
      }
      const referenceId = data.mtnReferenceId as string | undefined;
      if (!referenceId) {
        res.status(200).send('OK');
        return;
      }

      // Authoritative status from MTN — the callback body is never trusted.
      const env = await resolveMtnEnv();
      const token = await getMtnToken(env);
      const result = await mtnFetch(
        env, token, `/collection/v1_0/requesttopay/${referenceId}`, 'GET',
      );
      console.log(
        `[momoWebhook] ref=${referenceId} env=${env.environment} ` +
        `HTTP ${result.status}: ${JSON.stringify(result.body)}`,
      );
      if (result.ok) {
        await reconcileMtnDeposit(contribRef, result.body ?? {});
      }
    } catch (e) {
      console.error('[momoWebhook] reconcile error', e);
    }
    // Always 200: MTN doesn't retry, and the poll/sweep cover anything missed.
    res.status(200).send('OK');
  },
);

// ── cleanStuckMtnMomoDeposits ──────────────────────────────────────
// Runs hourly. Finds MTN mobile-money contributions still `pending` after 2 h
// (payer ignored the PIN prompt, or the app was closed before the poll
// resolved), fetches the live status from MTN, and reconciles. Any deposit
// still unresolved is force-marked `failed` so the pending queue never
// accumulates ghost entries. Reuses the existing (status, createdAt) index;
// MTN deposits are identified in-memory by the presence of mtnReferenceId.

export const cleanStuckMtnMomoDeposits = onSchedule(
  { region: 'europe-west1', schedule: 'every 1 hours', secrets: MTN_SECRETS },
  async () => {
    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 2 * 60 * 60 * 1000),
    );

    const snap = await db
      .collection(COL_CONTRIBUTIONS)
      .where('status', '==', 'pending')
      .where('createdAt', '<', cutoff)
      .orderBy('createdAt', 'asc')
      .get();

    const mtn = snap.docs.filter((d) => !!(d.data().mtnReferenceId as string | undefined));
    if (mtn.length === 0) {
      console.log('[cleanStuckMtnMomoDeposits] nothing to process');
      return;
    }

    const env = await resolveMtnEnv();
    let token: string;
    try {
      token = await getMtnToken(env);
    } catch (e) {
      console.error('[cleanStuckMtnMomoDeposits] token error', e);
      return;
    }

    let reconciled = 0;
    let forceFailed = 0;

    await Promise.all(
      mtn.map(async (doc) => {
        const referenceId = doc.data().mtnReferenceId as string;
        try {
          const r = await mtnFetch(
            env, token, `/collection/v1_0/requesttopay/${referenceId}`, 'GET',
          );
          if (r.ok) {
            const result = await reconcileMtnDeposit(doc.ref, r.body ?? {});
            if (result !== 'pending') {
              reconciled++;
              return;
            }
          }
        } catch (e) {
          console.warn(`[cleanStuckMtnMomoDeposits] fetch error for ${referenceId}`, e);
        }

        // Still pending after cutoff (or MTN returned an error) — force fail.
        await doc.ref.update({
          status: 'failed',
          notes: 'Délai de paiement expiré',
          pawaPayFailureCode: 'TIMEOUT',
          mtnStatus: 'FAILED',
        });
        forceFailed++;
      }),
    );

    console.log(
      `[cleanStuckMtnMomoDeposits] scanned=${mtn.length} reconciled=${reconciled} forceFailed=${forceFailed}`,
    );
  },
);
