import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/game_data.dart';
import 'match_engine.dart';

enum ReplayStartResult {
  started,
  tooEarly,
  wrongPhase,
  wrongTurn,
  missingDeadline,
  missingPreparedData,
  writeConflict,
}

extension ReplayStartResultX on ReplayStartResult {
  bool get startedOk => this == ReplayStartResult.started;

  String get code => switch (this) {
    ReplayStartResult.started => 'started',
    ReplayStartResult.tooEarly => 'too_early',
    ReplayStartResult.wrongPhase => 'wrong_phase',
    ReplayStartResult.wrongTurn => 'wrong_turn',
    ReplayStartResult.missingDeadline => 'missing_deadline',
    ReplayStartResult.missingPreparedData => 'missing_prepared_data',
    ReplayStartResult.writeConflict => 'write_conflict',
  };
}

class RoomGameService {
  RoomGameService._();

  static final Random _random = Random();

  static int turnTimeSeconds(Map<String, dynamic> gameConfig) {
    return (gameConfig['turn_time_seconds'] as num?)?.toInt() ?? 60;
  }

  static Map<String, dynamic> buildTurnTimingUpdate(
    Map<String, dynamic> gameConfig, {
    DateTime? now,
  }) {
    final seconds = turnTimeSeconds(gameConfig);
    final baseTime = now ?? DateTime.now();
    return {
      'turn_timer': seconds,
      'turn_deadline_ms': baseTime.millisecondsSinceEpoch + (seconds * 1000),
    };
  }

  static Map<String, dynamic> buildMatchCountdownUpdate({
    int seconds = 60,
    DateTime? now,
  }) {
    final baseTime = now ?? DateTime.now();
    return {
      'match_countdown_seconds': seconds,
      'match_deadline_ms': baseTime.millisecondsSinceEpoch + (seconds * 1000),
    };
  }

  static Map<String, dynamic> pickSpecialMatchEvent() {
    final entries = specialMatchEvents.entries.toList(growable: false);
    final chosen = entries[_random.nextInt(entries.length)];
    return {
      'id': chosen.key,
      'name': chosen.value['name'],
      'description': chosen.value['description'],
      'intro': chosen.value['intro'],
    };
  }

