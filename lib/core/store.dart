import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'radio_browser.dart';

/// Az app tartós adatai: adólista, beállítások, dalelőzmények.
class Store extends ChangeNotifier {
  Store._(this._prefs);
  final SharedPreferences _prefs;

  final List<Station> stations = [];
  final AppSettings settings = AppSettings();
  final List<HistoryEntry> history = [];

  /// Ellenőrzött stream-címek (így az első induláshoz nem kell az online adatbázis).
  static const knownUrls = {
    'MegaDance Rádió': 'https://gamershouse.hu:8080/livemega.mp3',
    'Rádió 1': 'https://icast.connectmedia.hu/5201/live.mp3',
    'Retro Rádió': 'https://icast.connectmedia.hu/5001/live.mp3',
  };

  static List<Station> defaults() => [
        Station(
            id: newId(),
            name: 'MegaDance Rádió',
            url: knownUrls['MegaDance Rádió']!,
            query: 'megadance',
            codec: 'MP3',
            bitrate: 192,
            homepage: 'https://megadanceradio.hu'),
        Station(
            id: newId(),
            name: 'Rádió 1',
            url: knownUrls['Rádió 1']!,
            query: 'Rádió 1',
            codec: 'MP3',
            bitrate: 128,
            homepage: 'https://radio1.hu'),
        Station(
            id: newId(),
            name: 'Retro Rádió',
            url: knownUrls['Retro Rádió']!,
            query: 'Retro Rádió',
            codec: 'MP3',
            bitrate: 128,
            homepage: 'https://retroradio.hu'),
      ];

  static Future<Store> load() async {
    final p = await SharedPreferences.getInstance();
    final s = Store._(p);
    try {
      final raw = p.getString('stations');
      if (raw != null) {
        s.stations.addAll((jsonDecode(raw) as List).map((e) => Station.fromJson(Map<String, dynamic>.from(e as Map))));
      } else {
        s.stations.addAll(defaults());
      }
    } catch (_) {
      s.stations.addAll(defaults());
    }
    // korábbi telepítés: ha egy alapadónak még nincs címe, kitöltjük az ismert címmel
    var fixed = false;
    for (final st in s.stations) {
      final known = knownUrls[st.name];
      if (!st.hasUrl && known != null) {
        st.url = known;
        fixed = true;
      }
    }
    if (fixed) s.saveStations();
    try {
      final raw = p.getString('settings');
      if (raw != null) s.settings.load(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {}
    try {
      final raw = p.getString('history');
      if (raw != null) {
        s.history.addAll((jsonDecode(raw) as List).map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map))));
      }
    } catch (_) {}
    return s;
  }

  void saveStations() {
    _prefs.setString('stations', jsonEncode(stations.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  void saveSettings() {
    _prefs.setString('settings', jsonEncode(settings.toJson()));
    notifyListeners();
  }

  void _saveHistory() => _prefs.setString('history', jsonEncode(history.map((e) => e.toJson()).toList()));

  Station? byId(String id) {
    for (final s in stations) {
      if (s.id == id) return s;
    }
    return null;
  }

  bool hasUrl(String url) => stations.any((s) => s.url == url);

  void add(Station s) {
    stations.add(s);
    saveStations();
  }

  void remove(Station s) {
    stations.remove(s);
    history.removeWhere((h) => h.stationId == s.id);
    _saveHistory();
    saveStations();
  }

  void move(int from, int to) {
    if (to < 0 || to >= stations.length) return;
    final s = stations.removeAt(from);
    stations.insert(to, s);
    saveStations();
  }

  void resetToDefaults() {
    stations
      ..clear()
      ..addAll(defaults());
    history.clear();
    _saveHistory();
    saveStations();
  }

  void addHistory(String stationId, String title) {
    final last = history.where((h) => h.stationId == stationId).firstOrNull;
    if (last != null && last.title == title) return;
    history.insert(0, HistoryEntry(DateTime.now(), title, stationId));
    if (history.length > 1000) history.removeRange(1000, history.length);
    _saveHistory();
    notifyListeners();
  }

  void clearHistory({String? stationId}) {
    if (stationId == null) {
      history.clear();
    } else {
      history.removeWhere((h) => h.stationId == stationId);
    }
    _saveHistory();
    notifyListeners();
  }

  /// Az első indításkor kikeresi a hiányzó stream-címeket és logókat.
  Future<void> resolvePending() async {
    var changed = false;
    for (final st in stations.where((s) => s.query.isNotEmpty).toList()) {
      try {
        final found = await RadioBrowser.resolve(st.query);
        if (found == null) continue;
        if (!st.hasUrl) {
          st.url = found.url;
          st.codec = found.codec;
          st.bitrate = found.bitrate;
        }
        if (st.favicon.isEmpty) st.favicon = found.favicon;
        st.query = '';
        changed = true;
      } catch (_) {}
    }
    if (changed) saveStations();
  }

  String exportJson() => prettyJson({
        'app': 'balage-radio',
        'exported': DateTime.now().toIso8601String(),
        'stations': stations.map((e) => e.toJson()).toList(),
      });

  /// A PWA exportját is elfogadja. Visszaadja a beolvasott adók számát.
  int importJson(String text, {required bool replace}) {
    final d = jsonDecode(text);
    final list = (d is Map ? d['stations'] : d) as List;
    final parsed = list
        .whereType<Map>()
        .map((e) => Station.fromJson(Map<String, dynamic>.from(e)))
        .where((s) => s.name.isNotEmpty && s.hasUrl)
        .toList();
    if (replace) {
      stations
        ..clear()
        ..addAll(parsed);
    } else {
      for (final s in parsed) {
        if (!hasUrl(s.url)) stations.add(Station.fromJson({...s.toJson(), 'id': newId()}));
      }
    }
    saveStations();
    return parsed.length;
  }
}
