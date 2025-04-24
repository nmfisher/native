// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../code_generator.dart';
import '../strings.dart' as strings;
import 'utils.dart';

final _logger = Logger('jsgen.code_generator.writer');

/// To store generated String bindings.
class Writer {
  final String? header;

  /// Holds bindings, which lookup symbols.
  final List<Binding> lookUpBindings;

  /// Holds bindings which don't lookup symbols.
  final List<Binding> noLookUpBindings;

  late String _className;
  String get className => _className;

  final String? classDocComment;

  final List<String> nativeEntryPoints;

  /// Tracks where enumType.getInteropDartType is called. Reset everytime [generate] is
  /// called.
  bool usedEnumCType = false;

  String? _pkgWebLibraryPrefix;
  String get pkgWebLibraryPrefix {
    if (_pkgWebLibraryPrefix != null) {
      return _pkgWebLibraryPrefix!;
    }

    final import = _usedImports.firstWhere(
        (element) => element.name == pkgWebImport.name,
        orElse: () => pkgWebImport);
    _usedImports.add(import);
    return _pkgWebLibraryPrefix = import.prefix;
  }

  String? _jsInteropLibraryPrefix;
  String get jsInteropLibraryPrefix {
    if (_jsInteropLibraryPrefix != null) {
      return _jsInteropLibraryPrefix!;
    }

    final import = _usedImports.firstWhere(
        (element) => element.name == jsInteropImport.name,
        orElse: () => jsInteropImport);
    _usedImports.add(import);
    return _jsInteropLibraryPrefix = import.prefix;
  }

  late String selfImportPrefix = () {
    final import = _usedImports
        .firstWhere((element) => element.name == self.name, orElse: () => self);
    _usedImports.add(import);
    return import.prefix;
  }();

  final Set<LibraryImport> _usedImports = {};

  String _lookupFuncIdentifier = "LOOKUP";
  String get lookupFuncIdentifier => _lookupFuncIdentifier;

  late String _symbolAddressClassName;
  late String _symbolAddressVariableName;
  late String _symbolAddressLibraryVarName;

  /// Initial namers set after running constructor. Namers are reset to this
  /// initial state everytime [generate] is called.
  late UniqueNamer _initialTopLevelUniqueNamer, _initialWrapperLevelUniqueNamer;

  /// Used by [Binding]s for generating required code.
  late UniqueNamer _topLevelUniqueNamer;
  UniqueNamer get topLevelUniqueNamer => _topLevelUniqueNamer;
  late UniqueNamer _wrapperLevelUniqueNamer;
  UniqueNamer get wrapperLevelUniqueNamer => _wrapperLevelUniqueNamer;

  late String _arrayHelperClassPrefix;

  /// Guaranteed to be a unique prefix.
  String get arrayHelperClassPrefix => _arrayHelperClassPrefix;

  /// Set true after calling [generate]. Indicates if
  /// [generateSymbolOutputYamlMap] can be called.
  bool get canGenerateSymbolOutput => _canGenerateSymbolOutput;
  bool _canGenerateSymbolOutput = false;

  final bool silenceEnumWarning;

