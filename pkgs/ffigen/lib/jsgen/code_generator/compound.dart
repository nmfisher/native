// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import '../code_generator.dart';

import 'binding_string.dart';
import 'utils.dart';
import 'writer.dart';

enum CompoundType { struct, union }

/// A binding for Compound type - Struct/Union.
abstract class Compound extends BindingType {
  /// Marker for if a struct definition is complete.
  ///
  /// A function can be safely pass this struct by value if it's complete.
  bool isIncomplete;

  List<Member> members;

  bool get isOpaque => members.isEmpty;

  /// Value for `@Packed(X)` annotation. Can be null (no packing), 1, 2, 4, 8,
  /// or 16.
  ///
  /// Only supported for [CompoundType.struct].
  int? pack;

  /// Marker for checking if the dependencies are parsed.
  bool parsedDependencies = false;

  CompoundType compoundType;
  bool get isStruct => compoundType == CompoundType.struct;
  bool get isUnion => compoundType == CompoundType.union;

  /// The way the native type is written in C source code. This isn't always the
  /// same as the originalName, because the type may need to be prefixed with
  /// `struct` or `union`, depending on whether the declaration is a typedef.
  final String nativeType;

  // @override
  // String getWasmType(Writer w) => originalName;

  Compound({
    super.usr,
    super.originalName,
    required super.name,
    required this.compoundType,
    this.isIncomplete = false,
    this.pack,
    super.dartDoc,
    List<Member>? members,
    super.isInternal,
    String? nativeType,
  })  : members = members ?? [],
        nativeType = nativeType ?? originalName ?? name;

  factory Compound.fromType({
    required CompoundType type,
    String? usr,
    String? originalName,
    required String name,
    bool isIncomplete = false,
    int? pack,
    String? dartDoc,
    List<Member>? members,
    String? nativeType,
  }) {
    switch (type) {
      case CompoundType.struct:
        return Struct(
          usr: usr,
          originalName: originalName,
          name: name,
          isIncomplete: isIncomplete,
          pack: pack,
          dartDoc: dartDoc,
          members: members,
          nativeType: nativeType,
        );
      case CompoundType.union:
        return Union(
          usr: usr,
          originalName: originalName,
          name: name,
          isIncomplete: isIncomplete,
          pack: pack,
          dartDoc: dartDoc,
          members: members,
          nativeType: nativeType,
        );
    }
  }

  String _getInlineArrayTypeString(Type type, Writer w) {
    if (type is ConstantArray) {
      return 'Array<'
          '${_getInlineArrayTypeString(type.child, w)}>';
    }
    return type.getWasmType(w);
  }

