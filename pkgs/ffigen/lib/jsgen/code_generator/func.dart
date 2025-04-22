// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:math';

import '../code_generator.dart';
import '../config_provider/config_types.dart';

import 'binding_string.dart';
import 'utils.dart';
import 'writer.dart';

/// A binding for C function.
///
/// For example, take the following C function.
///
/// ```c
/// int sum(int a, int b);
/// ```
///
/// The generated Dart code for this function (without `FfiNative`) is as
/// follows.
///
/// ```dart
/// int sum(int a, int b) {
///   return _sum(a, b);
/// }
///
/// final _dart_sum _sum = _dylib.lookupFunction<_c_sum, _dart_sum>('sum');
///
/// typedef _c_sum = ffi.Int32 Function(ffi.Int32 a, ffi.Int32 b);
///
/// typedef _dart_sum = int Function(int a, int b);
/// ```
///
/// When using `Native`, the code is as follows.
///
/// ```dart
/// @ffi.Native<ffi.Int32 Function(ffi.Int32 a, ffi.Int32 b)>('sum')
/// external int sum(int a, int b);
/// ```
class Func extends LookUpBinding {
  final FunctionType functionType;
  final bool exposeSymbolAddress;
  final bool exposeFunctionTypedefs;
  final bool isLeaf;
  final bool objCReturnsRetained;
  final bool useNameForLookup;
  late final String funcPointerName;

  /// Contains typealias for function type if [exposeFunctionTypedefs] is true.
  Typealias? _exposedFunctionTypealias;

  /// [originalName] is looked up in dynamic library, if not
  /// provided, takes the value of [name].
  Func({
    super.usr,
    required String name,
    super.originalName,
    super.dartDoc,
    required Type returnType,
    List<Parameter>? parameters,
    List<Parameter>? varArgParameters,
    this.exposeSymbolAddress = false,
    this.exposeFunctionTypedefs = false,
    this.isLeaf = false,
    this.objCReturnsRetained = false,
    this.useNameForLookup = false,
    super.isInternal,
  })  : functionType = FunctionType(
          returnType: returnType,
          parameters: parameters ?? const [],
          varArgParameters: varArgParameters ?? const [],
        ),
        super(
          name: name,
        ) {
    for (var i = 0; i < functionType.parameters.length; i++) {
      if (functionType.parameters[i].name.trim() == '') {
        functionType.parameters[i].name = 'arg$i';
      }
    }

    // Get function name with first letter in upper case.
    final upperCaseName = name[0].toUpperCase() + name.substring(1);
    if (exposeFunctionTypedefs) {
      _exposedFunctionTypealias = Typealias(
        name: upperCaseName,
        type: functionType,
        genFfiDartType: true,
        isInternal: true,
      );
    }
  }

