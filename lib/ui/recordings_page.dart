import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../core/engine.dart';
import 'common.dart';
import 'theme.dart';

class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  Directory? _dir;
  List<File> _files = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await RadioEngine.recordingsDir();
    final files = d
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'\.(mp3|aac|ogg|m4a)$', caseSensitive: false).hasMatch(f.path))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    if (!mounted) return;
    setState(() {
      _dir = d;
      _files = files;
    });
  }

  String _size(int b) => b > 1024 * 1024 ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB' : '${(b / 1024).round()} kB';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Felvételek'),
        actions: [
          if (Platform.isWindows && _dir != null)
            TextButton.icon(
              onPressed: () => Process.run('explorer', [_dir!.path]),
              icon: const Icon(Icons.folder_open),
              label: const Text('Mappa megnyitása'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: _files.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Még nincs felvételed. Lejátszás közben a „Felvétel” gombbal rögzíthetsz.',
                        textAlign: TextAlign.center, style: TextStyle(color: BC.muted)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _files.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final f = _files[i];
                      final st = f.statSync();
                      final m = st.modified;
                      final date = '${m.year}.${m.month.toString().padLeft(2, '0')}.${m.day.toString().padLeft(2, '0')}. '
                          '${m.hour.toString().padLeft(2, '0')}:${m.minute.toString().padLeft(2, '0')}';
                      return Container(
                        decoration: BoxDecoration(color: BC.navy, borderRadius: BorderRadius.circular(6), border: Border.all(color: BC.line)),
                        child: ListTile(
                          leading: const Icon(Icons.audio_file_outlined, color: BC.oliveLight),
                          title: Text(p.basenameWithoutExtension(f.path), maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text('$date · ${_size(st.size)}', style: const TextStyle(color: BC.muted, fontSize: 12)),
                          onTap: () => OpenFilex.open(f.path),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              tooltip: 'Megosztás',
                              icon: const Icon(Icons.share_outlined),
                              onPressed: () => Share.shareXFiles([XFile(f.path)]),
                            ),
                            IconButton(
                              tooltip: 'Törlés',
                              icon: const Icon(Icons.delete_outline, color: BC.danger),
                              onPressed: () async {
                                if (!await confirm(context, 'Törlöd ezt a felvételt?', ok: 'Törlés')) return;
                                await f.delete();
                                await _load();
                              },
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}
