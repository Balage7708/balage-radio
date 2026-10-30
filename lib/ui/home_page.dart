import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../app_scope.dart';
import '../core/engine.dart';
import '../core/models.dart';
import 'alarm_page.dart';
import 'common.dart';
import 'history_sheet.dart';
import 'led_meter.dart';
import 'mini_player.dart';
import 'recordings_page.dart';
import 'search_sheet.dart';
import 'settings_page.dart';
import 'station_edit.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool editing = false;
  bool mini = false;
  Rect? _savedBounds;

  Future<void> _setMini(bool on) async {
    if (!Platform.isWindows) return;
    if (on) {
      _savedBounds = await windowManager.getBounds();
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setMinimumSize(const Size(340, 150));
      await windowManager.setSize(const Size(440, 178));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setResizable(false);
    } else {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setResizable(true);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      await windowManager.setMinimumSize(const Size(380, 560));
      if (_savedBounds != null) {
        await windowManager.setBounds(_savedBounds!);
      } else {
        await windowManager.setSize(const Size(1120, 760));
      }
    }
    setState(() => mini = on);
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {}); // pl. az autós mód beállítása megváltozhatott
  }

  /// Autós mód: Androidon fekvő, széles képernyőn (pl. 9"-os fejegység), vagy ha be van kapcsolva.
  bool _isCar(BuildContext context) {
    final m = store.settings.carMode;
    if (m == 'on') return true;
    if (m == 'off') return false;
    final sz = MediaQuery.sizeOf(context);
    return Platform.isAndroid && sz.width > sz.height && sz.width >= 700;
  }

  List<Widget> _actions() => [
              IconButton(
                tooltip: 'Lista szerkesztése',
                isSelected: editing,
                selectedIcon: const Icon(Icons.check, color: Colors.white),
                style: editing ? IconButton.styleFrom(backgroundColor: BC.olive) : null,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => setState(() => editing = !editing),
              ),
              IconButton(tooltip: 'Adó hozzáadása', icon: const Icon(Icons.add), onPressed: () => showAddStation(context)),
              PopupMenuButton<String>(
                tooltip: 'Továbbiak',
                icon: const Icon(Icons.more_vert, color: BC.muted),
                onSelected: (v) {
                  switch (v) {
                    case 'alarm':
                      _open(const AlarmPage());
                    case 'rec':
                      _open(const RecordingsPage());
                    case 'settings':
                      _open(const SettingsPage());
                    case 'mini':
                      _setMini(true);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'alarm', child: ListTile(leading: Icon(Icons.alarm), title: Text('Ébresztő'))),
                  const PopupMenuItem(value: 'rec', child: ListTile(leading: Icon(Icons.library_music_outlined), title: Text('Felvételek'))),
                  if (Platform.isWindows)
                    const PopupMenuItem(value: 'mini', child: ListTile(leading: Icon(Icons.picture_in_picture_alt), title: Text('Mini lejátszó'))),
                  const PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('Beállítások'))),
                ],
              ),
      ];

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.space): () => engine.toggle(),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => engine.step(1),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => engine.step(-1),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => engine.setVolume(store.settings.volume + 5),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => engine.setVolume(store.settings.volume - 5),
    };

    if (mini) {
      return CallbackShortcuts(
        bindings: shortcuts,
        child: Focus(autofocus: true, child: MiniPlayer(onExpand: () => _setMini(false))),
      );
    }

    if (_isCar(context)) {
      return CallbackShortcuts(
        bindings: shortcuts,
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 60,
              titleSpacing: 14,
              title: const _Brand(),
              actions: [..._actions(), const SizedBox(width: 6)],
            ),
            body: ListenableBuilder(
              listenable: Listenable.merge([store, engine]),
              builder: (context, _) => _CarLayout(editing: editing, onDone: () => setState(() => editing = false)),
            ),
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: 68,
            titleSpacing: 16,
            title: const _Brand(),
            actions: [
              ..._actions(),
              const SizedBox(width: 8),
            ],
          ),
          body: ListenableBuilder(
            listenable: Listenable.merge([store, engine]),
            builder: (context, _) => LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 900;
              final grid = _StationGrid(editing: editing, onDone: () => setState(() => editing = false));
              if (wide) {
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 390,
                        child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: const PlayerCard(wide: true)),
                      ),
                      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(0, 20, 20, 20), child: grid)),
                    ]),
                  ),
                );
              }
              return ListView(padding: const EdgeInsets.all(16), children: [
                const PlayerCard(wide: false),
                const SizedBox(height: 22),
                grid,
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 44,
        height: 44,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: BC.paper, borderRadius: BorderRadius.circular(4)),
        child: Image.asset('assets/brand-logo.png', fit: BoxFit.contain),
      ),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        RichText(
          text: TextSpan(style: head(size: 19, weight: FontWeight.w500), children: const [
            TextSpan(text: 'Balage ', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: 'Rádió'),
          ]),
        ),
        const SizedBox(height: 2),
        Text('DRONE SERVICES', style: label(size: 9.5)),
      ]),
    ]);
  }
}

