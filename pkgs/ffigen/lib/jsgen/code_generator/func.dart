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

    if (dartDoc != null) {
      s.write(makeDartDoc(dartDoc!));
    }
    // Resolve name conflicts in function parameter names.
    final paramNamer = UniqueNamer({});
    for (final p in functionType.dartTypeParameters) {
      p.name = paramNamer.makeUnique(p.name);
    }

    //
    // we will generate two methods for each native function definition:
    // 1) an internal interop method that accepts/returns interop argument types
    // 2) a user-facing method that accepts/returns only Dart types, converting
    //    to interop types as needed and forwarding to (1)
    // The methods share the same name, but the interop method is prefixed with
    // an underscore.
    //
    // For arguments and return values that are primitive numeric types
    // (int/float/double), there is no difference between the interop and the
    // user-facing method. The signature will be exactly the same (except the
    // interop method will be marked as [external])
    //
    // If the interop method returns a struct by value:
    // - the first argument to the interop method will be a pointer to
    //   the struct
    // - the user-facing method will stack-allocate sufficient memory to
    //   represent the struct, and pass the pointer to the interop method
    // - after the interop method has returned, the user-facing method will
    //   instantiate the generated Dart class that corresponds to the struct,
    //   using getValue() to retrieve the correct vales.
    //
    // If the interop method takes a struct by value as an argument:
    // - the user-facing method will take, as an argument, the generated Dart
    //   class corresponding to the struct
    // - internally, the user-facing method will stack-allocate sufficient
    //   memory to represent the struct and call setValue to set its member
    //   values
    //
    // If the interop method takes a function pointer as an argument:
    // - the user-facing method will take, as an argument, a Dart
    //   function with the matching signature
    // - internally, the user-facing method will call addFunction to convert the
    //   Dart function to the correct interop type
    // - a Finalizer will be used to call removeFunction when the Dart Function
    //   is garbage-collected. (?)
    //
    String interopFunctionName = "_$name";
    String userFacingFunctionName = name;

    var interopArguments = <Parameter>[];
    var userFacingArguments = <Parameter>[];

    var structArgumentAllocator = '';

    for (final param in functionType.parameters) {
      var paramType = param.type;

      if (paramType.baseType is NativeFunc) {
        var fnType = (paramType.baseType as NativeFunc).type;

        var param = Parameter(type: fnType, objCConsumed: false);
        dartFunctionArguments.add(param);

        // structArgumentAllocator +=
        //     '''final $argPtrName = addFunction();\n''';
      } else if (paramType is Struct) {
        var argPtrName = '${param.name}_structPtr';
        var paramMembers = paramType.members;

        structArgumentAllocator +=
            '''final $argPtrName = stackAlloc<${paramType.name}>(${paramType.sizeInBytes});\n''';
        for (final paramMember in paramMembers) {
          structArgumentAllocator +=
              '''setValue($argPtrName, ${param.name}.${paramMember.name}.toJS, '${paramMember.type.llvmType}');''';
        }
        dartFunctionArguments.add(param);
      } else {
        dartFunctionArguments.add(param);
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

      for (final field in structType.members) {
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

      s.write('''external void _$name($argDeclString);''');
      s.write(
          '''${functionType.returnType.getFfiDartType(w)} $name($argDeclString) {
          $structArgumentAllocator
          final out = stackAlloc<${originalReturnType.getDartType(w)}>($structSize);
          _$name(out, $forwardArgsString);
          $fieldAllocators

          return ${originalReturnType.getDartType(w)}(${fieldConstructorArgs.join(',')});
        }''');
    } else {
      final argDeclString = functionType.dartTypeParameters
          .map((p) => '${p.type.getFfiDartType(w)} ${p.name},\n')
          .join('');
      final forwardArgsString =
          functionType.dartTypeParameters.map((p) => "${p.name},").join('');

      final nativeFuncName = name;
      s.write(
          '''external ${functionType.returnType.getFfiDartType(w)} _$nativeFuncName($argDeclString);''');
      s.write(
          '''${functionType.returnType.getFfiDartType(w)} $nativeFuncName($argDeclString) {
          $structArgumentAllocator
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
