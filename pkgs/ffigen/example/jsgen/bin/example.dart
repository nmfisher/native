import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import '../lib/generated_bindings.dart';

void main(List<String> args) {
  print("Running WASM example");

  final module = globalContext.getProperty('module'.toJS) as NativeLibrary;

  // final intPointer = module.stackAlloc<Int32>(1);
  // intPointer.setValue(11);
  // final floatPointer = module.stackAlloc<Float>(1);
  // floatPointer.setValue(0.1);

  // assert((floatPointer.getValue() - 0.1).abs() < 0.00001);
  // assert(module.sum(1, 2) == 3);

  // assert(module.subtract(intPointer, 2) == 9);

  // assert((module.divide(10, 2).getValue() - 5.0).abs() < 0.0001);

  // var result = module.dividePrecision(floatPointer, floatPointer);
  // assert(result.getValue() == 1.0);

  // var copy = module.copy_string('MY STRING'.toNativePointer(module));
  // assert(copy.getValue() == 'MY STRING', copy.getValue());

  // var myStruct = module.returnStructByValue(10.0, copy);
  // assert(myStruct.a == 10.0);
  // assert(myStruct.b.getValue() == 'MY STRING', myStruct.b.getValue());

  // var structArg = double3(1.0, 2.0, 3.0);
  // assert(
  //     module.structArgument(structArg) == 6, module.structArgument(structArg));
  // print("structArgument");
  // var done = false;
  // module.voidFunctionArgument(() {
  //   done = true;
  // });
  // done = false;

  // module.functionArgument((intVal) {
  //   print(intVal + 10);
  //   done = true;
  // });
  // assert(done);

  // print("Function argument completed");

  // final ptrArray = module.stackAlloc<Int32>(2);
  // ptrArray.setValue(2);
  // (ptrArray + 1).setValue(3);
  // assert(ptrArray.getValue() == 2);
  // assert((ptrArray + 1).getValue() == 3, (ptrArray + 1).getValue());

  final ptrA = module.stackAlloc<Int32>(1);
  ptrA.setValue(10);
  final ptrptrA = module.stackAlloc<Pointer<Int32>>(1);
  ptrptrA.setValue(ptrA);
  assert(ptrptrA.getValue().getValue() == 10);
  final ptrB = module.stackAlloc<Int32>(1);
  ptrB.setValue(20);
  final ptrptrB = module.stackAlloc<Pointer<Int32>>(1);
  ptrptrB.setValue(ptrB);
  var ptrptrResult = module.ptr_ptr(ptrptrA, ptrptrB);

  print(
      'addr 0 ${ptrptrResult.getValue().addr} addr 1 ${(ptrptrResult +1).getValue().addr}');

  final val1 = ptrptrResult.getValue().getValue();
  assert(val1 == 20, val1);
  final val2 = (ptrptrResult + 1).getValue().getValue();
  assert(val2 == 10, val2);

  print('Example completed');
}
