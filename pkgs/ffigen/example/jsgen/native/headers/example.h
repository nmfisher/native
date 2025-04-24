// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

typedef struct { 
    double x;
    double y; 
    double z;
} double3;

typedef int INTTYPE;

/** Adds 2 integers. */
int sum(int a, int b);

INTTYPE sum_with_typedef(INTTYPE a, INTTYPE b);

int **ptr_ptr(int **a, int **b);

/** Subtracts 2 integers. */
int subtract(int *a, int b);

/** Multiplies 2 integers, returns pointer to an integer,. */
int *multiply(int a, int b);

/** Divides 2 integers, returns pointer to a float. */
float *divide(int a, int b);

/** Divides 2 floats, returns a pointer to double. */
double *dividePrecision(float *a, float *b);

const char* copy_string(const char *instr);

struct MyStruct { 
    float a;
    const char* b;
};
typedef struct MyStruct MyStruct;

MyStruct returnStructByValue(float a, const char *b);

int structArgument(double3 vector);

void voidFunctionArgument(void(*callback)());
void functionArgument(void(*callback)(int arg));

enum MyEnum { 
    ENUM_VAL1,
    ENUM_VAL2,
};
typedef enum MyEnum MyEnum;

MyEnum returnEnum();

int acceptEnum(MyEnum val);


