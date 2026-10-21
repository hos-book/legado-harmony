// Run the actual page actions and database transaction against an in-memory RDB adapter.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const page = fs.readFileSync(`${projectRoot}/entry/src/main/ets/pages/BookSource.ets`, 'utf8');
const database = fs.readFileSync(`${projectRoot}/entry/src/main/ets/model/data/AppDatabase.ts`, 'utf8');
function method(source, name) {
  const match = new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm').exec(source);
  assert(match, name);
  const end = source.indexOf('\n  }', match.index);
  assert(end > match.index);
  return source.slice(match.index, end + '\n  }'.length).replace('private ', '');
}
const compile = text => stripTypeScriptTypes(text, { mode: 'strip' });
const seed = (url, order, overrides = {}) => ({
  bookSourceUrl: url, bookSourceName: url, customOrder: order,
  lastUpdateTime: order, isPinned: 0, isBottom: 0, ...overrides
});

function harness(initial) {
  let rows = initial.map(row => ({ ...row }));
  let failWrite = false;
  const toasts = [];
  const values = new Map();
  class Predicates {
    conditions = [];
    equalTo(key, value) { this.conditions.push([key, value]); return this; }
    matches(row) { return this.conditions.every(([key, value]) => row[key] === value); }
  }
  const store = {
    async createTransaction() {
      const pending = rows.map(row => ({ ...row }));
      let writes = 0;
      return {
        async update(bucket, predicates) {
          // Fail after a partial write, exercising transaction rollback rather than only early failure.
          if (failWrite && ++writes === 2) throw new Error('simulated write failure');
          for (const row of pending) if (predicates.matches(row)) Object.assign(row, bucket);
        },
        async commit() { rows = pending; },
        async rollback() {}
      };
    },
    async query(predicates) {
      const found = rows.filter(row => predicates.matches(row));
      let index = -1;
      return {
        goToNextRow: () => ++index < found.length,
        getColumnIndex: name => name,
        getString: key => found[index][key],
        close() {}
      };
    }
  };
  const context = vm.createContext({
    console: { error() {} },
    BookSource: class {},
    relationalStore: { RdbPredicates: Predicates },
    CloudSyncChangeTracker: { markBookSourceChanged() {} },
    HdsFeedback: { showToast: text => toasts.push(text) },
    AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value) }
  });
  vm.runInContext(compile(`
    globalThis.db = {
      ${method(database, 'updateBookSourceOrders')},
      ${method(database, 'getBottomBookSourceUrls')}
    };
    globalThis.AppDatabase = { getInstance: () => db };
    globalThis.page = {
      ${['isSourceAtBottom', 'actionSourceAtBottom', 'sortFilteredSources',
        'toggleActionSourceBottom', 'toggleActionSourcePinned', 'moveVisibleSourceTo',
        'applyAndPersistSourceOrder', 'copyBookSourceRuntime'].map(name => method(page, name)).join(',\n')}
    };
  `), context);
  const p = context.page;
  context.db.store = store;
  Object.assign(p, {
    isBatchOperating: false, sourceOrderSaving: false, sourceSortMode: 'custom',
    sourceFirstVisibleIndex: 0, sourceVisibleItemCount: 1, draggingSourceUrl: '',
    actionSource() { return this.allSources.find(source => source.bookSourceUrl === this.actionSourceUrl); },
    closeSourceActions() { this.actionSourceUrl = ''; },
    applySourceFilters() {
      this.sources = this.sortFilteredSources(this.allSources);
      this.visibleSources = this.sources;
    },
    restoreSourceListViewport() {}
  });
  async function reload() {
    p.allSources = rows.map(row => ({ ...row, isPinned: row.isPinned === 1 }));
    p.bottomSourceUrls = await context.db.getBottomBookSourceUrls();
    p.applySourceFilters();
  }
  return {
    p, reload, toasts,
    rows: () => JSON.parse(JSON.stringify(rows)),
    fail: () => { failWrite = true; },
    async action(url, name = 'toggleActionSourceBottom') {
      p.actionSourceUrl = url;
      await p[name]();
    },
    urls: () => Array.from(p.sources, source => source.bookSourceUrl)
  };
}