  Writer({
    required this.lookUpBindings,
    required this.noLookUpBindings,
    required String className,
    List<LibraryImport>? additionalImports,
    this.classDocComment,
    this.header,
    required this.silenceEnumWarning,
    required this.nativeEntryPoints,
  }) {
    final globalLevelNameSet = noLookUpBindings.map((e) => e.name).toSet();
    final wrapperLevelNameSet = lookUpBindings.map((e) => e.name).toSet();
    final allNameSet = <String>{}
      ..addAll(globalLevelNameSet)
      ..addAll(wrapperLevelNameSet);

    _initialTopLevelUniqueNamer = UniqueNamer(globalLevelNameSet);
    _initialWrapperLevelUniqueNamer = UniqueNamer(wrapperLevelNameSet);
    final allLevelsUniqueNamer = UniqueNamer(allNameSet);

    /// Wrapper class name must be unique among all names.
    _className = _resolveNameConflict(
      name: className,
      makeUnique: allLevelsUniqueNamer,
      markUsed: [_initialWrapperLevelUniqueNamer, _initialTopLevelUniqueNamer],
    );

    /// Library imports prefix should be unique unique among all names.
    if (additionalImports != null) {
      for (final lib in additionalImports) {
        lib.prefix = _resolveNameConflict(
          name: lib.prefix,
          makeUnique: allLevelsUniqueNamer,
          markUsed: [
            _initialWrapperLevelUniqueNamer,
            _initialTopLevelUniqueNamer
          ],
        );
      }
    }

    /// Resolve name conflicts of identifiers used for SymbolAddresses.
    _symbolAddressClassName = _resolveNameConflict(
      name: '_SymbolAddresses',
      makeUnique: allLevelsUniqueNamer,
      markUsed: [_initialWrapperLevelUniqueNamer, _initialTopLevelUniqueNamer],
    );
    _symbolAddressVariableName = _resolveNameConflict(
      name: 'addresses',
      makeUnique: _initialWrapperLevelUniqueNamer,
      markUsed: [_initialWrapperLevelUniqueNamer],
    );
    _symbolAddressLibraryVarName = _resolveNameConflict(
      name: '_library',
      makeUnique: _initialWrapperLevelUniqueNamer,
      markUsed: [_initialWrapperLevelUniqueNamer],
    );

    /// Finding a unique prefix for Array Helper Classes and store into
    /// [_arrayHelperClassPrefix].
    final base = 'ArrayHelper';
    _arrayHelperClassPrefix = base;
    var suffixInt = 0;
    for (var i = 0; i < allNameSet.length; i++) {
      if (allNameSet.elementAt(i).startsWith(_arrayHelperClassPrefix)) {
        // Not a unique prefix, start over with a new suffix.
        i = -1;
        suffixInt++;
        _arrayHelperClassPrefix = '$base$suffixInt';
      }
    }

    _resetUniqueNamersNamers();
  }

  /// Resolved name conflict using [makeUnique] and marks the result as used in
  /// all [markUsed].
  String _resolveNameConflict({
    required String name,
    required UniqueNamer makeUnique,
    List<UniqueNamer> markUsed = const [],
  }) {
    final s = makeUnique.makeUnique(name);
    for (final un in markUsed) {
      un.markUsed(s);
    }
    return s;
  }

  /// Resets the namers to initial state. Namers are reset before generating.
  void _resetUniqueNamersNamers() {
    _topLevelUniqueNamer = _initialTopLevelUniqueNamer.clone();
    _wrapperLevelUniqueNamer = _initialWrapperLevelUniqueNamer.clone();
  }

  void markImportUsed(LibraryImport import) {
    _usedImports.add(import);
  }

  final _structs = <Struct>{};

  void markStruct(Struct type) {
    _structs.add(type);
    print("ADDED $type");
  }

