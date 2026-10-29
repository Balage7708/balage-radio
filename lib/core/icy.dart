import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Kiolvassa egy rádióstream ICY-metaadatából az épp szóló dal címét.
/// Saját maga dekódolja a szöveget, mert sok magyar adó Windows-1250 kódolással küldi.
class IcyReader {
  static const _cp1250High = '\u20ac\ufffd\u201a\ufffd\u201e\u2026\u2020\u2021\ufffd\u2030\u0160\u2039\u015a\u0164\u017d\u0179\ufffd\u2018\u2019\u201c\u201d\u2022\u2013\u2014\ufffd\u2122\u0161\u203a\u015b\u0165\u017e\u017a\u00a0\u02c7\u02d8\u0141\u00a4\u0104\u00a6\u00a7\u00a8\u00a9\u015e\u00ab\u00ac\u00ad\u00ae\u017b\u00b0\u00b1\u02db\u0142\u00b4\u00b5\u00b6\u00b7\u00b8\u0105\u015f\u00bb\u013d\u02dd\u013e\u017c\u0154\u00c1\u00c2\u0102\u00c4\u0139\u0106\u00c7\u010c\u00c9\u0118\u00cb\u011a\u00cd\u00ce\u010e\u0110\u0143\u0147\u00d3\u00d4\u0150\u00d6\u00d7\u0158\u016e\u00da\u0170\u00dc\u00dd\u0162\u00df\u0155\u00e1\u00e2\u0103\u00e4\u013a\u0107\u00e7\u010d\u00e9\u0119\u00eb\u011b\u00ed\u00ee\u010f\u0111\u0144\u0148\u00f3\u00f4\u0151\u00f6\u00f7\u0159\u016f\u00fa\u0171\u00fc\u00fd\u0163\u02d9';

  static String decode(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      final b = StringBuffer();
      for (final c in bytes) {
        b.write(c < 128 ? String.fromCharCode(c) : _cp1250High[c - 128]);
      }
      return b.toString();
    }
  }

  static Future<String> fetchTitle(String url, {Duration timeout = const Duration(seconds: 9)}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..userAgent = 'BalageRadio/1.0';
    final done = Completer<String>();
    StreamSubscription<List<int>>? sub;
    Timer? guard;
    void finish(String v) {
      if (!done.isCompleted) done.complete(v);
      guard?.cancel();
      sub?.cancel();
      client.close(force: true);
    }

    guard = Timer(timeout, () => finish(''));
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('Icy-MetaData', '1');
      final res = await req.close();
      final metaint = int.tryParse(res.headers.value('icy-metaint') ?? '') ?? 0;
      if (res.statusCode != 200 || metaint <= 0) {
        finish('');
        return await done.future;
      }
      final buf = BytesBuilder(copy: false);
      var pos = metaint;
      sub = res.listen((chunk) {
        buf.add(chunk);
        final data = buf.toBytes();
        while (data.length > pos) {
          final len = data[pos] * 16;
          if (data.length < pos + 1 + len) break;
          if (len > 0) {
            var meta = data.sublist(pos + 1, pos + 1 + len);
            var end = meta.length;
            while (end > 0 && meta[end - 1] == 0) {
              end--;
            }
            meta = meta.sublist(0, end);
            final text = decode(meta);
            final m = RegExp(r"StreamTitle='(.*?)';(?=\s*(?:Stream\w+=|$))", dotAll: true).firstMatch(text) ??
                RegExp(r"StreamTitle='(.*)'", dotAll: true).firstMatch(text);
            finish(m?.group(1)?.trim() ?? '');
            return;
          }
          pos += 1 + len + metaint;
        }
        if (data.length > 400000) finish('');
      }, onError: (_) => finish(''), onDone: () => finish(''), cancelOnError: true);
    } catch (_) {
      finish('');
    }
    return done.future;
  }
}
