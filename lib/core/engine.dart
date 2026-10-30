import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'icy.dart';
import 'native_meter.dart';
import 'models.dart';
import 'radio_browser.dart';
import 'store.dart';

enum PlayState { stopped, connecting, buffering, playing, reconnecting }

/// A kivezérlésjelző nyers mérései (dBFS), ~30-szor másodpercenként frissül.
class MeterLevels {
  double rmsL = -99, rmsR = -99, peakL = -99, peakR = -99;
  void silence() => rmsL = rmsR = peakL = peakR = -99;
}

/// A lejátszómotor: mpv (media_kit) alapú. Közvetlenül játssza le a streamet,
/// az mpv szűrőláncából jön a hangszín és a LED-jelző, a stream-record a felvétel.
class RadioEngine extends ChangeNotifier {
  RadioEngine(this.store);
  final Store store;

  late final Player player;
  NativePlayer get _np => player.platform as NativePlayer;

  Station? current;
  bool want = false;
  PlayState state = PlayState.stopped;
  String status = '';
  String nowTitle = '';
  final MeterLevels levels = MeterLevels();

  bool recording = false;
  String? recordingPath;
  DateTime? recordingSince;

  /// Ha a felület nem látszik, nem mérünk (akkumulátorkímélés).
  bool uiVisible = true;

  Timer? _titleTimer, _meterTimer, _retryTimer, _stallTimer, _fadeTimer, _watchdog;

  /// Hibanapló a Beállításokban (mpv üzenetek, csatlakozások).
  final List<String> log = [];
  String lastError = '';
  bool _audioFlowing = false;
  Duration _lastPos = Duration.zero;
  DateTime _lastProgress = DateTime.now();

  void addLog(String m) => _log(m);

