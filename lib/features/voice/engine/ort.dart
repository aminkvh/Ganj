import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// A minimal binding to ONNX Runtime's C API: enough to run small models (the voice's letters-to-phonemes model)
/// on the same onnxruntime library that sherpa-onnx already ships with the app.
///
/// Function slots are indices into `OrtApi` (onnxruntime_c_api.h); the table only ever grows, so they hold for every
/// runtime at or above [_apiVersion].
class Ort {
  Ort._(this._api);

  static const _apiVersion = 17;

  final Pointer<Pointer<Void>> _api;

  /// On macOS sherpa-onnx links onnxruntime into its own library, which the app has already loaded: use it from
  /// the process when it is there, else a separate libonnxruntime.dylib.
  static DynamicLibrary _macOS() {
    final p = DynamicLibrary.process();
    return p.providesSymbol('OrtGetApiBase') ? p : DynamicLibrary.open('libonnxruntime.dylib');
  }

  /// Opens onnxruntime from [path], or from the platform's usual name next to the app.
  factory Ort.open([String? path]) {
    final lib = path != null
        ? DynamicLibrary.open(path)
        : Platform.isIOS
        ? DynamicLibrary.process()
        : Platform.isMacOS
        ? _macOS()
        : DynamicLibrary.open(Platform.isWindows ? 'onnxruntime.dll' : 'libonnxruntime.so');
    final base = lib.lookupFunction<Pointer<Pointer<Void>> Function(), Pointer<Pointer<Void>> Function()>(
      'OrtGetApiBase',
    )();
    final getApi = base[0]
        .cast<NativeFunction<Pointer<Pointer<Void>> Function(Uint32)>>()
        .asFunction<Pointer<Pointer<Void>> Function(int)>();
    final api = getApi(_apiVersion);
    if (api == nullptr) throw StateError('onnxruntime does not offer C API version $_apiVersion');
    return Ort._(api);
  }

  Pointer<NativeFunction<N>> _p<N extends Function>(int slot) => _api[slot].cast<NativeFunction<N>>();

  late final _getErrorMessage = _p<Pointer<Utf8> Function(Pointer<Void>)>(2)
      .asFunction<Pointer<Utf8> Function(Pointer<Void>)>();
  late final _releaseStatus = _p<Void Function(Pointer<Void>)>(93).asFunction<void Function(Pointer<Void>)>();
  late final _createEnv = _p<Pointer<Void> Function(Int32, Pointer<Utf8>, Pointer<Pointer<Void>>)>(3)
      .asFunction<Pointer<Void> Function(int, Pointer<Utf8>, Pointer<Pointer<Void>>)>();
  late final _createSessionOptions = _p<Pointer<Void> Function(Pointer<Pointer<Void>>)>(10)
      .asFunction<Pointer<Void> Function(Pointer<Pointer<Void>>)>();
  late final _setIntraOpNumThreads = _p<Pointer<Void> Function(Pointer<Void>, Int32)>(24)
      .asFunction<Pointer<Void> Function(Pointer<Void>, int)>();
  late final _createSessionFromArray =
      _p<Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Size, Pointer<Void>, Pointer<Pointer<Void>>)>(
        8,
      ).asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int, Pointer<Void>, Pointer<Pointer<Void>>)>();
  late final _createCpuMemoryInfo = _p<Pointer<Void> Function(Int32, Int32, Pointer<Pointer<Void>>)>(69)
      .asFunction<Pointer<Void> Function(int, int, Pointer<Pointer<Void>>)>();
  late final _createTensor =
      _p<
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Void>,
              Size,
              Pointer<Int64>,
              Size,
              Int32,
              Pointer<Pointer<Void>>,
            )
          >(49)
          .asFunction<
            Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int, Pointer<Int64>, int, int, Pointer<Pointer<Void>>)
          >();
  late final _run =
      _p<
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Pointer<Utf8>>,
              Pointer<Pointer<Void>>,
              Size,
              Pointer<Pointer<Utf8>>,
              Size,
              Pointer<Pointer<Void>>,
            )
          >(9)
          .asFunction<
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Pointer<Utf8>>,
              Pointer<Pointer<Void>>,
              int,
              Pointer<Pointer<Utf8>>,
              int,
              Pointer<Pointer<Void>>,
            )
          >();
  late final _getTensorMutableData = _p<Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>)>(51)
      .asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>)>();
  late final _getTensorTypeAndShape = _p<Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>)>(65)
      .asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>)>();
  late final _getDimensionsCount = _p<Pointer<Void> Function(Pointer<Void>, Pointer<Size>)>(61)
      .asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Size>)>();
  late final _getDimensions = _p<Pointer<Void> Function(Pointer<Void>, Pointer<Int64>, Size)>(62)
      .asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Int64>, int)>();
  late final _releaseEnv = _p<Void Function(Pointer<Void>)>(92).asFunction<void Function(Pointer<Void>)>();
  late final _releaseMemoryInfo = _p<Void Function(Pointer<Void>)>(94).asFunction<void Function(Pointer<Void>)>();
  late final _releaseSession = _p<Void Function(Pointer<Void>)>(95).asFunction<void Function(Pointer<Void>)>();
  late final _releaseValue = _p<Void Function(Pointer<Void>)>(96).asFunction<void Function(Pointer<Void>)>();
  late final _releaseTypeInfo = _p<Void Function(Pointer<Void>)>(99).asFunction<void Function(Pointer<Void>)>();
  late final _releaseSessionOptions = _p<Void Function(Pointer<Void>)>(100).asFunction<void Function(Pointer<Void>)>();

  void _check(Pointer<Void> status) {
    if (status == nullptr) return;
    final msg = _getErrorMessage(status).toDartString();
    _releaseStatus(status);
    throw OrtException(msg);
  }

  Pointer<Void>? _env;
  Pointer<Void>? _memInfo;

  Pointer<Void> get _environment => _env ??= using<Pointer<Void>>((a) {
    final out = a<Pointer<Void>>();
    _check(_createEnv(3 /* ORT_LOGGING_LEVEL_ERROR */, 'ganj'.toNativeUtf8(allocator: a), out));
    return out.value;
  });

  Pointer<Void> get _cpu => _memInfo ??= using<Pointer<Void>>((a) {
    final out = a<Pointer<Void>>();
    _check(_createCpuMemoryInfo(0 /* OrtDeviceAllocator */, 0 /* OrtMemTypeDefault */, out));
    return out.value;
  });

  /// A session over a model held in memory (avoids wide-character paths on Windows).
  OrtSession session(Uint8List model, {int threads = 2}) => using((a) {
    final opts = a<Pointer<Void>>();
    _check(_createSessionOptions(opts));
    try {
      _check(_setIntraOpNumThreads(opts.value, threads));
      final buf = a<Uint8>(model.length);
      buf.asTypedList(model.length).setAll(0, model);
      final out = a<Pointer<Void>>();
      _check(_createSessionFromArray(_environment, buf.cast(), model.length, opts.value, out));
      return OrtSession._(this, out.value);
    } finally {
      _releaseSessionOptions(opts.value);
    }
  });

  void dispose() {
    if (_memInfo != null) _releaseMemoryInfo(_memInfo!);
    if (_env != null) _releaseEnv(_env!);
    _memInfo = _env = null;
  }
}

