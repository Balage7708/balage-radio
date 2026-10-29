import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'engine.dart';
import 'store.dart';

/// Ébresztő kedvenc adóval.
/// Androidon rendszerébresztőként ütemezi (teljes képernyős értesítés indítja az appot),
/// Windowson akkor szól, ha az app fut (akár mini lejátszóként vagy a tálcán).
class AlarmService {
  AlarmService(this.store, this.engine);
  final Store store;
  final RadioEngine engine;

  final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
  Timer? _inApp;
  DateTime? _lastFire;
  bool launchedByAlarm = false;
  DateTime? nextAlarm;

  static const _baseId = 100;

  Future<void> init() async {
    tzdata.initializeTimeZones();
    if (Platform.isAndroid) {
      try {
        await _fln.initialize(
          const InitializationSettings(android: AndroidInitializationSettings('ic_stat_radio')),
          onDidReceiveNotificationResponse: (r) {
            if (r.payload == 'alarm') fire();
          },
        );
        final details = await _fln.getNotificationAppLaunchDetails();
        if (details?.didNotificationLaunchApp == true && details?.notificationResponse?.payload == 'alarm') {
          launchedByAlarm = true;
        }
      } catch (_) {}
    }
    await reschedule();
  }

  /// Androidon engedélyek kérése (értesítés, pontos ébresztés, teljes képernyő).
  Future<void> requestPermissions() async {
    if (!Platform.isAndroid) return;
    final a = _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    try {
      await a?.requestNotificationsPermission();
    } catch (_) {}
    try {
      await a?.requestExactAlarmsPermission();
    } catch (_) {}
    try {
      await a?.requestFullScreenIntentPermission();
    } catch (_) {}
  }

  List<DateTime> _occurrences({int count = 7}) {
    final a = store.settings.alarm;
    final now = DateTime.now();
    final out = <DateTime>[];
    for (var d = 0; d < 15 && out.length < count; d++) {
      final t = DateTime(now.year, now.month, now.day + d, a.hour, a.minute);
      if (t.isAfter(now) && a.days.contains(t.weekday)) out.add(t);
    }
    return out;
  }

  Future<void> reschedule() async {
    _inApp?.cancel();
    nextAlarm = null;
    if (Platform.isAndroid) {
      for (var i = 0; i < 7; i++) {
        try {
          await _fln.cancel(_baseId + i);
        } catch (_) {}
      }
    }
    final a = store.settings.alarm;
    if (!a.enabled || a.days.isEmpty) return;
    final occ = _occurrences();
    if (occ.isEmpty) return;
    nextAlarm = occ.first;
    _inApp = Timer(occ.first.difference(DateTime.now()), () {
      fire();
      Timer(const Duration(minutes: 1), reschedule);
    });
    if (Platform.isAndroid) {
      final st = store.byId(a.stationId);
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'alarm',
          'Ébresztő',
          channelDescription: 'Ébresztés kedvenc rádióadóval',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
      );
      for (var i = 0; i < occ.length; i++) {
        try {
          await _fln.zonedSchedule(
            _baseId + i,
            'Ébresztő',
            '${st?.name ?? 'Rádió'} – koppints rá, ha nem indul el magától',
            tz.TZDateTime.from(occ[i], tz.UTC),
            details,
            androidScheduleMode: AndroidScheduleMode.alarmClock,
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
            payload: 'alarm',
          );
        } catch (_) {}
      }
    }
  }

  /// Ébresztés indítása (ütemezve, értesítésről vagy a Teszt gombbal).
  Future<void> fire() async {
    final now = DateTime.now();
    if (_lastFire != null && now.difference(_lastFire!).inSeconds < 90) return;
    _lastFire = now;
    final a = store.settings.alarm;
    final st = store.byId(a.stationId) ?? store.stations.where((s) => s.hasUrl).firstOrNull;
    if (st == null) return;
    await engine.playWithFade(st, a.volume, a.fadeMinutes);
  }

  Future<void> test() async {
    _lastFire = null;
    await fire();
  }
}
