import { readFile } from 'fs/promises';
import { compile } from './example.mjs';
import example from './example_lib.js';
console.log(example);

async function runDartWasm() {
    globalThis['module'] = await example();

    const wasmBytes = await readFile('example.wasm');
    const compiledApp = await compile(wasmBytes);
    const instantiatedApp = await compiledApp.instantiate({});
    instantiatedApp.invokeMain();
}

runDartWasm().catch(console.error);

