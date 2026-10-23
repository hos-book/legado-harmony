import assert from 'node:assert/strict';
import test from 'node:test';
import Fastify from 'fastify';
import type { PoolClient } from 'pg';
import { parseMembershipSalesPilot } from './membershipSales.js';
import { registerMembershipRoutes } from './membershipRoutes.js';
import { MEMBERSHIP_PRODUCTS, MembershipError } from './membershipPolicy.js';

const id = 'd105489a-3d17-4f18-af36-7a15e5e1b3ae';
test('pilot configuration requires explicit IDs, products and timezone expiry', () => {
  assert.equal(parseMembershipSalesPilot(), undefined);
  for (const args of [[id, '', ''], ['icyn', 'MONTHLY', '2030-01-01T00:00:00Z'],
    [id, '*', '2030-01-01T00:00:00Z'], [id, 'MONTHLY', '2030-01-01']]) {
    assert.throws(() => parseMembershipSalesPilot(...args));
  }
});

test('HTTP catalog uses authenticated identity and rejects request-supplied pilot privileges', async t => {
  const app = Fastify();
  t.after(() => app.close());
  const db = { query: async () => ({ rows: MEMBERSHIP_PRODUCTS.map(p => ({ sku: p.sku, sales_enabled: false, sales_starts_at: null })) }) } as unknown as PoolClient;
  registerMembershipRoutes(app, {
    enabled: true, superEnabled: false,
    salesPilot: parseMembershipSalesPilot(id, 'MONTHLY,SUPER_LIFETIME', new Date(Date.now() + 60000).toISOString()),
    authenticate: async (req, reply) => {
      if (!['Bearer pilot', 'Bearer other'].includes(req.headers.authorization || '')) {
        await reply.code(401).send({ code: 'UNAUTHORIZED' });
      }
    },
    userId: req => req.headers.authorization === 'Bearer pilot' ? id : '00000000-0000-0000-0000-000000000001',
    transaction: async work => work(db), limit: async () => {}, account: async () => ({}), wallet: async () => ({})
  });
  app.setErrorHandler((error, _req, reply) => {
    if (error instanceof MembershipError) return reply.code(error.statusCode).send({ code: error.code });
    return reply.code(500).send({ code: 'UNEXPECTED' });
  });
  const publicCatalog = await app.inject('/v1/membership/catalog?userId=' + id);
  assert.ok(publicCatalog.json().products.every((p: { salesEnabled: boolean }) => !p.salesEnabled));
  assert.equal((await app.inject('/v1/membership/catalog/account')).statusCode, 401);
  for (const [token, expected] of [['other', []], ['pilot', ['MONTHLY']]] as const) {
    const res = await app.inject({ url: '/v1/membership/catalog/account', headers: { authorization: 'Bearer ' + token } });
    assert.equal(res.statusCode, 200);
    assert.equal(res.headers['cache-control'], 'private, no-store');
    assert.deepEqual(res.json().products.filter((p: { salesEnabled: boolean }) => p.salesEnabled).map((p: { sku: string }) => p.sku), expected);
  }
  const forged = await app.inject({ method: 'POST', url: '/v1/membership/quote',
    headers: { authorization: 'Bearer other' }, payload: { sku: 'MONTHLY', userId: id, salesPilot: true } });
  assert.equal(forged.statusCode, 409);
  assert.equal(forged.json().code, 'MEMBERSHIP_NOT_ON_SALE');
  const superQuote = await app.inject({ method: 'POST', url: '/v1/membership/quote',
    headers: { authorization: 'Bearer pilot' }, payload: { sku: 'SUPER_LIFETIME' } });
  assert.equal(superQuote.json().code, 'CLOUD_NOT_CONFIGURED');
});
