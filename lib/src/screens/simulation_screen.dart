// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/session_controller.dart';
import '../services/match_engine.dart';
import '../services/room_game_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialogs.dart';
import '../widgets/ui.dart';

class SimulationScreen extends StatefulWidget {
  const SimulationScreen({super.key});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _liveSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _currentSub;
  final ScrollController _flowScrollController = ScrollController();
  Timer? _hostTimer;
  MatchEngine? _engine;
  int? _activeMatchTurn;
  bool _replayMode = false;

  Map<String, dynamic> liveState = {};
  Map<String, dynamic> currentState = {};
  String p1Name = 'Oyuncu 1';
  String p2Name = 'Oyuncu 2';
  bool _persistingResult = false;
  bool _flowPanelOpen = false;
  int _lastFlowPanelLogCount = -1;
  bool _advancingTurn = false;
  bool _hostTickInProgress = false;

  void _runDetached(Future<void> Function() task) {
    unawaited(
      Future<void>.microtask(() async {
        try {
          await task();
        } catch (_) {}
      }),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _currentSub?.cancel();
    _flowScrollController.dispose();
    _resetHostRuntime();
    super.dispose();
  }

  void _resetHostRuntime() {
    _hostTimer?.cancel();
    _hostTimer = null;
    _engine = null;
    _activeMatchTurn = null;
    _replayMode = false;
    _hostTickInProgress = false;
  }

  Future<void> _start() async {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null) return;

    final p1Doc = await roomRef.collection('players').doc('oyuncu_1').get();
    final p2Doc = await roomRef.collection('players').doc('oyuncu_2').get();
    if (mounted) {
      setState(() {
        p1Name = p1Doc.data()?['team_name'] as String? ?? 'Oyuncu 1';
        p2Name = p2Doc.data()?['team_name'] as String? ?? 'Oyuncu 2';
      });
    }

    _currentSub = roomRef
        .collection('game_state')
        .doc('current')
        .snapshots()
        .listen((snapshot) async {
          final data = snapshot.data();
          if (data == null || !mounted) return;
          setState(() => currentState = data);
          if (data['phase'] == 'live_match') {
            await _ensureLiveMatchStarted();
          } else {
            _resetHostRuntime();
          }
        });

    _liveSub = roomRef
        .collection('game_state')
        .doc('live_match')
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data();
          if (data == null || !mounted) return;
          setState(() => liveState = data);
          if ((currentState['phase'] as String? ?? 'drafting') ==
              'live_match') {
            unawaited(_ensureLiveMatchStarted());
          }
        });

    await _ensureLiveMatchStarted();
  }

  Future<void> _ensureLiveMatchStarted() async {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null) return;
    final current =
        (await roomRef.collection('game_state').doc('current').get()).data() ??
        <String, dynamic>{};
    if (current['phase'] != 'live_match') return;
    if (!session.isHost) return;

    final p1Doc =
        (await roomRef.collection('players').doc('oyuncu_1').get()).data() ??
        <String, dynamic>{};
    final p2Doc =
        (await roomRef.collection('players').doc('oyuncu_2').get()).data() ??
        <String, dynamic>{};
    final p1Team = await roomRef
        .collection('players')
        .doc('oyuncu_1')
        .collection('my_team')
        .get();
    final p2Team = await roomRef
        .collection('players')
        .doc('oyuncu_2')
        .collection('my_team')
        .get();
    p1Doc['my_team_list'] = p1Team.docs
        .map((doc) => {'id': doc.id, 'data': doc.data()})
        .toList(growable: false);
    p2Doc['my_team_list'] = p2Team.docs
        .map((doc) => {'id': doc.id, 'data': doc.data()})
        .toList(growable: false);

    final live =
        (await roomRef.collection('game_state').doc('live_match').get())
            .data() ??
        <String, dynamic>{};
    final initialScore = Map<String, int>.from(
      (live['score'] as Map?)?.map(
            (key, value) =>
                MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
          ) ??
          {'oyuncu_1': 0, 'oyuncu_2': 0},
    );
    final roomData = (await roomRef.get()).data() ?? <String, dynamic>{};
    final matchTurn = (live['match_turn'] as num?)?.toInt() ?? 0;
    final currentTurn = (current['current_turn'] as num?)?.toInt() ?? matchTurn;
    final preparedTurn = (live['prepared_turn'] as num?)?.toInt();
    final replaySteps = List<Map<String, dynamic>>.from(
      ((live['replay_steps'] as List?) ?? const []).map(
        (step) =>
            Map<String, dynamic>.from((step as Map).cast<String, dynamic>()),
      ),
    );
    if (matchTurn != currentTurn) {
      return;
    }
    if (preparedTurn == null || preparedTurn != currentTurn) {
      return;
    }
    if (replaySteps.isNotEmpty) {
      final shouldStartReplay =
          _hostTimer?.isActive != true ||
          _activeMatchTurn != matchTurn ||
          !_replayMode;
      if (!shouldStartReplay) return;
      session.playWhistleSound();
      _resetHostRuntime();
      _replayMode = true;
      _activeMatchTurn = matchTurn;
      _hostTimer = Timer.periodic(
        const Duration(milliseconds: 650),
        (_) => _hostReplayLoop(),
      );
      return;
    }
    _engine = MatchEngine(
      p1Doc,
      p2Doc,
      (live['match_number'] as num?)?.toInt() ?? 1,
      live['weather'] as String? ?? 'Güneşli',
      live['home_id'] as String? ?? 'oyuncu_1',
      initialScore,
      roomData['is_bot'] == true,
      specialEvent:
          (live['special_event'] as Map?)?.cast<String, dynamic>() ??
          (current['match_special_event'] as Map?)?.cast<String, dynamic>(),
    );
    _activeMatchTurn = matchTurn;

    _hostTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _hostLoop(),
    );
  }

  Map<String, dynamic> _projectReplayStats(
    Map<String, dynamic>? finalStats,
    int minute,
  ) {
    if (finalStats == null || finalStats.isEmpty) return const {};
    final progress = (minute / 90).clamp(0.0, 1.0);
    final projected = <String, dynamic>{};
    for (final entry in finalStats.entries) {
      final teamStats = Map<String, dynamic>.from(
        (entry.value as Map?) ?? const <String, dynamic>{},
      );
      final nextTeamStats = <String, dynamic>{};
      for (final statEntry in teamStats.entries) {
        final value = statEntry.value;
        if ((statEntry.key == 'pass_percentage' ||
                statEntry.key == 'possession_percent') &&
            value is num) {
          nextTeamStats[statEntry.key] = value.toInt();
          continue;
        }
        if (value is int) {
          nextTeamStats[statEntry.key] = (value * progress).round();
          continue;
        }
        if (value is num) {
          nextTeamStats[statEntry.key] = double.parse(
            (value.toDouble() * progress).toStringAsFixed(2),
          );
          continue;
        }
        nextTeamStats[statEntry.key] = value;
      }
      projected[entry.key] = nextTeamStats;
    }
    return projected;
  }

  Future<void> _hostReplayLoop() async {
    if (_hostTickInProgress) return;
    _hostTickInProgress = true;
    try {
      final session = context.read<SessionController>();
      final roomRef = session.roomRef;
      if (roomRef == null) return;

      final currentDoc = await roomRef
          .collection('game_state')
          .doc('current')
          .get();
      final current = currentDoc.data() ?? <String, dynamic>{};
      if (current['phase'] != 'live_match') {
        _resetHostRuntime();
        return;
      }

      final liveRef = roomRef.collection('game_state').doc('live_match');
      final liveDoc = await liveRef.get();
      final state = liveDoc.data() ?? <String, dynamic>{};
      if (state['is_finished'] == true) {
        _resetHostRuntime();
        return;
      }

      final replaySteps = List<Map<String, dynamic>>.from(
        ((state['replay_steps'] as List?) ?? const []).map(
          (step) =>
              Map<String, dynamic>.from((step as Map).cast<String, dynamic>()),
        ),
      );
      if (replaySteps.isEmpty) {
        _resetHostRuntime();
        return;
      }

      final replayIndex = (state['replay_index'] as num?)?.toInt() ?? 0;
      final currentTurn = (state['match_turn'] as num?)?.toInt() ?? 0;
      final preparedTurn = (state['prepared_turn'] as num?)?.toInt();
      if (preparedTurn == null || preparedTurn != currentTurn) {
        _resetHostRuntime();
        return;
      }
      if (replayIndex >= replaySteps.length) {
        _resetHostRuntime();
        await _completeReplayIfStillLive(
          roomRef: roomRef,
          currentTurn: currentTurn,
        );
        return;
      }

      final step = replaySteps[replayIndex];
      final minute = (step['minute'] as num?)?.toInt() ?? 0;
      final finalData =
          (state['replay_final_data'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final projectedStats = _projectReplayStats(
        (finalData['stats'] as Map?)?.cast<String, dynamic>(),
        minute,
      );
      final update = <String, dynamic>{
        'minute': minute,
        'score': Map<String, dynamic>.from(
          (step['score'] as Map?) ?? (state['score'] as Map?) ?? const {},
        ),
        'momentum': (step['momentum'] as num?)?.toInt() ?? 50,
        'red_cards': List<String>.from(
          (step['red_cards'] as List?) ?? const [],
        ),
        'yellow_cards': List<String>.from(
          (step['yellow_cards'] as List?) ?? const [],
        ),
        'injuries': List<String>.from((step['injuries'] as List?) ?? const []),
        'stats': projectedStats,
        'replay_index': replayIndex + 1,
      };
      final stepLogs = List<String>.from((step['logs'] as List?) ?? const []);
      if (stepLogs.isNotEmpty) {
        update['log'] = FieldValue.arrayUnion(stepLogs);
      }
      await liveRef.update(update);

      if (replayIndex + 1 >= replaySteps.length) {
        _resetHostRuntime();
        await _completeReplayIfStillLive(
          roomRef: roomRef,
          currentTurn: currentTurn,
        );
      }
    } finally {
      _hostTickInProgress = false;
    }
  }

  Future<void> _completeReplayIfStillLive({
    required DocumentReference<Map<String, dynamic>> roomRef,
    required int currentTurn,
  }) async {
    final currentDoc =
        (await roomRef.collection('game_state').doc('current').get()).data() ??
        const <String, dynamic>{};
    if ((currentDoc['phase'] as String? ?? 'drafting') != 'live_match') {
      return;
    }
    if ((currentDoc['current_turn'] as num?)?.toInt() != currentTurn) {
      return;
    }
    final liveDoc =
        (await roomRef.collection('game_state').doc('live_match').get())
            .data() ??
        const <String, dynamic>{};
    if ((liveDoc['match_turn'] as num?)?.toInt() != currentTurn) {
      return;
    }
    final preparedTurn = (liveDoc['prepared_turn'] as num?)?.toInt();
    if (preparedTurn == null || preparedTurn != currentTurn) {
      return;
    }
    await RoomGameService.completePreparedMatchReplay(
      roomRef: roomRef,
      currentTurn: currentTurn,
    );
  }

  Future<void> _hostLoop() async {
    if (_hostTickInProgress) return;
    _hostTickInProgress = true;
    try {
      final session = context.read<SessionController>();
      final roomRef = session.roomRef;
      if (roomRef == null || _engine == null) return;

      final liveDoc = await roomRef
          .collection('game_state')
          .doc('live_match')
          .get();
      final state = liveDoc.data();
      if (state == null || state['is_finished'] == true) {
        _resetHostRuntime();
        return;
      }

      final p1LiveSubs = List<Map<String, dynamic>>.from(
        (state['p1_live_subs'] as List?) ?? const [],
      );
      final p2LiveSubs = List<Map<String, dynamic>>.from(
        (state['p2_live_subs'] as List?) ?? const [],
      );
      final newSubLogs = <String>[];

      if (p1LiveSubs.isNotEmpty) {
        final before = _engine!.log.length;
        _engine!.processSubstitutions('oyuncu_1', p1LiveSubs);
        newSubLogs.addAll(_engine!.log.sublist(before));
        await roomRef.collection('game_state').doc('live_match').update({
          'p1_live_subs': FieldValue.arrayRemove(p1LiveSubs),
        });
      }
      if (p2LiveSubs.isNotEmpty) {
        final before = _engine!.log.length;
        _engine!.processSubstitutions('oyuncu_2', p2LiveSubs);
        newSubLogs.addAll(_engine!.log.sublist(before));
        await roomRef.collection('game_state').doc('live_match').update({
          'p2_live_subs': FieldValue.arrayRemove(p2LiveSubs),
        });
      }
      if (newSubLogs.isNotEmpty) {
        await roomRef.collection('game_state').doc('live_match').update({
          'log': FieldValue.arrayUnion(newSubLogs),
          'p1_state': _engine!.getTeamState(_engine!.t1),
          'p2_state': _engine!.getTeamState(_engine!.t2),
        });
      }

      final chunk = _engine!.playChunk(1);
      final update = <String, dynamic>{
        'minute': _engine!.minute,
        'score': _engine!.score,
        'momentum': _engine!.momentum,
        'stats': _engine!.stats,
        'p1_state': _engine!.getTeamState(_engine!.t1),
        'p2_state': _engine!.getTeamState(_engine!.t2),
        'red_cards': List<String>.from(
          _engine!.events['red_cards']!.cast<String>(),
        ),
        'yellow_cards': List<String>.from(
          _engine!.events['yellow_cards']!.cast<String>(),
        ),
        'injuries': List<String>.from(
          _engine!.events['injuries']!.cast<String>(),
        ),
      };
      if (chunk.logs.isNotEmpty) {
        update['log'] = FieldValue.arrayUnion(chunk.logs);
      }

      if (chunk.finished) {
        final finalData = _engine!.getFinalData();
        update['is_finished'] = true;
        _resetHostRuntime();
        await roomRef.collection('game_state').doc('current').update({
          'phase': 'results',
          'score': finalData.score,
          'match_log': finalData.log,
          'match_mvp': finalData.mvp,
          'match_stats': finalData.stats,
          'match_events': finalData.events,
          'match_player_performance': finalData.performance,
          'final_teams': finalData.finalTeams,
        });
      }

      await roomRef.collection('game_state').doc('live_match').update(update);
    } finally {
      _hostTickInProgress = false;
    }
  }

  Future<void> _sendSubstitution() async {
    await _openLiveSubsPanel();
    return;
    /*
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null) return;

    final myState = (session.playerId == 'oyuncu_1' ? liveState['p1_state'] : liveState['p2_state']) as Map? ?? {};
    final onPitch = Map<String, dynamic>.from((myState['on_pitch'] as Map?) ?? {});
    final bench = Map<String, dynamic>.from((myState['bench'] as Map?) ?? {});
    String? outSlot;
    String? inSlot;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setModalState) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: outSlot,
                  items: onPitch.keys.map((slot) => DropdownMenuItem<String>(value: slot, child: Text(slot))).toList(growable: false),
                  onChanged: (value) => setModalState(() => outSlot = value),
                  decoration: const InputDecoration(labelText: 'Çıkacak oyuncu slotu'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: inSlot,
                  items: bench.keys.map((slot) => DropdownMenuItem<String>(value: slot, child: Text(slot))).toList(growable: false),
                  onChanged: (value) => setModalState(() => inSlot = value),
                  decoration: const InputDecoration(labelText: 'Girecek oyuncu slotu'),
                ),
                const SizedBox(height: 16),
                GameFilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Gönder'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (outSlot == null || inSlot == null) return;
    final field = session.playerId == 'oyuncu_1' ? 'p1_live_subs' : 'p2_live_subs';
    await roomRef.collection('game_state').doc('live_match').update({
      field: FieldValue.arrayUnion([
        {'rid': DateTime.now().microsecondsSinceEpoch.toString(), 'slot_out': outSlot, 'slot_in': inSlot, 't': liveState['minute'] ?? 0}
      ]),
    });
    */
  }

  Future<void> _showMatchStats() async {
    await _showDetailedMatchStats();
    return;
    /*
    final stats = (currentState['match_stats'] as Map?)?.cast<String, dynamic>();
    if (stats == null) return;
    await showGameDialog(
      context,
      title: 'Maç İstatistikleri',
      message: 'Şut ${stats['oyuncu_1']['total_shots']} - ${stats['oyuncu_2']['total_shots']}\n'
          'İsabetli ${stats['oyuncu_1']['shots_on_target']} - ${stats['oyuncu_2']['shots_on_target']}\n'
          'Pas %${stats['oyuncu_1']['pass_percentage']} - %${stats['oyuncu_2']['pass_percentage']}',
    );
  }

    */
  }

  Future<void> _resetForNextTurn() async {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null || _advancingTurn) return;

    setState(() => _advancingTurn = true);
    try {
      final currentRef = roomRef.collection('game_state').doc('current');
      final liveRef = roomRef.collection('game_state').doc('live_match');
      final latestCurrent = currentState.isNotEmpty
          ? Map<String, dynamic>.from(currentState)
          : Map<String, dynamic>.from(
              session.currentGameState ?? const <String, dynamic>{},
            );
      final latestLive = liveState.isNotEmpty
          ? Map<String, dynamic>.from(liveState)
          : <String, dynamic>{};
      final finishedLocally =
          (latestCurrent['phase'] as String? ?? 'drafting') == 'results' ||
          latestLive['is_finished'] == true;
      if (!finishedLocally) {
        _releaseNextTurnLock(session);
        return;
      }

      final currentTurn =
          (latestCurrent['current_turn'] as num?)?.toInt() ??
          (latestLive['match_turn'] as num?)?.toInt() ??
          session.activeTurnNumber;
      final nextTurn = currentTurn + 1;
      final nextTiming = RoomGameService.buildTurnTimingUpdate(
        session.gameConfig,
      );
      final optimisticCurrent = <String, dynamic>{
        ...latestCurrent,
        'current_turn': nextTurn,
        'current_player_id': 'oyuncu_1',
        'phase': 'drafting',
        ...nextTiming,
      };
      const optimisticLive = <String, dynamic>{
        'minute': 0,
        'score': {'oyuncu_1': 0, 'oyuncu_2': 0},
        'log': <String>[],
        'stats': <String, dynamic>{},
        'momentum': 50,
        'is_finished': false,
      };

      _resetHostRuntime();
      final optimisticPlayerState = {
        ...(session.currentPlayerState ?? const <String, dynamic>{}),
        'current_shop_pool': <String>[],
        'shop_generated_turn': 0,
      };
      session.applyOptimisticDraftTransition(
        gameState: optimisticCurrent,
        playerState: optimisticPlayerState,
      );
      if (mounted) {
        setState(() {
          currentState = optimisticCurrent;
          liveState = optimisticLive;
        });
      }
      _releaseNextTurnLock(session);
      _runDetached(() async {
        await _commitNextTurnTransition(
          roomRef: roomRef,
          currentRef: currentRef,
          liveRef: liveRef,
          nextTurn: nextTurn,
          nextTiming: nextTiming,
        );
      });
      _runDetached(() async {
        await _persistMatchResultData(
          roomRef: roomRef,
          snapshotCurrent:
              (latestCurrent['phase'] as String? ?? 'drafting') == 'results'
              ? latestCurrent
              : null,
          snapshotLive: latestLive.isNotEmpty ? latestLive : null,
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() => _advancingTurn = false);
      } else {
        _advancingTurn = false;
      }
    }
  }

  void _releaseNextTurnLock(SessionController session) {
    if (mounted) {
      setState(() => _advancingTurn = false);
    } else {
      _advancingTurn = false;
    }
    session.switchView(GameView.draft);
  }

  Future<void> _commitNextTurnTransition({
    required DocumentReference<Map<String, dynamic>> roomRef,
    required DocumentReference<Map<String, dynamic>> currentRef,
    required DocumentReference<Map<String, dynamic>> liveRef,
    required int nextTurn,
    required Map<String, dynamic> nextTiming,
  }) async {
    final currentData = (await currentRef.get()).data() ?? <String, dynamic>{};
    final remoteTurn = (currentData['current_turn'] as num?)?.toInt() ?? 1;
    final remotePhase = currentData['phase'] as String? ?? 'drafting';
    if (remotePhase == 'drafting' && remoteTurn >= nextTurn) {
      return;
    }

    final batch = roomRef.firestore.batch();
    batch.update(currentRef, {
      'current_turn': nextTurn,
      'current_player_id': 'oyuncu_1',
      'phase': 'drafting',
      ...nextTiming,
      'match_log': FieldValue.delete(),
      'match_stats': FieldValue.delete(),
      'match_player_performance': FieldValue.delete(),
      'final_teams': FieldValue.delete(),
      'match_events': FieldValue.delete(),
      'season_awards_processed': false,
      'season_awards_summary': null,
    });
    batch.set(liveRef, {
      'match_number': null,
      'match_turn': nextTurn,
      'weather': null,
      'home_id': null,
      'minute': 0,
      'score': {'oyuncu_1': 0, 'oyuncu_2': 0},
      'log': <String>[],
      'stats': <String, dynamic>{},
      'momentum': 50,
      'p1_live_subs': <dynamic>[],
      'p2_live_subs': <dynamic>[],
      'p1_state': <String, dynamic>{},
      'p2_state': <String, dynamic>{},
      'red_cards': <dynamic>[],
      'yellow_cards': <dynamic>[],
      'injuries': <dynamic>[],
      'is_finished': false,
    });
    batch.update(roomRef.collection('players').doc('oyuncu_1'), {
      'current_shop_pool': <String>[],
      'shop_generated_turn': 0,
    });
    batch.update(roomRef.collection('players').doc('oyuncu_2'), {
      'current_shop_pool': <String>[],
      'shop_generated_turn': 0,
    });
    await batch.commit();
  }

  Future<Map<String, Map<String, dynamic>>> _loadTeamLookup(
    String playerId,
  ) async {
    final roomRef = context.read<SessionController>().roomRef;
    if (roomRef == null) return const {};
    final query = await roomRef
        .collection('players')
        .doc(playerId)
        .collection('my_team')
        .get();
    return {for (final doc in query.docs) doc.id: doc.data()};
  }

  String _cleanLogText(String entry) {
    return entry.replaceAll(RegExp(r'\[/?[a-z_]+\]'), '');
  }

  List<String> _currentMatchLogs() {
    return List<String>.from(
      (liveState['log'] as List?) ??
          (currentState['match_log'] as List?) ??
          const [],
    );
  }

  void _scheduleFlowPanelToLatest(int logCount, {bool force = false}) {
    if (!_flowPanelOpen) return;
    if (!force && logCount == _lastFlowPanelLogCount) return;
    _lastFlowPanelLogCount = logCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_flowScrollController.hasClients) return;
      final target = _flowScrollController.position.maxScrollExtent;
      _flowScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  double _doubleValue(dynamic value, [double fallback = 0]) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  double _clampMetric(double value) {
    return value.clamp(1.0, 10.0).toDouble();
  }

  double _roundMetric(double value) {
    return double.parse(value.toStringAsFixed(1));
  }

  List<double> _metricHistory(Map<String, dynamic> playerData, String key) {
    final raw = (playerData['${key}_history'] as List?) ?? const [];
    final parsed = raw
        .map((value) => _doubleValue(value, 5))
        .where((value) => value > 0)
        .toList(growable: false);
    if (parsed.isNotEmpty) {
      return parsed.map(_clampMetric).toList(growable: false);
    }
    return [_clampMetric(_doubleValue(playerData[key], 5))];
  }

  List<double> _appendMetricHistory(
    List<double> existing,
    double value, {
    int limit = 8,
  }) {
    final next = [...existing.map(_clampMetric), _clampMetric(value)];
    if (next.length <= limit) return next;
    return next.sublist(next.length - limit);
  }

  ({Color color, IconData icon}) _logStyle(String entry) {
    if (entry.startsWith('[goal]')) {
      return (color: AppColors.accent, icon: Icons.sports_soccer_rounded);
    }
    if (entry.startsWith('[chance]')) {
      return (
        color: AppColors.warning,
        icon: Icons.local_fire_department_rounded,
      );
    }
    if (entry.startsWith('[card_red]')) {
      return (color: AppColors.danger, icon: Icons.square_rounded);
    }
    if (entry.startsWith('[card_yellow]')) {
      return (color: AppColors.gold, icon: Icons.crop_square_rounded);
    }
    if (entry.startsWith('[injury]')) {
      return (color: AppColors.warning, icon: Icons.healing_rounded);
    }
    if (entry.startsWith('[sub]')) {
      return (color: AppColors.info, icon: Icons.swap_horiz_rounded);
    }
    if (entry.startsWith('[event]')) {
      return (color: AppColors.accent, icon: Icons.campaign_rounded);
    }
    return (color: AppColors.text, icon: Icons.chevron_right_rounded);
  }

  Map<String, dynamic>? _statsSource() {
    return (liveState['stats'] as Map?)?.cast<String, dynamic>() ??
        (currentState['match_stats'] as Map?)?.cast<String, dynamic>();
  }

  int _intStat(Map<String, dynamic>? stats, String teamId, String key) {
    final team = (stats?[teamId] as Map?)?.cast<String, dynamic>();
    return (team?[key] as num?)?.toInt() ?? 0;
  }

  double _doubleStat(Map<String, dynamic>? stats, String teamId, String key) {
    final team = (stats?[teamId] as Map?)?.cast<String, dynamic>();
    return (team?[key] as num?)?.toDouble() ?? 0;
  }

  int _possessionPercent(Map<String, dynamic>? stats, String teamId) {
    final stored = _intStat(stats, teamId, 'possession_percent');
    if (stored > 0) return stored;
    final left = _intStat(stats, 'oyuncu_1', 'possession_count');
    final right = _intStat(stats, 'oyuncu_2', 'possession_count');
    final total = left + right;
    if (total == 0) return 50;
    final own = _intStat(stats, teamId, 'possession_count');
    return ((own / total) * 100).round();
  }

  String _momentumLabel(int value) {
    if (value >= 65) return '$p1Name baskılı';
    if (value <= 35) return '$p2Name baskılı';
    return 'Oyun dengede';
  }

  Widget _metricCard({
    required String label,
    required String left,
    required String right,
    required Color color,
  }) {
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  left,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'vs',
                style: TextStyle(
                  color: color.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Expanded(
                child: Text(
                  right,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFlowEntry(
    BuildContext context,
    String entry, {
    bool compact = false,
  }) {
    final style = _logStyle(entry);
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 8 : 10),
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(compact ? 16 : 18),
        border: Border.all(color: style.color.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 30 : 34,
            height: compact ? 30 : 34,
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(
              style.icon,
              size: compact ? 16 : 18,
              color: style.color,
            ),
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Text(
              _cleanLogText(entry),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: compact ? 1.28 : 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreboardHero({
    required Map<String, dynamic>? stats,
    required Map<String, dynamic> score,
    required int minute,
    required bool isFinished,
    required List<String> redCards,
    required List<String> injuries,
    required Map<String, dynamic>? matchMvp,
  }) {
    final momentum = ((liveState['momentum'] as num?)?.toInt() ?? 50).clamp(
      0,
      100,
    );
    final weather = liveState['weather'] as String? ?? 'Güneşli';

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoBadge(
                label: isFinished ? 'Maç tamamlandı' : 'Dakika $minute',
                color: AppColors.info,
              ),
              InfoBadge(label: weather, color: AppColors.gold),
              InfoBadge(
                label: _momentumLabel(momentum),
                color: momentum >= 50 ? AppColors.accent : AppColors.warning,
              ),
              if (matchMvp != null)
                InfoBadge(
                  label: 'MVP ${matchMvp['name']}',
                  color: AppColors.accent,
                ),
              if (redCards.isNotEmpty)
                InfoBadge(
                  label: 'Kırmızı ${redCards.length}',
                  color: AppColors.danger,
                ),
              if (injuries.isNotEmpty)
                InfoBadge(
                  label: 'Sakat ${injuries.length}',
                  color: AppColors.warning,
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  p1Name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  '${score['oyuncu_1']}  -  ${score['oyuncu_2']}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  p2Name,
                  textAlign: TextAlign.right,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            minHeight: 11,
            value: momentum / 100,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Top akışı',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: AppColors.muted),
                ),
              ),
              Text(
                '${_doubleStat(stats, 'oyuncu_1', 'expected_goals').toStringAsFixed(2)} xG'
                ' - '
                '${_doubleStat(stats, 'oyuncu_2', 'expected_goals').toStringAsFixed(2)} xG',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: AppColors.text),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _playerLabel(
    String slot,
    String playerId,
    Map<String, Map<String, dynamic>> teamLookup,
    Map<String, dynamic> staminaMap,
    Set<String> lockedPlayers,
  ) {
    final player = teamLookup[playerId] ?? const <String, dynamic>{};
    final name = player['name'] as String? ?? playerId;
    final mevki = player['mevki'] as String? ?? slot;
    final stamina = ((staminaMap[playerId] as num?)?.toDouble() ?? 100).round();
    final status = lockedPlayers.contains(playerId) ? 'Kilitli' : '%$stamina';
    return '$slot • $name ($mevki) • $status';
  }

  Future<void> _openLiveSubsPanel() async {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    final playerId = session.playerId;
    if (roomRef == null || playerId == null) return;

    final myState = Map<String, dynamic>.from(
      ((playerId == 'oyuncu_1' ? liveState['p1_state'] : liveState['p2_state'])
              as Map?) ??
          const <String, dynamic>{},
    );
    final usedSubs = (myState['sub_count'] as num?)?.toInt() ?? 0;
    final remainingSubs = 4 - usedSubs;
    if (remainingSubs <= 0) {
      await showGameDialog(
        context,
        title: 'Değişiklik Yok',
        message: 'Bu maç için 4 değişiklik hakkın doldu.',
      );
      return;
    }

    final initialOnPitch = Map<String, String>.from(
      ((myState['on_pitch'] as Map?) ?? const <String, dynamic>{}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    );
    final initialBench = Map<String, String>.from(
      ((myState['bench'] as Map?) ?? const <String, dynamic>{}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    );
    if (initialBench.isEmpty) {
      await showGameDialog(
        context,
        title: 'Yedek Yok',
        message: 'Kulübede uygun yedek oyuncu bulunmuyor.',
      );
      return;
    }

    final teamLookup = await _loadTeamLookup(playerId);
    final staminaMap = Map<String, dynamic>.from(
      (myState['stamina'] as Map?) ?? const <String, dynamic>{},
    );
    final lockedPlayers = {
      ...List<String>.from((liveState['red_cards'] as List?) ?? const []),
      ...List<String>.from((liveState['injuries'] as List?) ?? const []),
    };
    if (!mounted) return;

    final workingOnPitch = Map<String, String>.from(initialOnPitch);
    final workingBench = Map<String, String>.from(initialBench);
    final queuedSubs = <Map<String, String>>[];
    String? outSlot;
    String? inSlot;

    final shouldSubmit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          void queueCurrentSelection() {
            if (outSlot == null ||
                inSlot == null ||
                queuedSubs.length >= remainingSubs) {
              return;
            }
            final outgoingPlayer = workingOnPitch[outSlot!];
            final incomingPlayer = workingBench[inSlot!];
            if (outgoingPlayer == null || incomingPlayer == null) return;

            queuedSubs.add({'slot_out': outSlot!, 'slot_in': inSlot!});
            workingOnPitch[outSlot!] = incomingPlayer;
            workingBench.remove(inSlot!);
            workingBench[outSlot!] = outgoingPlayer;
            outSlot = null;
            inSlot = null;
          }

          return SafeArea(
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              decoration: const BoxDecoration(
                color: AppColors.midnight,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Canlı Değişiklik',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        InfoBadge(
                          label: 'Kalan $remainingSubs',
                          color: AppColors.info,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (queuedSubs.isNotEmpty) ...[
                      Text(
                        'Gönderilecek Liste',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: queuedSubs
                            .map((sub) {
                              final outId = initialOnPitch[sub['slot_out']];
                              final inId =
                                  initialBench[sub['slot_in']] ??
                                  workingOnPitch[sub['slot_out']];
                              final outName = outId == null
                                  ? sub['slot_out']!
                                  : (teamLookup[outId]?['name'] as String? ??
                                        outId);
                              final inName = inId == null
                                  ? sub['slot_in']!
                                  : (teamLookup[inId]?['name'] as String? ??
                                        inId);
                              return InfoBadge(
                                label: '$outName → $inName',
                                color: AppColors.accent,
                              );
                            })
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      'Sahadan Çıkacak',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: workingOnPitch.entries
                            .map((entry) {
                              final currentPlayerId = entry.value;
                              final disabled = lockedPlayers.contains(
                                currentPlayerId,
                              );
                              return RadioListTile<String>(
                                value: entry.key,
                                groupValue: outSlot,
                                activeColor: AppColors.accent,
                                onChanged: disabled
                                    ? null
                                    : (value) =>
                                          setModalState(() => outSlot = value),
                                title: Text(
                                  _playerLabel(
                                    entry.key,
                                    currentPlayerId,
                                    teamLookup,
                                    staminaMap,
                                    lockedPlayers,
                                  ),
                                ),
                              );
                            })
                            .toList(growable: false),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Oyuna Girecek',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: workingBench.entries
                            .map((entry) {
                              return RadioListTile<String>(
                                value: entry.key,
                                groupValue: inSlot,
                                activeColor: AppColors.accentSoft,
                                onChanged: (value) =>
                                    setModalState(() => inSlot = value),
                                title: Text(
                                  _playerLabel(
                                    entry.key,
                                    entry.value,
                                    teamLookup,
                                    staminaMap,
                                    const {},
                                  ),
                                ),
                              );
                            })
                            .toList(growable: false),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GameOutlinedButton(
                            onPressed:
                                queuedSubs.length >= remainingSubs ||
                                    outSlot == null ||
                                    inSlot == null
                                ? null
                                : () => setModalState(queueCurrentSelection),
                            child: const Text('Listeye Ekle'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GameFilledButton(
                            onPressed: queuedSubs.isEmpty
                                ? null
                                : () => Navigator.of(context).pop(true),
                            child: Text('Gönder (${queuedSubs.length})'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (shouldSubmit != true || queuedSubs.isEmpty) return;
    final field = playerId == 'oyuncu_1' ? 'p1_live_subs' : 'p2_live_subs';
    await roomRef.collection('game_state').doc('live_match').update({
      field: FieldValue.arrayUnion(
        queuedSubs
            .map((sub) {
              return {
                'rid':
                    '${DateTime.now().microsecondsSinceEpoch}-${sub['slot_out']}-${sub['slot_in']}',
                'slot_out': sub['slot_out'],
                'slot_in': sub['slot_in'],
                't': liveState['minute'] ?? 0,
              };
            })
            .toList(growable: false),
      ),
    });
    if (!mounted) return;
    showGameSnack(context, 'Değişiklik talepleri gönderildi.');
  }

  Future<void> _openMatchFlowPanel() async {
    final roomRef = context.read<SessionController>().roomRef;
    if (roomRef == null) return;
    _flowPanelOpen = true;
    _lastFlowPanelLogCount = -1;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: false,
        useSafeArea: true,
        barrierColor: Colors.black.withValues(alpha: 0.72),
        backgroundColor: Colors.transparent,
        builder: (context) {
          return FractionallySizedBox(
            heightFactor: 0.96,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.midnight,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: roomRef
                    .collection('game_state')
                    .doc('live_match')
                    .snapshots(),
                builder: (context, snapshot) {
                  final liveData = snapshot.data?.data() ?? liveState;
                  final panelLogs = List<String>.from(
                    (liveData['log'] as List?) ??
                        (currentState['match_log'] as List?) ??
                        const [],
                  );
                  final panelScore = Map<String, dynamic>.from(
                    (liveData['score'] as Map?) ??
                        (currentState['score'] as Map?) ??
                        {'oyuncu_1': 0, 'oyuncu_2': 0},
                  );
                  final panelMinute =
                      (liveData['minute'] as num?)?.toInt() ?? 0;
                  final panelFinished =
                      liveData['is_finished'] == true ||
                      currentState['phase'] == 'results';

                  if (panelLogs.isNotEmpty) {
                    _scheduleFlowPanelToLatest(
                      panelLogs.length,
                      force: _lastFlowPanelLogCount < 0,
                    );
                  } else {
                    _lastFlowPanelLogCount = 0;
                  }

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Maç Akışı',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                  tooltip: 'Kapat',
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                InfoBadge(
                                  label: panelFinished
                                      ? 'Maç tamamlandı'
                                      : 'Dakika $panelMinute',
                                  color: AppColors.info,
                                ),
                                InfoBadge(
                                  label:
                                      '${panelScore['oyuncu_1']} - ${panelScore['oyuncu_2']}',
                                  color: AppColors.gold,
                                ),
                                InfoBadge(
                                  label: '${panelLogs.length} olay',
                                  color: AppColors.accent,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0x22FFFFFF)),
                      Expanded(
                        child: panelLogs.isEmpty
                            ? Center(
                                child: Text(
                                  'Maç başlıyor...',
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(color: AppColors.muted),
                                ),
                              )
                            : ListView.builder(
                                controller: _flowScrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  18,
                                  20,
                                  24,
                                ),
                                itemCount: panelLogs.length,
                                itemBuilder: (context, index) {
                                  return _buildFlowEntry(
                                    context,
                                    panelLogs[index],
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      );
    } finally {
      _flowPanelOpen = false;
      _lastFlowPanelLogCount = -1;
    }
  }

  Future<void> _showDetailedMatchStats() async {
    final stats =
        (currentState['match_stats'] as Map?)?.cast<String, dynamic>() ??
        (liveState['stats'] as Map?)?.cast<String, dynamic>();
    if (stats == null) return;
    final events =
        (currentState['match_events'] as Map?)?.cast<String, dynamic>() ??
        (liveState['match_events'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final goals = List<Map<String, dynamic>>.from(
      (events['goals'] as List?) ?? const [],
    );
    final scorers = <String, int>{};
    final assisters = <String, int>{};
    for (final goal in goals) {
      final scorer = goal['scorer_name'] as String?;
      final assister = goal['assist_name'] as String?;
      if (scorer != null) {
        scorers[scorer] = (scorers[scorer] ?? 0) + 1;
      }
      if (assister != null) {
        assisters[assister] = (assisters[assister] ?? 0) + 1;
      }
    }
    final mvp = (currentState['match_mvp'] as Map?)?.cast<String, dynamic>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.midnight,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'Detaylı Maç Raporu',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Temel İstatistikler',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _statsRow(
                        'Şut',
                        '${stats['oyuncu_1']['total_shots']}',
                        '${stats['oyuncu_2']['total_shots']}',
                      ),
                      _statsRow(
                        'xG',
                        ((stats['oyuncu_1']['expected_goals'] as num?)
                                    ?.toDouble() ??
                                0)
                            .toStringAsFixed(2),
                        ((stats['oyuncu_2']['expected_goals'] as num?)
                                    ?.toDouble() ??
                                0)
                            .toStringAsFixed(2),
                      ),
                      _statsRow(
                        'İsabetli Şut',
                        '${stats['oyuncu_1']['shots_on_target']}',
                        '${stats['oyuncu_2']['shots_on_target']}',
                      ),
                      _statsRow(
                        'Büyük Fırsat',
                        '${stats['oyuncu_1']['big_chances']}',
                        '${stats['oyuncu_2']['big_chances']}',
                      ),
                      _statsRow(
                        'Tehlikeli Atak',
                        '${stats['oyuncu_1']['dangerous_attacks']}',
                        '${stats['oyuncu_2']['dangerous_attacks']}',
                      ),
                      _statsRow(
                        'Anahtar Pas',
                        '${stats['oyuncu_1']['key_passes'] ?? 0}',
                        '${stats['oyuncu_2']['key_passes'] ?? 0}',
                      ),
                      _statsRow(
                        'Kontra Atak',
                        '${stats['oyuncu_1']['counter_attacks'] ?? 0}',
                        '${stats['oyuncu_2']['counter_attacks'] ?? 0}',
                      ),
                      _statsRow(
                        'Pas %',
                        '%${stats['oyuncu_1']['pass_percentage']}',
                        '%${stats['oyuncu_2']['pass_percentage']}',
                      ),
                      _statsRow(
                        'Kurtarış',
                        '${stats['oyuncu_1']['saves']}',
                        '${stats['oyuncu_2']['saves']}',
                      ),
                      _statsRow(
                        'Top Kapma',
                        '${stats['oyuncu_1']['tackles']}',
                        '${stats['oyuncu_2']['tackles']}',
                      ),
                      _statsRow(
                        'Faul',
                        '${stats['oyuncu_1']['fouls']}',
                        '${stats['oyuncu_2']['fouls']}',
                      ),
                      _statsRow(
                        'Korner',
                        '${stats['oyuncu_1']['corners']}',
                        '${stats['oyuncu_2']['corners']}',
                      ),
                      _statsRow(
                        'Ofsayt',
                        '${stats['oyuncu_1']['offsides'] ?? 0}',
                        '${stats['oyuncu_2']['offsides'] ?? 0}',
                      ),
                      _statsRow(
                        'Orta',
                        '${stats['oyuncu_1']['crosses']}',
                        '${stats['oyuncu_2']['crosses']}',
                      ),
                      _statsRow(
                        'Duran Top',
                        '${stats['oyuncu_1']['set_pieces']}',
                        '${stats['oyuncu_2']['set_pieces']}',
                      ),
                      _statsRow(
                        'Topla Oynama',
                        '%${stats['oyuncu_1']['possession_percent']}',
                        '%${stats['oyuncu_2']['possession_percent']}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Öne Çıkanlar',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _badgeLine(
                        'Maçın Oyuncusu',
                        mvp?['name'] as String? ?? '-',
                      ),
                      _badgeLine(
                        'Golcüler',
                        scorers.isEmpty
                            ? 'Gol yok'
                            : scorers.entries
                                  .map(
                                    (entry) => '${entry.key} (${entry.value})',
                                  )
                                  .join(', '),
                      ),
                      _badgeLine(
                        'Asistler',
                        assisters.isEmpty
                            ? 'Asist yok'
                            : assisters.entries
                                  .map(
                                    (entry) => '${entry.key} (${entry.value})',
                                  )
                                  .join(', '),
                      ),
                      _badgeLine(
                        'Kırmızı Kartlar',
                        List<String>.from(
                              (events['red_cards'] as List?) ?? const [],
                            ).join(', ').isEmpty
                            ? 'Yok'
                            : List<String>.from(
                                (events['red_cards'] as List?) ?? const [],
                              ).join(', '),
                      ),
                      _badgeLine(
                        'Sakatlıklar',
                        List<String>.from(
                              (events['injuries'] as List?) ?? const [],
                            ).join(', ').isEmpty
                            ? 'Yok'
                            : List<String>.from(
                                (events['injuries'] as List?) ?? const [],
                              ).join(', '),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GameFilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Kapat'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statsRow(String label, String left, String right) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(left, textAlign: TextAlign.left)),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(right, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _badgeLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _persistMatchResultData({
    required DocumentReference<Map<String, dynamic>> roomRef,
    Map<String, dynamic>? snapshotCurrent,
    Map<String, dynamic>? snapshotLive,
  }) async {
    if (_persistingResult) return;
    _persistingResult = true;
    try {
      final currentRef = roomRef.collection('game_state').doc('current');
      final liveRef = roomRef.collection('game_state').doc('live_match');
      final currentDoc =
          snapshotCurrent ?? (await currentRef.get()).data() ?? currentState;
      final liveDoc = snapshotLive ?? (await liveRef.get()).data() ?? liveState;

      final currentTurn = (currentDoc['current_turn'] as num?)?.toInt() ?? 1;
      if ((currentDoc['last_results_applied_turn'] as num?)?.toInt() ==
          currentTurn) {
        return;
      }

      final score = Map<String, dynamic>.from(
        (currentDoc['score'] as Map?) ?? {'oyuncu_1': 0, 'oyuncu_2': 0},
      );
      final events =
          (currentDoc['match_events'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final performance =
          ((currentDoc['match_player_performance'] as Map?) ??
                  const <String, dynamic>{})
              .map(
                (key, value) => MapEntry(key.toString(), _doubleValue(value)),
              );
      final redCards = List<String>.from(
        (liveDoc['red_cards'] as List?) ??
            (events['red_cards'] as List?) ??
            const [],
      );
      final yellowCards = List<String>.from(
        (liveDoc['yellow_cards'] as List?) ??
            (events['yellow_cards'] as List?) ??
            const [],
      );
      final injuries = List<String>.from(
        (liveDoc['injuries'] as List?) ??
            (events['injuries'] as List?) ??
            const [],
      );

      final batch = roomRef.firestore.batch();
      final updates = <String, dynamic>{
        'match_scores.match_$currentTurn':
            '${score['oyuncu_1']}-${score['oyuncu_2']}',
        'last_results_applied_turn': currentTurn,
      };

      for (final goal in List<Map<String, dynamic>>.from(
        (events['goals'] as List?) ?? const [],
      )) {
        final scorerName = goal['scorer_name'] as String?;
        final assistName = goal['assist_name'] as String?;
        if (scorerName != null && scorerName.isNotEmpty) {
          updates['season_stats.goals.$scorerName'] = FieldValue.increment(1);
        }
        if (assistName != null && assistName.isNotEmpty) {
          updates['season_stats.assists.$assistName'] = FieldValue.increment(1);
        }
      }

      final mvp = (currentDoc['match_mvp'] as Map?)?.cast<String, dynamic>();
      final mvpId = mvp?['id'] as String?;
      final mvpName = mvp?['name'] as String?;
      if (mvpName != null && mvpName.isNotEmpty) {
        updates['season_stats.mvps.$mvpName'] = FieldValue.increment(1);
      }
      batch.update(currentRef, updates);

      for (final playerId in const ['oyuncu_1', 'oyuncu_2']) {
        final opponentId = playerId == 'oyuncu_1' ? 'oyuncu_2' : 'oyuncu_1';
        final playerRef = roomRef.collection('players').doc(playerId);
        final playerDoc = (await playerRef.get()).data() ?? <String, dynamic>{};
        final formationSlots = Map<String, dynamic>.from(
          (playerDoc['formation_slots'] as Map?) ?? const <String, dynamic>{},
        );
        final starterIds = formationSlots.entries
            .where((entry) => !entry.key.startsWith('BENCH'))
            .map((entry) => (entry.value as Map?)?['player_id'])
            .whereType<String>()
            .toSet();
        final captainId = playerDoc['captain_id'] as String?;
        final teamGoals = (score[playerId] as num?)?.toInt() ?? 0;
        final opponentGoals = (score[opponentId] as num?)?.toInt() ?? 0;
        final goalDiff = teamGoals - opponentGoals;
        final teamMoraleDelta = goalDiff > 0
            ? 0.7 + min(0.45, goalDiff * 0.12)
            : goalDiff < 0
            ? -0.6 - min(0.4, goalDiff.abs() * 0.1)
            : 0.08;
        final teamFormDelta = goalDiff > 0
            ? 0.45 + min(0.3, goalDiff * 0.08)
            : goalDiff < 0
            ? -0.32 - min(0.28, goalDiff.abs() * 0.07)
            : 0.05;
        final loanQuery = await playerRef
            .collection('my_team')
            .where('is_loan', isEqualTo: true)
            .get();
        final departingLoanIds = <String>[];

        for (final doc in loanQuery.docs) {
          departingLoanIds.add(doc.id);
          batch.delete(doc.reference);
        }
        final squadQuery = await playerRef.collection('my_team').get();
        final squadDocs = squadQuery.docs;
        final trackedIds = starterIds.isEmpty
            ? squadDocs.map((doc) => doc.id)
            : starterIds;
        var teamPerformanceAverage = 0.0;
        var trackedPerformanceCount = 0;
        for (final playerCardId in trackedIds) {
          final value = performance[playerCardId];
          if (value == null) continue;
          teamPerformanceAverage += value;
          trackedPerformanceCount += 1;
        }
        if (trackedPerformanceCount == 0 && squadDocs.isNotEmpty) {
          for (final doc in squadDocs) {
            final value = performance[doc.id];
            if (value == null) continue;
            teamPerformanceAverage += value;
            trackedPerformanceCount += 1;
          }
        }
        if (trackedPerformanceCount > 0) {
          teamPerformanceAverage /= trackedPerformanceCount;
        }

        for (final squadDoc in squadDocs) {
          if (departingLoanIds.contains(squadDoc.id)) continue;
          final playerData = squadDoc.data();
          final playerCardId = squadDoc.id;
          final mevki = playerData['mevki'] as String? ?? '';
          final onPitch = starterIds.contains(playerCardId);
          final currentMorale = _clampMetric(
            _doubleValue(playerData['morale'], 5),
          );
          final currentForm = _clampMetric(_doubleValue(playerData['form'], 5));
          final perfValue =
              performance[playerCardId] ??
              (onPitch ? teamPerformanceAverage : 0.0);
          final perfDelta = onPitch
              ? ((perfValue - teamPerformanceAverage) / 18)
                    .clamp(-0.45, 0.55)
                    .toDouble()
              : (goalDiff > 0
                    ? 0.12
                    : goalDiff < 0
                    ? -0.08
                    : 0.02);
          final captainMultiplier = captainId == playerCardId ? 1.12 : 1.0;
          var moraleDelta =
              teamMoraleDelta * (onPitch ? captainMultiplier : 0.45) +
              perfDelta;
          var formDelta =
              teamFormDelta * (onPitch ? captainMultiplier : 0.35) +
              perfDelta * 1.15;

          if (playerCardId == mvpId) {
            moraleDelta += 0.9;
            formDelta += 0.75;
          }
          if (redCards.contains(playerCardId)) {
            moraleDelta -= 1.35;
            formDelta -= 0.65;
          }
          if (yellowCards.contains(playerCardId)) {
            moraleDelta -= 0.25;
            formDelta -= 0.18;
          }
          if (injuries.contains(playerCardId)) {
            moraleDelta -= 0.95;
            formDelta -= 0.7;
          }
          if (mevki == 'Kaleci' && opponentGoals == 0 && onPitch) {
            moraleDelta += 0.35;
            formDelta += 0.3;
          }
          if (mevki == 'Forvet' && teamGoals == 0 && onPitch) {
            moraleDelta -= 0.18;
            formDelta -= 0.26;
          }
          if (mevki == 'Defans' && opponentGoals >= 2 && onPitch) {
            moraleDelta -= 0.15;
            formDelta -= 0.2;
          }

          final nextMorale = _roundMetric(
            _clampMetric(currentMorale + moraleDelta),
          );
          final nextForm = _roundMetric(_clampMetric(currentForm + formDelta));
          final update = <String, dynamic>{
            'morale': nextMorale,
            'form': nextForm,
            'morale_history': _appendMetricHistory(
              _metricHistory(playerData, 'morale'),
              nextMorale,
            ),
            'form_history': _appendMetricHistory(
              _metricHistory(playerData, 'form'),
              nextForm,
            ),
            'morale_last_delta': _roundMetric(nextMorale - currentMorale),
            'form_last_delta': _roundMetric(nextForm - currentForm),
            'last_trend_turn': currentTurn,
          };
          if (redCards.contains(playerCardId)) {
            update['status'] = 'cezalı';
            update['status_duration'] = 1;
          }
          if (injuries.contains(playerCardId)) {
            update['status'] = 'sakat';
            update['status_duration'] = 2;
          }
          batch.update(squadDoc.reference, update);
        }

        final cleanupUpdate = RoomGameService.buildRosterCleanupUpdate(
          playerDoc,
          departingLoanIds,
        );
        if (cleanupUpdate.isNotEmpty) {
          batch.update(playerRef, cleanupUpdate);
        }
      }

      await batch.commit();
      final refreshedCurrent = (await currentRef.get()).data();
      if (refreshedCurrent != null && mounted) {
        setState(() => currentState = refreshedCurrent);
      }
    } finally {
      _persistingResult = false;
    }
  }

  Future<String?> _findOwner(String playerName) async {
    final roomRef = context.read<SessionController>().roomRef;
    if (roomRef == null || playerName.isEmpty || playerName == 'Yok') {
      return null;
    }

    for (final playerId in const ['oyuncu_1', 'oyuncu_2']) {
      final query = await roomRef
          .collection('players')
          .doc(playerId)
          .collection('my_team')
          .where('name', isEqualTo: playerName)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) return playerId;
    }
    return null;
  }

  (String, int) _getTopPlayer(Map<String, dynamic> stats) {
    if (stats.isEmpty) return ('Yok', 0);
    final normalized = stats.map(
      (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0),
    );
    final winner = normalized.entries.reduce(
      (best, current) => current.value > best.value ? current : best,
    );
    return (winner.key, winner.value);
  }

  Future<void> _handleSeasonEnd() async {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null) return;

    await _persistMatchResultData(roomRef: roomRef);

    final currentRef = roomRef.collection('game_state').doc('current');
    final latestState = (await currentRef.get()).data() ?? currentState;
    final existingSummary = latestState['season_awards_summary'] as String?;
    if (latestState['season_awards_processed'] == true &&
        existingSummary != null) {
      if (!mounted) return;
      await showGameDialog(
        context,
        title: 'Sezon Sonu Ödülleri',
        message: existingSummary,
      );
      if (mounted) session.switchView(GameView.lobby);
      return;
    }

    final stats =
        (latestState['season_stats'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final (topScorer, goals) = _getTopPlayer(
      (stats['goals'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    final (topAssister, assists) = _getTopPlayer(
      (stats['assists'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    final (seasonMvp, mvpCount) = _getTopPlayer(
      (stats['mvps'] as Map?)?.cast<String, dynamic>() ?? const {},
    );

    final scorerOwner = await _findOwner(topScorer);
    final assisterOwner = await _findOwner(topAssister);
    final mvpOwner = await _findOwner(seasonMvp);

    final batch = roomRef.firestore.batch();
    if (scorerOwner != null && goals > 0) {
      batch.update(roomRef.collection('players').doc(scorerOwner), {
        'gold': FieldValue.increment(150),
      });
    }
    if (assisterOwner != null && assists > 0) {
      batch.update(roomRef.collection('players').doc(assisterOwner), {
        'gold': FieldValue.increment(150),
      });
    }
    if (mvpOwner != null && mvpCount > 0) {
      batch.update(roomRef.collection('players').doc(mvpOwner), {
        'gold': FieldValue.increment(200),
      });
    }

    final summary =
        'Gol Kralı: $topScorer ($goals gol) • Menajeri 150 altın kazandı.\n'
        'Asist Kralı: $topAssister ($assists asist) • Menajeri 150 altın kazandı.\n'
        'Sezonun Oyuncusu: $seasonMvp ($mvpCount MVP) • Menajeri 200 altın kazandı.';
    batch.update(currentRef, {
      'season_awards_processed': true,
      'season_awards_summary': summary,
    });
    await batch.commit();

    if (!mounted) return;
    await showGameDialog(
      context,
      title: 'Sezon Sonu Ödülleri',
      message: summary,
    );
    if (mounted) session.switchView(GameView.lobby);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final isFinished =
        liveState['is_finished'] == true || currentState['phase'] == 'results';
    final score = Map<String, dynamic>.from(
      (liveState['score'] as Map?) ??
          (currentState['score'] as Map?) ??
          {'oyuncu_1': 0, 'oyuncu_2': 0},
    );
    final rawLogs = _currentMatchLogs();
    final previewLogs = rawLogs.length > 4
        ? rawLogs.sublist(rawLogs.length - 4)
        : rawLogs;
    final minute = (liveState['minute'] as num?)?.toInt() ?? 0;
    final maxTurns = (session.gameConfig['max_turns'] as num?)?.toInt() ?? 21;
    final isSeasonEnd =
        (currentState['current_turn'] as num?)?.toInt() == maxTurns;
    final matchMvp = (currentState['match_mvp'] as Map?)
        ?.cast<String, dynamic>();
    final redCards = List<String>.from(
      (liveState['red_cards'] as List?) ??
          ((currentState['match_events'] as Map?)?['red_cards'] as List?) ??
          const [],
    );
    final injuries = List<String>.from(
      (liveState['injuries'] as List?) ??
          ((currentState['match_events'] as Map?)?['injuries'] as List?) ??
          const [],
    );
    final specialEvent =
        (currentState['match_special_event'] as Map?)
            ?.cast<String, dynamic>() ??
        (liveState['special_event'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final stats = _statsSource();

    return GamePageScaffold(
      title: 'Canlı Maç',
      subtitle: isFinished ? 'Maç tamamlandı' : 'Dakika $minute',
      actions: [
        if (!isFinished)
          GameIconButton(
            onPressed: _sendSubstitution,
            icon: const Icon(Icons.swap_horiz_rounded),
            tooltip: 'Canlı değişiklik',
          ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _scoreboardHero(
            stats: stats,
            score: score,
            minute: minute,
            isFinished: isFinished,
            redCards: redCards,
            injuries: injuries,
            matchMvp: matchMvp,
          ),
          if ((specialEvent['name'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 14),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      InfoBadge(
                        label: specialEvent['name'] as String,
                        color: AppColors.warning,
                      ),
                    ],
                  ),
                  if ((specialEvent['description'] as String?)?.isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 10),
                    Text(specialEvent['description'] as String),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth >= 560
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _metricCard(
                      label: 'Şut / İsabet',
                      left:
                          '${_intStat(stats, 'oyuncu_1', 'total_shots')} / ${_intStat(stats, 'oyuncu_1', 'shots_on_target')}',
                      right:
                          '${_intStat(stats, 'oyuncu_2', 'total_shots')} / ${_intStat(stats, 'oyuncu_2', 'shots_on_target')}',
                      color: AppColors.accent,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _metricCard(
                      label: 'xG / Büyük Fırsat',
                      left:
                          '${_doubleStat(stats, 'oyuncu_1', 'expected_goals').toStringAsFixed(2)} / ${_intStat(stats, 'oyuncu_1', 'big_chances')}',
                      right:
                          '${_doubleStat(stats, 'oyuncu_2', 'expected_goals').toStringAsFixed(2)} / ${_intStat(stats, 'oyuncu_2', 'big_chances')}',
                      color: AppColors.gold,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _metricCard(
                      label: 'Tehlikeli Atak',
                      left:
                          '${_intStat(stats, 'oyuncu_1', 'dangerous_attacks')}',
                      right:
                          '${_intStat(stats, 'oyuncu_2', 'dangerous_attacks')}',
                      color: AppColors.warning,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _metricCard(
                      label: 'Topa Sahip Olma',
                      left: '%${_possessionPercent(stats, 'oyuncu_1')}',
                      right: '%${_possessionPercent(stats, 'oyuncu_2')}',
                      color: AppColors.info,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Maç Akışı',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    InfoBadge(
                      label: '${rawLogs.length} olay',
                      color: AppColors.info,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Akışı tam ekran açıp sabit panelden canlı olarak izleyebilirsin.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 14),
                if (previewLogs.isEmpty)
                  const Text('Maç başlıyor...')
                else
                  ...previewLogs.map(
                    (entry) => _buildFlowEntry(context, entry, compact: true),
                  ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: GameFilledButtonIcon(
                    onPressed: _openMatchFlowPanel,
                    icon: const Icon(Icons.fullscreen_rounded),
                    label: const Text('Akışı İzle'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              GameOutlinedButton(
                onPressed:
                    currentState['match_stats'] == null &&
                        liveState['stats'] == null
                    ? null
                    : _showMatchStats,
                child: const Text('İstatistikler'),
              ),
              if (isFinished)
                GameFilledButton(
                  onPressed: _advancingTurn
                      ? null
                      : () async {
                          if ((currentState['current_turn'] as num?)?.toInt() ==
                              ((session.gameConfig['max_turns'] as num?)
                                      ?.toInt() ??
                                  21)) {
                            await _handleSeasonEnd();
                            return;
                          }
                          await _resetForNextTurn();
                        },
                  child: Text(
                    _advancingTurn
                        ? 'Hazırlanıyor...'
                        : isSeasonEnd
                        ? 'Sezon Ödülleri'
                        : 'Yeni Tura Başla',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