/// A lejátszó kártya: logó, most szól, LED-jelző, vezérlők, hangerő, gyorsgombok.
class PlayerCard extends StatefulWidget {
  const PlayerCard({super.key, required this.wide});
  final bool wide;

  @override
  State<PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<PlayerCard> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _ensureTick() {
    if (engine.recording && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    } else if (!engine.recording && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  String _elapsed() {
    final s = engine.recordingSince;
    if (s == null) return '';
    final d = DateTime.now().difference(s);
    String two(int v) => v.toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}' : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([engine, store]),
        builder: (context, _) => _card(context),
      );

  Widget _card(BuildContext context) {
    _ensureTick();
    final st = engine.current;
    final wide = widget.wide;
    final hasSong = engine.nowTitle.isNotEmpty;
    final art = st == null
        ? Container(
            decoration: BoxDecoration(color: BC.navy2, borderRadius: BorderRadius.circular(4)),
            child: Center(child: Icon(Icons.radio, size: wide ? 72 : 40, color: BC.oliveLight)),
          )
        : StationLogo(st, size: wide ? 180 : 96, fontSize: wide ? 68 : 38);

    final meta = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DotLabel(st?.name ?? 'Válassz egy adót'),
        const SizedBox(height: 6),
        Text(
          st == null ? '—' : (hasSong ? engine.songTitle : (engine.want ? 'Élő adás' : '—')),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: wide ? TextAlign.center : TextAlign.start,
          style: head(size: 21),
        ),
        if (engine.artist.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(engine.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: BC.muted, fontSize: 15)),
          ),
        const SizedBox(height: 4),
        _StatusLine(),
      ],
    );

    final playing = engine.want;
    final controls = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _CtlButton(icon: Icons.skip_previous, onTap: () => engine.step(-1), tooltip: 'Előző adó'),
      const SizedBox(width: 16),
      _CtlButton(
        icon: playing ? Icons.stop : Icons.play_arrow,
        big: true,
        onTap: () => engine.toggle(),
        tooltip: playing ? 'Megállítás' : 'Lejátszás',
      ),
      const SizedBox(width: 16),
      _CtlButton(icon: Icons.skip_next, onTap: () => engine.step(1), tooltip: 'Következő adó'),
    ]);

    final vol = Row(children: [
      const Icon(Icons.volume_up, size: 20, color: BC.muted),
      Expanded(
        child: Slider(
          value: store.settings.volume.toDouble(),
          min: 0,
          max: 100,
          onChanged: (v) => engine.setVolume(v.round()),
        ),
      ),
      SizedBox(width: 30, child: Text('${store.settings.volume}', style: const TextStyle(color: BC.muted, fontSize: 12))),
    ]);

    final chips = Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
      ActionChip(
        avatar: Icon(engine.recording ? Icons.stop_circle : Icons.fiber_manual_record, size: 16, color: BC.danger),
        label: Text(engine.recording ? 'Felvétel ${_elapsed()}' : 'Felvétel'),
        side: BorderSide(color: engine.recording ? BC.danger : BC.line),
        onPressed: playing || engine.recording
            ? () async {
                final was = engine.recording;
                await engine.toggleRecording();
                if (!context.mounted) return;
                if (!was && engine.recording) toast(context, 'Felvétel indul');
                if (was) toast(context, 'Felvétel elmentve – Menü → Felvételek');
              }
            : null,
      ),
      ActionChip(
        avatar: const Icon(Icons.music_note, size: 16),
        label: const Text('Spotify'),
        onPressed: hasSong ? () => openSpotify(engine.nowTitle) : null,
      ),
      ActionChip(
        avatar: const Icon(Icons.play_circle_outline, size: 16),
        label: const Text('YouTube'),
        onPressed: hasSong ? () => openYoutube(engine.nowTitle) : null,
      ),
      ActionChip(
        avatar: const Icon(Icons.copy, size: 16),
        label: const Text('Másolás'),
        onPressed: hasSong
            ? () {
                Clipboard.setData(ClipboardData(text: engine.nowTitle));
                toast(context, 'Vágólapra másolva');
              }
            : null,
      ),
      ActionChip(
        avatar: const Icon(Icons.history, size: 16),
        label: const Text('Előzmények'),
        onPressed: () => showHistory(context),
      ),
    ]);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: BC.navy,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BC.line),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 40, offset: Offset(0, 16))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (wide) ...[
          Center(child: SizedBox(width: 180, height: 180, child: art)),
          const SizedBox(height: 16),
          meta,
        ] else
          Row(children: [
            SizedBox(width: 96, height: 96, child: art),
            const SizedBox(width: 14),
            Expanded(child: meta),
          ]),
        if (store.settings.meter && engine.meterSupported) ...[
          const SizedBox(height: 16),
          const LedMeter(),
        ],
        const SizedBox(height: 16),
        controls,
        const SizedBox(height: 8),
        vol,
        const SizedBox(height: 6),
        chips,
      ]),
    );
  }
}

