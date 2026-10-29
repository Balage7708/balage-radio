import 'package:audio_service/audio_service.dart';

import 'engine.dart';

/// Androidon: értesítés, zárolt képernyő, fülhallgató- és Bluetooth-gombok.
class RadioAudioHandler extends BaseAudioHandler {
  RadioAudioHandler(this.engine) {
    engine.addListener(_sync);
    _sync();
  }

  final RadioEngine engine;
  String _lastKey = '';

  void _sync() {
    final st = engine.current;
    final key = '${st?.id}|${engine.nowTitle}|${engine.want}|${engine.state}';
    if (key == _lastKey) return;
    _lastKey = key;

    if (st != null) {
      final hasSong = engine.songTitle.isNotEmpty;
      mediaItem.add(MediaItem(
        id: st.id,
        title: hasSong ? engine.songTitle : st.name,
        artist: hasSong ? (engine.artist.isNotEmpty ? engine.artist : st.name) : 'Élő adás',
        album: st.name,
        artUri: st.favicon.isNotEmpty ? Uri.tryParse(st.favicon) : null,
      ));
    }
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        engine.want ? MediaControl.stop : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: !engine.want
          ? AudioProcessingState.idle
          : engine.state == PlayState.playing
              ? AudioProcessingState.ready
              : AudioProcessingState.buffering,
      playing: engine.want,
    ));
  }

  @override
  Future<void> play() => engine.resume();

  @override
  Future<void> pause() => engine.stop();

  @override
  Future<void> stop() async {
    await engine.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() => engine.step(1);

  @override
  Future<void> skipToPrevious() => engine.step(-1);
}
