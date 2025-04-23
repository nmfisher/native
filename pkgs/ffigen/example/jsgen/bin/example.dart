import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import '../lib/generated_bindings.dart';

void main(List<String> args) {
  print("Running WASM example");

  final module = globalContext.getProperty('module'.toJS) as NativeLibrary;

  final intPointer = module.stackAlloc<Int32>(1);
  intPointer.setValue(11);
  final floatPointer = module.stackAlloc<Float>(1);
  floatPointer.setValue(0.1);

  assert((floatPointer.getValue() - 0.1).abs() < 0.00001);
  assert(module.sum(1, 2) == 3);

  assert(module.subtract(intPointer, 2) == 9);

  assert((module.divide(10, 2).getValue() - 5.0).abs() < 0.0001);

  var result = module.dividePrecision(floatPointer, floatPointer);
  assert(result.getValue() == 1.0);

  var copy = module.copy_string('MY STRING'.toNativePointer(module));
  assert(copy.getValue() == 'MY STRING', copy.getValue());

  var myStruct = module.returnStructByValue(10.0, copy);
  assert(myStruct.a == 10.0);
  assert(myStruct.b.getValue() == 'MY STRING', myStruct.b.getValue());

  var structArg = double3(1.0, 2.0, 3.0);
  assert(module.structArgument(structArg) == 6, module.structArgument(structArg));

  print('Example completed');
}
