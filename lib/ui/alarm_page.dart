import 'dart:io';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import 'common.dart';
import 'theme.dart';

class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key});

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> {
  static const _dayNames = ['H', 'K', 'Sze', 'Cs', 'P', 'Szo', 'V'];

  Future<void> _save() async {
    store.saveSettings();
    await alarms.reschedule();
    if (mounted) setState(() {});
  }

  String _nextText() {
    final n = alarms.nextAlarm;
    if (n == null) return 'Nincs beállított ébresztés.';
    const days = ['hétfő', 'kedd', 'szerda', 'csütörtök', 'péntek', 'szombat', 'vasárnap'];
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final sameDay = n.year == now.year && n.month == now.month && n.day == now.day;
    final isTomorrow = n.year == tomorrow.year && n.month == tomorrow.month && n.day == tomorrow.day;
    final when = sameDay ? 'ma' : (isTomorrow ? 'holnap' : days[n.weekday - 1]);
    return 'Következő ébresztés: $when ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final a = store.settings.alarm;
    final stations = store.stations.where((s) => s.hasUrl).toList();
    if (a.stationId.isEmpty && stations.isNotEmpty) a.stationId = stations.first.id;
    final selected = stations.any((s) => s.id == a.stationId) ? a.stationId : (stations.isNotEmpty ? stations.first.id : null);

    return Scaffold(
      appBar: AppBar(title: const Text('Ébresztő')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: BC.navy, borderRadius: BorderRadius.circular(6), border: Border.all(color: BC.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: a.hour, minute: a.minute),
                        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
                      );
                      if (t == null) return;
                      a
                        ..hour = t.hour
                        ..minute = t.minute;
                      await _save();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text('${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}',
                          style: head(size: 52, weight: FontWeight.w600, color: a.enabled ? BC.paper : BC.muted)),
                    ),
                  ),
                  const Spacer(),
                  Switch(
                    value: a.enabled,
                    onChanged: (v) async {
                      a.enabled = v;
                      if (v) await alarms.requestPermissions();
                      await _save();
                    },
                  ),
                ]),
                const SizedBox(height: 4),
                Text(_nextText(), style: const TextStyle(color: BC.muted, fontSize: 13)),
                const SizedBox(height: 16),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(_dayNames[d - 1]),
                      selected: a.days.contains(d),
                      showCheckmark: false,
                      onSelected: (v) async {
                        v ? a.days.add(d) : a.days.remove(d);
                        await _save();
                      },
                    ),
                ]),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  value: selected,
                  decoration: const InputDecoration(labelText: 'Adó'),
                  items: [for (final s in stations) DropdownMenuItem(value: s.id, child: Text(s.name))],
                  onChanged: (v) async {
                    a.stationId = v ?? '';
                    await _save();
                  },
                ),
                const SizedBox(height: 16),
                Text('Felhangosodás: ${a.fadeMinutes == 0 ? 'azonnal teljes hangerő' : '${a.fadeMinutes} perc alatt'}',
                    style: const TextStyle(color: BC.muted)),
                Slider(
                  value: a.fadeMinutes.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  onChanged: (v) => setState(() => a.fadeMinutes = v.round()),
                  onChangeEnd: (_) => _save(),
                ),
                Text('Végső hangerő: ${a.volume}', style: const TextStyle(color: BC.muted)),
                Slider(
                  value: a.volume.toDouble(),
                  min: 10,
                  max: 100,
                  onChanged: (v) => setState(() => a.volume = v.round()),
                  onChangeEnd: (_) => _save(),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await alarms.test();
                      if (context.mounted) toast(context, 'Ébresztő teszt – felhangosodással');
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Kipróbálom most'),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Text(
              Platform.isWindows
                  ? 'Windowson az ébresztő akkor szól, ha a Balage Rádió fut (akár mini lejátszóként vagy lekicsinyítve). A gép nem lehet alvó állapotban.'
                  : 'Androidon az ébresztő akkor is szól, ha az app be van zárva: a megadott időben elindítja az appot és a rádiót. '
                      'Első bekapcsoláskor engedélyezd az értesítéseket és a pontos ébresztést. Ha a telefon az akkumulátor-kímélés miatt késlelteti, '
                      'a Beállítások → Akkumulátor menüben vedd ki a Balage Rádiót az optimalizálásból.',
              style: const TextStyle(color: BC.muted, fontSize: 13, height: 1.45),
            ),
          ]),
        ),
      ),
    );
  }
}