  /// Writes all bindings to a String.
  String generate() {
    final s = StringBuffer();

    // We write the source first to determine which imports are actually
    // referenced. Headers and [s] are then combined into the final result.
    final result = StringBuffer();

    // Reset unique namers to initial state.
    _resetUniqueNamersNamers();

    // Reset [usedEnumCType].
    usedEnumCType = false;

    // Write file header (if any).
    if (header != null) {
      result.writeln(header);
    }

    // Write auto generated declaration.
    result.write(makeDoc(
        'AUTO GENERATED FILE, DO NOT EDIT.\n\nGenerated by `package:jsgen`.'));

    // Write lint ignore if not specified by user already.
    if (!RegExp(r'ignore_for_file:\s*type\s*=\s*lint').hasMatch(header ?? '')) {
      result.write(makeDoc('ignore_for_file: type=lint'));
    }

    /// Write [lookUpBindings].
    if (lookUpBindings.isNotEmpty) {
      // Write doc comment for wrapper class.
      if (classDocComment != null) {
        s.write(makeDartDoc(classDocComment!));
      }
      // Write wrapper classs.

      s.write('''
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

///
/// Sub-classes of [NativeType] represent a "native" type (by which we mean a
/// type that can be passed to a WASM-compiled native function), and its
/// equivalent Dart representation.
///
/// Most sub-classes are non-constructible; they are only intended to preserve
/// compile-time type information and to translate between native types and
/// their Dart equivalent.
///
/// The exceptions are [Pointer] and sub-classes of [Struct]; these can be
/// instantiated and returned to the user.
///
/// Sub-classes doesn't necessarily represent a singular WASM type; for example,
/// WASM does not have a char type but we implement a [Char] type to help
/// preserve "native" type information. Without this, [const char*] would only be
/// represented as Pointer<Int64>, and we would have no way of knowing that
/// it can safely be interpreted/converted to a Dart String.
///
///
sealed class NativeType<T> {}

extension type _PtrType<T extends NativeType>(int addr) {
  _PtrType<T> operator +(int offset) => _PtrType<T>(addr + offset);
  _PtrType<U> cast<U extends NativeType>() => this as _PtrType<U>;
}

class Int32 extends NativeType<int> {
  Int32._();
}

class Int64 extends NativeType<int> {
  Int64._();
}

class Double extends NativeType<double> {
  Double._();
}

class Float extends NativeType<double> {
  Float._();
}

class Char extends NativeType<int> {
  Char._();
}

class Void extends NativeType<void> {
  Void._();
}

class NativeFunction<T> extends NativeType<Function> {
  NativeFunction._();
}

abstract class Struct extends NativeType {}

extension CharPtr on Pointer<Char> {
  void setValue(String value) {
    var len = module._lengthBytesUTF8(value);
    module._stringToUTF8(value, this.addr, len);
  }

  String getValue() {
    return module._UTF8ToString(this.addr);
  }
}

class Pointer<T extends NativeType> extends NativeType<int> {
  final NativeLibrary module;
  final _PtrType<T> addr;

  final llvmType = switch (T) {
    Double => "double",
    Float => "float",
    Int32 => "i32",
    Int64 => "i64",
    Char => "i32",
    Pointer => "*",
    _ => T.toString().startsWith("Pointer")
        ? "*"
        : throw UnimplementedError(T.toString())
  };

  Pointer(this.addr, this.module);

  Pointer<T> operator +(int offset) =>
      Pointer<T>(addr + (offset * sizeOf<Pointer>()), module);
  Pointer<U> cast<U extends NativeType>() => this as Pointer<U>;
}

extension PtrPtr<T extends NativeType> on Pointer<Pointer<T>> {
  void setValue(Pointer<T> value) {
    module.setValue(addr, (value.addr as int).toJS, llvmType);
  }

  Pointer<T> getValue() {
    var jsValue = module.getValue(this.addr, llvmType);
    return Pointer<T>(jsValue.toDartInt as _PtrType<T>, module);
  }
}

extension Int32Ptr on Pointer<Int32> {
  void setValue(int value) {
    module.setValue(addr, value.toJS, llvmType);
  }

  int getValue() {
    var jsValue = module.getValue(this.addr, llvmType);
    return jsValue.toDartInt;
  }
}

extension Int64Ptr on Pointer<Int64> {
  void setValue(int value) {
    module.setValue(addr, value.toJS, llvmType);
  }

  int getValue() {
    var jsValue = module.getValue(this.addr, llvmType);
    return jsValue.toDartInt;
  }
}

extension FloatPtr on Pointer<Float> {
  void setValue(double value) {
    module.setValue(addr, value.toJS, llvmType);
  }

  double getValue() {
    var jsValue = module.getValue(this.addr, llvmType);
    return jsValue.toDartDouble;
  }
}

extension DoublePtr on Pointer<Double> {
  void setValue(double value) {
    module.setValue(addr, value.toJS, llvmType);
  }

  double getValue() {
    var jsValue = module.getValue(this.addr, llvmType);
    return jsValue.toDartDouble;
  }
}

extension StringUtils on String {
  self.Pointer<Char> toNativePointer(NativeLibrary module) {
    var len = module._lengthBytesUTF8(this) + 1;
    var ptr = module._stackAlloc<Char>(len);
    module._stringToUTF8(this, ptr, len);
    return Pointer<Char>(ptr, module);
  }
}

extension type NativeLibrary(JSObject _) implements JSObject {
  
  @JS('stackAlloc')
  external _PtrType<T> _stackAlloc<T extends NativeType>(int numBytes);
  self.Pointer<T> stackAlloc<T extends NativeType>(int count) {
    final numBytes = sizeOf<T>() * count;
    var addr = _stackAlloc<T>(numBytes);
    return Pointer<T>(addr, this);
  }

  external JSNumber getValue(_PtrType addr, String llvmType);
  external void setValue(
      _PtrType addr, JSNumber value, String llvmType);

  @JS("lengthBytesUTF8")
  external int _lengthBytesUTF8(String str);

  @JS("UTF8ToString")
  external String _UTF8ToString(_PtrType<Char> ptr);

  @JS("stringToUTF8")
  external void _stringToUTF8(
      String str, _PtrType<Char> ptr, int maxBytesToWrite);

  external void writeArrayToMemory(JSUint8Array data, JSNumber ptr);

  external _PtrType<NativeFunction> addFunction(
      JSFunction f, String signature);
  external void removeFunction(_PtrType<NativeFunction> f);
  external JSAny get ALLOC_STACK;
  external JSAny get HEAPU32;
  external JSAny get HEAP32;

''');
      s.write('\n');
      for (final b in lookUpBindings) {
        s.write(b.toBindingString(this).string);
      }
      s.write('}\n\n');

      s.write('''
int sizeOf<T>() {
  final size = switch (T) {
    Int32 => 4,
    Float => 4,
    Pointer => sizeOf<Int32>(),
    Int64 => 8,
    Double => 8,
    ${_structs.map((s) => "${s.name} => ${s.sizeInBytes},").join("\n")}
    _ => T.toString().startsWith("Pointer")
        ? sizeOf<Pointer>()
        : throw UnimplementedError(T.toString())
  };
  return size;
}\n''');
    }

    /// Write [noLookUpBindings].
    for (final b in noLookUpBindings) {
      s.write(b.toBindingString(this).string);
    }

    // Write neccesary imports.
    for (final lib in _usedImports) {
      final path = lib.importPath();
      result.write("import '$path' as ${lib.prefix};\n");
    }
    result.write(s);

    // Warn about Enum usage in API surface.
    if (!silenceEnumWarning && usedEnumCType) {
      _logger.severe('The integer type used for enums is '
          'implementation-defined. FFIgen tries to mimic the integer sizes '
          'chosen by the most common compilers for the various OS and '
          'architecture combinations. To prevent any crashes, remove the '
          'enums from your API surface. To rely on the (unsafe!) mimicking, '
          'you can silence this warning by adding silence-enum-warning: true '
          'to the FFIgen config.');
    }

    _canGenerateSymbolOutput = true;
    return result.toString();
  }

