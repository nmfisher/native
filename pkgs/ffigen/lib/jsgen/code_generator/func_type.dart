// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../code_generator.dart';
import 'utils.dart';

import 'writer.dart';

/// Represents a function type.
class FunctionType extends Type {
  final Type returnType;
  final List<Parameter> parameters;
  final List<Parameter> varArgParameters;

  /// Get all the parameters for generating the dart type. This includes both
  /// [parameters] and [varArgParameters].
  List<Parameter> get dartTypeParameters => parameters + varArgParameters;

  FunctionType({
    required this.returnType,
    required this.parameters,
    this.varArgParameters = const [],
  });

  String _getTypeImpl(
      bool writeArgumentNames, String Function(Type) typeToString,
      {String? varArgWrapper}) {
    final params = varArgWrapper != null ? parameters : dartTypeParameters;
    String? varArgPack;
    if (varArgWrapper != null && varArgParameters.isNotEmpty) {
      final varArgPackBuf = StringBuffer();
      varArgPackBuf.write('$varArgWrapper<(');
      varArgPackBuf.write(varArgParameters.map<String>((p) {
        return '${typeToString(p.type)} ${writeArgumentNames ? p.name : ""}';
      }).join(', '));
      varArgPackBuf.write(',)>');
      varArgPack = varArgPackBuf.toString();
    }

    // Write return Type.
    final sb = StringBuffer();
    sb.write(typeToString(returnType));

    // Write Function.
    sb.write(' Function(');
    sb.write([
      ...params.map<String>((p) {
        return '${typeToString(p.type)} ${writeArgumentNames ? p.name : ""}';
      }),
      if (varArgPack != null) varArgPack,
    ].join(', '));
    sb.write(')');

    return sb.toString();
  }

  @override
  String getInteropDartType(Writer w, {bool writeArgumentNames = true}) =>
      _getTypeImpl(writeArgumentNames, (Type t) => t.getInteropDartType(w),
          varArgWrapper: '${w.selfImportPrefix}.VarArgs');

  @override
  String getDartType(Writer w, {bool writeArgumentNames = true}) =>
      _getTypeImpl(writeArgumentNames, (Type t) => t.getDartType(w));

  @override
  String getNativeType({String varName = ''}) {
    final arg = dartTypeParameters.map<String>((p) => p.type.getNativeType());
    return '${returnType.getNativeType()} (*$varName)(${arg.join(', ')})';
  }
    
  @override
  String cacheKey() => _getTypeImpl(false, (Type t) => t.cacheKey());

  @override
  void addDependencies(Set<Binding> dependencies) {
    returnType.addDependencies(dependencies);
    for (final p in parameters) {
      p.type.addDependencies(dependencies);
    }
  }

  void addParameterNames(List<String> names) {
    if (names.length != parameters.length) {
      return;
    }
    final paramNamer = UniqueNamer({});
    for (var i = 0; i < parameters.length; i++) {
      final finalName = paramNamer.makeUnique(names[i]);
      parameters[i] = Parameter(
        type: parameters[i].type,
        originalName: names[i],
        name: finalName,
        objCConsumed: false,
      );
    }
  }

  @override
  String get llvmType => throw UnimplementedError();

  @override
  int get sizeInBytes => throw UnimplementedError();
}

/// Represents a NativeFunction<Function>.
class NativeFunc extends Type {
  // Either a FunctionType or a Typealias of a FunctionType.
  final Type _type;

  NativeFunc(this._type) : assert(_type is FunctionType || _type is Typealias);

  FunctionType get type {
    if (_type is Typealias) {
      return _type.typealiasType as FunctionType;
    }
    return _type as FunctionType;
  }

  @override
  void addDependencies(Set<Binding> dependencies) {
    _type.addDependencies(dependencies);
  }

  @override
  String getInteropDartType(Writer w, {bool writeArgumentNames = true}) {
    final funcType = _type is FunctionType
        ? _type.getInteropDartType(w, writeArgumentNames: writeArgumentNames)
        : _type.getInteropDartType(w);
    return '${w.selfImportPrefix}.NativeFunction<$funcType>';
  }

  @override
  String getNativeType({String varName = ''}) =>
      _type.getNativeType(varName: varName);

  @override
  String toString() => 'NativeFunction<${_type.toString()}>';

  @override
  String cacheKey() => 'NatFn(${_type.cacheKey()})';

  @override
  String get llvmType => throw Exception();

  @override
  String getWasmType(Writer w) => getInteropDartType(w);

  String get wasmSignature {
    var ft = _type is Typealias
        ? _type.typealiasType as FunctionType
        : _type as FunctionType;
    var signature = "";
    var returnType = ft.returnType;
    if (returnType is NativeType) {
      signature += returnType.wasmType;
    } else if (returnType is PointerType) {
      signature += returnType.wasmType;
    } else {
      throw UnsupportedError(returnType.toString());
    }
    for (final param in ft.parameters) {
      var paramType = param.type;
      if (paramType is NativeType) {
        signature += paramType.wasmType;
      } else if (paramType is PointerType) {
        signature += paramType.wasmType;
      } else {
        throw UnsupportedError(returnType.toString());
      }
    }
    return signature;
  }

  @override
  int get sizeInBytes => throw UnimplementedError();
}
