import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import 'theme.dart';

String initialsOf(String name) {
  final w = name.replaceAll(RegExp(r'r[aá]di[oó]', caseSensitive: false), '').trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (w.isEmpty) return name.isNotEmpty ? name[0].toUpperCase() : '?';
  return (w[0][0] + (w.length > 1 ? w[1][0] : '')).toUpperCase();
}

/// Az adó logója, vagy ha nincs, színes monogram.
class StationLogo extends StatelessWidget {
  const StationLogo(this.station, {super.key, this.size = 44, this.radius = 4, this.fontSize});
  final Station station;
  final double size, radius;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final letters = Center(
      child: Text(initialsOf(station.name), style: head(size: fontSize ?? size * 0.38, weight: FontWeight.w700, color: Colors.white)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: BC.toneFor(station.name),
        child: station.favicon.isEmpty
            ? letters
            : Container(
                color: Colors.white,
                padding: EdgeInsets.all(size * 0.07),
                child: Image.network(
                  station.favicon,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(color: BC.toneFor(station.name), child: letters),
                ),
              ),
      ),
    );
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 2600)));
}

String _cleanQ(String t) => t.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').replaceFirst(RegExp(r'\s+-\s+'), ' ').trim();

Future<void> openSpotify(String title) =>
    launchUrl(Uri.parse('https://open.spotify.com/search/${Uri.encodeComponent(_cleanQ(title))}'), mode: LaunchMode.externalApplication);

Future<void> openYoutube(String title) => launchUrl(
    Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeComponent(_cleanQ(title))}'),
    mode: LaunchMode.externalApplication);

/// Kis szekciócím olíva pöttyel, ahogy a weboldalon.
class DotLabel extends StatelessWidget {
  const DotLabel(this.text, {super.key, this.big = false});
  final String text;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: const BoxDecoration(color: BC.oliveLight, shape: BoxShape.circle)),
      SizedBox(width: big ? 10 : 8),
      Flexible(
        child: Text(big ? text : text.toUpperCase(),
            overflow: TextOverflow.ellipsis, style: big ? head(size: 18) : label()),
      ),
    ]);
  }
}

Future<bool> confirm(BuildContext context, String text, {String ok = 'Igen'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Mégse')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}
