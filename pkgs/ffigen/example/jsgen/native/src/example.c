// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <emscripten.h>
#include <emscripten/console.h>
#include "example.h"



/** Adds 2 integers. */
int EMSCRIPTEN_KEEPALIVE sum(int a, int b) {
    return a + b;
}

/** Subtracts 2 integers. */
int EMSCRIPTEN_KEEPALIVE subtract(int *a, int b) {
    return *a - b;
}

/** Multiplies 2 integers, returns pointer to an integer. */
int *EMSCRIPTEN_KEEPALIVE multiply(int a, int b) {
    int *result = (int *)malloc(sizeof(int));
    *result = a * b;
    return result;
}

/** Divides 2 integers, returns pointer to a float. */
float *EMSCRIPTEN_KEEPALIVE divide(int a, int b) {
    float *result = (float *)malloc(sizeof(float));
    *result = (float)a / b;
    return result;
}

/** Divides 2 floats, returns a pointer to double. */
double *EMSCRIPTEN_KEEPALIVE dividePrecision(float *a, float *b) {
    double *result = (double *)malloc(sizeof(double));
    *result = (double)*a / (double)*b;
    return result;
}

const char *EMSCRIPTEN_KEEPALIVE copy_string(const char *instr) {
    const char * outstr = (char*)malloc(strlen(instr) + 1);
    strcpy(outstr, instr);
    return outstr;
}

MyStruct EMSCRIPTEN_KEEPALIVE returnStructByValue(float a, const char *b) {
    emscripten_console_log("returnStructByValue");
    MyStruct result;
    result.a = a;
    
    // Allocate and copy the string to ensure it persists
    char *str_copy = (char *)malloc(strlen(b) + 1);
    emscripten_console_logf("ptr : %d", str_copy);
    strcpy(str_copy, b);
    result.b = str_copy;
    
    return result;
}

int EMSCRIPTEN_KEEPALIVE structArgument(double3 vector) {
    return vector.x + vector.y + vector.z;
}

void EMSCRIPTEN_KEEPALIVE functionArgument(void(*callback)(int arg)) {
    // Call the function pointer with some value
    if (callback != NULL) {
        callback(42);
    }
}