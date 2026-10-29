import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import 'common.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  void _save({bool filters = false}) {
    store.saveSettings();
    if (filters) engine.applyFilters();
    setState(() {});
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          decoration: BoxDecoration(color: BC.navy, borderRadius: BorderRadius.circular(6), border: Border.all(color: BC.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DotLabel(title),
            const SizedBox(height: 6),
            ...children,
          ]),
        ),
      );

  Widget _eqSlider(String name, int value, ValueChanged<int> onChanged) => Row(children: [
        SizedBox(width: 64, child: Text(name, style: const TextStyle(color: BC.muted))),
        SizedBox(width: 52, child: Text('${value > 0 ? '+' : ''}$value dB', style: const TextStyle(fontSize: 12))),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: -12,
            max: 12,
            divisions: 24,
            onChanged: store.settings.eq.on ? (v) => onChanged(v.round()) : null,
            onChangeEnd: (_) => _save(filters: true),
          ),
        ),
      ]);

  Future<void> _export() async {
    final json = store.exportJson();
    final name = 'balage-radio-adok-${DateTime.now().toIso8601String().substring(0, 10)}.json';
    if (Platform.isWindows) {
      final path = await FilePicker.platform.saveFile(dialogTitle: 'Adólista mentése', fileName: name, allowedExtensions: ['json'], type: FileType.custom);
      if (path == null) return;
      await File(path).writeAsString(json);
      if (mounted) toast(context, 'Elmentve');
    } else {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$name');
      await f.writeAsString(json);
      await Share.shareXFiles([XFile(f.path)], subject: 'Balage Rádió adólista');
    }
  }

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.single;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null || !mounted) return;
    final replace = await confirm(context, 'Lecseréled a mostani listát? (Nem = hozzáfűzés a meglévőkhöz)', ok: 'Lecserélem');
    try {
      final n = store.importJson(utf8.decode(bytes), replace: replace);
      if (mounted) toast(context, '$n adó beolvasva');
    } catch (_) {
      if (mounted) toast(context, 'Ez nem érvényes adólista-fájl');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = store.settings;
    final eq = s.eq;
    return Scaffold(
      appBar: AppBar(title: const Text('Beállítások')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            _section('Kivezérlésjelző', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Két soros LED-es kivezérlésjelző (L / R)'),
                value: s.meter,
                onChanged: (v) {
                  s.meter = v;
                  _save(filters: true);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Csúcsérték-tartás'),
                value: s.peakHold,
                onChanged: s.meter
                    ? (v) {
                        s.peakHold = v;
                        _save();
                      }
                    : null,
              ),
            ]),
            _section('Hangszín', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hangszínszabályzó'),
                value: eq.on,
                onChanged: (v) {
                  eq.on = v;
                  _save(filters: true);
                },
              ),
              _eqSlider('Mély', eq.low, (v) => setState(() => eq.low = v)),
              _eqSlider('Közép', eq.mid, (v) => setState(() => eq.mid = v)),
              _eqSlider('Magas', eq.high, (v) => setState(() => eq.high = v)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hangerő-kiegyenlítés (adók és dalok között)'),
                value: eq.norm,
                onChanged: eq.on
                    ? (v) {
                        eq.norm = v;
                        _save(filters: true);
                      }
                    : null,
              ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in const [('Lineáris', 0, 0, 0), ('Basszus+', 5, 0, 2), ('Beszéd', -2, 3, 1), ('Dance', 3, -1, 4)])
                  ActionChip(
                    label: Text(p.$1),
                    onPressed: eq.on
                        ? () {
                            eq
                              ..low = p.$2
                              ..mid = p.$3
                              ..high = p.$4;
                            _save(filters: true);
                          }
                        : null,
                  ),
              ]),
            ]),
            _section('Felvétel', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dalonként külön fájl'),
                subtitle: const Text('A „most szól” cím váltásakor új fájlt kezd, a dal nevével.', style: TextStyle(color: BC.muted, fontSize: 12)),
                value: s.recordPerSong,
                onChanged: (v) {
                  s.recordPerSong = v;
                  _save();
                },
              ),
              Text(
                Platform.isWindows ? 'Mentési hely: Zene\\Balage Rádió mappa' : 'A felvételeket a Menü → Felvételek oldalon találod.',
                style: const TextStyle(color: BC.muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
            ]),
            _section('Adatok', [
              const Text('Az adólistát átviheted másik eszközre. A régi webes app exportját is be tudja olvasni.',
                  style: TextStyle(color: BC.muted, fontSize: 13)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.upload_file), label: const Text('Exportálás')),
                OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.download), label: const Text('Importálás')),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: BC.danger),
                  onPressed: () async {
                    if (!await confirm(context, 'Visszaállítod az alap adólistát? A saját adóid törlődnek.', ok: 'Visszaállítás')) return;
                    await engine.stop();
                    store.resetToDefaults();
                    await store.resolvePending();
                    if (context.mounted) toast(context, 'Alaplista visszaállítva');
                  },
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Alaplista'),
                ),
              ]),
              const SizedBox(height: 6),
            ]),
            _section('Hibanapló', [
              const Text('Ha valami nem működik, másold ki a naplót, és küldd el.', style: TextStyle(color: BC.muted, fontSize: 13)),
              const SizedBox(height: 8),
              Container(
                height: 160,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: BC.navyDeep, borderRadius: BorderRadius.circular(4), border: Border.all(color: BC.line)),
                child: SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    engine.log.isEmpty ? '(üres)' : engine.log.skip(engine.log.length > 60 ? engine.log.length - 60 : 0).join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: BC.muted),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Napló másolása'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: engine.log.join('\n')));
                    toast(context, 'Napló a vágólapon');
                  },
                ),
                OutlinedButton.icon(icon: const Icon(Icons.refresh, size: 18), label: const Text('Frissítés'), onPressed: () => setState(() {})),
              ]),
              const SizedBox(height: 6),
            ]),
            if (Platform.isWindows)
              _section('Billentyűk', const [
                Text('Szóköz: lejátszás / állj · ← →: előző / következő adó · ↑ ↓: hangerő', style: TextStyle(color: BC.muted)),
                SizedBox(height: 6),
              ]),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Balage Rádió $appVersion · lejátszómotor: mpv', textAlign: TextAlign.center, style: const TextStyle(color: BC.muted, fontSize: 12)),
            ),
          ]),
        ),
      ),
    );
  }
}
