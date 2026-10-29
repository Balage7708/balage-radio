import 'dart:convert';

/// Egy rádióadó a listában.
class Station {
  Station({
    required this.id,
    required this.name,
    this.url = '',
    this.favicon = '',
    this.homepage = '',
    this.codec = '',
    this.bitrate = 0,
    this.tags = '',
    this.query = '',
  });

  final String id;
  String name;
  String url;
  String favicon;
  String homepage;
  String codec;
  int bitrate;
  String tags;

  /// Ha még nincs stream-cím, ez alapján keresi ki a Radio Browserből.
  String query;

  bool get hasUrl => url.trim().isNotEmpty;

  String get subtitle {
    if (!hasUrl) return 'Cím keresése…';
    final parts = <String>[
      if (codec.isNotEmpty) codec.toUpperCase(),
      if (bitrate > 0) '$bitrate kbps',
    ];
    return parts.isEmpty ? 'stream' : parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'favicon': favicon,
        'homepage': homepage,
        'codec': codec,
        'bitrate': bitrate,
        'tags': tags,
        if (query.isNotEmpty) 'query': query,
      };

  factory Station.fromJson(Map<String, dynamic> j) => Station(
        id: (j['id'] ?? newId()).toString(),
        name: (j['name'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        favicon: (j['favicon'] ?? '').toString(),
        homepage: (j['homepage'] ?? '').toString(),
        codec: (j['codec'] ?? '').toString(),
        bitrate: int.tryParse('${j['bitrate'] ?? 0}') ?? 0,
        tags: (j['tags'] ?? '').toString(),
        query: (j['query'] ?? '').toString(),
      );
}

class HistoryEntry {
  HistoryEntry(this.time, this.title, this.stationId);
  final DateTime time;
  final String title;
  final String stationId;

  Map<String, dynamic> toJson() => {'t': time.millisecondsSinceEpoch, 'title': title, 's': stationId};
  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
        (j['title'] ?? '').toString(),
        (j['s'] ?? '').toString(),
      );
}

class EqSettings {
  bool on = false;
  int low = 0, mid = 0, high = 0;
  bool norm = true;

  Map<String, dynamic> toJson() => {'on': on, 'low': low, 'mid': mid, 'high': high, 'norm': norm};
  void load(Map<String, dynamic> j) {
    on = j['on'] == true;
    low = (j['low'] as num?)?.toInt() ?? 0;
    mid = (j['mid'] as num?)?.toInt() ?? 0;
    high = (j['high'] as num?)?.toInt() ?? 0;
    norm = j['norm'] != false;
  }
}

class AlarmSettings {
  bool enabled = false;
  int hour = 7, minute = 0;

  /// 1 = hétfő … 7 = vasárnap
  Set<int> days = {1, 2, 3, 4, 5};
  String stationId = '';
  int fadeMinutes = 3;
  int volume = 70;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'days': days.toList()..sort(),
        'stationId': stationId,
        'fade': fadeMinutes,
        'volume': volume,
      };
  void load(Map<String, dynamic> j) {
    enabled = j['enabled'] == true;
    hour = (j['hour'] as num?)?.toInt() ?? 7;
    minute = (j['minute'] as num?)?.toInt() ?? 0;
    days = ((j['days'] as List?) ?? const [1, 2, 3, 4, 5]).map((e) => (e as num).toInt()).toSet();
    stationId = (j['stationId'] ?? '').toString();
    fadeMinutes = (j['fade'] as num?)?.toInt() ?? 3;
    volume = (j['volume'] as num?)?.toInt() ?? 70;
  }
}

class AppSettings {
  int volume = 85; // 0–100
  bool meter = true;
  bool peakHold = true;

  /// A LED-jelző érzékenysége (dB): negatív = kevesebb LED világít.
  int meterOffset = -9;
  bool recordPerSong = false;
  String lastStationId = '';
  final EqSettings eq = EqSettings();
  final AlarmSettings alarm = AlarmSettings();

  Map<String, dynamic> toJson() => {
        'volume': volume,
        'meter': meter,
        'peak': peakHold,
        'meterOff': meterOffset,
        'recPerSong': recordPerSong,
        'last': lastStationId,
        'eq': eq.toJson(),
        'alarm': alarm.toJson(),
      };
  void load(Map<String, dynamic> j) {
    volume = (j['volume'] as num?)?.toInt() ?? 85;
    meter = j['meter'] != false;
    peakHold = j['peak'] != false;
    meterOffset = (j['meterOff'] as num?)?.toInt() ?? -9;
    recordPerSong = j['recPerSong'] == true;
    lastStationId = (j['last'] ?? '').toString();
    if (j['eq'] is Map) eq.load(Map<String, dynamic>.from(j['eq'] as Map));
    if (j['alarm'] is Map) alarm.load(Map<String, dynamic>.from(j['alarm'] as Map));
  }
}

int _idSeq = 0;
String newId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_idSeq++).toRadixString(36)}';

String prettyJson(Object o) => const JsonEncoder.withIndent('  ').convert(o);
