import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

/// Rendszerszintű hangszintmérő, független a lejátszómotortól.
/// Windows: a Hangerő-keverő saját mérője (IAudioMeterInformation) erre az appra.
/// Android: a rendszer Visualizer mérője (csúcs + RMS).
abstract class NativeMeter {
  /// [csúcsL, csúcsR] dBFS-ben, vagy null, ha még nincs adat.
  Future<List<double>?> read();
  void stop();
  String get status;

  static NativeMeter? create() {
    if (Platform.isWindows) return WinSessionMeter();
    if (Platform.isAndroid) return AndroidMeter();
    return null;
  }
}

double _db(double lin) => lin > 0.0000001 ? 20 * log(lin) / ln10 : -99.0;

// ---------------------------------------------------------------- Android

class AndroidMeter implements NativeMeter {
  static const _ch = MethodChannel('balage/meter');
  bool _started = false;
  DateTime _lastStart = DateTime.fromMillisecondsSinceEpoch(0);
  @override
  String status = '';

  @override
  Future<List<double>?> read() async {
    try {
      if (!_started) {
        if (DateTime.now().difference(_lastStart).inSeconds < 2) return null;
        _lastStart = DateTime.now();
        final r = await _ch.invokeMethod<String>('start');
        status = r ?? '';
        _started = r == 'ok';
        if (!_started) return null;
      }
      final v = await _ch.invokeListMethod<int>('read');
      if (v == null || v.isEmpty) return null;
      final peak = v[0] / 100.0; // millibel → dB
      return [peak, peak];
    } catch (e) {
      status = '$e';
      _started = false;
      return null;
    }
  }

  @override
  void stop() {
    if (!_started) return;
    _started = false;
    _ch.invokeMethod('stop').catchError((_) => null);
  }
}

// ---------------------------------------------------------------- Windows (COM, közvetlen FFI)

final class _GUID extends Struct {
  @Uint32()
  external int d1;
  @Uint16()
  external int d2;
  @Uint16()
  external int d3;
  @Array(8)
  external Array<Uint8> d4;
}

Pointer<_GUID> _guid(String s, Allocator a) {
  final h = s.replaceAll('-', '');
  final p = a<_GUID>();
  p.ref.d1 = int.parse(h.substring(0, 8), radix: 16);
  p.ref.d2 = int.parse(h.substring(8, 12), radix: 16);
  p.ref.d3 = int.parse(h.substring(12, 16), radix: 16);
  for (var i = 0; i < 8; i++) {
    p.ref.d4[i] = int.parse(h.substring(16 + i * 2, 18 + i * 2), radix: 16);
  }
  return p;
}

typedef _CoInitN = Int32 Function(Pointer<Void>, Uint32);
typedef _CoInitD = int Function(Pointer<Void>, int);
typedef _CoCreateN = Int32 Function(Pointer<_GUID>, Pointer<Void>, Uint32, Pointer<_GUID>, Pointer<Pointer<Void>>);
typedef _CoCreateD = int Function(Pointer<_GUID>, Pointer<Void>, int, Pointer<_GUID>, Pointer<Pointer<Void>>);

