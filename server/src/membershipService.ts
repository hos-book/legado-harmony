import { randomUUID } from 'node:crypto';
import type { PoolClient } from 'pg';
import { MembershipSalesPilot, pilotAllows } from './membershipSales.js';
import {
  MEMBERSHIP_POLICY_VERSION, MEMBERSHIP_PRODUCTS, MembershipError, MembershipState,
  MembershipPurchasePlan, MembershipSku, VoiceTier, membershipActive, membershipBenefits,
  membershipCycle, membershipGiftCycle, membershipGiftChars, membershipProduct, planMembershipPurchase
} from './membershipPolicy.js';

export interface MembershipDb { query: PoolClient['query']; }

export async function readMembership(db: MembershipDb, userId: string): Promise<MembershipState | null> {
  const result = await db.query<{
    id: string; sku: MembershipSku; anchor_at: Date; expires_at: Date | null;
    paid_months: number; permanent_credit_points: string; revision: number;
  }>(`SELECT p.*, a.revision FROM membership_accounts a
      JOIN membership_periods p ON p.id = a.period_id WHERE a.user_id = $1`, [userId]);
  const row = result.rows[0];
  return row ? {
    periodId: row.id, sku: row.sku, anchorAt: row.anchor_at.getTime(),
    expiresAt: row.expires_at?.getTime() ?? null, paidMonths: row.paid_months,
    permanentCreditPoints: Number(row.permanent_credit_points), revision: row.revision
  } : null;
}

/** Lightweight queue-priority check; refund debt suspends every paid benefit. */
export async function membershipPriority(db: MembershipDb, userId: string, now = Date.now()): Promise<boolean> {
  if (!membershipActive(await readMembership(db, userId), now)) return false;
  const debt = await db.query<{ iap_debt_points: string }>(
    'SELECT iap_debt_points FROM account_debts WHERE user_id = $1', [userId]);
  return Number(debt.rows[0]?.iap_debt_points ?? 0) <= 0;
}

/**
 * The product that pays for `now`. A periodic period keeps the SKU of its latest purchase, so an annual
 * member who adds a month would otherwise look monthly; the covering order decides benefits instead.
 */
export async function membershipTierSku(db: MembershipDb, state: MembershipState, now = Date.now()): Promise<MembershipSku> {
  if (state.expiresAt === null) return state.sku;
  const covering = await db.query<{ sku: MembershipSku }>(`SELECT sku FROM membership_orders
    WHERE period_id = $1 AND term_starts_at <= $2 AND term_ends_at > $2
    ORDER BY term_starts_at DESC LIMIT 1`, [state.periodId, new Date(now)]);
  return covering.rows[0]?.sku ?? state.sku;
}

async function lockAccount(db: MembershipDb, userId: string): Promise<void> {
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`membership:${userId}`]);
}

async function assertNoDebt(db: MembershipDb, userId: string): Promise<void> {
  const result = await db.query<{ iap_debt_points: string }>(
    'SELECT iap_debt_points FROM account_debts WHERE user_id = $1', [userId]);
  if (Number(result.rows[0]?.iap_debt_points ?? 0) > 0) {
    throw new MembershipError(403, 'ACCOUNT_PAYMENT_RESTRICTED', '账号存在退款欠款，请先补齐');
  }
}

async function assertOnSale(db: MembershipDb, sku: MembershipSku, userId: string,
  now: number, pilot?: MembershipSalesPilot): Promise<void> {
  const result = await db.query<{ sales_enabled: boolean }>(
    'SELECT sales_enabled FROM membership_products WHERE sku = $1 FOR SHARE', [sku]);
  if (!result.rows[0] || (!result.rows[0].sales_enabled && !pilotAllows(pilot, userId, sku, now))) {
    throw new MembershipError(409, 'MEMBERSHIP_NOT_ON_SALE', '该会员尚未开放购买');
  }
}

