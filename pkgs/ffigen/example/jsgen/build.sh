mkdir -p build
dart compile wasm --enable-asserts  bin/example.dart -o build/example.wasm || exit -1;
cd build
emcc --no-entry \
    -I../native/headers \
    -sENVIRONMENT=shell,node \
    -sWASM_BIGINT=1 \
    -sALLOW_MEMORY_GROWTH=1 \
    -sALLOW_TABLE_GROWTH=1 \
    -sEXPORT_NAME=example \
    -sMODULARIZE \
    -sEXPORTED_RUNTIME_METHODS=wasmExports,wasmTable,addFunction,removeFunction,ccall,cwrap,allocate,intArrayFromString,intArrayToString,getValue,setValue,UTF8ToString,stringToUTF8,writeArrayToMemory,lengthBytesUTF8 \
    -sEXPORTED_FUNCTIONS=_malloc,stackAlloc,_free \
    -sFULL_ES3 \
    -o example_lib.js \
    ../native/src/example.c || exit -1;
cp ../native/js/main.js .
node main.js