typedef _ReleaseN = Uint32 Function(Pointer<Void>);
typedef _ReleaseD = int Function(Pointer<Void>);
typedef _QueryN = Int32 Function(Pointer<Void>, Pointer<_GUID>, Pointer<Pointer<Void>>);
typedef _QueryD = int Function(Pointer<Void>, Pointer<_GUID>, Pointer<Pointer<Void>>);
typedef _DefEndpointN = Int32 Function(Pointer<Void>, Int32, Int32, Pointer<Pointer<Void>>);
typedef _DefEndpointD = int Function(Pointer<Void>, int, int, Pointer<Pointer<Void>>);
typedef _ActivateN = Int32 Function(Pointer<Void>, Pointer<_GUID>, Uint32, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _ActivateD = int Function(Pointer<Void>, Pointer<_GUID>, int, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _OutPtrN = Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _OutPtrD = int Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _OutI32N = Int32 Function(Pointer<Void>, Pointer<Int32>);
typedef _OutI32D = int Function(Pointer<Void>, Pointer<Int32>);
typedef _OutU32N = Int32 Function(Pointer<Void>, Pointer<Uint32>);
typedef _OutU32D = int Function(Pointer<Void>, Pointer<Uint32>);
typedef _GetSessionN = Int32 Function(Pointer<Void>, Int32, Pointer<Pointer<Void>>);
typedef _GetSessionD = int Function(Pointer<Void>, int, Pointer<Pointer<Void>>);
typedef _PeaksN = Int32 Function(Pointer<Void>, Uint32, Pointer<Float>);
typedef _PeaksD = int Function(Pointer<Void>, int, Pointer<Float>);

/// Egy COM-objektum vtable-jének [index]. bejegyzése.
Pointer<Void> _fn(Pointer<Void> obj, int index) => obj.cast<Pointer<Pointer<Void>>>().value[index];

void _release(Pointer<Void> p) {
  if (p != nullptr) _fn(p, 2).cast<NativeFunction<_ReleaseN>>().asFunction<_ReleaseD>()(p);
}

class WinSessionMeter implements NativeMeter {
  WinSessionMeter() {
    final ole = DynamicLibrary.open('ole32.dll');
    _coInit = ole.lookupFunction<_CoInitN, _CoInitD>('CoInitializeEx');
    _coCreate = ole.lookupFunction<_CoCreateN, _CoCreateD>('CoCreateInstance');
  }

  late final _CoInitD _coInit;
  late final _CoCreateD _coCreate;
  bool _comReady = false;
  Pointer<Void> _meter = nullptr;
  int _channels = 0;
  DateTime _lastTry = DateTime.fromMillisecondsSinceEpoch(0);
  final Pointer<Float> _buf = calloc<Float>(8);
  @override
  String status = '';

  static const _clsctxAll = 0x17;

  bool _find() {
    if (!_comReady) {
      _coInit(nullptr, 0x2); // COINIT_APARTMENTTHREADED; ha már inicializált, nem baj
      _comReady = true;
    }
    final a = Arena();
    Pointer<Void> en = nullptr, dev = nullptr, mgr = nullptr, se = nullptr;
    try {
      final out = a<Pointer<Void>>();
      var hr = _coCreate(_guid('BCDE0395-E52F-467C-8E3D-C4579291692E', a), nullptr, _clsctxAll,
          _guid('A95664D2-9614-4F35-A746-DE8DB63617E6', a), out);
      if (hr < 0) return _fail('CoCreateInstance $hr');
      en = out.value;
      hr = _fn(en, 4).cast<NativeFunction<_DefEndpointN>>().asFunction<_DefEndpointD>()(en, 0 /*eRender*/, 0 /*eConsole*/, out);
      if (hr < 0) return _fail('Nincs kimeneti hangeszköz ($hr)');
      dev = out.value;
      hr = _fn(dev, 3).cast<NativeFunction<_ActivateN>>().asFunction<_ActivateD>()(dev, _guid('77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F', a), _clsctxAll, nullptr, out);
      if (hr < 0) return _fail('SessionManager $hr');
      mgr = out.value;
      hr = _fn(mgr, 5).cast<NativeFunction<_OutPtrN>>().asFunction<_OutPtrD>()(mgr, out);
      if (hr < 0) return _fail('SessionEnumerator $hr');
      se = out.value;
      final cnt = a<Int32>();
      _fn(se, 3).cast<NativeFunction<_OutI32N>>().asFunction<_OutI32D>()(se, cnt);
      final iidCtl2 = _guid('BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D', a);
      final iidMeter = _guid('C02216F6-8C67-4B5B-9D00-D008E73E0064', a);
      final pidOut = a<Uint32>();
      for (var i = 0; i < cnt.value; i++) {
        if (_fn(se, 4).cast<NativeFunction<_GetSessionN>>().asFunction<_GetSessionD>()(se, i, out) < 0) continue;
        final ctl = out.value;
        try {
          if (_fn(ctl, 0).cast<NativeFunction<_QueryN>>().asFunction<_QueryD>()(ctl, iidCtl2, out) < 0) continue;
          final ctl2 = out.value;
          _fn(ctl2, 14).cast<NativeFunction<_OutU32N>>().asFunction<_OutU32D>()(ctl2, pidOut);
          _release(ctl2);
          if (pidOut.value != pid) continue;
          if (_fn(ctl, 0).cast<NativeFunction<_QueryN>>().asFunction<_QueryD>()(ctl, iidMeter, out) < 0) continue;
          _meter = out.value;
          final ch = a<Uint32>();
          _fn(_meter, 4).cast<NativeFunction<_OutU32N>>().asFunction<_OutU32D>()(_meter, ch);
          _channels = ch.value.clamp(1, 8);
          status = 'ok ($_channels csatorna)';
          return true;
        } finally {
          _release(ctl);
        }
      }
      return _fail('Az app hangja még nem jelent meg a Windows keverőjében');
    } catch (e) {
      return _fail('$e');
    } finally {
      _release(se);
      _release(mgr);
      _release(dev);
      _release(en);
      a.releaseAll();
    }
  }

  bool _fail(String m) {
    status = m;
    return false;
  }

  @override
  Future<List<double>?> read() async {
    if (_meter == nullptr) {
      if (DateTime.now().difference(_lastTry).inMilliseconds < 1000) return null;
      _lastTry = DateTime.now();
      if (!_find()) return null;
    }
    final hr = _fn(_meter, 5).cast<NativeFunction<_PeaksN>>().asFunction<_PeaksD>()(_meter, _channels, _buf);
    if (hr < 0) {
      stop();
      return null;
    }
    final l = _buf[0];
    final r = _channels > 1 ? _buf[1] : l;
    return [_db(l), _db(r)];
  }

  @override
  void stop() {
    if (_meter != nullptr) {
      _release(_meter);
      _meter = nullptr;
    }
  }
}