  @override
  BindingString toBindingString(Writer w) {
    final s = StringBuffer();
    final enclosingFuncName = name;

    if (dartDoc != null) {
      s.write(makeDartDoc(dartDoc!));
    }
    // Resolve name conflicts in function parameter names.
    final paramNamer = UniqueNamer({});
    for (final p in functionType.dartTypeParameters) {
      p.name = paramNamer.makeUnique(p.name);
    }

    // if the function accepts a struct argument by value,
    // we need to call stackAlloc to allocate memory for the struct and
    // pass the pointer to this struct instead of the value itself.

    for (final param in functionType.parameters) {
      if (param.type is Struct) {
        final paramStructType = param.type as Struct;
        int paramStructSize = 0;
        for (final member in paramStructType.members) {}
        var argPtrName = '${param.name}_structPtr';
        // for()
        // var structSize =
        // var allocateParamStruct = '''
        //   final $argPtrName  = stackAlloc($fieldSize);
        //   setValue(${structName}_${field.name}, param.arg, $llvmType)
        //   ''';
      }
    }

    // if the function returns a struct by value,
    // we need to transform the invocation to allocate memory
    // for the return type struct, and pass a pointer to this struct as the first parameter
    if (functionType.returnType is Struct) {
      final originalReturnType = functionType.returnType;

      final structType = functionType.returnType as Struct;
      final structName = structType.name;

      final outParam = Parameter(
          name: '${structName}_out',
          type: PointerType(originalReturnType),
          objCConsumed: false);

      final argDeclString = [outParam, ...functionType.dartTypeParameters]
          .map((p) => '${p.type.getFfiDartType(w)} ${p.name},\n')
          .join('');
      final forwardArgsString =
          functionType.dartTypeParameters.map((p) => "${p.name},").join('');

      var structSize = 0;
      var fieldAllocators = '';
      final fieldConstructorArgs = <String>[];
      late String llvmType;
      late String jsToDart;

      for (var field in structType.members) {
        if (field.type is! NativeType && field.type is! PointerType) {
          throw Exception('Unsupported : ${field.type}');
        }

        late String jsToDart;
        final dartType = field.type.getDartType(w);
        if (dartType == 'double') {
          jsToDart = '.toDartDouble';
        } else if (dartType == 'int') {
          jsToDart = '.toDartInt';
        } else if (field.type is PointerType) {
          final ptrType = field.type as PointerType;
          final inner = ptrType.child.getDartType(w);
          jsToDart = '.toDartInt as Pointer<$inner>';
        }
        structSize += field.type.sizeInBytes;

        fieldAllocators +=
            '''final ${structName}_${field.name} = getValue(out, '${field.type.llvmType}')$jsToDart;\n''';

        fieldConstructorArgs.add('${structName}_${field.name}');
      }

      s.write('''external void _$enclosingFuncName($argDeclString);''');
      s.write(
          '''${functionType.returnType.getFfiDartType(w)} $enclosingFuncName($argDeclString) {
          final out = stackAlloc<${originalReturnType.getDartType(w)}>($structSize);
          _$enclosingFuncName(out, $forwardArgsString);
          $fieldAllocators

          return ${originalReturnType.getDartType(w)}(${fieldConstructorArgs.join(',')});
        }''');
    } else {
      final argDeclString = functionType.dartTypeParameters
          .map((p) => '${p.type.getFfiDartType(w)} ${p.name},\n')
          .join('');
      final forwardArgsString =
          functionType.dartTypeParameters.map((p) => "${p.name},").join('');

      final nativeFuncName = enclosingFuncName;
      s.write(
          '''external ${functionType.returnType.getFfiDartType(w)} _$nativeFuncName($argDeclString);''');
      s.write(
          '''${functionType.returnType.getFfiDartType(w)} $nativeFuncName($argDeclString) {
          return _$nativeFuncName($forwardArgsString);
        }''');
    }

    return BindingString(type: BindingStringType.func, string: s.toString());
  }

  @override
  void addDependencies(Set<Binding> dependencies) {
    if (dependencies.contains(this)) return;

    dependencies.add(this);
    functionType.addDependencies(dependencies);
    if (exposeFunctionTypedefs) {
      _exposedFunctionTypealias!.addDependencies(dependencies);
    }
  }
}

/// Represents a Parameter, used in [Func], [Typealias], [ObjCMethod], and
/// [ObjCBlock].
class Parameter {
  final String? originalName;
  String name;
  Type type;
  final bool objCConsumed;

  Parameter({
    String? originalName,
    this.name = '',
    required Type type,
    required this.objCConsumed,
  })  : originalName = originalName ?? name,
        // A [NativeFunc] is wrapped with a pointer because this is a shorthand
        // used in C for Pointer to function.
        type = type.typealiasType is NativeFunc ? PointerType(type) : type;

  String getNativeType({String varName = ''}) =>
      '${type.getNativeType(varName: varName)}'
      '${objCConsumed ? ' __attribute__((ns_consumed))' : ''}';

  @override
  String toString() => '$type $name';
}
