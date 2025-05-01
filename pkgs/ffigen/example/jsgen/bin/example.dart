// ignore_for_file: unreachable_from_main
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import '../lib/generated_bindings.dart';


void main(List<String> args) async {
  print("Running WASM example");

  NativeLibrary.initBindings("module");
  
  final intPointer = Int32.stackAlloc(1);
  intPointer.setValue(11);
  assert(intPointer.getValue() == 11);

  final floatPointer = Float32.stackAlloc(1);
  floatPointer.setValue(5.0);
  assert(floatPointer.getValue() == 5.0, floatPointer.getValue());
  assert(sum(1, 2) == 3);
  assert(sum_with_typedef(1, 2) == 3);
  assert(subtract(intPointer, 2) == 9);
  assert((divide(10, 2).getValue() - 5.0).abs() < 0.0001);
  assert(divide_precision(floatPointer, floatPointer).getValue() == 1.0);
  var copy = copy_string('MY STRING'.toNativeUtf8());
  assert(copy.toDartString() == 'MY STRING', copy.toDartString());

  var myStruct = return_struct_by_value(10.0, copy);

  assert(myStruct.a == 10.0, myStruct.a);
  assert(myStruct.c == 2, myStruct.c);
  assert(myStruct.b.toDartString() == 'MY STRING', myStruct.b.toDartString());

  var ptr = MyStruct.stackAlloc();
  ptr.setFrom(MyStruct(20.0, Pointer<Char>(0 as Pointer<Char>), 8, ptr));
  assert(ptr.toDart().a == 20.0, ptr.toDart().a);

  var structArg = double3(1.0, 2.0, 3.0, ptr);
  assert(
      struct_as_argument(structArg) == 6, struct_as_argument(structArg));
  
  accept_struct_ptr(Pointer<Never>(0));
  
  print("structArgument done");
  assert(GLOBALINT.toString() == "9223372036854775808", GLOBALINT.toString());
  
  final bigIntFnResult = bigint_method(BigInt.parse("9223372036854775808"));
  assert(bigIntFnResult == BigInt.parse("9223372036854775809"), bigIntFnResult.toString());

  var done = false;
  void Function() callback = () {
    done = true;
  };

  
  final fnPtr = callback.addFunction();
  accept_fn_pointer_with_no_args(fnPtr);
  assert(done);
  
  done = false;
  print("voidFunctionArgument done");

  fnPtr.dispose();

  final fnPtr2 = (int intVal) {
    print(intVal + 10);
    done = true;
  }.addFunction();

  accept_fn_pointer_with_primitive_args(fnPtr2);

  fnPtr.dispose();

  assert(done);

  done = false;

  final fnPtr3 =  (Pointer<MyStruct> ptr) {
    done = true;
  }.addFunction();

  
  accept_fn_pointer_with_ptr_args(fnPtr3);
  done = false;
  accept_fn_typedef_arg(fnPtr3.cast());
  fnPtr3.dispose();

  assert(done);

  print("Function argument completed");
}

//   final ptrArray = module.stackAlloc<Int32>(2);
//   ptrArray.setValue(2);
//   (ptrArray + 1).setValue(3);
//   assert(ptrArray.getValue() == 2);
//   assert((ptrArray + 1).getValue() == 3, (ptrArray + 1).getValue());

//   var arrayPtr = module.return_array();
//   for (int i = 0; i < 4; i++) {
//     final val = (arrayPtr + i).getValue();
//     assert(val == (i + 1).toDouble());
//   }
//   var array = Array<Double>(4, arrayPtr.addr, module);

//   var len = array.asUint8List().length;
//   var arrayDoubleData = array
//       .asUint8List()
//       .buffer
//       .asFloat64List(array.asUint8List().offsetInBytes, array.numElements);
//   assert(arrayDoubleData[0] == 1.0, arrayDoubleData[0]);
//   assert(arrayDoubleData[1] == 2.0, arrayDoubleData[1]);
//   assert(arrayDoubleData[2] == 3.0, arrayDoubleData[2]);
//   assert(arrayDoubleData[3] == 4.0, arrayDoubleData[3]);

//   array.setValue(
//       Float64List.fromList([10.0, 11.0, 12.0, 13.0]).buffer.asUint8List());
//   for (int i = 0; i < 4; i++) {
//     final val = (arrayPtr + i).getValue();
//     assert(val == (i + 10).toDouble());
//   }
//   final ptrA = module.stackAlloc<Int32>(1);
//   ptrA.setValue(10);
//   final ptrptrA = module.stackAlloc<Pointer<Int32>>(1);
//   ptrptrA.setValue(ptrA);
//   assert(ptrptrA.getValue().getValue() == 10);
//   final ptrB = module.stackAlloc<Int32>(1);
//   ptrB.setValue(20);
//   final ptrptrB = module.stackAlloc<Pointer<Int32>>(1);
//   ptrptrB.setValue(ptrB);
//   var ptrptrResult = module.ptr_ptr(ptrptrA, ptrptrB);

//   print(
//       'addr 0 ${ptrptrResult.getValue().addr} addr 1 ${(ptrptrResult + 1).getValue().addr}');

//   final val1 = ptrptrResult.getValue().getValue();
//   assert(val1 == 20, val1);
//   final val2 = (ptrptrResult + 1).getValue().getValue();
//   assert(val2 == 10, val2);

//   print('Example completed');
// }
