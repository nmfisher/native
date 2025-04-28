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

INTTYPE EMSCRIPTEN_KEEPALIVE sum_with_typedef(INTTYPE a, INTTYPE b) {
    return a + b;
}

int EMSCRIPTEN_KEEPALIVE subtract(int *a, int b) {
    return *a - b;
}

int *EMSCRIPTEN_KEEPALIVE multiply(int a, int b) {
    int *result = (int *)malloc(sizeof(int));
    *result = a * b;
    return result;
}

float *EMSCRIPTEN_KEEPALIVE divide(int a, int b) {
    float *result = (float *)malloc(sizeof(float));
    *result = (float)a / b;
    return result;
}

double EMSCRIPTEN_KEEPALIVE *  return_array() {
    double *arr = (double*)malloc(sizeof(double) * 4);
    arr[0] = 1.0;
    arr[1] = 2.0;
    arr[2] = 3.0;
    arr[3] = 4.0;
    return arr;
}

int ** EMSCRIPTEN_KEEPALIVE ptr_ptr(int **a, int **b) {
    int **out = (int **)malloc(sizeof(int*) * 2);
    out[0] = (int *)malloc(sizeof(int*));
    out[1] = (int *)malloc(sizeof(int*));
    *out[0] = **b;
    *out[1] = **a;
    return out;
}

double *EMSCRIPTEN_KEEPALIVE divide_precision(float *a, float *b) {
    double *result = (double *)malloc(sizeof(double));
    *result = (double)*a / (double)*b;
    return result;
}

const char *EMSCRIPTEN_KEEPALIVE copy_string(const char *instr) {
    const char * outstr = (char*)malloc(strlen(instr) + 1);
    strcpy(outstr, instr);
    return outstr;
}

MyStruct EMSCRIPTEN_KEEPALIVE return_struct_by_value(float a, const char *b) {
    MyStruct result;
    result.a = a;
    char *str_copy = (char *)malloc(strlen(b) + 1);
    strcpy(str_copy, b);
    result.b = str_copy;
    return result;
}

int EMSCRIPTEN_KEEPALIVE struct_as_argument(double3 vector) {
    return (int)(vector.x + vector.y + vector.z);
}

void EMSCRIPTEN_KEEPALIVE accept_fn_pointer_with_no_args(void(*callback)()) {
    callback();
}

void EMSCRIPTEN_KEEPALIVE accept_fn_typedef_arg(FunctionTypedef arg) {
    arg(NULL);
}

void EMSCRIPTEN_KEEPALIVE accept_fn_pointer_with_primitive_args(void(*callback)(int arg)) {
    if (callback != NULL) {
        callback(42);
    }
}

void EMSCRIPTEN_KEEPALIVE accept_fn_pointer_with_ptr_args(void(*callback)(MyStruct *arg)) {
    callback(NULL);
}

MyEnum EMSCRIPTEN_KEEPALIVE returnEnum() {
    return ENUM_VAL1;
}

int EMSCRIPTEN_KEEPALIVE acceptEnum(MyEnum val) {
    switch(val) {
        case ENUM_VAL1:
            return 0;
        case ENUM_VAL2:
            return 1;
    }
}


