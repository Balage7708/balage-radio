import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models.dart';

/// A nyílt Radio Browser adatbázis (kb. 50 000 adó) kliense.
class RadioBrowser {
  static const _hosts = [
    'de1.api.radio-browser.info',
    'nl1.api.radio-browser.info',
    'at1.api.radio-browser.info',
    'de2.api.radio-browser.info',
  ];
  static const _ua = {'User-Agent': 'BalageRadio/1.0'};

  static Future<List<Map<String, dynamic>>> _get(String path, Map<String, String> q) async {
    final hosts = [..._hosts]..shuffle(Random());
    Object? lastErr;
    for (final h in hosts) {
      try {
        final r = await http.get(Uri.https(h, path, q), headers: _ua).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final data = jsonDecode(utf8.decode(r.bodyBytes));
          return (data as List).cast<Map<String, dynamic>>();
        }
      } catch (e) {
        lastErr = e;
      }
    }
    throw Exception('A rádió-adatbázis most nem érhető el${lastErr != null ? '' : ''}');
  }

  static Future<List<Map<String, dynamic>>> search(String query,
      {bool byTag = false, String countryCode = 'HU', int limit = 60}) {
    final q = <String, String>{
      'hidebroken': 'true',
      'order': 'votes',
      'reverse': 'true',
      'limit': '$limit',
    };
    if (query.trim().isNotEmpty) q[byTag ? 'tag' : 'name'] = query.trim();
    if (countryCode.isNotEmpty) q['countrycode'] = countryCode;
    return _get('/json/stations/search', q);
  }

  static Station toStation(Map<String, dynamic> s) => Station(
        id: newId(),
        name: (s['name'] ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ' '),
        url: ((s['url_resolved'] ?? '').toString().isNotEmpty ? s['url_resolved'] : s['url']).toString(),
        favicon: (s['favicon'] ?? '').toString(),
        homepage: (s['homepage'] ?? '').toString(),
        codec: (s['codec'] ?? '').toString(),
        bitrate: (s['bitrate'] as num?)?.toInt() ?? 0,
        tags: (s['tags'] ?? '').toString(),
      );

  static String norm(String s) {
    const from = 'áéíóöőúüűÁÉÍÓÖŐÚÜŰ';
    const to = 'aeiooouuuAEIOOOUUU';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Név alapján megkeresi a legjobb találatot (https előnyben, utána a szavazatok).
  static Future<Station?> resolve(String query) async {
    final list = await search(query, limit: 40);
    final q = norm(query);
    final cands = list.where((x) => norm('${x['name']}').startsWith(q)).toList();
    int httpsFirst(Map<String, dynamic> a) => '${a['url_resolved']}'.startsWith('https') ? 1 : 0;
    cands.sort((a, b) {
      final h = httpsFirst(b) - httpsFirst(a);
      if (h != 0) return h;
      return ((b['votes'] as num?) ?? 0).compareTo((a['votes'] as num?) ?? 0);
    });
    final best = cands.isNotEmpty ? cands.first : (list.isNotEmpty ? list.first : null);
    return best == null ? null : toStation(best);
  }
}
