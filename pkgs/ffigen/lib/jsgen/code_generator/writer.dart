// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../code_generator.dart';
import '../strings.dart' as strings;
import 'utils.dart';

final _logger = Logger('jsgen.code_generator.writer');

/// To store generated String bindings.
class Writer {
  final String? header;

  final List<Binding> bindings;
  final List<Binding> typeBindings;

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

  /// Initial namers set after running constructor. Namers are reset to this
  /// initial state everytime [generate] is called.
  late UniqueNamer _initialTopLevelUniqueNamer, _initialWrapperLevelUniqueNamer;

  /// Used by [Binding]s for generating required code.
  late UniqueNamer _topLevelUniqueNamer;
  UniqueNamer get topLevelUniqueNamer => _topLevelUniqueNamer;
  late UniqueNamer _wrapperLevelUniqueNamer;
  UniqueNamer get wrapperLevelUniqueNamer => _wrapperLevelUniqueNamer;

  /// Set true after calling [generate]. Indicates if
  /// [generateSymbolOutputYamlMap] can be called.
  bool get canGenerateSymbolOutput => _canGenerateSymbolOutput;
  bool _canGenerateSymbolOutput = false;

  final bool silenceEnumWarning;

  Writer({
    required this.bindings,
    required this.typeBindings,
    required String className,
    List<LibraryImport>? additionalImports,
    this.classDocComment,
    this.header,
    required this.silenceEnumWarning,
    required this.nativeEntryPoints,
  }) {
    final globalLevelNameSet = bindings.map((e) => e.name).toSet();
    final wrapperLevelNameSet = bindings.map((e) => e.name).toSet();
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

  final _arrays = <ConstantArray>{};
  void markArray(ConstantArray arr) {
    _arrays.add(arr);
  }
  
  final _nativeFunctions = <FunctionType>{};
  void markNativeFunction(FunctionType func) {
    _nativeFunctions.add(func);
  }

  /// Resets the namers to initial state. Namers are reset before generating.
  void _resetUniqueNamersNamers() {
    _topLevelUniqueNamer = _initialTopLevelUniqueNamer.clone();
    _wrapperLevelUniqueNamer = _initialWrapperLevelUniqueNamer.clone();
  }

  void markImportUsed(LibraryImport import) {
    _usedImports.add(import);
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

    /// Write [bindings].
    if (bindings.isNotEmpty) {
      // Write doc comment for wrapper class.
      if (classDocComment != null) {
        s.write(makeDartDoc(classDocComment!));
      }
      // Write wrapper classs.

      s.write('''
import 'dart:typed_data';
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
/// The exceptions are [Pointer], [Array] and sub-classes of [Struct]; these can be
/// instantiated and returned to the user.
///
/// Sub-classes doesn't necessarily represent a singular WASM type; for example,
/// WASM does not have a char type but we implement a [Char] type to help
/// preserve "native" type information. Without this, [const char*] would only be
/// represented as Pointer<Int64>, and we would have no way of knowing that
/// it can safely be interpreted/converted to a Dart String.
///
///
abstract final class NativeType {

}

extension type const Pointer<T extends NativeType>(int addr) implements int {
  Pointer<T> operator +(int byteOffset) =>
      Pointer<T>(this.addr + byteOffset);
  Pointer<U> cast<U extends NativeType>() => this as Pointer<U>;
  void free() {
    _lib._free(this);
  }

  int get address => addr;
}

base class PointerClass<T extends NativeType> extends NativeType {
  final Pointer<T> addr;

  PointerClass(this.addr);

  String get llvmType => '*';
  int size() => 4;

  static PointerClass<PointerClass<T>> stackAlloc<T extends NativeType>(int count) {
    return _lib._stackAlloc<T>(4 * count) as PointerClass<PointerClass<T>>;
  }

  PointerClass<T> operator +(int numElements) => PointerClass<T>(
      this.addr.addr + (numElements * size()) as Pointer<T>);
  PointerClass<U> cast<U extends NativeType>() => this as PointerClass<U>;
}

extension type Null._(NativeType value) implements NativeType {

}

Pointer<NativeFunction<T>> addFunction<T>(JSFunction fn, String signature) {
  return _lib.addFunction(fn, signature);
}

extension type Char._(NativeType value) implements NativeType {
  static Pointer<Char> stackAlloc(int count) {
    return Pointer<Char>(_lib._stackAlloc<Char>(4 * count));
  }
}

extension type const Uint32._(NativeType nt) implements NativeType {
  static Pointer<Uint32> stackAlloc(int count) {
    return _lib._stackAlloc<Uint32>(4 * count);
  }
}

extension type const Uint8._(NativeType nt) implements NativeType {
  static Pointer<Uint8> stackAlloc(int count) {
    return _lib._stackAlloc<Uint8>(count);
  }
}

extension type const Int8._(NativeType nt) implements NativeType {
  static Pointer<Int8> stackAlloc(int count) {
    return _lib._stackAlloc<Int8>(count);
  }
}

extension type const Uint16._(NativeType nt) implements NativeType {
  static Pointer<Uint16> stackAlloc(int count) {
    return _lib._stackAlloc<Uint16>(2 * count);
  }
}

extension type const Int16._(NativeType nt) implements NativeType {
  static Pointer<Int16> stackAlloc(int count) {
    return _lib._stackAlloc<Int16>(2 * count);
  }
}

extension type const Int32._(NativeType nt) implements NativeType {
  static Pointer<Int32> stackAlloc(int count) {
    return _lib._stackAlloc<Int32>(4 * count);
  }
}

extension type Int64(NativeType nt) implements NativeType {
  static Pointer<Int64> stackAlloc(int count) {
    return _lib._stackAlloc<Int64>(8 * count);
  }
}
extension type Float32._(NativeType nt) implements NativeType {
  static Pointer<Float32> stackAlloc(int count) {
    return _lib._stackAlloc<Float32>(4 * count);
  }
}
extension type Float64._(NativeType nt) implements NativeType {
  static Pointer<Float64> stackAlloc(int count) {
    return _lib._stackAlloc<Float64>(8 * count);
  }
}
extension type NativeFunction<T>._(NativeType nt) implements NativeType {}
extension type Void._(NativeType nt) implements NativeType {}

Pointer<Never> nullptr = Pointer<Never>(0);

extension PointerPointerClass<T extends NativeType>
    on Pointer<PointerClass<T>> {
  operator [](int i) => this + i;
  void operator []=(int i, Pointer<T> value) {
    _lib.setValue(this + (i * 4), value.addr.toJS, 'i64');
  }
}

extension fncp<T extends NativeType> on void Function(Pointer<T>) {
  Pointer<NativeFunction<void Function(Pointer<T>)>> addFunction() {
    var fnPtr = _lib.addFunction<void Function(Pointer<T>)>(this.toJS, "vp");
    return fnPtr;
  }
}

extension VoidPointerClass on Pointer<Void> {
  String get llvmType => 'v';

  static Pointer<Void> fromAddress(int addr) => Pointer<Void>(addr);
}

extension Int32PointerClass on Pointer<Int32> {
  String get llvmType => 'i32';

  void setValue(int value) {
    _lib.setValue(this, value.toJS, llvmType);
  }

  int getValue() {
    return _lib.getValue(this, llvmType).toDartInt;
  }

  static Pointer<Int32> fromAddress(int addr) => Pointer<Int32>(addr);
}

extension Int64Pointer on Pointer<Int64> {
  String get llvmType => 'i64';

  void setValue(int value) {
    _lib.setValue(this, value.toJS, llvmType);
  }

  int getValue() {
    return _lib.getValue(this, llvmType).toDartInt;
  }

  static Pointer<Int64> fromAddress(int addr) => Pointer<Int64>(addr);
}

extension Float32Pointer on Pointer<Float32> {
  String get llvmType => 'float';

  void setValue(double value) {
    _lib.setValue(this, value.toJS, llvmType);
  }

  double getValue() {
    return _lib.getValue(this, llvmType).toDartDouble;
  }

  Float32List asTypedList(int length) {
    final start = addr;
    final end = addr + (length * 4);
    return Float32List.sublistView(_lib.HEAPU8.toDart, start, end);
  }

  double operator [](int i) {
    return _lib.getValue(this + (i * 4), 'f').toDartDouble;
  }

  operator []=(int i, double val) {
    _lib.setValue(this + (i * 4), val.toJS, 'f');
  }

  static Pointer<Float32> fromAddress(int addr) => Pointer<Float32>(addr);
}

extension Float64Pointer on Pointer<Float64> {
  String get llvmType => 'double';

  void setValue(double value) {
    _lib.setValue(this, value.toJS, llvmType);
  }

  double getValue() {
    return _lib.getValue(this, llvmType).toDartDouble;
  }

  Float64List asTypedList(int length) {
    final start = addr;
    final end = addr + (length * 8);
    return Float64List.sublistView(_lib.HEAPU8.toDart, start, end);
  }

  static Pointer<Float64> fromAddress(int addr) => Pointer<Float64>(addr);
}

extension StringUtils on String {
  self.Pointer<Char> toNativeUtf8() {
    var len = _lib._lengthBytesUTF8(this) + 1;
    var ptr = Char.stackAlloc(len);
    _lib._stringToUTF8(this, ptr, len);
    return ptr;
  }
}

extension CharPtr on Pointer<Char> {
  void setValue(String value) {
    var len = _lib._lengthBytesUTF8(value);
    _lib._stringToUTF8(value, this, len);
  }

  String toDartString() {
    return _lib._UTF8ToString(this);
  }

  static Pointer<Char> fromAddress(int addr) => Pointer<Char>(addr);
}

extension DisposePointerClass<T extends NativeType> on Pointer<NativeFunction> {
  void dispose() {
    _lib.removeFunction(this);
  }
}

sealed class Struct extends NativeType {
  final Pointer _address;

  Struct(this._address);

  static create<T extends Struct>() {
    throw Exception();
  }

}

extension StructPointer<T extends Struct> on T {
  Pointer<T> get address => _address as Pointer<T>;
}

extension type const Array<T extends NativeType>._(
    ({int numElements, Pointer<T> addr}) _) {
  Array<U> cast<U extends NativeType>() => this as Array<U>;

  Uint8List asUint8List() {
    final start = _.addr;
    final end = _.addr.addr + _.numElements;

    return Uint8List.sublistView(
      _lib.HEAPU8.toDart,
      start.addr,
      end,
    );
  }

  void setValue(Uint8List data) {
    _lib.writeArrayToMemory(data.toJS, _.addr);
  }
}

late NativeLibrary _lib;

Pointer<T> malloc<T extends NativeType>(int numBytes) {
  return _lib._malloc<T>(numBytes);
}

void free(Pointer ptr) {
  _lib._free(ptr);
}

@JS('BigInt')
external JSBigInt bigInt(String s);

@JS('BigInt.asUintN')
external JSBigInt bigIntasUintN(int numBits, JSBigInt bi);

extension JSBigIntExtension on JSBigInt {
  
  BigInt get toDart {
    return BigInt.parse(this.toString());
  }
}

extension BigIntExtension on int {
  JSBigInt get toJSBigInt {
    return bigInt(this.toString());
  }
}

extension DartBigIntExtension on BigInt {
  JSBigInt get toJSBigInt {
    return bigInt(this.toString());
  }
}

extension type NativeLibrary(JSObject _) implements JSObject {

  static NativeLibrary get instance => _lib;
  
  static void initBindings(String moduleName) {
    _lib = globalContext.getProperty(moduleName.toJS);
  }

  @JS('stackAlloc')
  external Pointer<T> _stackAlloc<T extends NativeType>(int numBytes);

  external Pointer<T> _malloc<T extends NativeType>(int numBytes);
  external void _free(Pointer ptr);

  @JS('getValue')
  external JSBigInt getValueBigInt(Pointer addr, String llvmType);
  external JSNumber getValue(Pointer addr, String llvmType);
  external void setValue(Pointer addr, JSNumber value, String llvmType);

  @JS("lengthBytesUTF8")
  external int _lengthBytesUTF8(String str);

  @JS("UTF8ToString")
  external String _UTF8ToString(Pointer<Char> ptr);

  @JS("stringToUTF8")
  external void _stringToUTF8(
      String str, Pointer<Char> ptr, int maxBytesToWrite);

  external void writeArrayToMemory(JSUint8Array data, Pointer ptr);

  external Pointer<NativeFunction<T>> addFunction<T>(JSFunction f, String signature);
  external void removeFunction<T>(Pointer<NativeFunction<T>> f);
  external JSUint8Array get HEAPU8;

''');
      s.write('\n');
      for (final b in bindings) {
        s.write(b.toBindingString(this, writeModuleBinding: true).string);
      }
      s.write('}\n\n');
    }

    for (final b in bindings) {
      s.write(b.toBindingString(this, writeModuleBinding: false).string);
    }

    for (final b in typeBindings) {
      s.write(b.toBindingString(this, writeModuleBinding: false).string);
    }

    var written = <String>{};
    _nativeFunctions.forEachIndexed((i, fn) {
      if(written.contains(fn.cacheKey())) {
        return;
      }
      s.write(fn.getExtensionMethod(this, i));
      written.add(fn.cacheKey());
    });

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

  Map<String, dynamic> generateSymbolOutputYamlMap(String importFilePath) {
    if (!canGenerateSymbolOutput) {
      throw Exception('Invalid state: generateSymbolOutputYamlMap() '
          'called before generate()');
    }

    // Warn for macros.
    final hasMacroBindings = bindings.any(
        (element) => element is Constant && element.usr!.contains('@macro@'));
    if (hasMacroBindings) {
      _logger.info('Removing all Macros from symbol file since they cannot '
          'be cross referenced reliably.');
    }

    // Remove internal bindings and macros.
    bindings.removeWhere((element) {
      return element.isInternal ||
          (element is Constant && element.usr!.contains('@macro@'));
    });

    // Sort bindings alphabetically by USR.
    bindings.sort((a, b) => a.usr!.compareTo(b.usr!));

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
}
