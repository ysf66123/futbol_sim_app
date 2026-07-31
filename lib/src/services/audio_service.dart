import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

class AudioService {
  AudioService._();

  static final AudioService instance = AudioService._();

  final List<AudioPlayer> _clickPlayers = [];
  AudioPlayer? _whistlePlayer;
  var _clickIndex = 0;
  bool _initialized = false;
  Future<void>? _initializing;

  Future<void> playClick() async {
    await _ensureReady();
    if (_clickPlayers.isEmpty) return;
    final player = _clickPlayers[_clickIndex % _clickPlayers.length];
    _clickIndex++;
    await player.stop();
    await player.play(
      AssetSource('sounds/click_modern.wav'),
      volume: 0.78,
    );
  }

  Future<void> playWhistle() async {
    await _ensureReady();
    final player = _whistlePlayer;
    if (player == null) return;
    await player.stop();
    await player.play(
      AssetSource('sounds/whistle.wav'),
      volume: 0.9,
    );
  }

  Future<void> _ensureReady() async {
    if (_initialized) return;
    final pending = _initializing;
    if (pending != null) {
      await pending;
      return;
    }

    final completer = Completer<void>();
    _initializing = completer.future;
    try {
      for (var i = 0; i < 3; i++) {
        final player = AudioPlayer(playerId: 'click_$i');
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setReleaseMode(ReleaseMode.stop);
        _clickPlayers.add(player);
      }
      _whistlePlayer = AudioPlayer(playerId: 'whistle_fx');
      await _whistlePlayer!.setReleaseMode(ReleaseMode.stop);
      _initialized = true;
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _initializing = null;
    }
  }
}