  List<Binding> get _allBindings => <Binding>[
        ...noLookUpBindings,
        ...lookUpBindings,
      ];

  Map<String, dynamic> generateSymbolOutputYamlMap(String importFilePath) {
    final bindings = _allBindings;
    if (!canGenerateSymbolOutput) {
      throw Exception('Invalid state: generateSymbolOutputYamlMap() '
          'called before generate()');
    }

    // Warn for macros.
    final hasMacroBindings = bindings.any(
        (element) => element is Constant && element.usr.contains('@macro@'));
    if (hasMacroBindings) {
      _logger.info('Removing all Macros from symbol file since they cannot '
          'be cross referenced reliably.');
    }

    // Remove internal bindings and macros.
    bindings.removeWhere((element) {
      return element.isInternal ||
          (element is Constant && element.usr.contains('@macro@'));
    });

    // Sort bindings alphabetically by USR.
    bindings.sort((a, b) => a.usr.compareTo(b.usr));

    final usesFfiNative = true;

    return {
      strings.formatVersion: strings.symbolFileFormatVersion,
      strings.files: {
        importFilePath: {
          strings.usedConfig: {
            strings.ffiNative: usesFfiNative,
          },
          strings.symbols: {
            for (final b in bindings) b.usr: {strings.name: b.name},
          },
        },
      },
    };
  }