// Ordinary last row (including a one-source library) is never implicitly bottom-pinned.
for (const initial of [[seed('Only', 0)], [seed('Z', 0), seed('A', 1)]]) {
  const h = harness(initial);
  await h.reload();
  assert(h.p.allSources.every(source => !h.p.isSourceAtBottom(source)));
  h.p.sourceSortMode = 'name';
  h.p.applySourceFilters();
  assert.deepEqual(h.urls(), initial.map(row => row.bookSourceUrl).sort());
}

const h = harness([seed('Pinned', 0, { isPinned: 1 }), seed('A', 1), seed('B', 2), seed('C', 3)]);
await h.reload();
await h.action('A');
assert.deepEqual(h.urls(), ['Pinned', 'B', 'C', 'A']);
assert.equal(h.rows().find(row => row.bookSourceUrl === 'A').isBottom, 1);
await h.reload(); // Reopening the page retains explicit state.
h.p.actionSourceUrl = 'A';
assert.equal(h.p.actionSourceAtBottom(), true);
for (const mode of ['custom', 'name', 'oldest', 'latest']) {
  h.p.sourceSortMode = mode;
  h.p.applySourceFilters();
  assert.equal(h.urls()[0], 'Pinned');
  assert.equal(h.urls().at(-1), 'A');
}
h.p.sourceSortMode = 'custom';
await h.action('B');
assert.deepEqual(h.urls(), ['Pinned', 'C', 'A', 'B']);
await h.p.moveVisibleSourceTo(3, 2); // Reordering within the bottom group preserves both flags.
assert.deepEqual(h.urls(), ['Pinned', 'C', 'B', 'A']);
assert.equal(h.rows().find(row => row.bookSourceUrl === 'A').isBottom, 1);
assert.equal(h.rows().find(row => row.bookSourceUrl === 'B').isBottom, 1);
await h.action('A'); // Cancel just A; other bottom-pinned sources retain their state.
assert.deepEqual(h.urls(), ['Pinned', 'A', 'C', 'B']);
assert.equal(h.rows().find(row => row.bookSourceUrl === 'A').isBottom, 0);
await h.action('B', 'toggleActionSourcePinned');
assert.equal(h.rows().find(row => row.bookSourceUrl === 'B').isBottom, 0);
assert.equal(h.rows().find(row => row.bookSourceUrl === 'B').isPinned, 1);
await h.action('B'); // Bottom and top are mutually exclusive.
assert.equal(h.rows().find(row => row.bookSourceUrl === 'B').isPinned, 0);
assert.equal(h.rows().find(row => row.bookSourceUrl === 'B').isBottom, 1);
await h.p.moveVisibleSourceTo(h.urls().indexOf('B'), 1);
assert.equal(h.rows().find(row => row.bookSourceUrl === 'B').isBottom, 0);
assert.deepEqual(h.urls(), ['Pinned', 'B', 'A', 'C']);

// Being last already still supports explicit bottom -> cancel; one-source lists also work.
for (const initial of [[seed('Only', 0)], [seed('A', 0), seed('B', 1)]]) {
  const single = harness(initial);
  await single.reload();
  const url = initial.at(-1).bookSourceUrl;
  await single.action(url);
  await single.reload();
  assert.equal(single.rows().find(row => row.bookSourceUrl === url).isBottom, 1);
  await single.action(url);
  assert.equal(single.rows().find(row => row.bookSourceUrl === url).isBottom, 0);
}

// Partial storage failures restore both flags and the visible order, including cancellation.
for (const bottom of [0, 1]) {
  const broken = harness([seed('A', 5, { isBottom: bottom }), seed('B', 10)]);
  await broken.reload();
  const before = broken.rows();
  const order = broken.urls();
  broken.fail();
  await broken.action('A');
  assert.deepEqual(broken.rows(), before);
  assert.deepEqual(broken.urls(), order);
  assert.equal(broken.p.isSourceAtBottom(broken.p.allSources[0]), bottom === 1);
  assert.equal(broken.p.sourceOrderSaving, false);
  assert.equal(broken.toasts.at(-1), '保存排序失败');
}

// The menu must expose the inverse action for persisted explicit state.
assert.match(page, /this\.actionSourceAtBottom\(\) \? '取消置底' : '置底'/);
assert.match(database, /column: 'isBottom', definition: 'isBottom INTEGER DEFAULT 0'/);
console.log('Book source position checks passed: explicit state, cancel, reload, sorting, drag, mutual exclusion, rollback.');
