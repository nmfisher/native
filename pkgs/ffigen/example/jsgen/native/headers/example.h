// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

typedef void (*FunctionTypedef)(void *const owner);

typedef struct { 
    double x;
    double y; 
    double z;
} double3;

struct MyStruct { 
    float a;
    const char* b;
};
typedef struct MyStruct MyStruct;
struct StructWithArray {
    double foo[4];
};
typedef struct StructWithArray StructWithArray;

typedef int INTTYPE;

/** Adds 2 integers. */
int sum(int a, int b);

INTTYPE sum_with_typedef(INTTYPE a, INTTYPE b);

void accept_fn_typedef_arg(FunctionTypedef arg);
FunctionTypedef return_fn_typedef();

double* return_array();

void accept_struct_with_array(StructWithArray arg);
StructWithArray return_struct_with_array_by_value();
void *return_void_ptr();
void accept_void_ptr(void *arg);

MyStruct *return_struct_ptr();

void accept_struct_ptr(MyStruct *arg);

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

MyStruct returnStructByValue(float a, const char *b);

int structArgument(double3 vector);

void voidFunctionArgument(void(*callback)());
void primitiveFunctionArgument(void(*callback)(int arg));
void nonPrimitiveFunctionArgument(void(*callback)(MyStruct *arg));

enum MyEnum { 
    ENUM_VAL1,
    ENUM_VAL2,
};
typedef enum MyEnum MyEnum;

MyEnum returnEnum();

int acceptEnum(MyEnum val);


