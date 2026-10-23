import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${file}`, 'utf8');
const compile = text => stripTypeScriptTypes(text.replace(/^import [\s\S]*?;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });
// The graphics enum is deliberately zero-based like the SDK, unlike ArkUI's numeric font weight.
const context = vm.createContext({
  graphicsText: { FontWeight: Object.fromEntries(Array.from({ length: 9 }, (_, i) => [`W${(i + 1) * 100}`, i])) },
  ReaderCommentBubbleStyle: class { identity() { return 'bubble'; } }
});
const typography = read('components/reader/ReaderLayoutSettings.ets');
const fields = typography.slice(typography.indexOf('export class ReaderTypographyField'), typography.indexOf('/**\n * 正文排版') > 0 ?
  typography.indexOf('/**\n * 正文排版') : typography.indexOf('/**\r\n * 正文排版'));
vm.runInContext([
  'core/reader/ReaderFontWeight.ts', 'core/reader/ReaderV2LayoutSnapshot.ets',
  'core/reader/ReaderV2PageLayout.ets', 'core/reader/ReaderV2Style.ets', 'core/reader/ReaderV2Paginator.ets'
].map(file => compile(read(file))).join('\n') + '\n' + compile(fields) + `
  globalThis.api = { ReaderFontWeight, ReaderTypographyField, ReaderV2LayoutInput,
    ReaderV2LayoutSnapshot, ReaderV2Paginator, ReaderV2SpanStyleRange };
`, context);
const { ReaderFontWeight: Weight, ReaderTypographyField: Field, ReaderV2LayoutInput: Input,
  ReaderV2LayoutSnapshot: Snapshot, ReaderV2Paginator: Paginator, ReaderV2SpanStyleRange: Range } = context.api;

for (const [value, expected] of [[undefined, 400], [NaN, 400], [Infinity, 400], [-5, 100], [940, 900], [649, 600], [650, 700]]) {
  assert.equal(Weight.normalize(value), expected);
}
assert.equal(Field.LABELS[Field.FONT_WEIGHT], '字体粗细');
assert.equal(Field.FONT_WEIGHT, Field.FONT_SIZE + 1);
assert.equal(Field.step(Field.FONT_WEIGHT), 100);
assert.equal(Field.min(Field.FONT_WEIGHT), 100);
assert.equal(Field.max(Field.FONT_WEIGHT), 900);
assert.equal(Field.clamp(Field.FONT_WEIGHT, 649), 600);
assert.equal(Field.step(Field.FONT_SIZE), 1);
assert.equal(Field.clamp(Field.FONT_SIZE, 100), 50);
console.log('PASS: typography range, steps and input normalization');

const input = new Input();
input.viewportWidthPx = 800;
input.viewportHeightPx = 1200;
const original = Snapshot.create(input);
assert.equal(original.fontWeight, 400);
const block = { title: false, headingLevel: 0, text: '前文特殊字体后文', displayStart: 0 };
const document = { actions: [] };
const rule = new Range(2, 6);
rule.fontFamily = 'custom-face';
rule.fontSizePx = 48;
const identities = new Set();
for (let weight = 100; weight <= 900; weight += 100) {
  input.fontWeight = weight;
  const snapshot = Snapshot.create(input);
  identities.add(snapshot.identity);
  assert.equal(Paginator.baseTextStyle(block, snapshot).fontWeight, weight / 100 - 1);
  const styled = Paginator.styleAt(document, block, 3, snapshot, [rule]);
  assert.equal(styled.fontWeight, weight / 100 - 1);
  assert.equal(styled.fontFamilies[0], 'custom-face');
  assert.equal(styled.fontSize, 48);
  for (const heading of [{ ...block, title: true }, { ...block, headingLevel: 2 }]) {
    assert.equal(Paginator.baseTextStyle(heading, snapshot).fontWeight, 5);
    assert.equal(Paginator.buildSelectionRuns(document, heading, snapshot, [], 0, block.text.length)[0].fontWeight, 600);
  }
  const runs = Paginator.buildSelectionRuns(document, block, snapshot, [rule], 0, block.text.length);
  assert.equal(runs.map(run => run.text).join(''), block.text);
  assert(runs.every(run => run.fontWeight === weight));
  assert.equal(runs[1].fontFamily, 'custom-face');
}
assert.equal(identities.size, 9, 'weight changes must invalidate layout/page/selection caches');
assert.equal(original.fontWeight, 400, 'existing snapshots stay immutable when input changes');
console.log('PASS: all nine weights reach body and regex styles, selection metadata and cache identities; headings stay at 600');

// Execute the settings page's real handlers so insertion cannot silently shift the other typography controls.
const settingsPage = read('pages/Settings.ets');
const methods = settingsPage.slice(settingsPage.indexOf('  typographySettingOptions():'), settingsPage.indexOf('  setCurrentThemeBackgroundColor('));
const fontSetter = settingsPage.slice(settingsPage.indexOf('  setReaderFontWeight('), settingsPage.indexOf('  setReaderLetterSpacing('));
context.ReaderTypographyField = Field;
context.ReaderFontWeight = Weight;
vm.runInContext(compile(`class Controls {
  typographySettingIndex = 0;
  readerFontWeight = 400;
  readerFontSize = 20;
  readerLetterSpacing = 2;
  readerLineHeight = 12;
  readerParagraphSpacing = 4;
  readerMarginLeft = 18;
  readerMarginRight = 19;
  readerMarginTop = 20;
  readerMarginBottom = 21;
  saves = 0;
  saveReaderLayoutSettings() { this.saves++; }
  ${fontSetter}
  ${methods}
}
globalThis.controls = new Controls();`), context);
const controls = context.controls;
const options = controls.typographySettingOptions();
for (const [field, label] of [[Field.MARGIN_LEFT, '左边距'], [Field.MARGIN_RIGHT, '右边距'],
  [Field.MARGIN_TOP, '上边距'], [Field.MARGIN_BOTTOM, '下边距']]) {
  assert.equal(options[field]?.value, label, `Settings dropdown must expose ${label}`);
}
controls.typographySettingIndex = Field.FONT_WEIGHT;
controls.adjustCurrentTypographySetting(1);
assert.equal(controls.readerFontWeight, 500);
controls.adjustCurrentTypographySetting(-1);
assert.equal(controls.readerFontWeight, 400);
controls.openTypographyValueInput();
controls.typographyValueDraft = '649';
controls.applyTypographyValueInput();
assert.equal(controls.readerFontWeight, 600);
assert.equal(controls.saves, 3);
for (const [field, expected] of [[Field.LETTER_SPACING, 2], [Field.LINE_HEIGHT, 12], [Field.PARAGRAPH_SPACING, 4],
  [Field.MARGIN_LEFT, 18], [Field.MARGIN_RIGHT, 19], [Field.MARGIN_TOP, 20], [Field.MARGIN_BOTTOM, 21]]) {
  controls.typographySettingIndex = field;
  assert.equal(controls.currentTypographySettingValue(), expected);
}
console.log('PASS: settings handlers step by 100, normalize input and preserve all existing control mappings');
