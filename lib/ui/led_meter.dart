import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_scope.dart';
import 'theme.dart';

/// Két soros (L / R) LED-es kivezérlésjelző csúcsérték-tartással.
class LedMeter extends StatefulWidget {
  const LedMeter({super.key, this.height = 62, this.compact = false});
  final double height;
  final bool compact;

  @override
  State<LedMeter> createState() => _LedMeterState();
}

class _Ch {
  double lvl = -99, pk = -99;
  Duration hold = Duration.zero;
}

class _LedMeterState extends State<LedMeter> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _ch = [_Ch(), _Ch()];
  Duration _last = Duration.zero;
  final _repaint = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    engine.addListener(_wake);
  }

  void _wake() {
    if (engine.want && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    engine.removeListener(_wake);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.016 : min(0.1, (now - _last).inMicroseconds / 1e6);
    _last = now;
    final live = engine.want;
    final lv = engine.levels;
    final raw = [
      [live ? lv.rmsL : -99.0, live ? lv.peakL : -99.0],
      [live ? lv.rmsR : -99.0, live ? lv.peakR : -99.0],
    ];
    var moving = false;
    for (var c = 0; c < 2; c++) {
      final s = _ch[c];
      final rms = raw[c][0], pk = raw[c][1];
      // gyors felfutás, ~24 dB/s visszaesés
      s.lvl = rms > s.lvl ? s.lvl + (rms - s.lvl) * 0.7 : max(rms, s.lvl - 24 * dt);
      if (pk >= s.pk) {
        s.pk = pk;
        s.hold = now + const Duration(milliseconds: 1200);
      } else if (now > s.hold) {
        s.pk = max(-99, s.pk - 14 * dt);
      }
      if (s.lvl > -60 || s.pk > -60) moving = true;
    }
    if (moving || live) {
      _repaint.value++;
    } else {
      _repaint.value++;
      _last = Duration.zero;
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      padding: EdgeInsets.fromLTRB(8, 8, 8, widget.compact ? 6 : 4),
      decoration: BoxDecoration(
        color: const Color(0xFF06121B),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF1F3343)),
      ),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _MeterPainter(_ch, _repaint, showScale: !widget.compact, peakHold: store.settings.peakHold),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter(this.ch, Listenable repaint, {required this.showScale, required this.peakHold}) : super(repaint: repaint);
  final List<_Ch> ch;
  final bool showScale, peakHold;

  static const n = 32, floor = 50.0, curve = 1.35;
  static double dbAt(int i) => -floor * pow(1 - (i + 1) / n, curve);
  static double posOf(double db) => (1 - pow(min(floor, max(0, -db)) / floor, 1 / curve)) * n;
  static Color colorOf(double db) =>
      db > -3 ? const Color(0xFFFF4634) : (db > -9 ? const Color(0xFFFFB840) : const Color(0xFF7ED65C));

  @override
  void paint(Canvas canvas, Size size) {
    const lab = 14.0, gap = 6.0;
    final scaleH = showScale ? 12.0 : 0.0;
    final rowH = (size.height - gap - scaleH) / 2;
    const x0 = lab + 4;
    final span = size.width - x0 - 2;
    final pitch = span / n;
    final ledW = max(2.0, pitch - max(1.5, pitch * 0.22));
    final tp = TextPainter(textDirection: TextDirection.ltr);

    for (var c = 0; c < 2; c++) {
      final y = c * (rowH + gap);
      tp.text = TextSpan(text: c == 0 ? 'L' : 'R', style: const TextStyle(color: BC.oliveLight, fontSize: 10, fontWeight: FontWeight.w600));
      tp.layout();
      tp.paint(canvas, Offset(1, y + rowH / 2 - tp.height / 2));
      final lit = posOf(ch[c].lvl);
      final pkIdx = min(n - 1, posOf(ch[c].pk).floor());
      for (var i = 0; i < n; i++) {
        final col = colorOf(dbAt(i));
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(x0 + i * pitch, y, ledW, rowH), const Radius.circular(1.5));
        final on = i < lit;
        final isPk = peakHold && i == pkIdx && ch[c].pk > -floor;
        if (on || isPk) {
          canvas.drawRRect(
              r.inflate(1.5),
              Paint()
                ..color = col.withValues(alpha: 0.45)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
          canvas.drawRRect(
              r,
              Paint()
                ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(col, Colors.white, 0.3)!, col, Color.lerp(col, Colors.black, 0.3)!],
                  stops: const [0, 0.55, 1],
                ).createShader(r.outerRect));
        } else {
          canvas.drawRRect(r, Paint()..color = col.withValues(alpha: 0.13));
        }
      }
    }
    if (showScale) {
      final sy = 2 * rowH + gap + 1;
      for (final db in [-40, -20, -10, -6, -3, 0]) {
        tp.text = TextSpan(text: db == 0 ? '0 dB' : '$db', style: const TextStyle(color: Color(0xFF6F8290), fontSize: 9, fontWeight: FontWeight.w500));
        tp.layout();
        var x = x0 + posOf(db.toDouble()) * pitch - (pitch - ledW) / 2 - tp.width / 2 - (db == 0 ? 6 : 0);
        x = x.clamp(x0, size.width - tp.width);
        tp.paint(canvas, Offset(x, sy));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MeterPainter old) => old.peakHold != peakHold || old.showScale != showScale;
}
