import { compile } from './example.mjs';

const moduleJs = read('example_lib.js')
globalThis.eval(moduleJs);
globalThis['module'] = await example();
globalThis['printf'] = (v) => {
    console.log(v);
}
console.log(Object.keys(globalThis['module']));
console.log(typeof(globalThis['module']['HEAPU8']));

const wasmBytes = readbuffer('example.wasm');

async function runDartWasm() {
    const compiledApp = await compile(wasmBytes);
    const instantiatedApp = await compiledApp.instantiate({});
    instantiatedApp.invokeMain();
}

runDartWasm().catch(console.error);

