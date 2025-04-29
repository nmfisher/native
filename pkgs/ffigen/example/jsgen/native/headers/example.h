#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif


extern uint64_t GLOBALFO;
extern uint64_t TSWAP_CHAIN_CONFIG_HAS_STENCIL_BUFFER;

typedef void (*FunctionTypedef)(void *const owner);

typedef struct { 
    double x;
    double y; 
    double z;
} double3;

struct MyStruct { 
    float a;
    const char* b;
    int c;
};
typedef struct MyStruct MyStruct;

typedef struct MyOpaqueStruct MyOpaqueStruct;

struct StructWithArray {
    double foo[4];
};
typedef struct StructWithArray StructWithArray;

typedef int INTTYPE;

int sum(int a, int b);

INTTYPE sum_with_typedef(INTTYPE a, INTTYPE b);
int subtract(int *a, int b);
int *multiply(int a, int b);
float *divide(int a, int b);
double *divide_precision(float *a, float *b);

void accept_fn_typedef_arg(FunctionTypedef arg);
FunctionTypedef return_fn_typedef();

void Image_decodeRenderThread(uint8_t* data, size_t length, const char* name, void (*onComplete)(MyOpaqueStruct *));

double* return_array();

void *return_void_ptr();
void accept_void_ptr(void *arg);

int struct_as_argument(double3 vector);
MyStruct *return_struct_ptr();
void accept_struct_ptr(MyStruct *arg);
void accept_struct_with_array(StructWithArray arg);
StructWithArray return_struct_with_array_by_value();
MyStruct return_struct_by_value(float a, const char *b);

int **ptr_ptr(int **a, int **b);

const char* copy_string(const char *instr);

void accept_fn_pointer_with_no_args(void(*callback)());
void accept_fn_pointer_with_primitive_args(void(*callback)(int arg));
void accept_fn_pointer_with_ptr_args(void(*callback)(MyStruct *arg));
void accept_opaque_struct_ptr(MyOpaqueStruct *ptr);

enum MyEnum { 
    ENUM_VAL1,
    ENUM_VAL2,
};
typedef enum MyEnum MyEnum;
MyEnum return_enum();
int accept_enum(MyEnum val);

enum MyEnumAsInt { 
    ENUM_AS_INT_VAL1,
    ENUM_AS_INT_VAL2,
};

enum MyEnumAsInt return_enum_as_int();

#ifdef __cplusplus
}
#endif
