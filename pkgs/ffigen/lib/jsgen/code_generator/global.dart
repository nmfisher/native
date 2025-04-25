// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../config_provider/config_types.dart';
import 'binding.dart';
import 'binding_string.dart';
import 'compound.dart';
import 'pointer.dart';
import 'type.dart';
import 'utils.dart';
import 'writer.dart';

/// A binding to a global variable
///
/// For a C global variable -
/// ```c
/// int a;
/// ```
/// The generated dart code is -
/// ```dart
/// final int a = _dylib.lookup<ffi.Int32>('a').value;
/// ```
class Global extends Binding {
  final Type type;
  final FfiNativeConfig nativeConfig;
  final bool constant;

  Global({
    required super.usr,
    required super.originalName,
    required super.name,
    required this.type,
    super.dartDoc,
    this.constant = false,
    this.nativeConfig = const FfiNativeConfig(enabled: false),
  });

  @override
  BindingString toBindingString(Writer w, { bool writeModuleBinding = false}) {
    final s = StringBuffer();
    final globalVarName = name;
    if (dartDoc != null) {
      s.write(makeDartDoc(dartDoc!));
    }
    final dartType = type.getDartType(w);
    final ffiDartType = type.getInteropDartType(w);
    final cType = type.getInteropDartType(w);

    if (nativeConfig.enabled) {
      if (type case final ConstantArray arr) {
        throw UnimplementedError();
      }

      final pointerName =
          w.wrapperLevelUniqueNamer.makeUnique('_$globalVarName');

      s
        ..writeln(makeNativeAnnotation(
          w,
          nativeType: cType,
          dartName: pointerName,
          nativeSymbolName: pointerName,
          isLeaf: false,
        ))
        ..write('external ');
      if (constant) {
        s.write('final ');
      }

      s.writeln('$ffiDartType $pointerName;\n');
    } else {
      throw UnimplementedError();
    }

    return BindingString(type: BindingStringType.global, string: s.toString());
  }

  @override
  void addDependencies(Set<Binding> dependencies) {
    if (dependencies.contains(this)) return;

    dependencies.add(this);
    type.addDependencies(dependencies);
  }
}