  void _log(String m) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    log.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $m');
    if (log.length > 400) log.removeRange(0, log.length - 400);
  }
  int _retry = 0;
  bool _meterBusy = false;
  bool _buffering = false, _playing = false;
  bool _resumeAfterInterruption = false;
  bool _ducked = false;
  AudioSession? _session;
  final _subs = <StreamSubscription>[];

  String get songTitle {
    final i = nowTitle.indexOf(' - ');
    return i > 0 ? nowTitle.substring(i + 3).trim() : nowTitle;
  }

  String get artist {
    final i = nowTitle.indexOf(' - ');
    return i > 0 ? nowTitle.substring(0, i).trim() : '';
  }

  Future<void> init() async {
    player = Player(configuration: const PlayerConfiguration(title: 'Balage Rádió', logLevel: MPVLogLevel.warn));
    final opts = {
      'user-agent': 'BalageRadio/1.0',
      'network-timeout': '15',
      'cache': 'yes',
      // autóban (alagút, mobilnet) nagyobb puffer, hogy rövid kiesésnél se álljon meg a zene
      'cache-secs': Platform.isAndroid ? '45' : '20',
      'demuxer-readahead-secs': Platform.isAndroid ? '30' : '10',
      'demuxer-max-bytes': '12MiB',
      'stream-lavf-o': 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=10',
      'audio-buffer': '0.3',
      'cache-on-disk': 'no',
      'audio-display': 'no',
      'vid': 'no',
    };
    for (final kv in opts.entries) {
      try {
        await _np.setProperty(kv.key, kv.value);
      } catch (_) {}
    }
    await player.setVolume(store.settings.volume.toDouble());

    _subs.add(player.stream.playing.listen((v) {
      _playing = v;
      _updateState();
    }));
    _subs.add(player.stream.buffering.listen((b) {
      _buffering = b;
      _updateState();
    }));
    _subs.add(player.stream.position.listen((p) {
      if (p > _lastPos) {
        _lastProgress = DateTime.now();
        if (!_audioFlowing) {
          _audioFlowing = true;
          _filterFails = 0;
          _log('Hang érkezik (${current?.name})');
          _updateState();
        }
      }
      _lastPos = p;
    }));
    // A hibákat csak naplózzuk: az mpv sok átmeneti hibát jelez, ami nem állítja le a lejátszást.
    // Újracsatlakozni a figyelő (watchdog) dönt, ha tényleg nem jön hang.
    _subs.add(player.stream.error.listen((e) {
      lastError = e;
      _log('HIBA: $e');
    }));
    _subs.add(player.stream.log.listen((l) {
      _log('[${l.level}] ${l.prefix}: ${l.text.trim()}');
      // Ha a lejátszómotorból hiányzik egy szűrő, kihagyjuk, és újraindítjuk a lejátszást nélküle.
      final m = RegExp(r"No such filter: '([\w]+)'").firstMatch(l.text);
      if (m != null) {
        _namedMissing = true;
        if (missingFilters.add(m.group(1)!)) _refilterSoon();
      }
      // csak az ismeretlen okú szűrőhibákat számoljuk; a hiányzó szűrőt már fent kihagytuk
      if (l.text.contains('Audio filter initialized failed') && !_namedMissing) {
        _filterFails++;
        _refilterSoon();
      }
    }));
    _subs.add(player.stream.completed.listen((c) {
      if (c && want) _reconnect('Megszakadt');
    }));
    await applyFilters();

    if (Platform.isAndroid) {
      try {
        final s = await AudioSession.instance;
        await s.configure(const AudioSessionConfiguration.music());
        _session = s;
        _subs.add(s.interruptionEventStream.listen(_onInterruption));
        _subs.add(s.becomingNoisyEventStream.listen((_) => stop()));
      } catch (_) {}
    }
  }

  void _onInterruption(AudioInterruptionEvent e) {
    if (e.begin) {
      if (e.type == AudioInterruptionType.duck) {
        if (want) {
          _ducked = true;
          player.setVolume(store.settings.volume * 0.3);
        }
      } else if (want) {
        _resumeAfterInterruption = e.type == AudioInterruptionType.pause;
        stop();
      }
    } else {
      if (_ducked) {
        _ducked = false;
        player.setVolume(store.settings.volume.toDouble());
      }
      if (_resumeAfterInterruption) {
        _resumeAfterInterruption = false;
        resume();
      }
    }
  }

  void _updateState() {
    if (!want) return;
    final s = _playing && _audioFlowing && !_buffering
        ? PlayState.playing
        : (_buffering && _audioFlowing ? PlayState.buffering : PlayState.connecting);
    if (s == PlayState.playing) {
      _retry = 0;
      _stallTimer?.cancel();
    }
    if (state == PlayState.reconnecting && s != PlayState.playing) return;
    if (s != state) {
      state = s;
      status = switch (s) {
        PlayState.playing => 'Élő',
        PlayState.buffering => 'Pufferelés…',
        PlayState.connecting => 'Kapcsolódás…',
        _ => status,
      };
      notifyListeners();
    }
  }

  // ---------- lejátszás ----------

  Future<void> play(Station st, {bool keepVolume = false}) async {
    if (!st.hasUrl) {
      status = 'Ennek az adónak még nincs stream-címe.';
      notifyListeners();
      return;
    }
    if (current?.id != st.id) {
      await stopRecording();
      nowTitle = '';
    }
    current = st;
    want = true;
    _retry = 0;
    if (!keepVolume) {
      _fadeTimer?.cancel();
      _ducked = false;
      await player.setVolume(store.settings.volume.toDouble());
    }
    if (store.byId(st.id) != null) {
      store.settings.lastStationId = st.id;
      store.saveSettings();
    }
    try {
      await _session?.setActive(true);
    } catch (_) {}
    await _open();
    _startTitlePolling();
    _updateMeterTimer();
  }

  Future<void> resume() async {
    final st = current ?? store.byId(store.settings.lastStationId) ?? store.stations.where((s) => s.hasUrl).firstOrNull;
    if (st != null) await play(st);
  }

  Future<void> _open() async {
    _retryTimer?.cancel();
    if (current == null) return;
    state = PlayState.connecting;
    status = 'Kapcsolódás…';
    _audioFlowing = false;
    _lastPos = Duration.zero;
    _lastProgress = DateTime.now();
    lastError = '';
    notifyListeners();
    _namedMissing = false;
    _log('Megnyitás: ${current!.name} – ${current!.url}');
    _startWatchdog();
    try {
      await player.open(Media(current!.url), play: true);
    } catch (e) {
      lastError = '$e';
      _log('Megnyitási hiba: $e');
    }
  }

  /// Ha 20 mp-ig nem halad a lejátszás, újracsatlakozik.
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!want || state == PlayState.reconnecting) return;
      final idle = DateTime.now().difference(_lastProgress).inSeconds;
      if (idle >= 20) _reconnect(_audioFlowing ? 'Elakadt' : 'Nem érkezik hang');
    });
  }

  Future<void> stop() async {
    want = false;
    _watchdog?.cancel();
    _retryTimer?.cancel();
    _stallTimer?.cancel();
    _fadeTimer?.cancel();
    _titleTimer?.cancel();
    await stopRecording();
    try {
      await player.stop();
    } catch (_) {}
    state = PlayState.stopped;
    status = '';
    levels.silence();
    _updateMeterTimer();
    notifyListeners();
  }

  Future<void> toggle() => want ? stop() : resume();

  Future<void> step(int d) async {
    final list = store.stations.where((s) => s.hasUrl).toList();
    if (list.isEmpty) return;
    final i = current == null ? -1 : list.indexWhere((s) => s.id == current!.id);
    await play(list[(i + d + list.length) % list.length]);
  }

  void _reconnect(String reason) {
    if (!want || current == null) return;
    _retryTimer?.cancel();
    _stallTimer?.cancel();
    _retry++;
    final sec = min(30, 1 << min(_retry, 5));
    state = PlayState.reconnecting;
    status = '$reason – újra $sec mp múlva…${lastError.isNotEmpty ? ' ($lastError)' : ''}';
    _log('Újracsatlakozás: $reason, $sec mp múlva');
    notifyListeners();
    _retryTimer = Timer(Duration(seconds: sec), () {
      state = PlayState.connecting;
      _open();
    });
  }

  Future<void> setVolume(int v) async {
    store.settings.volume = v.clamp(0, 100);
    store.saveSettings();
    if (!_ducked) await player.setVolume(store.settings.volume.toDouble());
  }

  /// Ébresztéshez: halkan indul, majd felhangosodik.
  Future<void> playWithFade(Station st, int targetVolume, int minutes) async {
    _fadeTimer?.cancel();
    await player.setVolume(3);
    await play(st, keepVolume: true);
    if (minutes <= 0) {
      await player.setVolume(targetVolume.toDouble());
      return;
    }
    final start = DateTime.now();
    final total = minutes * 60;
    _fadeTimer = Timer.periodic(const Duration(seconds: 2), (t) {
      final f = DateTime.now().difference(start).inSeconds / total;
      final v = (3 + (targetVolume - 3) * f.clamp(0, 1)).toDouble();
      player.setVolume(v);
      if (f >= 1) {
        t.cancel();
        store.settings.volume = targetVolume;
        store.saveSettings();
      }
    });
  }

  // ---------- „most szól” ----------

  void _startTitlePolling() {
    _titleTimer?.cancel();
    _pollTitle();
    _titleTimer = Timer.periodic(const Duration(seconds: 12), (_) => _pollTitle());
  }

  Future<void> _pollTitle() async {
    final st = current;
    if (st == null || !want) return;
    final t = await IcyReader.fetchTitle(st.url);
    if (st != current || !want) return;
    await _setTitle(t);
  }

  bool _isJunk(String t, Station st) {
    final n = RadioBrowser.norm(t);
    return n.length < 3 || n == RadioBrowser.norm(st.name) || RegExp(r'^(unknown|nincscim|live|elo|adv|reklam|hirek?)$').hasMatch(n);
  }

  Future<void> _setTitle(String raw) async {
    var t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (current == null || _isJunk(t, current!)) t = '';
    if (t == nowTitle) return;
    nowTitle = t;
    if (t.isNotEmpty) store.addHistory(current!.id, t);
    notifyListeners();
    if (recording && store.settings.recordPerSong && t.isNotEmpty) {
      await stopRecording();
      await startRecording();
    }
  }

  // ---------- szűrők: hangszín + LED-jelző ----------

  /// A lejátszómotorból hiányzó szűrők (futás közben derül ki).
  /// A beépített mpv-ből ezek a szűrők ismerten hiányoznak (a media_kit FFmpeg-je
  /// csak az „equalizer”-t tartalmazza), ezért ki sem próbáljuk őket.
  final Set<String> missingFilters = {'bass', 'treble', 'acompressor', 'dynaudnorm', 'astats'};

  /// Windowson / Androidon a rendszer hangszintmérője adja a LED-jelző adatait.
  final NativeMeter? nativeMeter = NativeMeter.create();
  String get meterStatus => nativeMeter?.status ?? '';
  String _lastMeterStatus = '';
  final List<List<double>> _vuHist = [];
  double _agcRef = -20;
  DateTime? _dbgT;
  DateTime? _lastMeterRead;
  static double _lin(double db) => db <= -99 ? 0 : pow(10, db / 20).toDouble();
  static double _db20(double lin) => lin > 0.0000001 ? 20 * _log10(lin) : -99.0;
  bool _filtersBroken = false;
  int _filterFails = 0;
  bool _namedMissing = false;
  Timer? _refilterTimer;

  void _refilterSoon() {
    _refilterTimer?.cancel();
    _refilterTimer = Timer(const Duration(milliseconds: 400), () async {
      // ha a hibát nem egy konkrét szűrőnév okozta, biztonságból minden szűrőt kikapcsolunk
      if (_filterFails >= 2) _filtersBroken = true;
      await applyFilters();
      if (want) await _open();
    });
  }

  bool _has(List<String> names) => !_filtersBroken && names.every((n) => !missingFilters.contains(n));

  bool get eqSupported => _has(const ['equalizer']);
  bool get meterSupported => nativeMeter != null || _has(const ['astats']);
  bool get normSupported => _has(const ['acompressor']) || _has(const ['dynaudnorm']);

  Future<void> applyFilters() async {
    final s = store.settings;
    final parts = <String>[];
    if (s.eq.on) {
      if (_has(const ['bass', 'equalizer', 'treble'])) {
        parts.add('@eq:lavfi=[bass=g=${s.eq.low}:f=180:w=0.7,'
            'equalizer=f=1200:t=q:w=0.9:g=${s.eq.mid},'
            'treble=g=${s.eq.high}:f=4500:w=0.7]');
      } else if (_has(const ['equalizer'])) {
        parts.add('@eq:lavfi=[equalizer=f=150:t=q:w=0.8:g=${s.eq.low},'
            'equalizer=f=1200:t=q:w=0.9:g=${s.eq.mid},'
            'equalizer=f=6000:t=q:w=0.8:g=${s.eq.high}]');
      }
      if (s.eq.norm) {
        if (_has(const ['acompressor'])) {
          parts.add('@norm:lavfi=[acompressor=threshold=0.08:ratio=4:attack=10:release=300:makeup=2]');
        } else if (_has(const ['dynaudnorm'])) {
          parts.add('@norm:lavfi=[dynaudnorm=f=250:g=15]');
        }
      }
    }
    if (s.meter && nativeMeter == null && _has(const ['astats'])) parts.add('@vu:lavfi=[astats=metadata=1:reset=1]');
    try {
      await _np.setProperty('af', parts.join(','));
      _log('Szűrők: ${parts.isEmpty ? '(nincs)' : parts.join(', ')}');
    } catch (e) {
      _log('Szűrő hiba: $e');
    }
    _updateMeterTimer();
  }

  void _updateMeterTimer() {
    final run = want && store.settings.meter && uiVisible;
    if (run && _meterTimer == null) {
      _meterTimer = Timer.periodic(const Duration(milliseconds: 33), (_) => _readMeter());
    } else if (!run) {
      _meterTimer?.cancel();
      _meterTimer = null;
      levels.silence();
      nativeMeter?.stop();
    }
  }

  void setUiVisible(bool v) {
    uiVisible = v;
    _updateMeterTimer();
  }

  static final _astats = RegExp(r'lavfi\.astats\.(\d)\.(RMS_level|Peak_level)"?\s*[:=]\s*"?(-?inf|-?[0-9.]+)');

  Future<void> _readMeter() async {
    if (_meterBusy) return;
    _meterBusy = true;
    try {
      final nm = nativeMeter;
      if (nm != null) {
        final v = await nm.read();
        if (nm.status != _lastMeterStatus) {
          _lastMeterStatus = nm.status;
          _log('Szintmérő: ${nm.status}');
        }
        if (v == null) return;
        // Automatikus szintbeállítás: a közelmúlt legnagyobb csúcsa (lassan csökkenő burkoló)
        // lesz a skála teteje, így a jelző a hangerő-csúszkától és a mérési módtól függetlenül
        // ugyanúgy mozog. Az érzékenység-állító ehhez képest tolja el.
        final now = DateTime.now();
        final dt = _lastMeterRead == null ? 0.033 : now.difference(_lastMeterRead!).inMicroseconds / 1e6;
        _lastMeterRead = now;
        final top = max(v[0], v[1]);
        if (top > -90) _agcRef = top > _agcRef ? top : max(top, _agcRef - 0.4 * dt);
        final comp = -_agcRef - 1.5 + store.settings.meterOffset;
        final pl = v[0] <= -90 ? -99.0 : v[0] + comp;
        final pr = v[1] <= -90 ? -99.0 : v[1] + comp;
        // VU-jelleg: a csúcsok ~0,3 mp-es négyzetes átlaga, ahogy egy keverőpult mutatja
        _vuHist.add([_lin(pl), _lin(pr)]);
        if (_vuHist.length > 3) _vuHist.removeAt(0);
        double rms(int c) => sqrt(_vuHist.fold<double>(0, (a, e) => a + e[c] * e[c]) / _vuHist.length);
        levels.rmsL = _db20(rms(0));
        levels.rmsR = _db20(rms(1));
        levels.peakL = pl;
        levels.peakR = pr;
        if (_dbgT == null || now.difference(_dbgT!).inMilliseconds >= 2000) {
          _dbgT = now;
          String f(double x) => x.toStringAsFixed(1);
          _log('Szint: nyers L=${f(v[0])} R=${f(v[1])} dB · referencia=${f(_agcRef)} · sáv L=${f(levels.rmsL)} csúcs L=${f(pl)} · minták=${_vuHist.length}');
        }
        return;
      }
      final raw = await _np.getProperty('af-metadata/vu');
      double? rl, rr, pl, pr;
      for (final m in _astats.allMatches(raw)) {
        final v = m.group(3)!.contains('inf') ? -99.0 : (double.tryParse(m.group(3)!) ?? -99.0);
        final ch = m.group(1);
        final isRms = m.group(2) == 'RMS_level';
        if (ch == '1') {
          if (isRms) {
            rl = v;
          } else {
            pl = v;
          }
        } else if (ch == '2') {
          if (isRms) {
            rr = v;
          } else {
            pr = v;
          }
        }
      }
      if (rl != null) {
        // RMS + 3 dB ≈ szinuszos jelnél a csúcsértékhez igazítva, mint a klasszikus jelzőkön
        levels.rmsL = rl + 3;
        levels.rmsR = (rr ?? rl) + 3;
        levels.peakL = pl ?? rl;
        levels.peakR = pr ?? pl ?? rl;
      }
    } catch (_) {
    } finally {
      _meterBusy = false;
    }
  }

  // ---------- felvétel ----------

  static Future<Directory> recordingsDir() async {
    Directory base;
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'];
      base = Directory(home != null
          ? p.join(home, 'Music', 'Balage Rádió')
          : p.join((await getApplicationDocumentsDirectory()).path, 'Balage Rádió'));
    } else {
      final ext = await getExternalStorageDirectory();
      base = Directory(p.join((ext ?? await getApplicationDocumentsDirectory()).path, 'Felvetelek'));
    }
    await base.create(recursive: true);
    return base;
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<void> startRecording() async {
    final st = current;
    if (st == null || !want) return;
    final dir = await recordingsDir();
    var codec = '';
    try {
      codec = (await _np.getProperty('audio-codec-name')).toLowerCase();
    } catch (_) {}
    if (codec.isEmpty) codec = st.codec.toLowerCase();
    final ext = codec.contains('aac')
        ? 'aac'
        : (codec.contains('vorbis') || codec.contains('opus'))
            ? 'ogg'
            : 'mp3';
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}.${two(now.minute)}.${two(now.second)}';
    final label = store.settings.recordPerSong && nowTitle.isNotEmpty ? nowTitle : st.name;
    var name = _safe(label == st.name ? '${st.name} ($stamp)' : '$label – ${st.name} ($stamp)');
    if (name.length > 150) name = name.substring(0, 150);
    final path = p.join(dir.path, '$name.$ext');
    try {
      await _np.setProperty('stream-record', path);
      recording = true;
      recordingPath = path;
      recordingSince = now;
    } catch (_) {
      recording = false;
    }
    notifyListeners();
  }

  Future<void> stopRecording() async {
    if (!recording) return;
    try {
      await _np.setProperty('stream-record', '');
    } catch (_) {}
    recording = false;
    recordingSince = null;
    notifyListeners();
  }

  Future<void> toggleRecording() => recording ? stopRecording() : startRecording();

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}

/// Tízes alapú logaritmus (a dart:math `log`-ját az osztály `log` mezője elfedné).
double _log10(num x) => log(x) / ln10;