export async function membershipCatalog(db: MembershipDb, userId?: string,
  now = Date.now(), pilot?: MembershipSalesPilot) {
  const result = await db.query<{ sku: string; sales_enabled: boolean }>(
    'SELECT sku, sales_enabled FROM membership_products');
  return MEMBERSHIP_PRODUCTS.map((product) => ({
    ...product, salesEnabled: result.rows.some(row => row.sku === product.sku &&
      (row.sales_enabled || pilotAllows(pilot, userId, product.sku, now)))
  }));
}

/** The account can claim once per calendar month, even after an upgrade or a new paid period. */
async function readGiftClaim(db: MembershipDb, userId: string, cycle: ReturnType<typeof membershipGiftCycle>) {
  const result = await db.query<{ tier: VoiceTier; chars: number }>(
    `SELECT tier, chars FROM membership_gift_claims WHERE user_id=$1 AND
      (gift_month=$2 OR (gift_month IS NULL AND created_at >= $3 AND created_at < $4))
     ORDER BY created_at, period_id, cycle_index LIMIT 1`,
    [userId, cycle.index, new Date(cycle.startsAt), new Date(cycle.endsAt)]);
  return result.rows[0] ?? null;
}

export async function membershipSnapshot(db: MembershipDb, userId: string, now = Date.now()) {
  const state = await readMembership(db, userId);
  const debt = await db.query<{ iap_debt_points: string }>(
    'SELECT iap_debt_points FROM account_debts WHERE user_id = $1', [userId]);
  const restricted = Number(debt.rows[0]?.iap_debt_points ?? 0) > 0;
  const active = !restricted && membershipActive(state, now);
  const cycle = active ? membershipCycle(state!, now) : null;
  const giftCycle = active ? membershipGiftCycle(state!, now) : null;
  const tierSku = active ? await membershipTierSku(db, state!, now) : null;
  const claim = giftCycle ? await readGiftClaim(db, userId, giftCycle) : null;
  return {
    state, active, restricted, cycle, giftCycle, tierSku, claim,
    benefits: membershipBenefits(active ? state : null, now, tierSku ?? undefined),
    serverNow: now
  };
}

/** Call inside a transaction; quote fixes proration for 15 minutes. */
export async function quoteMembership(db: MembershipDb, userId: string, sku: MembershipSku,
  now = Date.now(), pilot?: MembershipSalesPilot) {
  membershipProduct(sku);
  await lockAccount(db, userId);
  await assertNoDebt(db, userId);
  await assertOnSale(db, sku, userId, now, pilot);
  const state = await readMembership(db, userId);
  const terms = state ? await db.query<{ term_starts_at: Date; term_ends_at: Date; points_spent: string }>(
    `SELECT term_starts_at, term_ends_at, points_spent FROM membership_orders
     WHERE period_id = $1 AND term_ends_at > $2`, [state.periodId, new Date(now)]) : null;
  const plan = planMembershipPurchase(state, (terms?.rows ?? []).map(row => ({
    startsAt: row.term_starts_at.getTime(), endsAt: row.term_ends_at.getTime(), points: Number(row.points_spent)
  })), sku, now, randomUUID());
  const quoteId = randomUUID();
  // Do not let a renewal quote cross the old membership's expiry.
  const expiresAt = Math.min(now + 15 * 60 * 1000,
    membershipActive(state, now) ? state!.expiresAt ?? Infinity : Infinity);
  await db.query(`INSERT INTO membership_quotes(id, user_id, policy_version, plan, expires_at)
    VALUES ($1,$2,$3,$4::jsonb,$5)`, [quoteId, userId, MEMBERSHIP_POLICY_VERSION, JSON.stringify(plan), new Date(expiresAt)]);
  return { quoteId, expiresAt, ...plan };
}

