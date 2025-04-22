// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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

    final ffiReturnType = functionType.returnType.getFfiDartType(w);
    final ffiArgDeclString = functionType.dartTypeParameters
        .map((p) => '${p.type.getFfiDartType(w)} ${p.name},\n')
        .join('');         

      final nativeFuncName = enclosingFuncName;
      s.write('''
external $ffiReturnType _$nativeFuncName($ffiArgDeclString);

''');

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
