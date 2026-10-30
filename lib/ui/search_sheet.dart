import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/models.dart';
import '../core/radio_browser.dart';
import 'common.dart';
import 'theme.dart';

Future<void> showAddStation(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= 700;
  if (wide) {
    return showDialog(
      context: context,
      builder: (_) => const Dialog(
        insetPadding: EdgeInsets.all(24),
        child: SizedBox(width: 680, height: 640, child: _AddStation()),
      ),
    );
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(heightFactor: 0.92, child: const _AddStation()),
  );
}

class _AddStation extends StatefulWidget {
  const _AddStation();

  @override
  State<_AddStation> createState() => _AddStationState();
}

class _AddStationState extends State<_AddStation> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _q = TextEditingController();
  bool _byTag = false;
  String _cc = 'HU';
  bool _loading = false;
  String? _error;
  List<Station> _results = [];
  final Set<String> _added = {};

  final _name = TextEditingController();
  final _url = TextEditingController();
  final _logo = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await RadioBrowser.search(_q.text, byTag: _byTag, countryCode: _cc);
      final seen = <String>{};
      final out = <Station>[];
      for (final m in list) {
        final s = RadioBrowser.toStation(m);
        if (!s.hasUrl || !seen.add('${RadioBrowser.norm(s.name)}|${s.url}')) continue;
        out.add(s);
      }
      if (!mounted) return;
      setState(() => _results = out);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _add(Station s) {
    if (store.hasUrl(s.url)) {
      toast(context, 'Már a listádon van');
      return;
    }
    store.add(Station.fromJson({...s.toJson(), 'id': newId()}));
    setState(() => _added.add(s.url));
    toast(context, 'Hozzáadva: ${s.name}');
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
        child: Row(children: [
          Expanded(
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: BC.oliveLight,
              labelColor: BC.paper,
              unselectedLabelColor: BC.muted,
              dividerColor: Colors.transparent,
              tabs: const [Tab(text: 'Keresés'), Tab(text: 'Saját cím')],
            ),
          ),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: TabBarView(controller: _tabs, children: [_searchTab(), _manualTab()]),
      ),
    ]);
  }

  Widget _searchTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(children: [
          TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Adó neve, pl. Petőfi, Jazzy…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<bool>(
                value: _byTag,
                decoration: const InputDecoration(isDense: true, labelText: 'Keresés'),
                items: const [
                  DropdownMenuItem(value: false, child: Text('név szerint')),
                  DropdownMenuItem(value: true, child: Text('műfaj szerint')),
                ],
                onChanged: (v) {
                  setState(() => _byTag = v ?? false);
                  _search();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _cc,
                decoration: const InputDecoration(isDense: true, labelText: 'Ország'),
                items: const [
                  DropdownMenuItem(value: 'HU', child: Text('Magyarország')),
                  DropdownMenuItem(value: '', child: Text('Bármely')),
                  DropdownMenuItem(value: 'AT', child: Text('Ausztria')),
                  DropdownMenuItem(value: 'DE', child: Text('Németország')),
                  DropdownMenuItem(value: 'GB', child: Text('Egyesült Királyság')),
                  DropdownMenuItem(value: 'US', child: Text('USA')),
                ],
                onChanged: (v) {
                  setState(() => _cc = v ?? 'HU');
                  _search();
                },
              ),
            ),
          ]),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: BC.oliveLight))
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                : _results.isEmpty
                    ? const Center(child: Text('Nincs találat.', style: TextStyle(color: BC.muted)))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final s = _results[i];
                          final have = _added.contains(s.url) || store.hasUrl(s.url);
                          final meta = [
                            if (s.codec.isNotEmpty) s.codec,
                            if (s.bitrate > 0) '${s.bitrate} kbps',
                            ...s.tags.split(',').where((t) => t.trim().isNotEmpty).take(3),
                          ].join(' · ');
                          return Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: BC.navyDeep,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: BC.line),
                            ),
                            child: Row(children: [
                              StationLogo(s),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: BC.muted)),
                                ]),
                              ),
                              IconButton.outlined(
                                tooltip: 'Belehallgatás',
                                onPressed: () {
                                  engine.play(s);
                                  toast(context, 'Belehallgatás: ${s.name}');
                                },
                                icon: const Icon(Icons.play_arrow),
                              ),
                              const SizedBox(width: 6),
                              IconButton.filled(
                                tooltip: have ? 'Már a listán' : 'Hozzáadás',
                                style: IconButton.styleFrom(backgroundColor: have ? BC.oliveLight : BC.olive),
                                onPressed: have ? null : () => _add(s),
                                icon: Icon(have ? Icons.check : Icons.add, color: Colors.white),
                              ),
                            ]),
                          );
                        },
                      ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text('Forrás: a nyílt Radio Browser adatbázis. A ▶ gombbal előbb belehallgathatsz.',
            style: TextStyle(fontSize: 12, color: BC.muted)),
      ),
    ]);
  }

  Widget _manualTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Név', hintText: 'pl. Kedvenc rádióm'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Add meg a nevet' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _url,
            decoration: const InputDecoration(labelText: 'Stream-cím (URL)', hintText: 'https://…/live.mp3'),
            validator: (v) => Uri.tryParse((v ?? '').trim())?.hasScheme == true ? null : 'Érvényes címet adj meg',
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _logo, decoration: const InputDecoration(labelText: 'Logó címe (nem kötelező)')),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(
              onPressed: () {
                if (!_form.currentState!.validate()) return;
                engine.play(Station(id: 'preview', name: _name.text.trim(), url: _url.text.trim(), favicon: _logo.text.trim()));
              },
              child: const Text('Kipróbál'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                if (!_form.currentState!.validate()) return;
                store.add(Station(id: newId(), name: _name.text.trim(), url: _url.text.trim(), favicon: _logo.text.trim()));
                toast(context, 'Adó hozzáadva');
                Navigator.pop(context);
              },
              child: const Text('Hozzáadás'),
            ),
          ]),
        ]),
      ),
    );
  }
}
