import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/models.dart';
import 'common.dart';
import 'theme.dart';

Future<void> showHistory(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 680),
    builder: (_) => const FractionallySizedBox(heightFactor: 0.85, child: _History()),
  );
}

class _History extends StatefulWidget {
  const _History();

  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  bool all = engine.current == null;

  String _day(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return 'MA';
    const months = ['január', 'február', 'március', 'április', 'május', 'június', 'július', 'augusztus', 'szeptember', 'október', 'november', 'december'];
    const days = ['hétfő', 'kedd', 'szerda', 'csütörtök', 'péntek', 'szombat', 'vasárnap'];
    return '${months[d.month - 1]} ${d.day}., ${days[d.weekday - 1]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final cur = engine.current;
        final List<HistoryEntry> rows = all || cur == null ? store.history : store.history.where((h) => h.stationId == cur.id).toList();
        final items = <Widget>[];
        String? lastDay;
        for (final h in rows.take(400)) {
          final d = _day(h.time);
          if (d != lastDay) {
            lastDay = d;
            items.add(Padding(padding: const EdgeInsets.fromLTRB(0, 14, 0, 4), child: Text(d, style: label())));
          }
          final i = h.title.indexOf(' - ');
          final artist = i > 0 ? h.title.substring(0, i) : '';
          final song = i > 0 ? h.title.substring(i + 3) : h.title;
          final sub = [artist, if (all) store.byId(h.stationId)?.name ?? ''].where((e) => e.isNotEmpty).join(' · ');
          items.add(Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BC.line))),
            child: Row(children: [
              SizedBox(
                width: 48,
                child: Text('${h.time.hour.toString().padLeft(2, '0')}:${h.time.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12, color: BC.muted, fontFeatures: [FontFeature.tabularFigures()])),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(song, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 12, color: BC.muted)),
                ]),
              ),
              TextButton(onPressed: () => openSpotify(h.title), child: const Text('Spotify')),
              TextButton(onPressed: () => openYoutube(h.title), child: const Text('YouTube')),
            ]),
          ));
        }
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              Expanded(child: Text('Előzmények', style: head(size: 18))),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Ez az adó')),
                  ButtonSegment(value: true, label: Text('Összes')),
                ],
                selected: {all},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => all = v.first),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Még nincs rögzített dal. A lista magától telik, amíg rádiót hallgatsz.',
                          textAlign: TextAlign.center, style: TextStyle(color: BC.muted)),
                    ),
                  )
                : ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: items),
          ),
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: BC.danger),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Előzmények törlése'),
                  onPressed: () async {
                    if (!await confirm(context, all ? 'Törlöd az összes előzményt?' : 'Törlöd ennek az adónak az előzményeit?', ok: 'Törlés')) return;
                    store.clearHistory(stationId: all ? null : cur?.id);
                  },
                ),
              ),
            ),
        ]);
      },
    );
  }
}