/** Wallet, ledger, membership, order and grant expiry changes commit atomically. */
export async function purchaseMembership(
  db: MembershipDb, userId: string, quoteId: string, requestId: string, now = Date.now(),
  pilot?: MembershipSalesPilot
) {
  if (typeof requestId !== 'string' || !requestId.trim() || requestId.length > 128 ||
      typeof quoteId !== 'string' || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(quoteId)) {
    throw new MembershipError(400, 'INVALID_MEMBERSHIP_REQUEST', '购买请求标识无效');
  }
  await lockAccount(db, userId);
  const duplicate = await db.query<{ id: string; quote_id: string }>(
    'SELECT id, quote_id FROM membership_orders WHERE user_id = $1 AND request_id = $2', [userId, requestId]);
  if (duplicate.rows[0]) {
    if (duplicate.rows[0].quote_id !== quoteId) {
      throw new MembershipError(409, 'MEMBERSHIP_REQUEST_CONFLICT', '相同请求标识不能购买不同报价');
    }
    return { orderId: duplicate.rows[0].id, duplicate: true };
  }
  // A second request ID for a consumed quote also returns the original order.
  const consumed = await db.query<{ id: string }>(
    'SELECT id FROM membership_orders WHERE user_id = $1 AND quote_id = $2', [userId, quoteId]);
  if (consumed.rows[0]) return { orderId: consumed.rows[0].id, duplicate: true };
  const quotes = await db.query<{ plan: MembershipPurchasePlan; expires_at: Date; policy_version: number }>(
    'SELECT plan, expires_at, policy_version FROM membership_quotes WHERE id = $1 AND user_id = $2 FOR UPDATE',
    [quoteId, userId]);
  const quote = quotes.rows[0];
  if (!quote || quote.expires_at.getTime() <= now || quote.policy_version !== MEMBERSHIP_POLICY_VERSION) {
    throw new MembershipError(409, 'MEMBERSHIP_QUOTE_EXPIRED', '报价已过期，请重新查看价格');
  }
  const plan = quote.plan;
  await assertOnSale(db, plan.sku, userId, now, pilot);
  const state = await readMembership(db, userId);
  if ((state?.revision ?? 0) !== plan.expectedRevision) {
    throw new MembershipError(409, 'MEMBERSHIP_OFFER_CHANGED', '会员状态已变化，请重新查看价格');
  }
  const wallets = await db.query<{ balance: string; paid_balance: string }>(
    'SELECT balance, paid_balance FROM point_wallets WHERE user_id = $1 FOR UPDATE', [userId]);
  await assertNoDebt(db, userId);
  const wallet = wallets.rows[0];
  if (!wallet || Number(wallet.paid_balance) < plan.payablePoints) {
    throw new MembershipError(409, 'INSUFFICIENT_PAID_POINTS', '充值点不足，赠送点不能用于购买会员');
  }
  const balanceAfter = Number(wallet.balance) - plan.payablePoints;
  await db.query(`UPDATE point_wallets SET balance = balance - $2, paid_balance = paid_balance - $2,
    updated_at = now() WHERE user_id = $1`, [userId, plan.payablePoints]);
  const ledger = await db.query<{ id: string }>(`INSERT INTO point_ledger
    (user_id, delta, balance_after, reason, reference_id, idempotency_key)
    VALUES ($1,$2,$3,'MEMBERSHIP_PURCHASE',$4,$5) RETURNING id`,
    [userId, -plan.payablePoints, balanceAfter, plan.sku, `membership:${userId}:${requestId}`]);
  // A new period starts at payment, rather than the potentially earlier quote time.
  const next = plan.newPeriod
    ? planMembershipPurchase(state, [], plan.sku, now, plan.next.periodId).next : plan.next;
  await db.query(`INSERT INTO membership_periods
    (id,user_id,sku,anchor_at,paid_months,expires_at,permanent_credit_points)
    VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (id) DO UPDATE SET
    sku=EXCLUDED.sku, paid_months=EXCLUDED.paid_months, expires_at=EXCLUDED.expires_at,
    permanent_credit_points=EXCLUDED.permanent_credit_points`,
    [next.periodId, userId, next.sku, new Date(next.anchorAt), next.paidMonths,
      next.expiresAt === null ? null : new Date(next.expiresAt), next.permanentCreditPoints]);
  await db.query(`INSERT INTO membership_accounts(user_id,period_id,revision) VALUES ($1,$2,$3)
    ON CONFLICT(user_id) DO UPDATE SET period_id=EXCLUDED.period_id,revision=EXCLUDED.revision`,
    [userId, next.periodId, next.revision]);
  // The same locks as synthesis/refunds keep balances and expiry changes consistent.
  for (const tier of ['STANDARD', 'PREMIUM']) {
    await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`tts-quota:${userId}:${tier}`]);
  }
  await db.query(`UPDATE tts_quota_grants SET expires_at=$2::timestamptz, updated_at=now()
    WHERE membership_period_id=$1`, [next.periodId,
    next.expiresAt === null ? 'infinity' : new Date(next.expiresAt).toISOString()]);
  const order = await db.query<{ id: string }>(`INSERT INTO membership_orders
    (user_id,period_id,sku,request_id,quote_id,list_points,credit_points,points_spent,
     term_starts_at,term_ends_at,point_ledger_id)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id`,
    [userId,next.periodId,plan.sku,requestId,quoteId,plan.listPoints,plan.creditPoints,plan.payablePoints,
      plan.term ? new Date(plan.newPeriod ? now : plan.term.startsAt) : null,
      plan.term ? new Date(next.expiresAt!) : null,ledger.rows[0]!.id]);
  return { orderId: order.rows[0]!.id, duplicate: false };
}

