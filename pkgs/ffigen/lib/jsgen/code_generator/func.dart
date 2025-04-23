// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:ffi';
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
/// The generated Dart code for this function is as
/// follows.
///
/// ```dart
/// external int _sum(int a, int b);
///
/// int sum(int a, int b) {
///   return _sum(a, b);
/// }
///
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
    final interopFunctionName = "_$name";
    final userFunctionName = name;

    var userReturnType = functionType.returnType.getDartType(w);
    var interopReturnType = functionType.returnType.getInteropDartType(w);

    final interopArguments = <Parameter>[];
    final userArguments = <Parameter>[];
    final interopArgumentConstructors = <String>[];
    final interopReturnTypeConstructors = <String>[];

    // iterate over the arguments for the native function
    for (final param in functionType.parameters) {
      final paramType = param.type;

      // if the argument is a function pointer:
      // 1) adjust the user facing function params to accept a matching Dart
      //    function argument
      // 2) inside the user-facing function, construct an interop type with
      //    addFunction
      if (paramType.baseType is NativeFunc) {
        final userParam = Parameter(
            name: param.name,
            originalName: param.originalName,
            type: (paramType.baseType as NativeFunc).type,
            objCConsumed: false);
        userArguments.add(userParam);

        final interopFnPtrName = '${param.name}_interopFnPtr';
        interopArguments.add(Parameter(
            name: interopFnPtrName, type: param.type, objCConsumed: false));

        final wasmSignature = (paramType.baseType as NativeFunc).wasmSignature;

        final paramConstructor = '''
final $interopFnPtrName = addFunction(${param.name}.toJS, "$wasmSignature");\n''';
        interopArgumentConstructors.add(paramConstructor);

        // if the argument is a struct:
        // 1) inside the user-facing function, stack-allocate memory for the
        //    struct
        // 2) populate the memory with the values from the Dart class
        // 3) adjust the interop argument to accept a pointer
      } else if (paramType is Struct) {
        final argPtrName = '${param.name}_structPtr';

        var paramConstructor =
            "final $argPtrName = _stackAlloc<${paramType.name}>(${paramType.sizeInBytes});\n";

        for (final paramMember in paramType.members) {
          paramConstructor +=
              "setValue($argPtrName, ${param.name}.${paramMember.name}.toJS, '${paramMember.type.llvmType}');\n";
        }
        interopArgumentConstructors.add(paramConstructor);
        interopArguments.add(Parameter(
            name: argPtrName,
            type: PointerType(paramType),
            objCConsumed: false));
        userArguments.add(param);
      } else if (paramType is PointerType) {
        interopArguments.add(param);
        userArguments.add(param);
      } else {
        interopArguments.add(param);
        userArguments.add(param);
      }
    }

    // if the function returns a struct by value:
    // 1) inside the user-facing function, stack-allocate memory for the struct
    // 2) adjust the parameters for the interop function to accept a pointer to
    //    this struct as the first parameter
    // 3) adjust the return type for the interop function to return void
    if (functionType.returnType is Struct) {
      final originalReturnType = functionType.returnType;
      interopReturnType =
          NativeType(SupportedNativeType.voidType).getDartType(w);

      final structType = functionType.returnType as Struct;
      final structName = structType.name;

      final outParam = Parameter(
          name: '${structName}_out',
          type: PointerType(originalReturnType),
          objCConsumed: false);
      interopArgumentConstructors.add(
          'final ${outParam.name} = _stackAlloc<${structType.name}>(${structType.sizeInBytes});');

      interopArguments.insert(0, outParam);

      var outFieldNames = <String>[];

      var offset = 0;

      for (final field in structType.members) {
        if (field.type is! NativeType && field.type is! PointerType) {
          throw Exception('Unsupported : ${field.type}');
        }

        late String jsToDart;
        String wrapper = "";
        final dartType = field.type.getDartType(w);
        if (dartType == 'double') {
          jsToDart = '.toDartDouble';
        } else if (dartType == 'int') {
          jsToDart = '.toDartInt';
        } else if (field.type is PointerType) {
          final ptrType = field.type as PointerType;
          final inner = ptrType.child.getWasmType(w);
          wrapper = 'Pointer(';
          jsToDart = '.toDartInt as PointerAddress<$inner>, this)';
        }

        var fieldName = '${structName}_${field.name}';
        outFieldNames.add(fieldName);

        interopReturnTypeConstructors.add(
            "final $fieldName = ${wrapper}getValue(${outParam.name} + ${offset}, '${field.type.llvmType}')$jsToDart;");
        offset += field.type.sizeInBytes;
      }
      interopReturnTypeConstructors.add(
          "return ${originalReturnType.getDartType(w)}(${outFieldNames.join(',')});");
      // if the return type is a PointerAddress, we need to wrap inside a Pointer
    } else if (functionType.returnType is PointerType) {
      var ptrType = functionType.returnType as PointerType;
      var wrappedType = ptrType.baseType;
      if (wrappedType is! NativeType) {
        throw UnimplementedError();
      }

      userReturnType = ptrType.getDartType(w);
      interopReturnTypeConstructors
          .add('return $userReturnType(result, this);');
    } else {
      interopReturnTypeConstructors.add('return result;');
    }

    final userArgsString = userArguments
        .map((p) => '${p.type.getDartType(w)} ${p.name},\n')
        .join('');
    final interopArgsString = interopArguments
        .map((p) => '${p.type.getInteropDartType(w)} ${p.name},\n')
        .join('');
    final invokeInteropArgsString = interopArguments.map((p) {
      if (p.type.baseType is NativeFunc) {
        return '${p.name}.cast(),';
      }

      if (p.type is PointerType && p.type.baseType is! Struct) {
        return '${p.name}.addr,';
      }

      return "${p.name},";
    }).join('');

    s.write(
        '''external $interopReturnType $interopFunctionName($interopArgsString);''');
    s.write('''$userReturnType $userFunctionName($userArgsString) {
            ${interopArgumentConstructors.join("\n")}
            final result = $interopFunctionName($invokeInteropArgsString);
            ${interopReturnTypeConstructors.join("\n")}
}''');

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