  static String _objcImport(String entryPoint, String outDir) {
    final frameworkHeader = parseObjCFrameworkHeader(entryPoint);

    if (frameworkHeader == null) {
      // If it's not a framework header, use a relative import.
      return '#import "${p.relative(entryPoint, from: outDir)}"\n';
    }

    // If it's a framework header, use a <> style import.
    return '#import <$frameworkHeader>\n';
  }

  /// Writes the Objective C code needed for the bindings, if any. Returns null
  /// if there are no bindings that need generated ObjC code. This function does
  /// not generate the output file, but the [outFilename] does affect the
  /// generated code.
  String? generateObjC(String outFilename) {
    final outDir = p.dirname(outFilename);

    final s = StringBuffer();
    s.write('''
#include <stdint.h>
''');

    for (final entryPoint in nativeEntryPoints) {
      s.write(_objcImport(entryPoint, outDir));
    }
    s.write('''

#if !__has_feature(objc_arc)
#error "This file must be compiled with ARC enabled"
#endif

id objc_retain(id);
id objc_retainBlock(id);
''');

    var empty = true;
    for (final binding in _allBindings) {
      final bindingString = binding.toObjCBindingString(this);
      if (bindingString != null) {
        empty = false;
        s.write(bindingString.string);
      }
    }
    return empty ? null : s.toString();
  }
}

/// Manages the generated `_SymbolAddress` class.
class SymbolAddressWriter {
  final List<_SymbolAddressUnit> _addresses = [];

  /// Used to check if we need to generate `_SymbolAddress` class.
  bool get shouldGenerate => _addresses.isNotEmpty;

  bool get hasNonNativeAddress => _addresses.any((e) => !e.native);

  void addSymbol({
    required String type,
    required String name,
    required String ptrName,
  }) {
    _addresses.add(_SymbolAddressUnit(type, name, ptrName, false));
  }

  void addNativeSymbol({required String type, required String name}) {
    _addresses.add(_SymbolAddressUnit(type, name, '', true));
  }

  String writeObject(Writer w) {
    final className = w._symbolAddressClassName;
    final fieldName = w._symbolAddressVariableName;

    if (hasNonNativeAddress) {
      return 'late final $fieldName = $className(this);';
    } else {
      return 'const $fieldName = $className();';
    }
  }

  String writeClass(Writer w) {
    final sb = StringBuffer();
    sb.write('class ${w._symbolAddressClassName} {\n');

    if (hasNonNativeAddress) {
      // Write Library object.
      sb.write('final ${w._className} ${w._symbolAddressLibraryVarName};\n');
      // Write Constructor.
      sb.write('${w._symbolAddressClassName}('
          'this.${w._symbolAddressLibraryVarName});\n');
    } else {
      // Native bindings are top-level, so we don't need a field here.
      sb.write('const ${w._symbolAddressClassName}();');
    }

    for (final address in _addresses) {
      sb.write('${address.type} get ${address.name} => ');

      if (address.native) {
        // For native fields and functions, we can use Native.addressOf to look
        // up their address.
        // The name of address getter shadows the actual element in the library,
        // so we need to use a self-import.
        final arg = '${w.selfImportPrefix}.${address.name}';
        // sb.writeln('${w.ffiLibraryPrefix}.Native.addressOf($arg);');
      } else {
        // For other elements, the generator will write a private field of type
        // Pointer which we can reference here.
        sb.writeln('${w._symbolAddressLibraryVarName}.${address.ptrName};');
      }
    }
    sb.write('}\n');
    return sb.toString();
  }
}

/// Holds the data for a single symbol address.
class _SymbolAddressUnit {
  final String type, name, ptrName;

  /// Whether the symbol we're looking up has been declared with `@Native`.
  final bool native;

  _SymbolAddressUnit(this.type, this.name, this.ptrName, this.native);
}
