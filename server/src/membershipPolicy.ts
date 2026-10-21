/** Versioned business rules. No client-supplied membership or price is authoritative. */
export const MEMBERSHIP_POLICY_VERSION = 1;
export type MembershipSku = 'MONTHLY' | 'ANNUAL' | 'LIFETIME' | 'SUPER_LIFETIME';
export type MembershipTier = 'STANDARD' | 'SUPER';
export type VoiceTier = 'STANDARD' | 'PREMIUM';

export interface MembershipProduct {
  sku: MembershipSku;
  name: string;
  points: number;
  months: number | null;
  tier: MembershipTier;
}

export const MEMBERSHIP_PRODUCTS: readonly MembershipProduct[] = Object.freeze([
  { sku: 'MONTHLY', name: '月度会员', points: 60, months: 1, tier: 'STANDARD' },
  { sku: 'ANNUAL', name: '年度会员', points: 480, months: 12, tier: 'STANDARD' },
  { sku: 'LIFETIME', name: '永久会员', points: 1290, months: null, tier: 'STANDARD' },
  { sku: 'SUPER_LIFETIME', name: '永久超级会员', points: 2490, months: null, tier: 'SUPER' }
] satisfies MembershipProduct[]);

export interface MembershipState {
  periodId: string;
  sku: MembershipSku;
  anchorAt: number;
  paidMonths: number;
  expiresAt: number | null;
  permanentCreditPoints: number;
  revision: number;
}

export interface MembershipTerm {
  startsAt: number;
  endsAt: number;
  points: number;
}

export class MembershipError extends Error {
  constructor(readonly statusCode: number, readonly code: string, message: string) {
    super(message);
  }
}

export function membershipProduct(sku: unknown): MembershipProduct {
  const product = MEMBERSHIP_PRODUCTS.find((item) => item.sku === sku);
  if (!product) throw new MembershipError(400, 'INVALID_MEMBERSHIP_SKU', '会员商品不存在');
  return product;
}

export function membershipActive(state: MembershipState | null, now: number): boolean {
  return state !== null && state.anchorAt <= now && (state.expiresAt === null || state.expiresAt > now);
}

const BEIJING_OFFSET_MS = 8 * 60 * 60 * 1000;

/** Add months from the original anchor, preserving the Beijing wall-clock time. */
export function membershipAnniversary(anchorAt: number, months: number): number {
  if (!Number.isFinite(anchorAt) || !Number.isSafeInteger(months) || months < 0) {
    throw new Error('Invalid membership anniversary');
  }
  const anchor = new Date(anchorAt + BEIJING_OFFSET_MS);
  const first = new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth() + months, 1));
  const lastDay = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0)).getUTCDate();
  return Date.UTC(first.getUTCFullYear(), first.getUTCMonth(), Math.min(anchor.getUTCDate(), lastDay),
    anchor.getUTCHours(), anchor.getUTCMinutes(), anchor.getUTCSeconds(), anchor.getUTCMilliseconds())
    - BEIJING_OFFSET_MS;
}

export function membershipCycle(state: MembershipState, now: number): {
  index: number; startsAt: number; endsAt: number;
} {
  if (!membershipActive(state, now)) {
    throw new MembershipError(403, 'MEMBERSHIP_INACTIVE', '请先开通有效会员');
  }
  const anchor = new Date(state.anchorAt + BEIJING_OFFSET_MS);
  const current = new Date(now + BEIJING_OFFSET_MS);
  let index = (current.getUTCFullYear() - anchor.getUTCFullYear()) * 12
    + current.getUTCMonth() - anchor.getUTCMonth();
  if (membershipAnniversary(state.anchorAt, index) > now) index--;
  return {
    index,
    startsAt: membershipAnniversary(state.anchorAt, index),
    endsAt: Math.min(membershipAnniversary(state.anchorAt, index + 1), state.expiresAt ?? Infinity)
  };
}

export function membershipGiftChars(sku: MembershipSku, tier: VoiceTier): number {
  return sku === 'SUPER_LIFETIME'
    ? (tier === 'STANDARD' ? 3000 : 1500)
    : (tier === 'STANDARD' ? 2000 : 1000);
}

export interface MembershipPurchasePlan {
  sku: MembershipSku;
  listPoints: number;
  creditPoints: number;
  payablePoints: number;
  expectedRevision: number;
  newPeriod: boolean;
  next: MembershipState;
  term: MembershipTerm | null;
}

export function planMembershipPurchase(
  current: MembershipState | null,
  terms: readonly MembershipTerm[],
  sku: MembershipSku,
  now: number,
  newPeriodId: string
): MembershipPurchasePlan {
  const product = membershipProduct(sku);
  const active = membershipActive(current, now) ? current : null;
  if (active?.expiresAt === null &&
      (active.sku === 'SUPER_LIFETIME' || sku !== 'SUPER_LIFETIME')) {
    throw new MembershipError(409, 'MEMBERSHIP_ALREADY_OWNED', '已拥有永久权益，无需重复购买或降级');
  }
  let creditPoints = 0;
  if (active && product.months === null) {
    creditPoints = active.expiresAt === null
      ? active.permanentCreditPoints
      : Math.floor(terms.reduce((sum, term) => {
        if (term.endsAt <= now || term.endsAt <= term.startsAt) return sum;
        const ratio = Math.min(1, (term.endsAt - now) / (term.endsAt - term.startsAt));
        return sum + term.points * ratio;
      }, 0));
    // Upgrade credits are not cash and cannot make an order negative.
    creditPoints = Math.min(product.points, Math.max(0, creditPoints));
  }
  const anchorAt = active?.anchorAt ?? now;
  const paidMonths = product.months === null ? 0 : (active?.paidMonths ?? 0) + product.months;
  const expiresAt = product.months === null ? null : membershipAnniversary(anchorAt, paidMonths);
  return {
    sku,
    listPoints: product.points,
    creditPoints,
    payablePoints: product.points - creditPoints,
    expectedRevision: current?.revision ?? 0,
    newPeriod: active === null,
    next: {
      periodId: active?.periodId ?? newPeriodId,
      sku,
      anchorAt,
      paidMonths,
      expiresAt,
      permanentCreditPoints: product.months === null ? product.points : 0,
      revision: (current?.revision ?? 0) + 1
    },
    term: expiresAt === null ? null : {
      startsAt: active?.expiresAt ?? now,
      endsAt: expiresAt,
      points: product.points
    }
  };
}

export function membershipBenefits(state: MembershipState | null, now: number) {
  const active = membershipActive(state, now);
  const superMember = active && state?.sku === 'SUPER_LIFETIME';
  return {
    memberThemes: active,
    ttsPriority: active,
    sourceCount: superMember ? null : active ? 500 : 50,
    sourceBytes: superMember ? null : (active ? 512 : 50) * 1024,
    cloudStorageBytes: superMember ? 1024 ** 3 : 0,
    monthlyDownloadBytes: superMember ? 1024 ** 3 : 0,
    standardGiftChars: active ? membershipGiftChars(state!.sku, 'STANDARD') : 0,
    premiumGiftChars: active ? membershipGiftChars(state!.sku, 'PREMIUM') : 0
  };
}
