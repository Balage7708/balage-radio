import 'core/alarm.dart';
import 'core/engine.dart';
import 'core/store.dart';

/// Az app egyetlen példányú szolgáltatásai.
late final Store store;
late final RadioEngine engine;
late final AlarmService alarms;

const appVersion = '1.0.x (hibanaplóval)';