class _StatusLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final live = engine.state == PlayState.playing && engine.want;
    final err = engine.state == PlayState.reconnecting;
    if (engine.status.isEmpty) return const SizedBox(height: 16);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (live)
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(right: 6),
          decoration: const BoxDecoration(color: BC.ok, shape: BoxShape.circle, boxShadow: [BoxShadow(color: BC.ok, blurRadius: 6)]),
        ),
      Flexible(
        child: Text(engine.status,
            overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: err ? BC.danger : BC.muted)),
      ),
    ]);
  }
}

class _CtlButton extends StatelessWidget {
  const _CtlButton({required this.icon, required this.onTap, this.big = false, this.tooltip, this.size});
  final IconData icon;
  final VoidCallback onTap;
  final bool big;
  final String? tooltip;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final s = size ?? (big ? 68.0 : 52.0);
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: big ? BC.olive : BC.navy2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: big ? BC.olive : BC.line)),
        elevation: big ? 6 : 0,
        shadowColor: const Color(0x665E6F49),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: SizedBox(width: s, height: s, child: Icon(icon, size: s * (big ? 0.5 : 0.5), color: Colors.white)),
        ),
      ),
    );
  }
}

class _StationGrid extends StatelessWidget {
  const _StationGrid({required this.editing, required this.onDone, this.big = false});
  final bool editing;
  final VoidCallback onDone;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final list = store.stations;
    final header = Row(children: [
      const Expanded(child: DotLabel('Adóim', big: true)),
      if (editing) TextButton(onPressed: onDone, child: const Text('Kész')),
    ]);
    if (list.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Text('Még nincs adód. Koppints a + gombra.', textAlign: TextAlign.center, style: TextStyle(color: BC.muted)),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, c) {
        final gap = big ? 12.0 : 10.0;
        final cols = editing ? 1 : (c.maxWidth / (big ? 230 : 190)).floor().clamp(1, 6);
        final w = (c.maxWidth - (cols - 1) * gap) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (var i = 0; i < list.length; i++) SizedBox(width: w, child: _StationTile(list[i], i, editing, big: big)),
        ]);
      }),
    ]);
  }
}

class _StationTile extends StatelessWidget {
  const _StationTile(this.st, this.index, this.editing, {this.big = false});
  final Station st;
  final int index;
  final bool editing;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final active = engine.current?.id == st.id;
    final playing = active && engine.want;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: editing ? null : () => playing ? engine.stop() : engine.play(st),
        child: Ink(
          padding: EdgeInsets.all(big ? 14 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: active ? BC.oliveLight : BC.line),
            gradient: active
                ? const LinearGradient(colors: [Color(0x475E6F49), BC.navy], stops: [0, 0.75])
                : null,
            color: active ? null : BC.navy,
          ),
          child: Row(children: [
            StationLogo(st, size: big ? 60 : 44),
            SizedBox(width: big ? 14 : 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(st.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: big ? 19 : 14)),
                const SizedBox(height: 3),
                Text(
                  playing ? '▶ Szól' : st.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: big ? 14 : 11,
                    fontWeight: playing ? FontWeight.w600 : FontWeight.w400,
                    color: playing ? BC.oliveLight : (st.hasUrl ? BC.muted : BC.warn),
                  ),
                ),
              ]),
            ),
            if (editing) ...[
              _SmallBtn(Icons.keyboard_arrow_up, index == 0 ? null : () => store.move(index, index - 1)),
              _SmallBtn(Icons.keyboard_arrow_down, index == store.stations.length - 1 ? null : () => store.move(index, index + 1)),
              _SmallBtn(Icons.edit_outlined, () => showEditStation(context, st)),
              _SmallBtn(Icons.delete_outline, () => deleteStation(context, st), color: BC.danger),
            ],
          ]),
        ),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn(this.icon, this.onTap, {this.color});
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: SizedBox(
        width: 36,
        height: 36,
        child: IconButton.outlined(
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            side: const BorderSide(color: BC.line),
            backgroundColor: BC.navy2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            foregroundColor: color ?? BC.muted,
          ),
          onPressed: onTap,
          icon: Icon(icon, size: 19),
        ),
      ),
    );
  }
}

