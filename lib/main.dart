import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_scope.dart';
import 'core/alarm.dart';
import 'core/audio_handler.dart';
import 'core/engine.dart';
import 'core/store.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final earlyErrors = <String>[];
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    final m = 'FLUTTER HIBA: ${d.exceptionAsString()}\n${d.stack.toString().split('\n').take(6).join('\n')}';
    try {
      engine.addLog(m);
    } catch (_) {
      earlyErrors.add(m);
    }
  };
  PlatformDispatcher.instance.onError = (e, st) {
    final m = 'HIBA: $e\n${st.toString().split('\n').take(6).join('\n')}';
    try {
      engine.addLog(m);
    } catch (_) {
      earlyErrors.add(m);
    }
    return true;
  };
  MediaKit.ensureInitialized();

  store = await Store.load();
  engine = RadioEngine(store);
  for (final m in earlyErrors) {
    engine.addLog(m);
  }
  try {
    await engine.init();
  } catch (e) {
    engine.addLog('Lejátszómotor indítási hiba: $e');
  }
  if (Platform.isAndroid) {
    try {
      final crash = await const MethodChannel('balage/system').invokeMethod<String>('previousCrash');
      if (crash != null && crash.trim().isNotEmpty) {
        engine.addLog('--- ELŐZŐ ÖSSZEOMLÁS (rendszernapló) ---\n${crash.trim()}\n--- vége ---');
      }
    } catch (_) {}
  }

  if (Platform.isAndroid) {
    try {
      await AudioService.init(
        builder: () => RadioAudioHandler(engine),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'hu.balagedrone.radio.playback',
          androidNotificationChannelName: 'Lejátszás',
          androidNotificationIcon: 'drawable/ic_stat_radio',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (_) {}
  }

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const opts = WindowOptions(
      size: Size(1120, 760),
      minimumSize: Size(380, 560),
      center: true,
      title: 'Balage Rádió',
      backgroundColor: BC.navyDeep,
    );
    windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  alarms = AlarmService(store, engine);
  await alarms.init();

  runApp(const BalageRadioApp());

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (alarms.launchedByAlarm) {
      await alarms.fire();
    } else if (store.settings.resumeOnStart || Platform.isAndroid && store.settings.autoStartBoot) {
      await engine.resume();
    }
    await store.resolvePending();
  });
}

class BalageRadioApp extends StatefulWidget {
  const BalageRadioApp({super.key});

  @override
  State<BalageRadioApp> createState() => _BalageRadioAppState();
}

class _BalageRadioAppState extends State<BalageRadioApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    engine.setUiVisible(s == AppLifecycleState.resumed || (Platform.isWindows && s == AppLifecycleState.inactive));
    if (s == AppLifecycleState.resumed) alarms.reschedule();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Balage Rádió',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomePage(),
    );
  }
}