  @override
  BindingString toBindingString(Writer w, {bool writeModuleBinding = false}) {
    final bindingType =
        isStruct ? BindingStringType.struct : BindingStringType.union;

    final s = StringBuffer();
    final enclosingClassName = 'Dart$name';
    if (dartDoc != null) {
      s.write(makeDartDoc(dartDoc!));
    }

    /// Adding [enclosingClassName] because dart doesn't allow class member
    /// to have the same name as the class.
    final localUniqueNamer = UniqueNamer({enclosingClassName});

    /// Marking type names because dart doesn't allow class member to have the
    /// same name as a type name used internally.
    for (final m in members) {
      localUniqueNamer.markUsed(m.type.getInteropDartType(w));
    }

    /// Write @Packed(X) annotation if struct is packed.
    if (isStruct && pack != null) {
      s.write('@${w.selfImportPrefix}.Packed($pack)\n');
    }
    final dartClassName = isStruct ? 'DartStruct' : 'Union';
    // Write class declaration.
    s.write('''
extension type $name(Struct addr) implements Struct {
  static Pointer<$name> stackAlloc() {
    return _lib._stackAlloc<$name>($sizeInBytes);
  }
}
extension ${name}Ext on Pointer<$name> {
  ${enclosingClassName} toDart() {''');
    int offset = 0;

    for (final field in members) {
      if (field.type is ConstantArray) {
        var arrType = field.type as ConstantArray;
        s.write(
            'var ${field.name} = Array<${field.type.baseArrayType.getWasmType(w)}>._((addr: (addr as Pointer).cast(), numElements: ${arrType.length}));\n');
      } else if (field.type is PointerType) {
        s.write('var ${field.name} = (addr as Pointer) + $offset;\n');
      } else {
        final llvmType = field.type is NativeType
            ? (field.type as NativeType).llvmType
            : "*";
        s.write(
            'var ${field.name} = _lib.getValue((addr as Pointer) + $offset, "$llvmType").toDartDouble;\n');
      }
      offset += field.type.sizeInBytes;
    }
    s.write(
        '''return ${enclosingClassName}(${members.map((m) => "${m.name}${m.type is PointerType ? ".cast()" : ""}").join(",")});
    }''');

    s.write('''void setFrom(${enclosingClassName} dartType) {''');
    offset = 0;
    for (final field in members) {
      final fieldType = field.type;
      final llvmType = fieldType.llvmType;
      String fieldAccessor = 'dartType.${field.name}';
      if (fieldType is ConstantArray) {
        fieldAccessor += '._.addr.addr';
      } else if (field.type is PointerType) {
        fieldAccessor += '.addr';
      }
      fieldAccessor += '.toJS';
      s.write(
          '_lib.setValue((addr as Pointer) + $offset, $fieldAccessor, "$llvmType");\n');
      offset += field.type.sizeInBytes;
    }
    s.write('}\n}');

    s.write('final class $enclosingClassName extends ');
    s.write('${w.selfImportPrefix}.${isOpaque ? 'Opaque' : dartClassName}{\n');
    const depth = '  ';

    // Constructor parameters
    List<String> constructorParams = [];

    for (final m in members) {
      m.name = localUniqueNamer.makeUnique(m.name);
      if (m.dartDoc != null) {
        s.write('$depth/// ');
        s.writeAll(m.dartDoc!.split('\n'), '\n$depth/// ');
        s.write('\n');
      }
      if (m.type case final ConstantArray arrayType) {
        s.write('${depth}${_getInlineArrayTypeString(m.type, w)} ');
        s.write('${m.name};\n\n');

        constructorParams.add('this.${m.name}');
      } else {
        final memberName = m.name;

        if (m.type case final PointerType ptrType) {
          s.write('${depth}final ${m.type.getDartType(w)} $memberName;\n\n');
        } else {
          s.write(
              '${depth}final ${m.type.getInteropDartType(w)} $memberName;\n\n');
        }

        constructorParams.add('this.$memberName');
      }
      if (m.type case EnumClass(:final generateAsInt) when !generateAsInt) {
        final enumName = m.type.getDartType(w);
        final memberName = m.name;
        s.write(
          '${depth}$enumName get $memberName => '
          '$enumName.fromValue(${memberName}AsInt);\n\n',
        );
      }
    }

    // Add constructor with required named parameters
    s.write('${depth} $enclosingClassName(\n');
    for (int i = 0; i < constructorParams.length; i++) {
      s.write('$depth$depth${constructorParams[i]}');
      if (i < constructorParams.length - 1) {
        s.write(',');
      }
      s.write('\n');
    }
    s.write('$depth);\n\n');

    s.write('}\n\n');

    return BindingString(type: bindingType, string: s.toString());
  }

  @override
  void addDependencies(Set<Binding> dependencies) {
    if (dependencies.contains(this)) return;

    dependencies.add(this);
    for (final m in members) {
      m.type.addDependencies(dependencies);
    }
  }

  @override
  bool get isIncompleteCompound => isIncomplete;

  @override
  String getInteropDartType(Writer w) {
    return name;
  }

  @override
  String getNativeType({String varName = ''}) => '$nativeType $varName';
}

class Member {
  final String? dartDoc;
  final String originalName;
  String name;
  final Type type;

  Member({
    String? originalName,
    required this.name,
    required this.type,
    this.dartDoc,
  }) : originalName = originalName ?? name;
}