Future<void> deleteStation(BuildContext context, Station st) async {
  if (!await confirm(context, 'Törlöd a listából: ${st.name}?', ok: 'Törlés')) return;
  if (engine.current?.id == st.id) await engine.stop();
  store.remove(st);
  if (context.mounted) toast(context, 'Törölve: ${st.name}');
}


/// Autós mód (pl. 9"-os, 1280×720-as fejegység): balra nagy lejátszó, jobbra nagy adógombok.
class _CarLayout extends StatelessWidget {
  const _CarLayout({required this.editing, required this.onDone});
  final bool editing;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final h = c.maxHeight;
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 5, child: _CarPlayer(height: h - 28)),
          const SizedBox(width: 14),
          Expanded(
            flex: 6,
            child: SingleChildScrollView(child: _StationGrid(editing: editing, onDone: onDone, big: true)),
          ),
        ]),
      );
    });
  }
}

class _CarPlayer extends StatelessWidget {
  const _CarPlayer({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final st = engine.current;
    final h = height;
    final art = (h * 0.25).clamp(72.0, 170.0);
    final play = (h * 0.21).clamp(76.0, 130.0);
    final meterH = (h * 0.15).clamp(54.0, 96.0);
    final songSize = (h * 0.065).clamp(22.0, 36.0);
    final hasSong = engine.nowTitle.isNotEmpty;
    final playing = engine.want;

    final logo = st == null
        ? Container(
            width: art,
            height: art,
            decoration: BoxDecoration(color: BC.navy2, borderRadius: BorderRadius.circular(4)),
            child: Icon(Icons.radio, size: art * 0.45, color: BC.oliveLight),
          )
        : StationLogo(st, size: art, fontSize: art * 0.38);

    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        logo,
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            DotLabel(st?.name ?? 'Válassz egy adót'),
            const SizedBox(height: 6),
            Text(
              st == null ? '—' : (hasSong ? engine.songTitle : (playing ? 'Élő adás' : '—')),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: head(size: songSize, weight: FontWeight.w700),
            ),
            if (engine.artist.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(engine.artist,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: BC.muted, fontSize: songSize * 0.7)),
              ),
            const SizedBox(height: 4),
            _StatusLine(),
          ]),
        ),
      ]),
      if (store.settings.meter && engine.meterSupported) ...[
        const SizedBox(height: 14),
        LedMeter(height: meterH),
      ],
      const Spacer(),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _CtlButton(icon: Icons.skip_previous, size: play * 0.78, onTap: () => engine.step(-1), tooltip: 'Előző adó'),
        SizedBox(width: play * 0.3),
        _CtlButton(icon: playing ? Icons.stop : Icons.play_arrow, big: true, size: play, onTap: () => engine.toggle()),
        SizedBox(width: play * 0.3),
        _CtlButton(icon: Icons.skip_next, size: play * 0.78, onTap: () => engine.step(1), tooltip: 'Következő adó'),
      ]),
      const Spacer(),
      Row(children: [
        _CarChip(
          icon: engine.recording ? Icons.stop_circle : Icons.fiber_manual_record,
          label: engine.recording ? 'Felvétel ●' : 'Felvétel',
          color: BC.danger,
          active: engine.recording,
          onTap: playing || engine.recording ? () => engine.toggleRecording() : null,
        ),
        const SizedBox(width: 10),
        _CarChip(icon: Icons.history, label: 'Előzmények', onTap: () => showHistory(context)),
        const SizedBox(width: 10),
        const Icon(Icons.volume_up, color: BC.muted),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 6, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12)),
            child: Slider(value: store.settings.volume.toDouble(), min: 0, max: 100, onChanged: (v) => engine.setVolume(v.round())),
          ),
        ),
      ]),
    ]);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: BC.navy, borderRadius: BorderRadius.circular(6), border: Border.all(color: BC.line)),
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: IntrinsicHeight(child: content),
          ),
        ),
      ),
    );
  }
}

class _CarChip extends StatelessWidget {
  const _CarChip({required this.icon, required this.label, this.onTap, this.color, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: BorderSide(color: active ? (color ?? BC.oliveLight) : BC.line),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 22, color: color),
      label: Text(label),
    );
  }
}