export async function claimMembershipGift(db: MembershipDb, userId: string, tier: VoiceTier, now = Date.now()) {
  if (tier !== 'STANDARD' && tier !== 'PREMIUM') {
    throw new MembershipError(400, 'INVALID_TTS_TIER', '请选择标准或精品额度');
  }
  await lockAccount(db, userId);
  // Coordinate with IAP reconciliation before checking debt.
  await db.query('SELECT user_id FROM point_wallets WHERE user_id=$1 FOR UPDATE', [userId]);
  await assertNoDebt(db, userId);
  const state = await readMembership(db, userId);
  if (!state || !membershipActive(state, now)) {
    throw new MembershipError(403, 'MEMBERSHIP_INACTIVE', '请先开通有效会员');
  }
  const cycle = membershipGiftCycle(state, now);
  const prior = await readGiftClaim(db, userId, cycle);
  if (prior) {
    if (prior.tier !== tier) throw new MembershipError(409, 'MEMBERSHIP_GIFT_ALREADY_CLAIMED', '本月已领取另一档额度');
    return { ...prior, duplicate: true };
  }
  const chars = membershipGiftChars(await membershipTierSku(db, state, now), tier);
  if (chars <= 0) {
    throw new MembershipError(403, 'MEMBERSHIP_GIFT_NOT_INCLUDED', '月度会员不含每月朗读礼包，年度及永久会员可领取');
  }
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`tts-quota:${userId}:${tier}`]);
  const key = `membership-gift-month:${userId}:${cycle.index}`;
  const balance = await db.query<{ balance: string }>(`SELECT COALESCE(SUM(remaining_chars),0)::bigint AS balance
    FROM tts_quota_grants WHERE user_id=$1 AND tier=$2 AND remaining_chars>0 AND expires_at>$3`,
    [userId,tier,new Date(now)]);
  const grant = await db.query<{ id: string }>(`INSERT INTO tts_quota_grants
    (user_id,tier,source,total_chars,remaining_chars,expires_at,reference_id,membership_period_id)
    VALUES ($1,$2,'MEMBERSHIP',$3,$3,$4::timestamptz,$5,$6) RETURNING id`,
    [userId,tier,chars,state.expiresAt === null ? 'infinity' : new Date(state.expiresAt).toISOString(),key,state.periodId]);
  await db.query(`INSERT INTO tts_quota_ledger
    (user_id,grant_id,tier,delta_chars,balance_after,reason,reference_id,idempotency_key)
    VALUES ($1,$2,$3,$4,$5,'MEMBERSHIP_GIFT',$6,$6)`,
    [userId,grant.rows[0]!.id,tier,chars,Number(balance.rows[0]!.balance)+chars,key]);
  await db.query(`INSERT INTO membership_gift_claims
    (period_id,cycle_index,user_id,tier,chars,quota_grant_id,gift_month,created_at)
    VALUES ($1,$2,$3,$4,$5,$6,$2,$7)`,
    [state.periodId,cycle.index,userId,tier,chars,grant.rows[0]!.id,new Date(now)]);
  return { tier, chars, duplicate: false };
}
