import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app_scope.dart';
import 'common.dart';
import 'led_meter.dart';
import 'theme.dart';

/// Windows: kis, mindig felül lévő lejátszó ablak. Az ablak bárhol megfogva mozgatható.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.onExpand});
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BC.navy,
      body: DragToMoveArea(
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: BC.line)),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: ListenableBuilder(
            listenable: Listenable.merge([engine, store]),
            builder: (context, _) {
              final st = engine.current;
              return Column(children: [
                Row(children: [
                  if (st != null) StationLogo(st, size: 40) else const Icon(Icons.radio, color: BC.oliveLight, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((st?.name ?? 'Balage Rádió').toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: label(size: 10)),
                      const SizedBox(height: 2),
                      Text(
                        engine.nowTitle.isNotEmpty ? engine.nowTitle : (engine.want ? 'Élő adás' : '—'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: head(size: 14),
                      ),
                    ]),
                  ),
                  IconButton(visualDensity: VisualDensity.compact, onPressed: () => engine.step(-1), icon: const Icon(Icons.skip_previous)),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: BC.olive, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                    onPressed: () => engine.toggle(),
                    icon: Icon(engine.want ? Icons.stop : Icons.play_arrow, color: Colors.white),
                  ),
                  IconButton(visualDensity: VisualDensity.compact, onPressed: () => engine.step(1), icon: const Icon(Icons.skip_next)),
                  IconButton(
                    tooltip: 'Teljes ablak',
                    visualDensity: VisualDensity.compact,
                    onPressed: onExpand,
                    icon: const Icon(Icons.open_in_full, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Bezárás',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => windowManager.close(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ]),
                const SizedBox(height: 8),
                if (store.settings.meter) const Expanded(child: LedMeter(height: 64, compact: true)),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