class OrtException implements Exception {
  const OrtException(this.message);

  final String message;

  @override
  String toString() => 'OrtException: $message';
}

/// An input tensor: int64 or float32 data with its shape.
class OrtInput {
  OrtInput.int64(this.name, Int64List data, this.shape) : _i64 = data, _f32 = null;

  OrtInput.float32(this.name, Float32List data, this.shape) : _f32 = data, _i64 = null;

  final String name;
  final List<int> shape;
  final Int64List? _i64;
  final Float32List? _f32;
}

/// A float32 output: data and shape, copied out of the runtime.
class OrtOutput {
  const OrtOutput(this.data, this.shape);

  final Float32List data;
  final List<int> shape;
}

class OrtSession {
  OrtSession._(this._ort, this._handle);

  final Ort _ort;
  Pointer<Void>? _handle;

  /// Runs the model on [inputs] and returns the named float32 [outputs].
  List<OrtOutput> run(List<OrtInput> inputs, List<String> outputs) => using((a) {
    final o = _ort;
    final values = a<Pointer<Void>>(inputs.length);
    final inNames = a<Pointer<Utf8>>(inputs.length);
    final outNames = a<Pointer<Utf8>>(outputs.length);
    final outValues = a<Pointer<Void>>(outputs.length);
    final made = <Pointer<Void>>[];
    try {
      for (var i = 0; i < inputs.length; i++) {
        final x = inputs[i];
        inNames[i] = x.name.toNativeUtf8(allocator: a);
        final shape = a<Int64>(x.shape.length);
        shape.asTypedList(x.shape.length).setAll(0, x.shape);
        final Pointer<Void> data;
        final int bytes;
        final int type;
        if (x._i64 != null) {
          final p = a<Int64>(x._i64.length);
          p.asTypedList(x._i64.length).setAll(0, x._i64);
          (data, bytes, type) = (p.cast(), x._i64.length * 8, 7 /* INT64 */);
        } else {
          final p = a<Float>(x._f32!.length);
          p.asTypedList(x._f32.length).setAll(0, x._f32);
          (data, bytes, type) = (p.cast(), x._f32.length * 4, 1 /* FLOAT */);
        }
        final v = a<Pointer<Void>>();
        o._check(o._createTensor(o._cpu, data, bytes, shape, x.shape.length, type, v));
        values[i] = v.value;
        made.add(v.value);
      }
      for (var i = 0; i < outputs.length; i++) {
        outNames[i] = outputs[i].toNativeUtf8(allocator: a);
        outValues[i] = nullptr;
      }
      o._check(o._run(_handle!, nullptr, inNames, values, inputs.length, outNames, outputs.length, outValues));
      return [for (var i = 0; i < outputs.length; i++) _read(a, outValues[i])];
    } finally {
      for (final v in made) {
        o._releaseValue(v);
      }
      for (var i = 0; i < outputs.length; i++) {
        if (outValues[i] != nullptr) o._releaseValue(outValues[i]);
      }
    }
  });

  OrtOutput _read(Allocator a, Pointer<Void> value) {
    final o = _ort;
    final info = a<Pointer<Void>>();
    o._check(o._getTensorTypeAndShape(value, info));
    try {
      final n = a<Size>();
      o._check(o._getDimensionsCount(info.value, n));
      final dims = a<Int64>(n.value);
      o._check(o._getDimensions(info.value, dims, n.value));
      final shape = List<int>.of(dims.asTypedList(n.value));
      final count = shape.fold(1, (p, d) => p * d);
      final data = a<Pointer<Void>>();
      o._check(o._getTensorMutableData(value, data));
      return OrtOutput(Float32List.fromList(data.value.cast<Float>().asTypedList(count)), shape);
    } finally {
      o._releaseTypeInfo(info.value);
    }
  }

  void dispose() {
    if (_handle != null) _ort._releaseSession(_handle!);
    _handle = null;
  }
}
