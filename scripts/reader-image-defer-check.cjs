// Exercise the actual host image-materialization boundary without a network/device.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(path.join(process.env.DEVECO_HOME,
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const engine = process.env.SOURCE_ENGINE_ROOT || path.resolve(__dirname, '../harmony-book-source-engine');
const compile = code => ts.transpileModule(code, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
} }).outputText;
function load(relative) {
  const exports = {};
  const filename = [path.join(engine, 'sourceengine/src/main/ets', relative),
    path.resolve(__dirname, '../entry/src/main/ets', relative)].find(fs.existsSync);
  vm.runInNewContext(compile(fs.readFileSync(filename, 'utf8')),
    { exports, require: () => ({}), console });
  return exports;
}
const { SourceEngineHost } = load('core/host/SourceEngineHost.ts');
const { ReaderImageMarker } = load('core/book/ReaderImageMarker.ts');
const text = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/core/book/WebBookService.ts'), 'utf8');
const method = text.match(/^  private async materializeReaderImageMarkers\([\s\S]*?^  \}/m)[0];
const calls = [];
const scope = { SourceEngineHost, ReaderImageMarker, HttpClient: { CANCELLED_ERROR: 'cancelled' },
  console, ComicImagePipeline: { materialize: async (_http, _source, url, force, cancelled, index) => {
    assert.equal(force, true); assert.equal(cancelled(), false); calls.push(url);
    return `/cache/${index}.png`;
  } } };
vm.runInNewContext(compile(`class Reader { ${method} }
globalThis.reader = new Reader();`), scope);
scope.reader.escapeRegex = text => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
(async () => {
  const source = {};
  const url = 'https://images.test/1.jpg,' + JSON.stringify({ headers: { Referer: 'https://source.test' },
    decode: { script: 'restoreJmImage', processPlainImages: true, params: { aid: 123 } }, imageIndex: 7 });
  const content = ReaderImageMarker.create(url, 800, 1200);
  SourceEngineHost.setReaderImagesDeferred(source, true);
  assert.equal(await scope.reader.materializeReaderImageMarkers(source, content), content);
  assert.equal(calls.length, 0, 'deferred content never downloads chapter images');
  assert.equal(ReaderImageMarker.parse(content).source, url, 'headers, decoding params and image index survive');
  await assert.rejects(scope.reader.materializeReaderImageMarkers(source, content, () => true), /cancelled/);
  SourceEngineHost.setReaderImagesDeferred(source, false);
  const output = await scope.reader.materializeReaderImageMarkers(source, ReaderImageMarker.create(url));
  assert.equal(calls.length, 1, 'default download/export behavior still materializes images');
  assert.equal(ReaderImageMarker.parse(output).source, '/cache/0.png');
  console.log('reader image defer: opt-in list, URL options, cancellation and default materialization passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