  static Future<void> prepareScheduledMatchReplay({
    required DocumentReference<Map<String, dynamic>> roomRef,
    required int currentTurn,
  }) async {
    final currentRef = roomRef.collection('game_state').doc('current');
    final liveRef = roomRef.collection('game_state').doc('live_match');
    final currentDoc = (await currentRef.get()).data() ?? <String, dynamic>{};
    if ((currentDoc['phase'] as String? ?? 'drafting') != 'match_countdown') {
      return;
    }
    if ((currentDoc['current_turn'] as num?)?.toInt() != currentTurn) {
      return;
    }

    final liveDoc = (await liveRef.get()).data() ?? <String, dynamic>{};
    if ((liveDoc['prepared_turn'] as num?)?.toInt() == currentTurn &&
        (liveDoc['replay_steps'] as List?)?.isNotEmpty == true &&
        liveDoc['replay_final_data'] is Map) {
      return;
    }

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

    final initialScore = Map<String, int>.from(
      ((liveDoc['score'] as Map?) ?? const <String, dynamic>{}).map(
        (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
      ),
    );
    final specialEvent =
        (liveDoc['special_event'] as Map?)?.cast<String, dynamic>() ??
        (currentDoc['match_special_event'] as Map?)?.cast<String, dynamic>();
    final roomData = (await roomRef.get()).data() ?? <String, dynamic>{};

    final engine = MatchEngine(
      p1Doc,
      p2Doc,
      (liveDoc['match_number'] as num?)?.toInt() ?? 1,
      liveDoc['weather'] as String? ?? 'Gunesli',
      liveDoc['home_id'] as String? ?? 'oyuncu_1',
      initialScore,
      roomData['is_bot'] == true,
      specialEvent: specialEvent,
    );

    final introLogs = List<String>.from((liveDoc['log'] as List?) ?? const []);
    if (introLogs.isNotEmpty) {
      engine.log.addAll(introLogs);
    }

    final replaySteps = <Map<String, dynamic>>[];
    while (true) {
      final chunk = engine.playChunk(1);
      replaySteps.add({
        'minute': engine.minute,
        'logs': List<String>.from(chunk.logs),
        'score': Map<String, dynamic>.from(engine.score),
        'momentum': engine.momentum,
        'red_cards': List<String>.from(
          engine.events['red_cards']!.cast<String>(),
        ),
        'yellow_cards': List<String>.from(
          engine.events['yellow_cards']!.cast<String>(),
        ),
        'injuries': List<String>.from(
          engine.events['injuries']!.cast<String>(),
        ),
      });
      if (chunk.finished) {
        break;
      }
    }

    final finalData = engine.getFinalData();
    await liveRef.set({
      'prepared_turn': currentTurn,
      'intro_log': introLogs,
      'replay_steps': replaySteps,
      'replay_final_data': {
        'score': finalData.score,
        'log': finalData.log,
        'mvp': finalData.mvp,
        'stats': finalData.stats,
        'events': finalData.events,
        'performance': finalData.performance,
        'final_teams': finalData.finalTeams,
      },
      'special_event': specialEvent,
    }, SetOptions(merge: true));
  }

  static Future<ReplayStartResult> startPreparedMatchReplay({
    required DocumentReference<Map<String, dynamic>> roomRef,
    required int currentTurn,
  }) async {
    return _startPreparedMatchReplayInternal(
      roomRef: roomRef,
      currentTurn: currentTurn,
      force: false,
    );
  }

  static Future<ReplayStartResult> forceStartPreparedMatchReplay({
    required DocumentReference<Map<String, dynamic>> roomRef,
    required int currentTurn,
  }) async {
    return _startPreparedMatchReplayInternal(
      roomRef: roomRef,
      currentTurn: currentTurn,
      force: true,
    );
  }

  static Future<ReplayStartResult> _startPreparedMatchReplayInternal({
    required DocumentReference<Map<String, dynamic>> roomRef,
    required int currentTurn,
    required bool force,
  }) async {
    final currentRef = roomRef.collection('game_state').doc('current');
    final liveRef = roomRef.collection('game_state').doc('live_match');
    try {
      return await roomRef.firestore.runTransaction<ReplayStartResult>((
        transaction,
      ) async {
        final currentSnapshot = await transaction.get(currentRef);
        final currentDoc = currentSnapshot.data() ?? <String, dynamic>{};
        if ((currentDoc['phase'] as String? ?? 'drafting') !=
            'match_countdown') {
          return ReplayStartResult.wrongPhase;
        }
        if ((currentDoc['current_turn'] as num?)?.toInt() != currentTurn) {
          return ReplayStartResult.wrongTurn;
        }

        final liveSnapshot = await transaction.get(liveRef);
        final liveDoc = liveSnapshot.data() ?? <String, dynamic>{};
        if (!_isReplayPayloadReady(liveDoc, currentTurn)) {
          return ReplayStartResult.missingPreparedData;
        }

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final deadlineMs = (currentDoc['match_deadline_ms'] as num?)?.toInt();
        const deadlineToleranceMs = 250;
        if (!force) {
          if (deadlineMs == null) {
            return ReplayStartResult.missingDeadline;
          }
          if (nowMs + deadlineToleranceMs < deadlineMs) {
            return ReplayStartResult.tooEarly;
          }
        }

        final initialScore = Map<String, dynamic>.from(
          (liveDoc['score'] as Map?) ?? const <String, dynamic>{},
        );
        final introLog = List<String>.from(
          (liveDoc['intro_log'] as List?) ??
              (liveDoc['log'] as List?) ??
              const [],
        );
        transaction.update(currentRef, {
          'phase': 'live_match',
          'match_deadline_ms': FieldValue.delete(),
          'match_countdown_seconds': FieldValue.delete(),
          'replay_start_last_error': FieldValue.delete(),
          'replay_start_last_error_at_ms': FieldValue.delete(),
        });
        transaction.update(
          liveRef,
          _buildReplayStartLiveUpdate(
            initialScore: initialScore,
            introLog: introLog,
            nowMs: nowMs,
          ),
        );
        return ReplayStartResult.started;
      });
    } on FirebaseException {
      return ReplayStartResult.writeConflict;
    }
  }

  static bool _isReplayPayloadReady(Map<String, dynamic> liveDoc, int turn) {
    final preparedTurn = (liveDoc['prepared_turn'] as num?)?.toInt();
    final replaySteps = liveDoc['replay_steps'] as List?;
    final finalData = liveDoc['replay_final_data'];
    return preparedTurn == turn &&
        replaySteps != null &&
        replaySteps.isNotEmpty &&
        finalData is Map;
  }

  static Map<String, dynamic> _buildReplayStartLiveUpdate({
    required Map<String, dynamic> initialScore,
    required List<String> introLog,
    required int nowMs,
  }) {
    return {
      'minute': 0,
      'score': initialScore,
      'log': introLog,
      'stats': <String, dynamic>{},
      'momentum': 50,
      'p1_live_subs': <dynamic>[],
      'p2_live_subs': <dynamic>[],
      'p1_state': <String, dynamic>{},
      'p2_state': <String, dynamic>{},
      'red_cards': <dynamic>[],
      'yellow_cards': <dynamic>[],
      'injuries': <dynamic>[],
      'replay_index': 0,
      'replay_started_at_ms': nowMs,
      'is_finished': false,
      'match_deadline_ms': FieldValue.delete(),
      'match_countdown_seconds': FieldValue.delete(),
    };
  }

  static Future<void> completePreparedMatchReplay({
    required DocumentReference<Map<String, dynamic>> roomRef,
    required int currentTurn,
  }) async {
    final currentRef = roomRef.collection('game_state').doc('current');
    final liveRef = roomRef.collection('game_state').doc('live_match');
    final currentDoc = (await currentRef.get()).data() ?? <String, dynamic>{};
    if ((currentDoc['phase'] as String? ?? 'drafting') != 'live_match') {
      return;
    }
    if ((currentDoc['current_turn'] as num?)?.toInt() != currentTurn) {
      return;
    }

    final liveDoc = (await liveRef.get()).data() ?? <String, dynamic>{};
    final finalData = (liveDoc['replay_final_data'] as Map?)
        ?.cast<String, dynamic>();
    if (finalData == null) {
      return;
    }
    final events =
        (finalData['events'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final batch = roomRef.firestore.batch();
    batch.update(currentRef, {
      'phase': 'results',
      'score': finalData['score'],
      'match_log': finalData['log'],
      'match_mvp': finalData['mvp'],
      'match_stats': finalData['stats'],
      'match_events': events,
      'match_player_performance': finalData['performance'],
      'final_teams': finalData['final_teams'],
    });
    batch.set(liveRef, {
      'minute': 90,
      'score': finalData['score'],
      'log': finalData['log'],
      'stats': finalData['stats'],
      'red_cards': List<String>.from(
        (events['red_cards'] as List?) ?? const [],
      ),
      'yellow_cards': List<String>.from(
        (events['yellow_cards'] as List?) ?? const [],
      ),
      'injuries': List<String>.from((events['injuries'] as List?) ?? const []),
      'is_finished': true,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  static Future<void> finalizeScheduledMatch({
    required DocumentReference<Map<String, dynamic>> roomRef,
    required int currentTurn,
  }) async {
    final currentRef = roomRef.collection('game_state').doc('current');
    final liveRef = roomRef.collection('game_state').doc('live_match');
    final currentDoc = (await currentRef.get()).data() ?? <String, dynamic>{};
    if ((currentDoc['phase'] as String? ?? 'drafting') != 'match_countdown') {
      return;
    }
    if ((currentDoc['current_turn'] as num?)?.toInt() != currentTurn) {
      return;
    }

    final liveDoc = (await liveRef.get()).data() ?? <String, dynamic>{};
    if ((liveDoc['is_finished'] as bool?) == true) {
      return;
    }
    if ((liveDoc['match_turn'] as num?)?.toInt() != currentTurn) {
      return;
    }

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

    final initialScore = Map<String, int>.from(
      ((liveDoc['score'] as Map?) ?? const <String, dynamic>{}).map(
        (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
      ),
    );
    final specialEvent =
        (liveDoc['special_event'] as Map?)?.cast<String, dynamic>() ??
        (currentDoc['match_special_event'] as Map?)?.cast<String, dynamic>();
    final roomData = (await roomRef.get()).data() ?? <String, dynamic>{};

    final engine = MatchEngine(
      p1Doc,
      p2Doc,
      (liveDoc['match_number'] as num?)?.toInt() ?? 1,
      liveDoc['weather'] as String? ?? 'Gunesli',
      liveDoc['home_id'] as String? ?? 'oyuncu_1',
      initialScore,
      roomData['is_bot'] == true,
      specialEvent: specialEvent,
    );

    final introLogs = List<String>.from((liveDoc['log'] as List?) ?? const []);
    if (introLogs.isNotEmpty) {
      engine.log.addAll(introLogs);
    }

    while (true) {
      final chunk = engine.playChunk(1);
      if (chunk.finished) {
        break;
      }
    }

    final finalData = engine.getFinalData();
    final update = <String, dynamic>{
      'minute': engine.minute,
      'score': finalData.score,
      'log': finalData.log,
      'momentum': engine.momentum,
      'stats': finalData.stats,
      'p1_state': engine.getTeamState(engine.t1),
      'p2_state': engine.getTeamState(engine.t2),
      'red_cards': List<String>.from(
        finalData.events['red_cards'] as List? ?? const [],
      ),
      'yellow_cards': List<String>.from(
        finalData.events['yellow_cards'] as List? ?? const [],
      ),
      'injuries': List<String>.from(
        finalData.events['injuries'] as List? ?? const [],
      ),
      'is_finished': true,
      'special_event': specialEvent,
    };

    final batch = roomRef.firestore.batch();
    batch.update(currentRef, {
      'phase': 'results',
      'score': finalData.score,
      'match_log': finalData.log,
      'match_mvp': finalData.mvp,
      'match_stats': finalData.stats,
      'match_events': finalData.events,
      'match_player_performance': finalData.performance,
      'final_teams': finalData.finalTeams,
      'match_special_event': specialEvent,
      'match_deadline_ms': FieldValue.delete(),
      'match_countdown_seconds': FieldValue.delete(),
    });
    batch.set(liveRef, update, SetOptions(merge: true));
    await batch.commit();
  }

  static Future<void> updatePlayerStatuses(
    FirebaseFirestore db,
    DocumentReference<Map<String, dynamic>> roomRef,
  ) async {
    final batch = db.batch();
    for (final playerId in playerList) {
      final query = await roomRef
          .collection('players')
          .doc(playerId)
          .collection('my_team')
          .where('status_duration', isGreaterThan: 0)
          .get();
      for (final doc in query.docs) {
        final newDuration =
            (doc.data()['status_duration'] as num?)?.toInt() ?? 0;
        final remaining = max(0, newDuration - 1);
        final update = <String, dynamic>{'status_duration': remaining};
        if (remaining <= 0) {
          update['status'] = 'uygun';
        }
        batch.update(doc.reference, update);
      }
    }
    await batch.commit();
  }

  static Map<String, dynamic> buildRosterCleanupUpdate(
    Map<String, dynamic> playerDocData,
    Iterable<String> departedPlayerIds,
  ) {
    final departed = departedPlayerIds.whereType<String>().toSet();
    if (departed.isEmpty) return const {};

    final updates = <String, dynamic>{};
    if (departed.contains(playerDocData['captain_id'])) {
      updates['captain_id'] = null;
    }

    final setPieceTakers = Map<String, dynamic>.from(
      (playerDocData['set_piece_takers'] as Map?) ?? const <String, dynamic>{},
    );
    var setPiecesChanged = false;
    for (final key in const ['pen', 'fk', 'cor']) {
      if (departed.contains(setPieceTakers[key])) {
        setPieceTakers[key] = null;
        setPiecesChanged = true;
      }
    }
    if (setPiecesChanged) {
      updates['set_piece_takers'] = setPieceTakers;
    }

    final formationSlots = Map<String, dynamic>.from(
      (playerDocData['formation_slots'] as Map?) ?? const <String, dynamic>{},
    );
    var slotsChanged = false;
    for (final entry in formationSlots.entries.toList()) {
      final slotData = Map<String, dynamic>.from(
        (entry.value as Map?) ?? const <String, dynamic>{},
      );
      if (departed.contains(slotData['player_id'])) {
        formationSlots[entry.key] = {
          ...slotData,
          'player_id': null,
          'instructions': <String>[],
        };
        slotsChanged = true;
      }
    }
    if (slotsChanged) {
      updates['formation_slots'] = formationSlots;
    }

    return updates;
  }

  static Future<void> processTurnStartEffects({
    required DocumentReference<Map<String, dynamic>> roomRef,
    required int currentTurn,
  }) async {
    final batch = roomRef.firestore.batch();
    var hasUpdates = false;

    for (final playerId in playerList) {
      final playerRef = roomRef.collection('players').doc(playerId);
      final playerDoc = (await playerRef.get()).data() ?? <String, dynamic>{};
      final updates = <String, dynamic>{};
      var goldDelta = 0;

      final delayedGoldLoss =
          (playerDoc['delayed_gold_loss'] as num?)?.toInt() ?? 0;
      final delayedGoldReturnTurn =
          (playerDoc['delayed_gold_return_turn'] as num?)?.toInt() ?? 6;
      if (delayedGoldLoss > 0 && currentTurn >= delayedGoldReturnTurn) {
        goldDelta += delayedGoldLoss * 2;
        updates['delayed_gold_loss'] = FieldValue.delete();
        updates['delayed_gold_return_turn'] = FieldValue.delete();
      }

      final delayedGoldRefund =
          (playerDoc['delayed_gold_refund'] as num?)?.toInt() ?? 0;
      final delayedGoldRefundTurn =
          (playerDoc['delayed_gold_refund_turn'] as num?)?.toInt() ?? 8;
      if (delayedGoldRefund > 0 && currentTurn >= delayedGoldRefundTurn) {
        goldDelta += delayedGoldRefund;
        updates['delayed_gold_refund'] = FieldValue.delete();
        updates['delayed_gold_refund_turn'] = FieldValue.delete();
      }

      if (goldDelta != 0) {
        updates['gold'] = FieldValue.increment(goldDelta);
      }

      if (updates.isNotEmpty) {
        batch.update(playerRef, updates);
        hasUpdates = true;
      }
    }

    if (hasUpdates) {
      await batch.commit();
    }
  }

  static Future<void> generateNewShopForPlayer({
    required DocumentReference<Map<String, dynamic>> roomRef,
    required String playerId,
    required Map<String, dynamic>? gameState,
    required Map<String, dynamic> gameConfig,
  }) async {
    final shopPoolSize = gameConfig['shop_pool_size'] as int? ?? 4;
    final configProbabilities = Map<String, dynamic>.from(
      gameConfig['shop_probabilities'] ??
          defaultGameConfig['shop_probabilities'] as Map,
    );

    final playerDoc =
        (await roomRef.collection('players').doc(playerId).get()).data() ??
        <String, dynamic>{};
    final debuffs =
        (playerDoc['active_debuffs'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final currentTurn = gameState?['current_turn'] as int? ?? 1;
    final goalkeepersBannedUntil =
        (debuffs['no_goalkeepers_until'] as num?)?.toInt() ?? 0;
    final goalkeepersBanned = currentTurn <= goalkeepersBannedUntil;

    final scoutingBuff = (playerDoc['active_scouting_buff'] as Map?)
        ?.cast<String, dynamic>();
    if (scoutingBuff != null) {
      final boostAmount =
          ((scoutingBuff['boost'] as num?)?.toDouble() ?? 0) * 100;
      if (scoutingBuff['tier'] == 'tier3') {
        configProbabilities['tier3_80_85'] =
            (configProbabilities['tier3_80_85'] as num).toDouble() +
            boostAmount;
        configProbabilities['tier1_0_70'] =
            (configProbabilities['tier1_0_70'] as num).toDouble() - boostAmount;
      } else if (scoutingBuff['tier'] == 'tier4') {
        configProbabilities['tier4_85_90'] =
            (configProbabilities['tier4_85_90'] as num).toDouble() +
            boostAmount;
        configProbabilities['tier1_0_70'] =
            (configProbabilities['tier1_0_70'] as num).toDouble() - boostAmount;
      }
      await roomRef.collection('players').doc(playerId).update({
        'active_scouting_buff': FieldValue.delete(),
      });
    }

    final poolDocs = await roomRef
        .collection('player_pool')
        .where('owner_id', isEqualTo: 'pool')
        .get();
    final tier1 = <Map<String, dynamic>>[];
    final tier2 = <Map<String, dynamic>>[];
    final tier3 = <Map<String, dynamic>>[];
    final tier4 = <Map<String, dynamic>>[];

    for (final doc in poolDocs.docs) {
      final data = doc.data();
      if (goalkeepersBanned && data['mevki'] == 'Kaleci') continue;
      final rating = (data['rating'] as num?)?.toInt() ?? 0;
      final player = {'id': doc.id, 'data': data};
      if (rating < 70) {
        tier1.add(player);
      } else if (rating < 80) {
        tier2.add(player);
      } else if (rating < 85) {
        tier3.add(player);
      } else {
        tier4.add(player);
      }
    }

    final brackets = [tier1, tier2, tier3, tier4];
    final weights = <double>[
      (configProbabilities['tier1_0_70'] as num?)?.toDouble() ?? 0,
      (configProbabilities['tier2_70_80'] as num?)?.toDouble() ?? 0,
      (configProbabilities['tier3_80_85'] as num?)?.toDouble() ?? 0,
      (configProbabilities['tier4_85_90'] as num?)?.toDouble() ?? 0,
    ];

    final newShopIds = <String>[];
    for (var i = 0; i < shopPoolSize; i++) {
      final availableBrackets = brackets
          .where((bucket) => bucket.isNotEmpty)
          .toList();
      if (availableBrackets.isEmpty) break;
      final chosenBracket =
          _weightedBracket(brackets, weights) ??
          availableBrackets[_random.nextInt(availableBrackets.length)];
      if (chosenBracket.isEmpty) continue;
      final player = chosenBracket.removeAt(
        _random.nextInt(chosenBracket.length),
      );
      newShopIds.add(player['id']! as String);
    }

    await roomRef.collection('players').doc(playerId).update({
      'current_shop_pool': newShopIds,
      'shop_generated_turn': currentTurn,
    });
  }

  static List<Map<String, dynamic>>? _weightedBracket(
    List<List<Map<String, dynamic>>> brackets,
    List<double> weights,
  ) {
    final total = weights.fold<double>(
      0,
      (accumulator, weight) => accumulator + max(0, weight),
    );
    if (total <= 0) return null;
    final roll = _random.nextDouble() * total;
    var cursor = 0.0;
    for (var i = 0; i < brackets.length; i++) {
      cursor += max(0, weights[i]);
      if (cursor >= roll) {
        return brackets[i];
      }
    }
    return brackets.last;
  }

  static Future<List<String>> getAvailablePlayerIdsFromPool(
    DocumentReference<Map<String, dynamic>> roomRef,
  ) async {
    final docs = await roomRef
        .collection('player_pool')
        .where('owner_id', isEqualTo: 'pool')
        .get();
    return docs.docs.map((doc) => doc.id).toList(growable: false);
  }

  static Future<List<String>> getAvailablePlayerIdsByRatingAndOwner(
    DocumentReference<Map<String, dynamic>> roomRef, {
    String ownerId = 'pool',
    int ratingLimit = 70,
  }) async {
    final docs = await roomRef
        .collection('player_pool')
        .where('owner_id', isEqualTo: ownerId)
        .get();
    return docs.docs
        .where(
          (doc) =>
              ((doc.data()['rating'] as num?)?.toInt() ?? 100) < ratingLimit,
        )
        .map((doc) => doc.id)
        .toList(growable: false);
  }

  static Future<Map<String, String>> getPlayerStatuses(
    DocumentReference<Map<String, dynamic>> roomRef,
  ) async {
    final docs = await roomRef.collection('player_pool').get();
    return {
      for (final doc in docs.docs)
        doc.id: doc.data()['owner_id'] as String? ?? 'pool',
    };
  }

  static Future<List<String>> getAvailableAugmentsForPlayer(
    DocumentReference<Map<String, dynamic>> roomRef,
    List<dynamic> globalAugmentPool,
  ) async {
    final statuses = await getPlayerStatuses(roomRef);
    final available = List<String>.from(
      globalAugmentPool.map((value) => value.toString()),
    );

    final valverdeId =
        augments['VALVERDE_BONUS']!['details']['player_id'] as String;
    if (statuses[valverdeId] != null && statuses[valverdeId] != 'pool') {
      available.remove('VALVERDE_BONUS');
    }

    final saraDiscountIds = List<String>.from(
      augments['SARA_DISCOUNT']!['details']['player_ids'] as List,
    );
    final anyAvailable = saraDiscountIds.any((id) => statuses[id] == 'pool');
    if (!anyAvailable) {
      available.remove('SARA_DISCOUNT');
    }

    return available;
  }

  static Future<List<String>> applyAugmentEffect({
    required FirebaseFirestore db,
    required DocumentReference<Map<String, dynamic>> roomRef,
    required Map<String, dynamic> gameConfig,
    required int currentTurn,
    required String playerId,
    required String opponentId,
    required String augmentId,
  }) async {
    final augmentData = augments[augmentId];
    if (augmentData == null) return const [];

    final messages = <String>[];
    final playerRef = roomRef.collection('players').doc(playerId);
    final opponentRef = roomRef.collection('players').doc(opponentId);
    final augmentType = augmentData['type'] as String? ?? '';

    if (augmentType == 'gold_reward') {
      await playerRef.update({
        'gold': FieldValue.increment(augmentData['details']['amount']),
      });
      return messages;
    }

    if (augmentType == 'player_reward') {
      await _transferPlayer(
        roomRef,
        augmentData['details']['player_id'] as String,
        playerId,
        permanentPoolRemoval: true,
      );
      return messages;
    }

    if (augmentType == 'gold_and_random_player') {
      await playerRef.update({
        'gold': FieldValue.increment(augmentData['details']['gold']),
      });
      final available = await getAvailablePlayerIdsFromPool(roomRef);
      if (available.isNotEmpty) {
        await _transferPlayer(
          roomRef,
          available[_random.nextInt(available.length)],
          playerId,
        );
      }
      return messages;
    }

    if (augmentId == 'LOW_RATING_PLAYER_150G') {
      await playerRef.update({
        'gold': FieldValue.increment(augmentData['details']['gold']),
      });
      final available = await getAvailablePlayerIdsByRatingAndOwner(
        roomRef,
        ratingLimit: augmentData['details']['rating_limit'] as int? ?? 70,
      );
      if (available.isNotEmpty) {
        await _transferPlayer(
          roomRef,
          available[_random.nextInt(available.length)],
          playerId,
        );
      }
      return messages;
    }

    if (augmentType == 'steal_player') {
      final opponentTeam = await opponentRef.collection('my_team').get();
      if (opponentTeam.docs.isEmpty) {
        messages.add('Rakibinin takımında oyuncu yoktu.');
        return messages;
      }
      final stolenDoc =
          opponentTeam.docs[_random.nextInt(opponentTeam.docs.length)];
      final stolenPlayerId = stolenDoc.id;
      final stolenData = stolenDoc.data();
      await stolenDoc.reference.delete();
      await playerRef.collection('my_team').doc(stolenPlayerId).set(stolenData);
      await roomRef.collection('player_pool').doc(stolenPlayerId).update({
        'owner_id': playerId,
      });
      final opponentData =
          (await opponentRef.get()).data() ?? <String, dynamic>{};
      final cleanupUpdate = buildRosterCleanupUpdate(opponentData, [
        stolenPlayerId,
      ]);
      if (cleanupUpdate.isNotEmpty) {
        await opponentRef.update(cleanupUpdate);
      }
      messages.add('${stolenData['name']} rakipten çalındı.');
      return messages;
    }

    if (augmentType == 'fates_trade') {
      await _applyFatesTrade(db, roomRef, playerId, opponentId);
      return messages;
    }

    if (augmentType == 'player_discount') {
      await playerRef.update({
        'active_augment_effects.player_discount_data': augmentData['details'],
      });
      return messages;
    }

    if (augmentId == 'RISKY_INCOME') {
      final lostGold = await db.runTransaction<int>((transaction) async {
        final snapshot = await transaction.get(playerRef);
        final currentGold = (snapshot.data()?['gold'] as num?)?.toInt() ?? 0;
        transaction.update(playerRef, {
          'gold': 0,
          'delayed_gold_loss': currentGold,
          'delayed_gold_return_turn': augmentData['details']['turn'] ?? 6,
        });
        return currentGold;
      });
      messages.add(
        '$lostGold altın kaybettin. 6. turda iki katı geri dönecek.',
      );
      return messages;
    }

    if (augmentType == 'persistent_multiplier') {
      final details = (augmentData['details'] as Map).cast<String, dynamic>();
      final key = details.keys.first;
      await playerRef.update({'active_augment_effects.$key': details[key]});
      return messages;
    }

    if (augmentType == 'stat_boost') {
      final details = (augmentData['details'] as Map).cast<String, dynamic>();
      await _applyStatBoost(
        roomRef,
        playerId,
        List<String>.from(details['stats'] as List),
        (details['amount'] as num?)?.toInt() ?? 0,
      );
      return messages;
    }

    if (augmentType == 'opponent_debuff') {
      final details = (augmentData['details'] as Map).cast<String, dynamic>();
      await opponentRef.update({
        'active_debuffs.${details['debuff_type']}': details['value'],
      });
      return messages;
    }

    if (augmentType == 'opponent_player_debuff') {
      await _applyOpponentStatDebuff(
        roomRef,
        opponentId,
        (augmentData['details']['amount'] as num?)?.toInt() ?? 0,
      );
      return messages;
    }

    if (augmentType == 'persistent_passive_effect') {
      if (augmentData['details']['effect_type'] == 'charisma') {
        await playerRef.update({
          'active_augment_effects.no_morale_loss': true,
          'active_augment_effects.synergy_boost': true,
        });
      } else {
        await playerRef.update({
          'active_augment_effects.passive_gold_active': true,
        });
      }
      return messages;
    }

    if (augmentType == 'persistent_match_effect' &&
        augmentData['details']['effect_type'] == 'head_start_goal') {
      final matchTurns = List<int>.from(
        (gameConfig['match_turns'] as List?) ?? const [7, 14, 21],
      );
      final nextMatch = matchTurns
          .where((turn) => turn > currentTurn)
          .cast<int?>()
          .firstWhere((turn) => turn != null, orElse: () => null);
      if (nextMatch != null) {
        await playerRef.update({
          'active_augment_effects.head_start_turn': nextMatch,
        });
      }
      return messages;
    }

    if (augmentType == 'opponent_delayed_gold_loss') {
      final lostGold = await db.runTransaction<int>((transaction) async {
        final snapshot = await transaction.get(opponentRef);
        final opponentGold = (snapshot.data()?['gold'] as num?)?.toInt() ?? 0;
        if (opponentGold > 0) {
          transaction.update(opponentRef, {
            'gold': 0,
            'delayed_gold_refund': opponentGold,
            'delayed_gold_refund_turn':
                augmentData['details']['return_turn'] ?? 8,
          });
        }
        return opponentGold;
      });
      if (lostGold > 0) {
        messages.add('Rakibin $lostGold altınını geçici olarak kaybetti.');
      }
      return messages;
    }

    if (augmentType == 'split_gold_reward') {
      await playerRef.update({
        'gold': FieldValue.increment(augmentData['details']['player_gold']),
      });
      await opponentRef.update({
        'gold': FieldValue.increment(augmentData['details']['opponent_gold']),
      });
      return messages;
    }

    if (augmentType == 'persistent_self_buff') {
      final details = (augmentData['details'] as Map).cast<String, dynamic>();
      if (details['buff_type'] == 'income_boost') {
        await playerRef.update({
          'active_augment_effects.income_boost_turns': details['duration'],
          'active_augment_effects.income_boost_value': details['value'],
        });
      } else if (details['buff_type'] == 'shop_discount') {
        await playerRef.update({
          'active_augment_effects.shop_discount_turns': details['duration'],
          'active_augment_effects.shop_discount_percent': details['value'],
        });
      }
      return messages;
    }

    if (augmentType == 'temporary_player') {
      final loanStar = loanStarsPool[_random.nextInt(loanStarsPool.length)];
      final playerDocData = <String, dynamic>{
        ...loanStar,
        'rating': calculateRating(
          Map<String, dynamic>.from(loanStar['stats'] as Map),
          loanStar['mevki'] as String,
        ),
        'price': 0,
        'is_loan': true,
        'status': 'uygun',
        'status_duration': 0,
      };
      await playerRef
          .collection('my_team')
          .doc(loanStar['id'] as String)
          .set(playerDocData);
      messages.add('${loanStar['name']} kiralık olarak takıma katıldı.');
      return messages;
    }

    if (augmentType == 'conditional_stat_boost') {
      await playerRef.update({
        'active_augment_effects.giant_killer_active': true,
      });
    }

    return messages;
  }

  static Future<void> _applyFatesTrade(
    FirebaseFirestore db,
    DocumentReference<Map<String, dynamic>> roomRef,
    String playerId,
    String opponentId,
  ) async {
    final opponentRef = roomRef.collection('players').doc(opponentId);
    final playerRef = roomRef.collection('players').doc(playerId);
    final opponentDoc = (await opponentRef.get()).data() ?? <String, dynamic>{};
    final opponentGold = (opponentDoc['gold'] as num?)?.toInt() ?? 0;
    final myTeam = await playerRef.collection('my_team').get();
    if (myTeam.docs.isEmpty) return;

    final playerToGive = myTeam.docs[_random.nextInt(myTeam.docs.length)];
    final playerToGiveData = playerToGive.data();
    final batch = db.batch();

    batch.update(opponentRef, {'gold': 0});
    batch.update(playerRef, {'gold': FieldValue.increment(opponentGold)});
    batch.delete(playerToGive.reference);
    batch.set(
      opponentRef.collection('my_team').doc(playerToGive.id),
      playerToGiveData,
    );
    batch.update(roomRef.collection('player_pool').doc(playerToGive.id), {
      'owner_id': opponentId,
    });

    final myData = (await playerRef.get()).data() ?? <String, dynamic>{};
    final cleanupUpdate = buildRosterCleanupUpdate(myData, [playerToGive.id]);
    if (cleanupUpdate.isNotEmpty) {
      batch.update(playerRef, cleanupUpdate);
    }
    await batch.commit();
  }

  static Future<void> _transferPlayer(
    DocumentReference<Map<String, dynamic>> roomRef,
    String playerId,
    String toOwner, {
    bool permanentPoolRemoval = false,
  }) async {
    final poolDoc = await roomRef.collection('player_pool').doc(playerId).get();
    if (!poolDoc.exists) return;
    final playerData = poolDoc.data();
    if (playerData == null) return;
    await roomRef
        .collection('players')
        .doc(toOwner)
        .collection('my_team')
        .doc(playerId)
        .set(playerData);
    await roomRef.collection('player_pool').doc(playerId).update({
      'owner_id': permanentPoolRemoval ? 'removed_by_augment' : toOwner,
    });
  }

  static Future<void> _applyStatBoost(
    DocumentReference<Map<String, dynamic>> roomRef,
    String playerId,
    List<String> statsToBoost,
    int amount,
  ) async {
    final teamDocs = await roomRef
        .collection('players')
        .doc(playerId)
        .collection('my_team')
        .get();
    final batch = roomRef.firestore.batch();
    for (final doc in teamDocs.docs) {
      final data = doc.data();
      final stats = Map<String, dynamic>.from(
        data['stats'] as Map? ?? const {},
      );
      for (final stat in statsToBoost) {
        stats[stat] = max(0, ((stats[stat] as num?)?.toInt() ?? 0) + amount);
      }
      batch.update(doc.reference, {
        'stats': stats,
        'rating': calculateRating(
          stats,
          data['mevki'] as String? ?? 'Orta Saha',
        ),
      });
    }
    await batch.commit();
  }

  static Future<void> _applyOpponentStatDebuff(
    DocumentReference<Map<String, dynamic>> roomRef,
    String opponentId,
    int amount,
  ) async {
    final teamDocs = await roomRef
        .collection('players')
        .doc(opponentId)
        .collection('my_team')
        .get();
    if (teamDocs.docs.isEmpty) return;
    final doc = teamDocs.docs[_random.nextInt(teamDocs.docs.length)];
    final data = doc.data();
    final stats = Map<String, dynamic>.from(data['stats'] as Map? ?? const {});
    for (final entry in stats.entries.toList()) {
      stats[entry.key] = max(0, ((entry.value as num?)?.toInt() ?? 0) + amount);
    }
    await doc.reference.update({
      'stats': stats,
      'rating': calculateRating(stats, data['mevki'] as String? ?? 'Orta Saha'),
    });
  }
}
