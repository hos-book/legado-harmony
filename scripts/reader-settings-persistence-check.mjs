import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${file}`, 'utf8');
const compile = text => stripTypeScriptTypes(text.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });

function harness() {
  const values = new Map([['appThemeId', 'classic-blue']]);
  const disk = new Map();
  let syncMarks = 0;
  let nextGate;
  const store = {
    get: async (key, fallback) => disk.has(key) ? disk.get(key) : fallback,
    put: async (key, value) => { disk.set(key, value); },
    flush: async () => {}
  };
  const context = vm.createContext({
    console,
    AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value) },
    preferences: { getPreferences: async () => {
      const gate = nextGate;
      nextGate = undefined;
      if (gate) await gate;
      return store;
    } },
    CloudSyncChangeTracker: { markPreferenceChanged() { syncMarks++; } },
    ReaderThemeHelper: {
      LIGHT_CUSTOM_BACKGROUND_COLOR: '#FFFFFF', LIGHT_CUSTOM_TEXT_COLOR: '#333333',
      DARK_CUSTOM_BACKGROUND_COLOR: '#121212', DARK_CUSTOM_TEXT_COLOR: '#CCCCCC',
      APP_THEME_INDEX: 0, normalizeIndex: value => value || 0
    },
    HexColor: { normalize: (value, fallback) => value || fallback }
  });
  vm.runInContext(compile(read('core/reader/ReaderInfoBarModel.ts')) + '\n' +
    compile(read('utils/ReaderSettingsStore.ets')) +
    '\n' + compile(read('account/ReaderPreferencesSync.ets')) +
    '\nglobalThis.api = { ReaderSettingsStore, ReaderSettings, ReaderInfoBarConfig, ReaderPreferencesSync };', context);
  const coordinator = read('account/CloudSyncCoordinator.ets');
  const remoteStart = coordinator.indexOf('      const remote = JSON.parse(raw) as ReaderPreferencesSyncPayload;');
  const remoteEnd = coordinator.indexOf("    } else if (entityType === 'replace_rule')", remoteStart);
  assert(remoteStart > 0 && remoteEnd > remoteStart);
  vm.runInContext(compile(`async function receive(raw: string): Promise<boolean> {
    const context = {};
    const entityState = { localKey: '' };
    const CloudSyncCoordinator = { readerSettingsBackfillPending: false };
    ${coordinator.slice(remoteStart, remoteEnd)}
    return CloudSyncCoordinator.readerSettingsBackfillPending;
  }
  globalThis.receiveReaderPreferences = receive;`), context);
  const { ReaderSettingsStore: settings, ReaderSettings, ReaderInfoBarConfig: Config } = context.api;
  settings.applyToStorage(new ReaderSettings());
  return { settings, Config, values, disk, sync: context.api.ReaderPreferencesSync,
    receive: context.receiveReaderPreferences,
    get syncMarks() { return syncMarks; },
    pauseNextAccess() {
      let release;
      nextGate = new Promise(resolve => { release = resolve; });
      return release;
    }
  };
}

const tests = {
  async 'all themes use the reading-preference sync scope'() {
    const coordinator = read('account/CloudSyncCoordinator.ets');
    stripTypeScriptTypes(coordinator, { mode: 'strip' });
    const start = coordinator.indexOf('  private static scopeAllows(');
    const end = coordinator.indexOf('  private static validateResponse(', start);
    const method = coordinator.slice(start, end).replace('private static scopeAllows', 'function scopeAllows');
    const allows = vm.runInNewContext(compile(method) + '\nscopeAllows;');
    const settings = { readingPreferencesEnabled: true, applicationPreferencesEnabled: false };
    for (const type of ['reader_settings', 'replace_rule', 'theme_settings', 'custom_theme_schemes']) {
      assert.equal(allows(settings, type), true, type);
      assert.equal(allows({ ...settings, readingPreferencesEnabled: false,
        applicationPreferencesEnabled: true }, type), false, type);
    }
  },
  async 'legacy cloud receive ignores device settings and keeps rules/themes'() {
    const h = harness();
    await h.settings.saveLayoutSettings({}, 29, 18, 6, 22, 24, 26, 28);
    const config = new h.Config();
    config.footerOffset = 9;
    await h.settings.saveReaderChromeSettings({}, true, true, config.serialize());
    const before = await h.settings.load({});
    const remote = { ...before, fontSize: 14, titleFontSize: 14, marginLeft: 0,
      readerHeaderEnabled: false, readerInfoBarConfig: '', volumeTurnPage: true,
      fontFamily: 'remote-font', fontFilePath: '/remote/font.ttf',
      regexFontEnabled: true, regexFontPattern: 'dialogue', regexFontSize: 24,
      lightCustomThemeBackgroundColor: '#112233' };
    assert.equal(await h.receive(JSON.stringify(remote)), true);
    const after = await h.settings.reload({});
    const allowed = Object.keys(h.sync.toPayload(before));
    for (const key of Object.keys(before).filter(key => !allowed.includes(key) && key !== 'themeIndex')) {
      assert.equal(after[key], before[key], `legacy receive must not change: ${key}`);
    }
    assert.equal(after.regexFontPattern, 'dialogue');
    assert.equal(after.lightCustomThemeBackgroundColor, '#112233');
    assert.equal(await h.receive(JSON.stringify(h.sync.toPayload(after))), false);
  },
  async 'sync payload contains only font rules and themes'() {
    const h = harness();
    const local = await h.settings.load({});
    const payload = h.sync.toPayload(local);
    const allowed = ['syncVersion', 'regexFontEnabled', 'regexFontPattern', 'regexFontMode',
      'regexFontFamily', 'regexFontSize', 'regexShadowColor', 'regexFontRulesRaw',
      'lightThemeIndex', 'darkThemeIndex', 'lightCustomThemeBackgroundColor', 'lightCustomThemeTextColor',
      'darkCustomThemeBackgroundColor', 'darkCustomThemeTextColor', 'customThemesRaw'];
    assert.deepEqual(Object.keys(payload).sort(), allowed.sort());
    const altered = JSON.parse(JSON.stringify(local));
    for (const key of Object.keys(altered).filter(key => !allowed.includes(key))) {
      altered[key] = typeof altered[key] === 'number' ? altered[key] + 3 :
        typeof altered[key] === 'boolean' ? !altered[key] : 'device-specific-value';
    }
    assert.equal(JSON.stringify(h.sync.toPayload(altered)), JSON.stringify(payload));
    const merged = h.sync.merge(local, { ...altered, regexFontPattern: 'dialogue', regexFontEnabled: true });
    for (const key of Object.keys(local).filter(key => !allowed.includes(key))) {
      assert.equal(merged[key], local[key], `legacy cloud field must stay local: ${key}`);
    }
    assert.equal(merged.regexFontPattern, 'dialogue');
    assert.equal(merged.regexFontEnabled, true);
  },
  async 'remote font rules preserve every unrelated local setting'() {
    const h = harness();
    await h.settings.saveLayoutSettings({}, 29, 18, 6, 22, 24, 26, 28);
    const config = new h.Config();
    config.footerOffset = 9;
    await h.settings.saveReaderChromeSettings({}, true, true, config.serialize());
    const before = await h.settings.load({});
    const remote = { ...before, fontSize: 14, titleFontSize: 14, marginLeft: 0,
      readerHeaderEnabled: false, readerInfoBarConfig: '', bodyFontFamily: 'other-device',
      regexFontEnabled: true, regexFontPattern: 'dialogue', regexFontSize: 24,
      regexFontRulesRaw: '{"version":3,"rules":[]}' };
    await h.settings.saveReaderFontRuleSettings({}, remote);
    const after = await h.settings.reload({});
    for (const key of Object.keys(before).filter(key => !key.startsWith('regex'))) {
      assert.equal(after[key], before[key], `font-rule receive must not modify: ${key}`);
    }
    assert.equal(after.regexFontPattern, 'dialogue');
    assert.equal(after.regexFontSize, 24);
    assert.equal(after.regexFontRulesRaw, remote.regexFontRulesRaw);
  },
  async 'local layout edits do not schedule cloud preference sync'() {
    const h = harness();
    await h.settings.saveLayoutSettings({}, 25, 12, 3);
    await h.settings.saveReaderChromeSettings({}, true, true, new h.Config().serialize());
    await h.settings.savePageTurnMode({}, 1);
    await h.settings.saveReadingInteractionSettings({}, true, 5, true);
    const style = await h.settings.load({});
    style.fontSize = 28;
    style.titleFontSize = 30;
    style.bodyFontFamily = 'local-font';
    await h.settings.saveReaderFontStyleSettings({}, style);
    assert.equal(h.syncMarks, 0);
    style.regexFontEnabled = true;
    style.regexFontPattern = 'dialogue';
    await h.settings.saveReaderFontStyleSettings({}, style);
    assert.equal(h.syncMarks, 1);
    const settings = await h.settings.load({});
    await h.settings.saveThemeSettings({}, settings.lightThemeIndex, settings.darkThemeIndex,
      settings.lightCustomThemeBackgroundColor, settings.lightCustomThemeTextColor,
      settings.darkCustomThemeBackgroundColor, settings.darkCustomThemeTextColor, false, settings.customThemesRaw);
    assert.equal(h.syncMarks, 2);
  },
  async 'reload retains the latest rapid typography edit'() {
    const h = harness();
    const release = h.pauseNextAccess();
    const first = h.settings.saveLayoutSettings({}, 24, 12, 0);
    const last = h.settings.saveLayoutSettings({}, 29, 18, 6);
    await new Promise(resolve => setImmediate(resolve));
    const reload = h.settings.reload({});
    await new Promise(resolve => setImmediate(resolve));
    release();
    await Promise.all([first, last]);
    const loaded = await reload;
    assert.equal(loaded.fontSize, 29);
    assert.equal(loaded.lineHeight, 18);
    assert.equal(loaded.paragraphSpacing, 6);
  },
  async 'reload waits for pending header/footer writes'() {
    const h = harness();
    await h.settings.saveReaderChromeSettings({}, false, true, new h.Config().serialize());
    const config = new h.Config();
    config.headerLeft = 'book';
    config.footerOffset = 9;
    config.progressBar = 'footer';
    const release = h.pauseNextAccess();
    const save = h.settings.saveReaderChromeSettings({}, true, true, config.serialize());
    // Let the queued write reach the paused preferences access.
    await new Promise(resolve => setImmediate(resolve));
    const reload = h.settings.reload({});
    await new Promise(resolve => setImmediate(resolve));
    release();
    await save;
    const loaded = await reload;
    assert.equal(loaded.readerHeaderEnabled, true);
    assert.equal(h.Config.parse(loaded.readerInfoBarConfig).footerOffset, 9);
    assert.equal(h.Config.parse(loaded.readerInfoBarConfig).progressBar, 'footer');
  },
  async 'late unrelated save preserves newer layout and header/footer settings'() {
    const h = harness();
    const release = h.pauseNextAccess();
    const oldSave = h.settings.saveKeepParagraphIndent({}, true);
    const config = new h.Config();
    config.headerLeft = 'book';
    config.footerOffset = 7;
    await h.settings.saveReaderChromeSettings({}, true, true, config.serialize());
    await h.settings.saveLayoutSettings({}, 27, 16, 4, 21, 23, 25, 26, 2, 'start');
    release();
    await oldSave;
    // Simulate returning to the reader after switching day/night mode.
    h.values.set('appDarkMode', true);
    let loaded = await h.settings.reload({});
    assert.equal(loaded.fontSize, 27);
    assert.equal(h.Config.parse(loaded.readerInfoBarConfig).footerOffset, 7);
    h.values.set('appDarkMode', false);
    loaded = await h.settings.reload({});
    assert.equal(loaded.fontSize, 27);
    assert.equal(loaded.keepParagraphIndent, true);
    assert.equal(loaded.readerHeaderEnabled, true);
  },
  async 'theme profiles remain independent after queued saves'() {
    const h = harness();
    await h.settings.saveLayoutSettings({}, 27, 16, 4);
    h.values.set('appThemeId', 'other-theme');
    await h.settings.switchThemeProfile({}, 'classic-blue', 'other-theme');
    await h.settings.saveLayoutSettings({}, 19, 10, 2);
    const config = new h.Config();
    config.headerLeft = 'book';
    const release = h.pauseNextAccess();
    const save = h.settings.saveReaderChromeSettings({}, true, true, config.serialize());
    await new Promise(resolve => setImmediate(resolve));
    h.values.set('appThemeId', 'classic-blue');
    const switched = h.settings.switchThemeProfile({}, 'other-theme', 'classic-blue');
    release();
    await save;
    assert.equal((await switched).fontSize, 27);
    h.values.set('appThemeId', 'other-theme');
    const loaded = await h.settings.switchThemeProfile({}, 'classic-blue', 'other-theme');
    assert.equal(loaded.fontSize, 19);
    assert.equal(loaded.readerHeaderEnabled, true);
    assert.equal(h.Config.parse(loaded.readerInfoBarConfig).headerLeft, 'book');
  }
};

let failures = 0;
for (const [name, test] of Object.entries(tests)) {
  try { await test(); console.log(`PASS: ${name}`); }
  catch (error) { failures++; console.error(`FAIL: ${name}\n${error.stack}`); }
}
if (failures) process.exitCode = 1;
