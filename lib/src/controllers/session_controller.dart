import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../data/game_data.dart';
import '../services/audio_service.dart';
import '../services/local_storage_service.dart';
import '../services/match_engine.dart';
import '../services/room_game_service.dart';
import '../utils/game_exception.dart';
import '../utils/hash.dart';

enum GameView {
  auth,
  lobby,
  admin,
  preGame,
  settings,
  draft,
  augment,
  formation,
  tactics,
  trade,
  simulation,
}

Map<String, dynamic> _cloneDefaultGameConfig() {
  return {
    ...defaultGameConfig,
    'match_turns': List<int>.from(defaultGameConfig['match_turns'] as List),
    'augment_turns': List<int>.from(defaultGameConfig['augment_turns'] as List),
    'shop_probabilities': Map<String, dynamic>.from(
      defaultGameConfig['shop_probabilities'] as Map,
    ),
  };
}

Map<String, Map<String, dynamic>> _cloneDefaultAugmentCatalog() {
  return {
    for (final entry in augments.entries)
      entry.key: {
        ...entry.value,
        'details': Map<String, dynamic>.from(
          (entry.value['details'] as Map?) ?? const <String, dynamic>{},
        ),
      },
  };
}

List<Map<String, dynamic>> _cloneDefaultPlayerCatalog() {
  return playerDataTemplate
      .map((template) {
        final stats = Map<String, dynamic>.from(template['stats'] as Map);
        final mevki = template['mevki'] as String? ?? 'Orta Saha';
        final rating = calculateRating(stats, mevki);
        return {
          'id': template['id'],
          'name': template['name'],
          'mevki': mevki,
          'stats': stats,
          'rating': rating,
          'price': calculatePrice(rating),
        };
      })
      .toList(growable: true);
}

class SessionController extends ChangeNotifier {
  static const String adminEmail = 'yusar646@gmail.com';
  static const String _augmentCatalogCollection = 'catalog_augments';
  static const String _playerCatalogCollection = 'catalog_players';
  static const int _matchCountdownFallbackSeconds = 60;
  static const int _matchCountdownForceGraceMs = 3000;

  SessionController({LocalStorageService? storage, AudioService? audio})
    : _storage = storage ?? LocalStorageService.instance,
      _audio = audio ?? AudioService.instance;

  final LocalStorageService _storage;
  final AudioService _audio;
  final Random _random = Random();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _gameStateSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _playerStateSubscription;
  Timer? _turnTicker;
  Timer? _botTurnTimer;
  Timer? _matchCountdownTicker;
  Timer? _matchCountdownWatchdogTicker;
  Timer? _matchReplayRetryTimer;

  bool isInitializing = true;
  bool busy = false;
  bool firebaseReady = false;
  String dbError = 'Bağlantı kurulmadı';

  GameView view = GameView.auth;

  String? username;
  String? email;
  String? roomCode;
  String? playerId;
  String? opponentId;
  bool isHost = false;
  Map<String, dynamic> gameConfig = _cloneDefaultGameConfig();
  Map<String, Map<String, dynamic>> augmentCatalog =
      _cloneDefaultAugmentCatalog();
  List<Map<String, dynamic>> playerCatalog = _cloneDefaultPlayerCatalog();

  Map<String, dynamic>? currentGameState;
  Map<String, dynamic>? currentPlayerState;
  int? _turnSecondsRemaining;
  int? _matchCountdownSecondsRemaining;

  List<String> pendingAugments = const [];
  int pendingAugmentTurn = 0;

  String? _roomRuntimeKey;
  bool _turnAdvanceInProgress = false;
  bool _augmentLookupInProgress = false;
  bool _shopGenerationInProgress = false;
  bool _deadlineRepairInProgress = false;
  bool _matchDeadlineRepairInProgress = false;
  bool _botTurnScheduled = false;
  bool _botTurnExecutionInProgress = false;
  bool _matchSimulationInProgress = false;
  bool _matchReplayPreparationInProgress = false;
  bool _matchReplayForceInProgress = false;
  int? _lastProcessedTurnEffectsTurn;
  int? _optimisticDraftTurn;
  int? _scheduledBotTurn;
  int? _lastSimulatedMatchTurn;
  int? _lastPreparedMatchTurn;
  int? _matchCountdownLocalTurn;
  int? _matchCountdownLocalStartMs;
  int? _matchCountdownLocalDurationSeconds;
  int? _matchCountdownExpiredAtMs;

  FirebaseFirestore? get firestore =>
      firebaseReady ? FirebaseFirestore.instance : null;

  DocumentReference<Map<String, dynamic>>? get roomRef {
    final code = roomCode;
    final db = firestore;
    if (code == null || db == null) return null;
    return db.collection('rooms').doc(code);
  }

  int? get turnSecondsRemaining => _turnSecondsRemaining;
  int? get matchCountdownSecondsRemaining => _matchCountdownSecondsRemaining;

  int get activeTurnNumber =>
      (currentGameState?['current_turn'] as num?)?.toInt() ?? 1;

  bool get isAdmin => email?.trim().toLowerCase() == adminEmail.toLowerCase();

  bool get isCurrentTurnMine =>
      currentGameState?['current_player_id'] == playerId;

  bool get showGlobalTurnHud {
    return playerId != null &&
        view != GameView.draft &&
        (currentGameState?['phase'] as String?) == 'drafting' &&
        _turnSecondsRemaining != null;
  }

  Future<void> initialize() async {
    try {
      await _storage.init();
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firebaseReady = true;
      dbError = '';
      await _loadCatalogData();
      await _tryAutoLogin();
    } catch (error) {
      firebaseReady = false;
      dbError = 'Firebase bağlantı hatası: $error';
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> _tryAutoLogin() async {
    final credentials = _storage.readCredentials();
    if (credentials == null) return;
    final db = firestore;
    if (db == null) return;

    final savedEmail = credentials['email'];
    final savedPassword = credentials['password'];
    if (savedEmail == null || savedPassword == null) return;

    final doc = await db.collection('users').doc(savedEmail).get();
    if (!doc.exists) return;
    final data = doc.data() ?? <String, dynamic>{};
    if (data['password'] != savedPassword) return;

    email = savedEmail;
    username = data['username'] as String?;
    view = GameView.lobby;
  }

  Map<String, dynamic> _normalizePlayerCatalogEntry(
    Map<String, dynamic> data, {
    String? fallbackId,
  }) {
    final stats =
        Map<String, dynamic>.from(
          (data['stats'] as Map?) ?? const <String, dynamic>{},
        ).map(
          (key, value) =>
              MapEntry(key, value is num ? value.toInt().clamp(0, 99) : 0),
        );
    final mevki = data['mevki'] as String? ?? 'Orta Saha';
    final rating = calculateRating(stats, mevki);
    return {
      'id': (data['id'] as String?) ?? fallbackId ?? _buildPlayerCatalogId(''),
      'name': (data['name'] as String? ?? 'Yeni Oyuncu').trim(),
      'mevki': mevki,
      'stats': stats,
      'rating': rating,
      'price': calculatePrice(rating),
    };
  }

  String _buildPlayerCatalogId(String name) {
    final normalized = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final base = normalized.isEmpty ? 'oyuncu' : normalized;
    final usedIds = {
      ...playerCatalog
          .map((player) => player['id'] as String?)
          .whereType<String>(),
      ..._cloneDefaultPlayerCatalog()
          .map((player) => player['id'] as String?)
          .whereType<String>(),
    };
    var counter = 1;
    while (true) {
      final candidate = '${base}_${counter.toString().padLeft(2, '0')}';
      if (!usedIds.contains(candidate)) {
        return candidate;
      }
      counter += 1;
    }
  }

  Future<void> _seedCatalogCollectionIfMissing() async {
    final db = firestore;
    if (db == null) return;

    final augmentProbe = await db
        .collection(_augmentCatalogCollection)
        .limit(1)
        .get();
    final playerProbe = await db
        .collection(_playerCatalogCollection)
        .limit(1)
        .get();
    if (augmentProbe.docs.isNotEmpty && playerProbe.docs.isNotEmpty) {
      return;
    }

    final batch = db.batch();
    if (augmentProbe.docs.isEmpty) {
      for (final entry in augments.entries) {
        batch.set(db.collection(_augmentCatalogCollection).doc(entry.key), {
          'name': entry.value['name'],
          'description': entry.value['description'],
          'type': entry.value['type'],
          'details': entry.value['details'],
        });
      }
    }
    if (playerProbe.docs.isEmpty) {
      for (final player in _cloneDefaultPlayerCatalog()) {
        batch.set(
          db.collection(_playerCatalogCollection).doc(player['id'] as String),
          {
            'name': player['name'],
            'mevki': player['mevki'],
            'stats': player['stats'],
            'rating': player['rating'],
            'price': player['price'],
          },
        );
      }
    }
    await batch.commit();
  }

  Future<void> _loadCatalogData({bool notify = false}) async {
    final db = firestore;
    if (db == null) {
      augmentCatalog = _cloneDefaultAugmentCatalog();
      playerCatalog = _cloneDefaultPlayerCatalog();
      if (notify) notifyListeners();
      return;
    }

    await _seedCatalogCollectionIfMissing();
    final augmentSnapshot = await db
        .collection(_augmentCatalogCollection)
        .get();
    final playerSnapshot = await db.collection(_playerCatalogCollection).get();

    final nextAugments = _cloneDefaultAugmentCatalog();
    for (final doc in augmentSnapshot.docs) {
      final existing = nextAugments[doc.id] ?? <String, dynamic>{};
      nextAugments[doc.id] = {...existing, ...doc.data()};
    }

    final nextPlayers =
        playerSnapshot.docs
            .map(
              (doc) =>
                  _normalizePlayerCatalogEntry({'id': doc.id, ...doc.data()}),
            )
            .toList(growable: true)
          ..sort((left, right) {
            final leftName = left['name'] as String? ?? '';
            final rightName = right['name'] as String? ?? '';
            return leftName.compareTo(rightName);
          });

    augmentCatalog = nextAugments;
    playerCatalog = nextPlayers.isEmpty
        ? _cloneDefaultPlayerCatalog()
        : nextPlayers;
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> refreshCatalogData() async {
    _ensureFirebase();
    await _loadCatalogData(notify: true);
  }

  Future<void> saveAugmentCatalogEntry({
    required String augmentId,
    required String name,
    required String description,
  }) async {
    _ensureFirebase();
    final trimmedName = name.trim();
    final trimmedDescription = description.trim();
    if (trimmedName.isEmpty || trimmedDescription.isEmpty) {
      throw GameException('Hata', 'Eklenti adı ve açıklaması boş olamaz.');
    }
    final current = augmentCatalog[augmentId] ?? augments[augmentId];
    if (current == null) {
      throw GameException('Hata', 'Eklenti bulunamadı.');
    }

    await firestore!.collection(_augmentCatalogCollection).doc(augmentId).set({
      'name': trimmedName,
      'description': trimmedDescription,
      'type': current['type'],
      'details': current['details'],
    }, SetOptions(merge: true));

    augmentCatalog[augmentId] = {
      ...current,
      'name': trimmedName,
      'description': trimmedDescription,
    };
    notifyListeners();
  }

  Future<void> savePlayerCatalogEntry({
    String? playerId,
    required String name,
    required String mevki,
    required Map<String, dynamic> stats,
  }) async {
    _ensureFirebase();
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw GameException('Hata', 'Oyuncu adı boş olamaz.');
    }

    final normalized = _normalizePlayerCatalogEntry({
      'id': playerId ?? _buildPlayerCatalogId(trimmedName),
      'name': trimmedName,
      'mevki': mevki,
      'stats': stats,
    });
    final id = normalized['id'] as String;

    await firestore!.collection(_playerCatalogCollection).doc(id).set({
      'name': normalized['name'],
      'mevki': normalized['mevki'],
      'stats': normalized['stats'],
      'rating': normalized['rating'],
      'price': normalized['price'],
    }, SetOptions(merge: false));

    final existingIndex = playerCatalog.indexWhere(
      (player) => player['id'] == id,
    );
    if (existingIndex >= 0) {
      playerCatalog[existingIndex] = normalized;
    } else {
      playerCatalog.add(normalized);
    }
    playerCatalog.sort((left, right) {
      final leftName = left['name'] as String? ?? '';
      final rightName = right['name'] as String? ?? '';
      return leftName.compareTo(rightName);
    });
    notifyListeners();
  }

  Map<String, dynamic> buildRandomPlayerProfile({required String mevki}) {
    int nextInRange(int min, int max) => min + _random.nextInt(max - min + 1);

    final stats = switch (mevki) {
      'Kaleci' => <String, int>{
        'hucum': nextInRange(18, 42),
        'savunma': nextInRange(72, 96),
        'dayaniklilik': nextInRange(66, 88),
        'sut': nextInRange(0, 18),
        'pas': nextInRange(42, 78),
        'hiz': nextInRange(40, 68),
      },
      'Defans' => <String, int>{
        'hucum': nextInRange(36, 70),
        'savunma': nextInRange(68, 96),
        'dayaniklilik': nextInRange(70, 92),
        'sut': nextInRange(24, 58),
        'pas': nextInRange(48, 78),
        'hiz': nextInRange(56, 86),
      },
      'Forvet' => <String, int>{
        'hucum': nextInRange(70, 97),
        'savunma': nextInRange(18, 50),
        'dayaniklilik': nextInRange(58, 82),
        'sut': nextInRange(68, 98),
        'pas': nextInRange(46, 78),
        'hiz': nextInRange(62, 92),
      },
      _ => <String, int>{
        'hucum': nextInRange(56, 88),
        'savunma': nextInRange(36, 74),
        'dayaniklilik': nextInRange(64, 88),
        'sut': nextInRange(44, 82),
        'pas': nextInRange(62, 94),
        'hiz': nextInRange(54, 82),
      },
    };

    final rating = calculateRating(stats, mevki);
    return {'stats': stats, 'rating': rating, 'price': calculatePrice(rating)};
  }

  void _ensureFirebase() {
    if (!firebaseReady || firestore == null) {
      throw GameException('Bağlantı Hatası', dbError);
    }
  }

  void _setBusy(bool value) {
    busy = value;
    notifyListeners();
  }

  void switchView(GameView nextView) {
    view = nextView;
    _syncRoomRuntimeToView();
    notifyListeners();
  }

  void applyOptimisticDraftTransition({
    required Map<String, dynamic> gameState,
    Map<String, dynamic>? playerState,
  }) {
    final phase = gameState['phase'] as String? ?? 'drafting';
    final turn = (gameState['current_turn'] as num?)?.toInt();
    if (phase == 'drafting' && turn != null) {
      _optimisticDraftTurn = turn;
    }
    currentGameState = Map<String, dynamic>.from(gameState);
    if (playerState != null) {
      currentPlayerState = Map<String, dynamic>.from(playerState);
    }
    _syncTurnCountdown();
    notifyListeners();
  }

  void openAugmentSelection(List<String> augmentIds, int turn) {
    pendingAugments = List<String>.from(augmentIds);
    pendingAugmentTurn = turn;
    switchView(GameView.augment);
  }

  void clearPendingAugments({bool notify = true}) {
    pendingAugments = const [];
    pendingAugmentTurn = 0;
    if (notify) {
      notifyListeners();
    }
  }

  void playClickSound() {
    // Intentionally silent for now.
  }

  void playWhistleSound() {
    unawaited(_audio.playWhistle());
  }

  Future<void> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    _ensureFirebase();
    _setBusy(true);
    try {
      final hashedPassword = sha256Hash(password);
      final doc = await firestore!.collection('users').doc(email).get();
      if (!doc.exists) {
        throw GameException('Hata', 'Kullanıcı bulunamadı. Kayıt olun.');
      }

      final data = doc.data() ?? <String, dynamic>{};
      if (data['password'] != hashedPassword) {
        throw GameException('Hata', 'Yanlış şifre girdiniz.');
      }

      this.email = email;
      username = data['username'] as String?;
      if (rememberMe) {
        await _storage.saveCredentials(
          email: email,
          passwordHash: hashedPassword,
        );
      } else {
        await _storage.clearCredentials();
      }
      view = GameView.lobby;
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String username,
    required bool rememberMe,
  }) async {
    _ensureFirebase();
    _setBusy(true);
    try {
      final userRef = firestore!.collection('users').doc(email);
      final existing = await userRef.get();
      if (existing.exists) {
        throw GameException('Hata', 'Bu e-posta kayıtlı.');
      }

      final hashedPassword = sha256Hash(password);
      await userRef.set({'username': username, 'password': hashedPassword});
      this.email = email;
      this.username = username;
      if (rememberMe) {
        await _storage.saveCredentials(
          email: email,
          passwordHash: hashedPassword,
        );
      }
      view = GameView.lobby;
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> logout() async {
    await _storage.clearCredentials();
    email = null;
    username = null;
    _resetRoomState();
    view = GameView.auth;
    notifyListeners();
  }

  Future<void> createRoom() async {
    _ensureFirebase();
    if (username == null) {
      throw GameException('Hata', 'Önce giriş yapılmalı.');
    }

    final code = _generateRoomCode();
    roomCode = code;
    isHost = true;
    playerId = 'oyuncu_1';
    opponentId = 'oyuncu_2';
    gameConfig = _cloneDefaultGameConfig();
    await setupNewRoom(code);
    view = GameView.preGame;
    _syncRoomRuntimeToView();
    notifyListeners();
  }

  Future<void> joinRoom(String code) async {
    _ensureFirebase();
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw GameException('Hata', 'Lütfen bir oda kodu girin.');
    }

    final roomDoc = await firestore!.collection('rooms').doc(normalized).get();
    if (!roomDoc.exists) {
      throw GameException('Hata', 'Böyle bir oda bulunamadı veya kod yanlış.');
    }

    roomCode = normalized;
    isHost = false;
    playerId = 'oyuncu_2';
    opponentId = 'oyuncu_1';
    await loadGameConfig();

    final room = roomRef!;
    await room.update({'p2_name': username});
    await room.collection('players').doc('oyuncu_2').update({
      'team_name': username,
    });
    view = GameView.preGame;
    _syncRoomRuntimeToView();
    notifyListeners();
  }

  Future<void> loadGameConfig() async {
    final room = roomRef;
    if (room == null) return;
    final configRef = room.collection('game_config').doc('current');
    final doc = await configRef.get();
    if (doc.exists) {
      gameConfig = Map<String, dynamic>.from(
        doc.data() ?? _cloneDefaultGameConfig(),
      );
    } else {
      gameConfig = _cloneDefaultGameConfig();
      await configRef.set(gameConfig);
    }
    notifyListeners();
  }

  Future<void> saveGameConfig(Map<String, dynamic> config) async {
    final room = roomRef;
    if (room == null) return;
    await room.collection('game_config').doc('current').set(config);
    gameConfig = Map<String, dynamic>.from(config);
    notifyListeners();
  }

  Future<void> setupNewRoom(String roomCode) async {
    final db = firestore;
    if (db == null) return;
    final room = db.collection('rooms').doc(roomCode);
    final batch = db.batch();

    batch.set(room, {
      'room_code': roomCode,
      'p1_name': username,
      'p2_name': 'Bekleniyor...',
      'p1_ready': false,
      'p2_ready': false,
      'is_started': false,
      'is_bot': false,
      'bot_difficulty': 'none',
    }, SetOptions(merge: true));

    batch.set(room.collection('game_state').doc('current'), {
      'current_player_id': 'oyuncu_1',
      'current_turn': 1,
      'phase': 'drafting',
      ...RoomGameService.buildTurnTimingUpdate(gameConfig),
      'score': {'oyuncu_1': 0, 'oyuncu_2': 0},
      'augment_pool': augmentCatalog.keys.toList(growable: false),
      'match_scores': <String, dynamic>{},
      'season_stats': {
        'goals': <String, dynamic>{},
        'assists': <String, dynamic>{},
        'mvps': <String, dynamic>{},
      },
      'last_results_applied_turn': 0,
      'season_awards_processed': false,
      'season_awards_summary': null,
    });

    final defaultTactics = <String, dynamic>{
      'gold': 200,
      'max_capacity': 15,
      'formation': '3-2-1',
      'facilities': <String>[],
      'active_augment_effects': <String, dynamic>{},
      'active_debuffs': <String, dynamic>{},
      'augments_chosen': <String>[],
      'augment_turns_completed': <int>[],
      'current_shop_pool': <String>[],
      'shop_generated_turn': 0,
      'income_taken_for_turn': 0,
      'last_scout_turn': 0,
      'captain_id': null,
      'set_piece_takers': {'pen': null, 'fk': null, 'cor': null},
      'mentality': 'Dengeli',
      'build_up_play': 'Dengeli',
      'focus_play': 'Karma',
      'crossing_type': 'Yüksek Orta',
      'defensive_line': 'Normal',
      'offside_trap': false,
      'pressing_trigger': 'Dengeli',
      'formation_slots': <String, dynamic>{},
    };

    for (final id in playerList) {
      batch.set(room.collection('players').doc(id), {
        ...defaultTactics,
        'team_name': id == 'oyuncu_1' ? username : 'Rakip',
      });
    }

    for (final template in playerCatalog) {
      final stats = Map<String, dynamic>.from(template['stats'] as Map);
      final rating = calculateRating(
        stats,
        template['mevki'] as String? ?? 'Orta Saha',
      );
      batch.set(room.collection('player_pool').doc(template['id'] as String), {
        'name': template['name'],
        'mevki': template['mevki'],
        'rating': rating,
        'price': calculatePrice(rating),
        'owner_id': 'pool',
        'stats': stats,
        'status': 'uygun',
        'status_duration': 0,
        'form': 5,
        'form_history': const [5.0],
        'morale': 5,
        'morale_history': const [5.0],
      });
    }

    await batch.commit();
  }

  Future<void> advanceCurrentTurn() async {
    final me = playerId;
    if (me == null) return;
    await _advanceTurnForPlayer(actingPlayerId: me);
  }

  Future<void> _advanceTurnForPlayer({required String actingPlayerId}) async {
    final room = roomRef;
    if (room == null || _turnAdvanceInProgress) return;

    final opponent = actingPlayerId == 'oyuncu_1' ? 'oyuncu_2' : 'oyuncu_1';
    _turnAdvanceInProgress = true;
    try {
      final latestGameState =
          (await room.collection('game_state').doc('current').get()).data() ??
          <String, dynamic>{};
      if ((latestGameState['phase'] as String? ?? 'drafting') != 'drafting') {
        return;
      }
      if (latestGameState['current_player_id'] != actingPlayerId) {
        return;
      }

      final playerDoc =
          (await room.collection('players').doc(actingPlayerId).get()).data() ??
          <String, dynamic>{};
      final currentTurn =
          (latestGameState['current_turn'] as num?)?.toInt() ?? 1;
      final activeEffects =
          (playerDoc['active_augment_effects'] as Map?)
              ?.cast<String, dynamic>() ??
          <String, dynamic>{};
      var passiveGold = 0;
      if (activeEffects['passive_gold_active'] == true && currentTurn.isEven) {
        passiveGold += 25 + _random.nextInt(26);
      }
      final facilities = List<String>.from(
        (playerDoc['facilities'] as List?) ?? const [],
      );
      if (facilities.contains('ticari_stadyum')) {
        passiveGold += 45;
      }
      if (passiveGold > 0) {
        await room.collection('players').doc(actingPlayerId).update({
          'gold': FieldValue.increment(passiveGold),
        });
      }

      final shopDiscountTurns =
          (activeEffects['shop_discount_turns'] as num?)?.toInt() ?? 0;
      if (shopDiscountTurns > 0) {
        final updates = <String, dynamic>{};
        if (shopDiscountTurns - 1 <= 0) {
          updates['active_augment_effects.shop_discount_turns'] =
              FieldValue.delete();
          updates['active_augment_effects.shop_discount_percent'] =
              FieldValue.delete();
        } else {
          updates['active_augment_effects.shop_discount_turns'] =
              shopDiscountTurns - 1;
        }
        await room.collection('players').doc(actingPlayerId).update(updates);
      }

      final matchTurns = List<int>.from(
        (gameConfig['match_turns'] as List?) ?? const [7, 14, 21],
      );
      if (matchTurns.contains(currentTurn) && actingPlayerId == 'oyuncu_2') {
        await _startSimulationLogic();
        return;
      }

      final update = <String, dynamic>{
        'current_player_id': opponent,
        ...RoomGameService.buildTurnTimingUpdate(gameConfig),
      };
      var shopTurn = currentTurn;
      if (actingPlayerId == 'oyuncu_2') {
        final nextTurn = currentTurn + 1;
        if (nextTurn > ((gameConfig['max_turns'] as num?)?.toInt() ?? 21)) {
          update['phase'] = 'finished';
        } else {
          update['current_turn'] = nextTurn;
          shopTurn = nextTurn;
          await RoomGameService.updatePlayerStatuses(room.firestore, room);
        }
      }
      if (update['phase'] != 'finished') {
        await RoomGameService.generateNewShopForPlayer(
          roomRef: room,
          playerId: opponent,
          gameState: {'current_turn': shopTurn},
          gameConfig: gameConfig,
        );
      }
      await room.collection('game_state').doc('current').update(update);
    } finally {
      _turnAdvanceInProgress = false;
    }
  }

  Future<void> _startSimulationLogic() async {
    final room = roomRef;
    if (room == null) return;

    final currentState =
        (await room.collection('game_state').doc('current').get()).data() ??
        currentGameState ??
        <String, dynamic>{};
    final currentTurn = (currentState['current_turn'] as num?)?.toInt() ?? 1;
    final matchTurns = List<int>.from(
      (gameConfig['match_turns'] as List?) ?? const [7, 14, 21],
    );
    final matchNumber = matchTurns.indexOf(currentTurn) + 1;
    final weather = [
      'Güneşli',
      'Bulutlu',
      'Yağmurlu',
      'Sıcak',
    ][_random.nextInt(4)];
    final homeId = matchNumber.isOdd ? 'oyuncu_1' : 'oyuncu_2';
    final p1Doc =
        (await room.collection('players').doc('oyuncu_1').get()).data() ??
        <String, dynamic>{};
    final p2Doc =
        (await room.collection('players').doc('oyuncu_2').get()).data() ??
        <String, dynamic>{};
    final p1Name = p1Doc['team_name'] as String? ?? 'Oyuncu 1';
    final p2Name = p2Doc['team_name'] as String? ?? 'Oyuncu 2';
    final p1Effects =
        (p1Doc['active_augment_effects'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final p2Effects =
        (p2Doc['active_augment_effects'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final p1Score = p1Effects['head_start_turn'] == currentTurn ? 1 : 0;
    final p2Score = p2Effects['head_start_turn'] == currentTurn ? 1 : 0;
    final specialEvent = RoomGameService.pickSpecialMatchEvent();
    final countdown = RoomGameService.buildMatchCountdownUpdate(seconds: 60);
    final introLog = (specialEvent['intro'] as String?)?.trim();
    final initialLog = <String>[
      '[event]MAÇ $matchNumber BAŞLIYOR! Hava: $weather[/event]',
    ];
    if (introLog != null && introLog.isNotEmpty) {
      initialLog.add('[event]$introLog[/event]');
    }
    if (p1Score > 0) {
      initialLog.add('[goal]$p1Name maça 1-0 önde başladı.[/goal]');
    }
    if (p2Score > 0) {
      initialLog.add('[goal]$p2Name maça 1-0 önde başladı.[/goal]');
    }

    await room.collection('game_state').doc('live_match').set({
      'match_number': matchNumber,
      'match_turn': currentTurn,
      'weather': weather,
      'home_id': homeId,
      'minute': 0,
      'score': {'oyuncu_1': p1Score, 'oyuncu_2': p2Score},
      'log': initialLog,
      'p1_live_subs': <dynamic>[],
      'p2_live_subs': <dynamic>[],
      'p1_state': <String, dynamic>{},
      'p2_state': <String, dynamic>{},
      'red_cards': <dynamic>[],
      'yellow_cards': <dynamic>[],
      'injuries': <dynamic>[],
      'is_finished': false,
      'special_event': specialEvent,
      ...countdown,
    });
    await room.collection('game_state').doc('current').update({
      'phase': 'match_countdown',
      'score': {'oyuncu_1': p1Score, 'oyuncu_2': p2Score},
      'match_number': matchNumber,
      'match_weather': weather,
      'match_home_id': homeId,
      'match_special_event': specialEvent,
      ...countdown,
    });
    if (view != GameView.draft) {
      switchView(GameView.draft);
    }
  }

  void _syncMatchCountdown(Map<String, dynamic> data) {
    final phase = data['phase'] as String? ?? 'drafting';
    if (phase != 'match_countdown') {
      _cancelMatchCountdown();
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final currentTurn =
        (data['current_turn'] as num?)?.toInt() ?? activeTurnNumber;
    final deadlineMs = (data['match_deadline_ms'] as num?)?.toInt();
    final configuredSeconds = max(
      0,
      min(
        _matchCountdownFallbackSeconds,
        (data['match_countdown_seconds'] as num?)?.toInt() ??
            _matchCountdownFallbackSeconds,
      ),
    );

    if (deadlineMs != null) {
      _matchCountdownLocalTurn = null;
      _matchCountdownLocalStartMs = null;
      _matchCountdownLocalDurationSeconds = null;
      _setMatchCountdownSecondsRemaining(_remainingSeconds(deadlineMs));
    } else {
      _ensureSyntheticMatchCountdownState(
        turn: currentTurn,
        initialSeconds: configuredSeconds,
        nowMs: nowMs,
      );
      _setMatchCountdownSecondsRemaining(
        _remainingSyntheticMatchCountdown(nowMs),
      );
      if (isHost) {
        unawaited(_ensureMatchCountdownDeadline(data));
      }
    }

    _updateMatchCountdownExpiredMarker(nowMs: nowMs, deadlineMs: deadlineMs);

    _matchCountdownTicker?.cancel();
    _matchCountdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      _handleMatchCountdownTick();
    });
    _matchCountdownWatchdogTicker?.cancel();
    _matchCountdownWatchdogTicker = Timer.periodic(
      const Duration(milliseconds: 400),
      (_) => _handleMatchCountdownWatchdogTick(),
    );
    _handleMatchCountdownTick();
    _handleMatchCountdownWatchdogTick();
  }

  void _ensureSyntheticMatchCountdownState({
    required int turn,
    required int initialSeconds,
    required int nowMs,
  }) {
    if (_matchCountdownLocalTurn == turn &&
        _matchCountdownLocalStartMs != null) {
      return;
    }
    _matchCountdownLocalTurn = turn;
    _matchCountdownLocalStartMs = nowMs;
    _matchCountdownLocalDurationSeconds = max(0, initialSeconds);
    _matchCountdownExpiredAtMs = null;
  }

  int _remainingSyntheticMatchCountdown(int nowMs) {
    final startMs = _matchCountdownLocalStartMs;
    final totalSeconds = _matchCountdownLocalDurationSeconds;
    if (startMs == null || totalSeconds == null) {
      return 0;
    }
    final elapsedSeconds = max(0, ((nowMs - startMs) / 1000).floor());
    return max(0, totalSeconds - elapsedSeconds);
  }

  void _updateMatchCountdownExpiredMarker({
    required int nowMs,
    required int? deadlineMs,
  }) {
    final expired = deadlineMs != null
        ? nowMs >= deadlineMs
        : (_matchCountdownSecondsRemaining ?? 1) <= 0;
    if (!expired) {
      _matchCountdownExpiredAtMs = null;
      return;
    }
    _matchCountdownExpiredAtMs ??= nowMs;
  }

  void _handleMatchCountdownTick() {
    final state = currentGameState;
    final phase = state?['phase'] as String?;
    if (phase != 'match_countdown') {
      _cancelMatchCountdown();
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final deadlineMs = (state?['match_deadline_ms'] as num?)?.toInt();
    int remaining;
    if (deadlineMs != null) {
      remaining = _remainingSeconds(deadlineMs);
    } else {
      final currentTurn =
          (state?['current_turn'] as num?)?.toInt() ?? activeTurnNumber;
      final configuredSeconds = max(
        0,
        min(
          _matchCountdownFallbackSeconds,
          (state?['match_countdown_seconds'] as num?)?.toInt() ??
              _matchCountdownFallbackSeconds,
        ),
      );
      _ensureSyntheticMatchCountdownState(
        turn: currentTurn,
        initialSeconds: configuredSeconds,
        nowMs: nowMs,
      );
      remaining = _remainingSyntheticMatchCountdown(nowMs);
      if (isHost) {
        unawaited(_ensureMatchCountdownDeadline(state ?? <String, dynamic>{}));
      }
    }

    _setMatchCountdownSecondsRemaining(remaining);
    _updateMatchCountdownExpiredMarker(nowMs: nowMs, deadlineMs: deadlineMs);
    if ((deadlineMs != null && nowMs >= deadlineMs) || remaining <= 0) {
      unawaited(_handleExpiredMatchCountdown());
    }
  }

  void _handleMatchCountdownWatchdogTick() {
    final state = currentGameState;
    if ((state?['phase'] as String? ?? 'drafting') != 'match_countdown') {
      _cancelMatchCountdown();
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final deadlineMs = (state?['match_deadline_ms'] as num?)?.toInt();
    _updateMatchCountdownExpiredMarker(nowMs: nowMs, deadlineMs: deadlineMs);
    final expiredAtMs = _matchCountdownExpiredAtMs;
    if (expiredAtMs == null || !isHost) return;
    final elapsedMs = nowMs - expiredAtMs;
    if (elapsedMs >= _matchCountdownForceGraceMs) {
      unawaited(_forceStartMatchCountdownReplay());
      return;
    }
    if (_matchSimulationInProgress) return;
    unawaited(_handleExpiredMatchCountdown());
  }

  Future<void> _ensureMatchCountdownDeadline(
    Map<String, dynamic> data, {
    int? fallbackSeconds,
  }) async {
    final room = roomRef;
    if (!isHost ||
        room == null ||
        (data['phase'] as String? ?? 'drafting') != 'match_countdown' ||
        data['match_deadline_ms'] != null ||
        _matchDeadlineRepairInProgress) {
      return;
    }

    final seconds = max(
      0,
      min(
        _matchCountdownFallbackSeconds,
        (data['match_countdown_seconds'] as num?)?.toInt() ??
            _matchCountdownSecondsRemaining ??
            fallbackSeconds ??
            _matchCountdownFallbackSeconds,
      ),
    );
    _matchDeadlineRepairInProgress = true;
    try {
      final countdown = RoomGameService.buildMatchCountdownUpdate(
        seconds: seconds,
      );
      await room
          .collection('game_state')
          .doc('current')
          .set(countdown, SetOptions(merge: true));
      await room
          .collection('game_state')
          .doc('live_match')
          .set(countdown, SetOptions(merge: true));
    } finally {
      _matchDeadlineRepairInProgress = false;
    }
  }

  Future<void> _markReplayStartFailure(ReplayStartResult result) async {
    final room = roomRef;
    if (!isHost || room == null || result == ReplayStartResult.started) return;
    try {
      await room.collection('game_state').doc('current').set({
        'replay_start_last_error': result.code,
        'replay_start_last_error_at_ms': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _onReplayStartSucceeded(int currentTurn) {
    _matchReplayRetryTimer?.cancel();
    _matchReplayRetryTimer = null;
    _matchCountdownExpiredAtMs = null;
    _lastSimulatedMatchTurn = currentTurn;
    if (view != GameView.simulation) {
      switchView(GameView.simulation);
    }
  }

  void _setMatchCountdownSecondsRemaining(int? value) {
    if (_matchCountdownSecondsRemaining == value) return;
    _matchCountdownSecondsRemaining = value;
    notifyListeners();
  }

  void _cancelMatchCountdown() {
    _matchCountdownTicker?.cancel();
    _matchCountdownTicker = null;
    _matchCountdownWatchdogTicker?.cancel();
    _matchCountdownWatchdogTicker = null;
    _matchReplayRetryTimer?.cancel();
    _matchReplayRetryTimer = null;
    _matchCountdownLocalTurn = null;
    _matchCountdownLocalStartMs = null;
    _matchCountdownLocalDurationSeconds = null;
    _matchCountdownExpiredAtMs = null;
    if (_matchCountdownSecondsRemaining == null) return;
    _matchCountdownSecondsRemaining = null;
    notifyListeners();
  }

  Future<void> _handleExpiredMatchCountdown() async {
    if (!isHost || _matchSimulationInProgress) {
      return;
    }
    final room = roomRef;
    final state = currentGameState;
    if (room == null || state == null) return;
    if ((state['phase'] as String? ?? 'drafting') != 'match_countdown') {
      return;
    }

    final currentTurn = (state['current_turn'] as num?)?.toInt() ?? 1;
    if (_lastSimulatedMatchTurn == currentTurn) {
      return;
    }

    _matchSimulationInProgress = true;
    try {
      await _ensurePreparedMatchReplay(currentTurn);
      var result = await RoomGameService.startPreparedMatchReplay(
        roomRef: room,
        currentTurn: currentTurn,
      );
      if (result == ReplayStartResult.missingPreparedData) {
        await _ensurePreparedMatchReplay(currentTurn, force: true);
        result = await RoomGameService.startPreparedMatchReplay(
          roomRef: room,
          currentTurn: currentTurn,
        );
      } else if (result == ReplayStartResult.missingDeadline) {
        await _ensureMatchCountdownDeadline(state, fallbackSeconds: 0);
        result = await RoomGameService.startPreparedMatchReplay(
          roomRef: room,
          currentTurn: currentTurn,
        );
      }

      if (result.startedOk) {
        _onReplayStartSucceeded(currentTurn);
      } else {
        unawaited(_markReplayStartFailure(result));
        _scheduleMatchReplayRetry();
      }
    } catch (_) {
      _scheduleMatchReplayRetry();
    } finally {
      _matchSimulationInProgress = false;
    }
  }

  Future<void> _forceStartMatchCountdownReplay() async {
    if (!isHost ||
        _matchReplayForceInProgress ||
        _matchSimulationInProgress ||
        _matchReplayPreparationInProgress) {
      return;
    }
    final room = roomRef;
    final state = currentGameState;
    if (room == null || state == null) return;
    if ((state['phase'] as String? ?? 'drafting') != 'match_countdown') return;
    final currentTurn =
        (state['current_turn'] as num?)?.toInt() ?? activeTurnNumber;
    if (_lastSimulatedMatchTurn == currentTurn) return;

    _matchReplayForceInProgress = true;
    try {
      await _ensurePreparedMatchReplay(currentTurn, force: true);
      await _ensureMatchCountdownDeadline(state, fallbackSeconds: 0);

      var result = await RoomGameService.startPreparedMatchReplay(
        roomRef: room,
        currentTurn: currentTurn,
      );
      if (result == ReplayStartResult.missingPreparedData) {
        await _ensurePreparedMatchReplay(currentTurn, force: true);
        result = await RoomGameService.startPreparedMatchReplay(
          roomRef: room,
          currentTurn: currentTurn,
        );
      }
      if (!result.startedOk) {
        result = await RoomGameService.forceStartPreparedMatchReplay(
          roomRef: room,
          currentTurn: currentTurn,
        );
      }

      if (result.startedOk) {
        _onReplayStartSucceeded(currentTurn);
      } else {
        unawaited(_markReplayStartFailure(result));
        _scheduleMatchReplayRetry();
      }
    } catch (_) {
      _scheduleMatchReplayRetry();
    } finally {
      _matchReplayForceInProgress = false;
    }
  }

  void _scheduleMatchReplayRetry() {
    if (!isHost) return;
    if (_matchReplayRetryTimer?.isActive == true) return;
    _matchReplayRetryTimer = Timer(const Duration(milliseconds: 350), () {
      _matchReplayRetryTimer = null;
      unawaited(_handleExpiredMatchCountdown());
    });
  }

  Future<void> _ensurePreparedMatchReplay(
    int currentTurn, {
    bool force = false,
  }) async {
    final room = roomRef;
    if (!isHost ||
        room == null ||
        _matchReplayPreparationInProgress ||
        (!force && _lastPreparedMatchTurn == currentTurn)) {
      return;
    }

    _matchReplayPreparationInProgress = true;
    try {
      await RoomGameService.prepareScheduledMatchReplay(
        roomRef: room,
        currentTurn: currentTurn,
      );
      _lastPreparedMatchTurn = currentTurn;
    } finally {
      _matchReplayPreparationInProgress = false;
    }
  }

  void _syncRoomRuntimeToView() {
    if (_viewNeedsRoomRuntime(view) && roomRef != null && playerId != null) {
      _startRoomRuntime();
      return;
    }
    _stopRoomRuntime();
  }

  bool _viewNeedsRoomRuntime(GameView candidate) {
    return switch (candidate) {
      GameView.draft ||
      GameView.augment ||
      GameView.formation ||
      GameView.tactics ||
      GameView.trade ||
      GameView.simulation => true,
      _ => false,
    };
  }

  void _startRoomRuntime() {
    final room = roomRef;
    final me = playerId;
    if (room == null || me == null) return;

    final runtimeKey = '${room.path}|$me';
    if (_roomRuntimeKey == runtimeKey) return;

    _stopRoomRuntime(clearState: false);
    _roomRuntimeKey = runtimeKey;

    _gameStateSubscription = room
        .collection('game_state')
        .doc('current')
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data();
          if (data == null) return;
          if (_shouldIgnoreIncomingGameState(data)) {
            return;
          }
          currentGameState = Map<String, dynamic>.from(data);
          _syncTurnCountdown();
          notifyListeners();
          unawaited(_handleGameStateUpdate(currentGameState!));
        });

    _playerStateSubscription = room
        .collection('players')
        .doc(me)
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data();
          if (data == null) return;
          currentPlayerState = Map<String, dynamic>.from(data);
          notifyListeners();
          unawaited(_handlePlayerStateUpdate(currentPlayerState!));
        });
  }

  void _stopRoomRuntime({bool clearState = true}) {
    _gameStateSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _gameStateSubscription = null;
    _playerStateSubscription = null;
    _roomRuntimeKey = null;
    _turnTicker?.cancel();
    _turnTicker = null;
    _botTurnTimer?.cancel();
    _botTurnTimer = null;
    _matchCountdownTicker?.cancel();
    _matchCountdownTicker = null;
    _matchCountdownWatchdogTicker?.cancel();
    _matchCountdownWatchdogTicker = null;
    _matchReplayRetryTimer?.cancel();
    _matchReplayRetryTimer = null;
    _turnAdvanceInProgress = false;
    _augmentLookupInProgress = false;
    _shopGenerationInProgress = false;
    _deadlineRepairInProgress = false;
    _matchDeadlineRepairInProgress = false;
    _botTurnScheduled = false;
    _botTurnExecutionInProgress = false;
    _matchSimulationInProgress = false;
    _matchReplayPreparationInProgress = false;
    _matchReplayForceInProgress = false;
    _scheduledBotTurn = null;
    _matchCountdownLocalTurn = null;
    _matchCountdownLocalStartMs = null;
    _matchCountdownLocalDurationSeconds = null;
    _matchCountdownExpiredAtMs = null;
    if (!clearState) return;
    currentGameState = null;
    currentPlayerState = null;
    _turnSecondsRemaining = null;
    _matchCountdownSecondsRemaining = null;
    _lastProcessedTurnEffectsTurn = null;
    _optimisticDraftTurn = null;
    _lastSimulatedMatchTurn = null;
    _lastPreparedMatchTurn = null;
    pendingAugments = const [];
    pendingAugmentTurn = 0;
  }

  bool _shouldIgnoreIncomingGameState(Map<String, dynamic> data) {
    final optimisticTurn = _optimisticDraftTurn;
    if (optimisticTurn == null) return false;
    final incomingTurn = (data['current_turn'] as num?)?.toInt() ?? 1;
    final incomingPhase = data['phase'] as String? ?? 'drafting';
    if (incomingPhase == 'drafting' && incomingTurn >= optimisticTurn) {
      _optimisticDraftTurn = null;
      return false;
    }
    return incomingTurn < optimisticTurn &&
        (incomingPhase == 'results' || incomingPhase == 'live_match');
  }

  Future<void> _handleGameStateUpdate(Map<String, dynamic> data) async {
    final room = roomRef;
    if (room == null) return;

    final phase = data['phase'] as String? ?? 'drafting';
    if (phase != 'drafting') {
      _optimisticDraftTurn = null;
    }
    if (phase == 'match_countdown') {
      _cancelTurnCountdown();
      _syncMatchCountdown(data);
      if (isHost) {
        unawaited(_ensureMatchCountdownDeadline(data));
      }
      unawaited(
        _ensurePreparedMatchReplay(
          (data['current_turn'] as num?)?.toInt() ?? activeTurnNumber,
        ),
      );
      if (view != GameView.draft) {
        switchView(GameView.draft);
      }
      return;
    }
    _cancelMatchCountdown();
    if (phase == 'live_match' || phase == 'results') {
      _cancelTurnCountdown();
      if (view != GameView.simulation) {
        switchView(GameView.simulation);
      }
      return;
    }
    if (phase != 'drafting') {
      _cancelTurnCountdown();
      return;
    }
    if (view == GameView.simulation) {
      switchView(GameView.draft);
    }

    final currentTurn = (data['current_turn'] as num?)?.toInt() ?? 1;
    if (pendingAugmentTurn != 0 && pendingAugmentTurn != currentTurn) {
      clearPendingAugments(notify: false);
    }

    if (isHost && _lastProcessedTurnEffectsTurn != currentTurn) {
      _lastProcessedTurnEffectsTurn = currentTurn;
      await RoomGameService.processTurnStartEffects(
        roomRef: room,
        currentTurn: currentTurn,
      );
    }

    await _ensureTurnDeadline(data);
    _syncTurnCountdown();
    await _maybeScheduleBotTurn(data);
    await _maybePromptAugmentSelection();
  }

  Future<void> _handlePlayerStateUpdate(Map<String, dynamic> data) async {
    if ((currentGameState?['phase'] as String? ?? 'drafting') != 'drafting') {
      return;
    }
    await _ensureShopReady(data);
    await _maybePromptAugmentSelection();
  }

  Future<void> _ensureShopReady(Map<String, dynamic> data) async {
    final room = roomRef;
    final me = playerId;
    if (room == null ||
        me == null ||
        _shopGenerationInProgress ||
        !isCurrentTurnMine) {
      return;
    }
    final shopIds = List<String>.from(
      (data['current_shop_pool'] as List?) ?? const [],
    );
    final generatedTurn = (data['shop_generated_turn'] as num?)?.toInt() ?? 0;
    final currentTurn = activeTurnNumber;
    if (generatedTurn == currentTurn || shopIds.isNotEmpty) return;

    _shopGenerationInProgress = true;
    try {
      await RoomGameService.generateNewShopForPlayer(
        roomRef: room,
        playerId: me,
        gameState: {'current_turn': currentTurn},
        gameConfig: gameConfig,
      );
    } finally {
      _shopGenerationInProgress = false;
    }
  }

  Future<void> _maybePromptAugmentSelection() async {
    final room = roomRef;
    final state = currentGameState;
    final playerState = currentPlayerState;
    if (room == null || state == null || playerState == null) return;
    if ((state['phase'] as String? ?? 'drafting') != 'drafting') return;

    final currentTurn = (state['current_turn'] as num?)?.toInt() ?? 1;
    final augmentTurns = List<int>.from(
      (gameConfig['augment_turns'] as List?) ?? const [1, 3, 6],
    );
    final completed = List<int>.from(
      (playerState['augment_turns_completed'] as List?) ?? const [],
    );

    if (pendingAugmentTurn != 0 && pendingAugmentTurn != currentTurn) {
      clearPendingAugments(notify: false);
    }
    if (!isCurrentTurnMine ||
        !augmentTurns.contains(currentTurn) ||
        completed.contains(currentTurn)) {
      if (pendingAugmentTurn == currentTurn &&
          completed.contains(currentTurn)) {
        clearPendingAugments(notify: false);
      }
      return;
    }

    if (pendingAugmentTurn == currentTurn && pendingAugments.isNotEmpty) {
      if (view != GameView.augment) {
        switchView(GameView.augment);
      }
      return;
    }
    if (_augmentLookupInProgress) return;

    _augmentLookupInProgress = true;
    try {
      final available = await RoomGameService.getAvailableAugmentsForPlayer(
        room,
        List<dynamic>.from((state['augment_pool'] as List?) ?? const []),
      );
      final latestState = currentGameState;
      final latestPlayerState = currentPlayerState;
      final latestTurn =
          (latestState?['current_turn'] as num?)?.toInt() ?? currentTurn;
      final latestCompleted = List<int>.from(
        (latestPlayerState?['augment_turns_completed'] as List?) ?? const [],
      );
      if (latestTurn != currentTurn ||
          latestCompleted.contains(currentTurn) ||
          !isCurrentTurnMine ||
          available.isEmpty) {
        return;
      }
      openAugmentSelection(_sampleAugments(available), currentTurn);
    } finally {
      _augmentLookupInProgress = false;
    }
  }

  List<String> _sampleAugments(List<String> available, {int count = 2}) {
    final unique = available.toSet().toList(growable: true);
    if (unique.length <= count) {
      return unique;
    }
    unique.shuffle(_random);
    return unique.take(count).toList(growable: false);
  }

  Future<void> _ensureTurnDeadline(Map<String, dynamic> data) async {
    final room = roomRef;
    if (room == null ||
        data['turn_deadline_ms'] != null ||
        _deadlineRepairInProgress) {
      return;
    }

    _deadlineRepairInProgress = true;
    try {
      await room
          .collection('game_state')
          .doc('current')
          .update(RoomGameService.buildTurnTimingUpdate(gameConfig));
    } finally {
      _deadlineRepairInProgress = false;
    }
  }

  void _syncTurnCountdown() {
    final phase = currentGameState?['phase'] as String?;
    if (phase != 'drafting') {
      _cancelTurnCountdown();
      return;
    }

    final deadlineMs = (currentGameState?['turn_deadline_ms'] as num?)?.toInt();
    if (deadlineMs == null) {
      _setTurnSecondsRemaining(
        (currentGameState?['turn_timer'] as num?)?.toInt(),
      );
      return;
    }

    _setTurnSecondsRemaining(_remainingSeconds(deadlineMs));
    _turnTicker?.cancel();
    _turnTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      _handleTurnTick();
    });
    if ((_turnSecondsRemaining ?? 1) <= 0) {
      unawaited(_handleExpiredDraftTurn());
    }
  }

  void _handleTurnTick() {
    final phase = currentGameState?['phase'] as String?;
    final deadlineMs = (currentGameState?['turn_deadline_ms'] as num?)?.toInt();
    if (phase != 'drafting' || deadlineMs == null) {
      _cancelTurnCountdown();
      return;
    }

    final remaining = _remainingSeconds(deadlineMs);
    _setTurnSecondsRemaining(remaining);
    if (remaining <= 0) {
      unawaited(_handleExpiredDraftTurn());
    }
  }

  int _remainingSeconds(int deadlineMs) {
    final diff = deadlineMs - DateTime.now().millisecondsSinceEpoch;
    return max(0, (diff / 1000).ceil());
  }

  void _setTurnSecondsRemaining(int? value) {
    if (_turnSecondsRemaining == value) return;
    _turnSecondsRemaining = value;
    notifyListeners();
  }

  void _cancelTurnCountdown() {
    _turnTicker?.cancel();
    _turnTicker = null;
    _setTurnSecondsRemaining(null);
  }

  Future<void> _handleExpiredDraftTurn() async {
    final state = currentGameState;
    final room = roomRef;
    if (state == null ||
        room == null ||
        _turnAdvanceInProgress ||
        _botTurnExecutionInProgress) {
      return;
    }
    if ((state['phase'] as String? ?? 'drafting') != 'drafting') return;

    final actingPlayerId = state['current_player_id'] as String? ?? 'oyuncu_1';
    final currentTurn = (state['current_turn'] as num?)?.toInt() ?? 1;
    if (actingPlayerId == playerId) {
      await advanceCurrentTurn();
      return;
    }
    if (!isHost || actingPlayerId != 'oyuncu_2') return;

    final roomData = (await room.get()).data() ?? <String, dynamic>{};
    if (roomData['is_bot'] == true) {
      final difficulty = roomData['bot_difficulty'] as String? ?? 'Kolay';
      _botTurnTimer?.cancel();
      _botTurnTimer = null;
      _botTurnScheduled = false;
      _scheduledBotTurn = null;
      await _executeBotTurnSafely(difficulty, currentTurn);
      return;
    }

    await _advanceTurnForPlayer(actingPlayerId: 'oyuncu_2');
  }

  Future<void> _maybeScheduleBotTurn(Map<String, dynamic> data) async {
    final room = roomRef;
    if (room == null || !isHost) return;

    final phase = data['phase'] as String? ?? 'drafting';
    if (phase != 'drafting' || data['current_player_id'] != 'oyuncu_2') {
      _botTurnTimer?.cancel();
      _botTurnTimer = null;
      _botTurnScheduled = false;
      _scheduledBotTurn = null;
      return;
    }

    final roomData = (await room.get()).data() ?? <String, dynamic>{};
    if (roomData['is_bot'] != true || _botTurnExecutionInProgress) return;

    final currentTurn = (data['current_turn'] as num?)?.toInt() ?? 1;
    final difficulty = roomData['bot_difficulty'] as String? ?? 'Kolay';
    final profile = _botProfile(difficulty);
    if (_botTurnScheduled && _scheduledBotTurn == currentTurn) return;

    final deadlineMs = (data['turn_deadline_ms'] as num?)?.toInt();
    final remainingSeconds = deadlineMs != null
        ? _remainingSeconds(deadlineMs)
        : (data['turn_timer'] as num?)?.toInt();
    final rollDelay =
        profile.reactionMinMs +
        _random.nextInt(profile.reactionMaxMs - profile.reactionMinMs + 1);
    final baseDelayMs = max(450, rollDelay - (currentTurn <= 3 ? 180 : 0));
    final delayMs = remainingSeconds == null
        ? baseDelayMs
        : max(250, min(baseDelayMs, (remainingSeconds * 1000) - 150));

    _botTurnScheduled = true;
    _scheduledBotTurn = currentTurn;
    _botTurnTimer?.cancel();
    _botTurnTimer = Timer(Duration(milliseconds: delayMs), () async {
      try {
        final latestState = currentGameState;
        final latestTurn =
            (latestState?['current_turn'] as num?)?.toInt() ?? currentTurn;
        if (latestState == null ||
            latestState['phase'] != 'drafting' ||
            latestState['current_player_id'] != 'oyuncu_2' ||
            latestTurn != currentTurn) {
          return;
        }
        await _executeBotTurnSafely(difficulty, currentTurn);
      } finally {
        _botTurnScheduled = false;
        _scheduledBotTurn = null;
      }
    });
  }

  Future<void> _executeBotTurnSafely(String difficulty, int currentTurn) async {
    if (_botTurnExecutionInProgress) return;
    _botTurnExecutionInProgress = true;
    try {
      await _executeBotTurn(difficulty, currentTurn);
    } catch (_) {
      await _advanceTurnForPlayer(actingPlayerId: 'oyuncu_2');
    } finally {
      _botTurnExecutionInProgress = false;
    }
  }

  int _botDifficultyTier(String difficulty) {
    return switch (difficulty) {
      'Zor' => 2,
      'Orta' => 1,
      _ => 0,
    };
  }

  _BotProfile _botProfile(String difficulty) {
    final tier = _botDifficultyTier(difficulty);
    return switch (tier) {
      2 => const _BotProfile(
        tier: 2,
        reactionMinMs: 850,
        reactionMaxMs: 1250,
        reserveGold: 80,
        maxBuysBase: 2,
        maxBuysBonus: 1,
        highGoldBuyThreshold: 420,
        shopScoreThreshold: 102,
        randomness: 0.08,
        riskAggression: 0.72,
      ),
      1 => const _BotProfile(
        tier: 1,
        reactionMinMs: 1300,
        reactionMaxMs: 1800,
        reserveGold: 120,
        maxBuysBase: 1,
        maxBuysBonus: 1,
        highGoldBuyThreshold: 320,
        shopScoreThreshold: 118,
        randomness: 0.18,
        riskAggression: 0.48,
      ),
      _ => const _BotProfile(
        tier: 0,
        reactionMinMs: 2200,
        reactionMaxMs: 2900,
        reserveGold: 170,
        maxBuysBase: 1,
        maxBuysBonus: 0,
        highGoldBuyThreshold: 99999,
        shopScoreThreshold: 142,
        randomness: 0.45,
        riskAggression: 0.22,
      ),
    };
  }

  double _botPlayerRating(Map<String, dynamic> playerData) {
    final stored = (playerData['rating'] as num?)?.toDouble();
    if (stored != null && stored > 0) return stored;
    final stats = Map<String, dynamic>.from(
      (playerData['stats'] as Map?) ?? const <String, dynamic>{},
    );
    return calculateRating(
      stats,
      playerData['mevki'] as String? ?? 'Orta Saha',
    ).toDouble();
  }

  double _botStat(Map<String, dynamic> playerData, String key) {
    final stats =
        (playerData['stats'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return (stats[key] as num?)?.toDouble() ?? 0;
  }

  double _botAverageRating(List<Map<String, dynamic>> roster) {
    final available = roster
        .where((item) {
          final data =
              (item['data'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          return (data['status'] as String? ?? 'uygun') == 'uygun';
        })
        .toList(growable: false);
    if (available.isEmpty) return 0;
    final total = available.fold<double>(0, (acc, item) {
      final data =
          (item['data'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return acc + _botPlayerRating(data);
    });
    return total / available.length;
  }

  ({int turnsUntil, bool botIsHome}) _nextBotMatchInfo(int currentTurn) {
    final matchTurns = List<int>.from(
      (gameConfig['match_turns'] as List?) ?? const [7, 14, 21],
    )..sort();
    for (var index = 0; index < matchTurns.length; index++) {
      if (matchTurns[index] >= currentTurn) {
        final matchNumber = index + 1;
        return (
          turnsUntil: matchTurns[index] - currentTurn,
          botIsHome: matchNumber.isEven,
        );
      }
    }
    return (turnsUntil: 99, botIsHome: false);
  }

  String _pickRankedBotChoice(
    List<MapEntry<String, double>> ranked,
    _BotProfile profile,
  ) {
    if (ranked.length <= 1) {
      return ranked.first.key;
    }
    final shortlistCount = switch (profile.tier) {
      2 => profile.randomness < 0.1 ? 2 : 3,
      1 => 3,
      _ => 4,
    };
    final weighted = ranked
        .take(min(ranked.length, shortlistCount))
        .toList(growable: false);
    final floorScore = weighted.last.value;
    final weights = <double>[];
    for (var index = 0; index < weighted.length; index++) {
      final preference =
          1.0 + (1.0 - profile.randomness) * (weighted.length - index);
      weights.add(
        max(0.25, (weighted[index].value - floorScore + 1.0) * preference),
      );
    }

    final totalWeight = weights.fold<double>(0, (acc, value) => acc + value);
    var roll = _random.nextDouble() * totalWeight;
    for (var index = 0; index < weighted.length; index++) {
      roll -= weights[index];
      if (roll <= 0) return weighted[index].key;
    }
    return weighted.first.key;
  }

  Map<String, int> _desiredStarterCounts(String formation) {
    final counts = <String, int>{
      'Kaleci': 0,
      'Defans': 0,
      'Orta Saha': 0,
      'Forvet': 0,
    };
    for (final slot in activeSlotsByFormation[formation] ?? const <String>[]) {
      if (slot.startsWith('BENCH')) continue;
      final positions = slotMevkiMap[slot] ?? getPositionFromSlot(slot);
      if (positions.isEmpty) continue;
      final position = positions.first;
      counts[position] = (counts[position] ?? 0) + 1;
    }
    return counts;
  }

  int _countByPosition(
    List<Map<String, dynamic>> roster, {
    required String position,
    required bool availableOnly,
  }) {
    return roster.where((item) {
      final data =
          (item['data'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final isAvailable = (data['status'] as String? ?? 'uygun') == 'uygun';
      if (availableOnly && !isAvailable) return false;
      if (!availableOnly && isAvailable) return false;
      return (data['mevki'] as String? ?? '') == position;
    }).length;
  }

  double _averageRosterStat(List<Map<String, dynamic>> roster, String key) {
    final available = roster
        .where((item) {
          final data =
              (item['data'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          return (data['status'] as String? ?? 'uygun') == 'uygun';
        })
        .toList(growable: false);
    if (available.isEmpty) return 0;
    final total = available.fold<double>(0, (acc, item) {
      final data =
          (item['data'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return acc + _botStat(data, key);
    });
    return total / available.length;
  }

  double _averagePositionRating(
    List<Map<String, dynamic>> roster,
    String position,
  ) {
    final available = roster
        .where((item) {
          final data =
              (item['data'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          return (data['status'] as String? ?? 'uygun') == 'uygun' &&
              (data['mevki'] as String? ?? '') == position;
        })
        .toList(growable: false);
    if (available.isEmpty) return 0;
    final total = available.fold<double>(0, (acc, item) {
      final data =
          (item['data'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return acc + _botPlayerRating(data);
    });
    return total / available.length;
  }

  String _chooseBotFormation(
    List<Map<String, dynamic>> roster,
    String difficulty,
  ) {
    final difficultyTier = _botDifficultyTier(difficulty);

    double slotFitScore(String slot, Map<String, dynamic> playerData) {
      final rating = _botPlayerRating(playerData);
      final attack = _botStat(playerData, 'hucum');
      final defense = _botStat(playerData, 'savunma');
      final passing = _botStat(playerData, 'pas');
      final shooting = _botStat(playerData, 'sut');
      final pace = _botStat(playerData, 'hiz');
      final stamina = _botStat(playerData, 'dayaniklilik');
      final mevki = playerData['mevki'] as String? ?? '';
      final naturalFit = (slotMevkiMap[slot] ?? const <String>[]).contains(
        mevki,
      );
      var score = rating * (naturalFit ? 1.35 : 0.72);
      if (slot.startsWith('GK')) {
        score += defense * 1.2 + passing * 0.15;
      } else if (slot.startsWith('DEF')) {
        score += defense * 1.3 + pace * 0.25 + stamina * 0.20;
      } else if (slot.startsWith('MID')) {
        score += passing * 1.0 + stamina * 0.30 + attack * 0.20;
      } else if (slot.startsWith('FWD')) {
        score += shooting * 1.0 + attack * 0.65 + pace * 0.30;
      }
      return score;
    }

    double formationScore(String candidate) {
      final activeSlots =
          (activeSlotsByFormation[candidate] ?? const <String>[])
              .where((slot) => !slot.startsWith('BENCH'))
              .toList(growable: false);
      final available = roster
          .where((item) {
            final data =
                (item['data'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            return (data['status'] as String? ?? 'uygun') == 'uygun';
          })
          .toList(growable: false);
      final used = <String>{};
      var total = 0.0;
      for (final slot in activeSlots) {
        double bestScore = -1000;
        String? bestId;
        for (final item in available) {
          final id = item['id'] as String;
          if (used.contains(id)) continue;
          final data =
              (item['data'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final score = slotFitScore(slot, data);
          if (score > bestScore) {
            bestScore = score;
            bestId = id;
          }
        }
        if (bestId == null) {
          total -= 60;
        } else {
          used.add(bestId);
          total += bestScore;
        }
      }
      return total;
    }

    final counts = <String, int>{
      'Kaleci': 0,
      'Defans': 0,
      'Orta Saha': 0,
      'Forvet': 0,
    };
    for (final item in roster) {
      final data =
          (item['data'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      if ((data['status'] as String? ?? 'uygun') != 'uygun') continue;
      final mevki = data['mevki'] as String?;
      if (mevki != null) counts[mevki] = (counts[mevki] ?? 0) + 1;
    }

    if (difficultyTier >= 2) {
      final ranked =
          ['3-2-1', '2-3-1', '2-2-2']
              .map(
                (candidate) => MapEntry(candidate, formationScore(candidate)),
              )
              .toList(growable: false)
            ..sort((a, b) => b.value.compareTo(a.value));
      return ranked.first.key;
    }
    if (difficultyTier == 0) {
      return ['3-2-1', '2-3-1', '2-2-2'][_random.nextInt(3)];
    }
    if (counts['Orta Saha']! >= 3 && counts['Forvet']! <= 1) return '2-3-1';
    if (counts['Forvet']! >= 2 && counts['Defans']! >= 2) return '2-2-2';
    if (counts['Defans']! >= 3) return '3-2-1';
    return counts['Orta Saha']! >= counts['Defans']! ? '2-3-1' : '3-2-1';
  }

  Map<String, Map<String, dynamic>> _buildBotFormationSlots(
    String formation,
    List<Map<String, dynamic>> roster,
    String difficulty,
  ) {
    final difficultyTier = _botDifficultyTier(difficulty);
    final slots = <String, Map<String, dynamic>>{
      for (final slot in activeSlotsByFormation[formation] ?? const <String>[])
        slot: {'player_id': null, 'instructions': <String>[]},
    };
    final available = roster
        .where((item) {
          final data =
              (item['data'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          return (data['status'] as String? ?? 'uygun') == 'uygun';
        })
        .toList(growable: false);
    final usedIds = <String>{};

    double slotScore(String slot, Map<String, dynamic> playerData) {
      final rating = _botPlayerRating(playerData);
      final attack = _botStat(playerData, 'hucum');
      final defense = _botStat(playerData, 'savunma');
      final passing = _botStat(playerData, 'pas');
      final shooting = _botStat(playerData, 'sut');
      final pace = _botStat(playerData, 'hiz');
      final stamina = _botStat(playerData, 'dayaniklilik');
      final mevki = playerData['mevki'] as String? ?? '';
      final naturalFit =
          slot.startsWith('BENCH') ||
          (slotMevkiMap[slot] ?? const <String>[]).contains(mevki);
      var score = rating * 3.2;
      if (slot.startsWith('GK')) {
        score += defense * 1.4 + passing * 0.35;
      } else if (slot.startsWith('DEF')) {
        score += defense * 1.3 + stamina * 0.45 + pace * 0.35;
      } else if (slot.startsWith('MID')) {
        score += passing * 1.0 + attack * 0.45 + defense * 0.35;
      } else if (slot.startsWith('FWD')) {
        score += shooting * 1.1 + attack * 0.9 + pace * 0.55;
      }
      return score * (naturalFit ? 1.0 : (difficultyTier >= 2 ? 0.55 : 0.68));
    }

    for (final slot
        in (activeSlotsByFormation[formation] ?? const <String>[]).where(
          (slot) => !slot.startsWith('BENCH'),
        )) {
      String? bestId;
      var bestScore = -10000.0;
      for (final item in available) {
        final id = item['id'] as String;
        if (usedIds.contains(id)) continue;
        final data =
            (item['data'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final score = slotScore(slot, data);
        if (score > bestScore) {
          bestScore = score;
          bestId = id;
        }
      }
      if (bestId != null) {
        usedIds.add(bestId);
        slots[slot] = {'player_id': bestId, 'instructions': <String>[]};
      }
    }

    final bench =
        available
            .where((item) => !usedIds.contains(item['id']))
            .toList(growable: false)
          ..sort((a, b) {
            final aData =
                (a['data'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            final bData =
                (b['data'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            return _botPlayerRating(bData).compareTo(_botPlayerRating(aData));
          });
    final benchSlots = (activeSlotsByFormation[formation] ?? const <String>[])
        .where((slot) => slot.startsWith('BENCH'))
        .toList(growable: false);
    for (
      var index = 0;
      index < bench.length && index < benchSlots.length;
      index++
    ) {
      slots[benchSlots[index]] = {
        'player_id': bench[index]['id'],
        'instructions': <String>[],
      };
    }
    return slots;
  }

  String? _pickBestBotStarterId(
    Map<String, Map<String, dynamic>> slots,
    List<Map<String, dynamic>> roster,
    double Function(Map<String, dynamic> playerData) scorer,
  ) {
    final lookup = <String, Map<String, dynamic>>{
      for (final item in roster)
        item['id'] as String:
            (item['data'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
    };
    String? bestId;
    var bestScore = -10000.0;
    for (final entry in slots.entries) {
      if (entry.key.startsWith('BENCH')) continue;
      final playerId = entry.value['player_id'] as String?;
      final playerData = playerId == null ? null : lookup[playerId];
      if (playerData == null) continue;
      final score = scorer(playerData);
      if (score > bestScore) {
        bestScore = score;
        bestId = playerId;
      }
    }
    return bestId;
  }

  List<String> _botInstructionsForSlot(
    String slot,
    Map<String, dynamic> playerData, {
    required String mentality,
    required String buildUpPlay,
    required String focusPlay,
    required String pressingTrigger,
    required int difficultyTier,
  }) {
    if (slot.startsWith('BENCH')) return const [];
    if (difficultyTier == 0 && _random.nextDouble() < 0.55) return const [];

    final passing = _botStat(playerData, 'pas');
    final defense = _botStat(playerData, 'savunma');
    final attack = _botStat(playerData, 'hucum');
    final shooting = _botStat(playerData, 'sut');
    final pace = _botStat(playerData, 'hiz');
    final stamina = _botStat(playerData, 'dayaniklilik');

    if (slot.startsWith('GK')) {
      if (buildUpPlay == 'Hızlı') return const ['Uzun Oyna'];
      if (passing >= 70) return const ['Topu Kısa Kullan'];
      return const [];
    }
    if (slot.startsWith('DEF')) {
      if ((mentality == 'Hücum' || mentality == 'Topyekûn Hücum') &&
          pace >= 74 &&
          stamina >= 72) {
        return const ['Bindirme Yap'];
      }
      if (difficultyTier >= 2 && defense >= 84) return const ['Sert Müdahale'];
      if (defense >= 76) return const ['Alanı Kapat'];
      return const [];
    }
    if (slot.startsWith('MID')) {
      if (passing >= 80 && buildUpPlay != 'Hızlı') {
        return const ['Oyunu Yavaşlat'];
      }
      if (attack + shooting >= 150 && stamina >= 72) {
        return const ['Ceza Sahasına Koşu'];
      }
      if (difficultyTier >= 1 && passing >= 74) return const ['Riskli Pas'];
      return const [];
    }
    if (slot.startsWith('FWD')) {
      if (pressingTrigger != 'Dengeli' &&
          stamina >= 70 &&
          difficultyTier >= 1) {
        return const ['Önde Baskı'];
      }
      if (focusPlay == 'Kanatlardan' || pace >= 78) {
        return const ['Kanala Koş'];
      }
      if (passing >= 72) return const ['Hedef Santrfor'];
    }
    return const [];
  }

  // ignore: unused_element
  Map<String, dynamic> _buildBotTactics(
    String difficulty,
    List<Map<String, dynamic>> roster,
    String formation,
    Map<String, Map<String, dynamic>> slots,
    int currentTurn, {
    required List<Map<String, dynamic>> opponentRoster,
  }) {
    final profile = _botProfile(difficulty);
    final difficultyTier = profile.tier;
    final lookup = <String, Map<String, dynamic>>{
      for (final item in roster)
        item['id'] as String:
            (item['data'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
    };
    final starters = <Map<String, dynamic>>[];
    for (final entry in slots.entries) {
      if (entry.key.startsWith('BENCH')) continue;
      final playerId = entry.value['player_id'] as String?;
      final playerData = playerId == null ? null : lookup[playerId];
      if (playerData != null) starters.add(playerData);
    }

    double average(String key) {
      if (starters.isEmpty) return 0;
      final total = starters.fold<double>(
        0,
        (acc, player) => acc + _botStat(player, key),
      );
      return total / starters.length;
    }

    double opponentAverage(String key) {
      final available = opponentRoster
          .where((item) {
            final data =
                (item['data'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            return (data['status'] as String? ?? 'uygun') == 'uygun';
          })
          .toList(growable: false);
      if (available.isEmpty) return 0;
      final total = available.fold<double>(
        0,
        (acc, item) =>
            acc +
            _botStat(
              (item['data'] as Map?)?.cast<String, dynamic>() ??
                  const <String, dynamic>{},
              key,
            ),
      );
      return total / available.length;
    }

    final avgAttack = average('hucum');
    final avgDefense = average('savunma');
    final avgPass = average('pas');
    final avgShot = average('sut');
    final avgSpeed = average('hiz');
    final avgStamina = average('dayaniklilik');
    final oppAttack = opponentAverage('hucum');
    final oppDefense = opponentAverage('savunma');
    final oppPass = opponentAverage('pas');
    final oppSpeed = opponentAverage('hiz');
    final avgMorale = starters.isEmpty
        ? 5.0
        : starters.fold<double>(
                0,
                (acc, player) =>
                    acc + ((player['morale'] as num?)?.toDouble() ?? 5.0),
              ) /
              starters.length;
    final avgForm = starters.isEmpty
        ? 5.0
        : starters.fold<double>(
                0,
                (acc, player) =>
                    acc + ((player['form'] as num?)?.toDouble() ?? 5.0),
              ) /
              starters.length;
    final nextMatch = _nextBotMatchInfo(currentTurn);
    final ownPower =
        (avgAttack + avgDefense + avgPass + avgShot + avgSpeed) / 5.0;
    final opponentPower = (oppAttack + oppDefense + oppPass + oppSpeed) / 4.0;
    // ignore: unused_local_variable
    final powerGap = ownPower - opponentPower;

    var mentality = 'Dengeli';
    if (difficultyTier >= 2) {
      if (nextMatch.turnsUntil <= 1 &&
          avgAttack >= 84 &&
          avgForm >= 5.4 &&
          avgMorale >= 5.2) {
        mentality = 'Topyekûn Hücum';
      } else if (avgAttack - avgDefense > 10) {
        mentality = 'Hücum';
      } else if (avgDefense - avgAttack > 12 || avgMorale < 4.8) {
        mentality = 'Defansif';
      }
    } else if (difficultyTier == 1) {
      mentality = avgAttack > avgDefense + 10 ? 'Hücum' : 'Dengeli';
    } else {
      mentality = [
        'Çok Defansif',
        'Defansif',
        'Dengeli',
        'Hücum',
      ][_random.nextInt(4)];
    }

    var buildUpPlay = 'Dengeli';
    if (difficultyTier == 0) {
      buildUpPlay = ['Yavaş', 'Dengeli', 'Hızlı'][_random.nextInt(3)];
    } else if (avgPass >= 80 && avgSpeed <= 73) {
      buildUpPlay = 'Yavaş';
    } else if (avgSpeed >= 77 || avgAttack > avgDefense + 12) {
      buildUpPlay = 'Hızlı';
    }

    final focusPlay = difficultyTier == 0
        ? ['Karma', 'Merkezden', 'Kanatlardan'][_random.nextInt(3)]
        : avgPass >= 78
        ? 'Merkezden'
        : (avgSpeed >= 76 || formation == '2-2-2' ? 'Kanatlardan' : 'Karma');
    final crossingType = difficultyTier == 0
        ? ['Yüksek Orta', 'Yer Orta'][_random.nextInt(2)]
        : focusPlay == 'Kanatlardan'
        ? (avgShot >= 76 ? 'Yüksek Orta' : 'Yer Orta')
        : (avgPass >= 80 ? 'Yer Orta' : 'Yüksek Orta');
    final defensiveLine = difficultyTier == 0
        ? (avgDefense < 70 ? 'Derin Savunma' : 'Normal')
        : avgDefense >= 79 &&
              avgSpeed >= 74 &&
              difficultyTier >= 1 &&
              avgMorale >= 5
        ? 'İleride Kur'
        : (avgDefense <= 69 ? 'Derin Savunma' : 'Normal');
    final pressingTrigger = difficultyTier == 0
        ? (avgStamina >= 76 && _random.nextDouble() < 0.25
              ? 'Top Kaybından Sonra'
              : 'Dengeli')
        : avgStamina >= 82 && difficultyTier >= 2 && avgForm >= 5
        ? 'Sürekli Baskı'
        : (avgStamina >= 74 ? 'Top Kaybından Sonra' : 'Dengeli');

    final enrichedSlots = <String, Map<String, dynamic>>{
      for (final entry in slots.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    for (final entry in enrichedSlots.entries) {
      final playerId = entry.value['player_id'] as String?;
      final playerData = playerId == null ? null : lookup[playerId];
      entry.value['instructions'] = playerData == null
          ? <String>[]
          : _botInstructionsForSlot(
              entry.key,
              playerData,
              mentality: mentality,
              buildUpPlay: buildUpPlay,
              focusPlay: focusPlay,
              pressingTrigger: pressingTrigger,
              difficultyTier: difficultyTier,
            );
    }

    return {
      'formation': formation,
      'formation_slots': enrichedSlots,
      'mentality': mentality,
      'build_up_play': buildUpPlay,
      'focus_play': focusPlay,
      'crossing_type': crossingType,
      'defensive_line': defensiveLine,
      'pressing_trigger': pressingTrigger,
      'offside_trap':
          defensiveLine == 'İleride Kur' &&
          avgSpeed >= 74 &&
          difficultyTier >= 1 &&
          avgMorale >= 5,
      'captain_id': _pickBestBotStarterId(
        enrichedSlots,
        roster,
        (playerData) =>
            _botPlayerRating(playerData) +
            ((playerData['morale'] as num?)?.toDouble() ?? 5) * 1.4 +
            ((playerData['form'] as num?)?.toDouble() ?? 5) * 1.2,
      ),
      'set_piece_takers': {
        'pen': _pickBestBotStarterId(
          enrichedSlots,
          roster,
          (playerData) =>
              _botStat(playerData, 'sut') * 1.2 + _botStat(playerData, 'hucum'),
        ),
        'fk': _pickBestBotStarterId(
          enrichedSlots,
          roster,
          (playerData) =>
              _botStat(playerData, 'pas') + _botStat(playerData, 'sut') * 0.8,
        ),
        'cor': _pickBestBotStarterId(
          enrichedSlots,
          roster,
          (playerData) =>
              _botStat(playerData, 'pas') * 1.1 +
              _botStat(playerData, 'hiz') * 0.2,
        ),
      },
    };
  }

  // ignore: unused_element
  Map<String, dynamic> _buildStrategicBotTactics(
    String difficulty,
    List<Map<String, dynamic>> roster,
    String formation,
    Map<String, Map<String, dynamic>> slots,
    int currentTurn, {
    required List<Map<String, dynamic>> opponentRoster,
  }) {
    final profile = _botProfile(difficulty);
    final difficultyTier = profile.tier;
    final lookup = <String, Map<String, dynamic>>{
      for (final item in roster)
        item['id'] as String:
            (item['data'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
    };
    final starters = <Map<String, dynamic>>[];
    for (final entry in slots.entries) {
      if (entry.key.startsWith('BENCH')) continue;
      final playerId = entry.value['player_id'] as String?;
      final playerData = playerId == null ? null : lookup[playerId];
      if (playerData != null) starters.add(playerData);
    }

    double averageStarterStat(String key) {
      if (starters.isEmpty) return 0;
      final total = starters.fold<double>(
        0,
        (acc, player) => acc + _botStat(player, key),
      );
      return total / starters.length;
    }

    double averageOpponentStat(String key) {
      final available = opponentRoster
          .where((item) {
            final data =
                (item['data'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            return (data['status'] as String? ?? 'uygun') == 'uygun';
          })
          .toList(growable: false);
      if (available.isEmpty) return 0;
      final total = available.fold<double>(
        0,
        (acc, item) =>
            acc +
            _botStat(
              (item['data'] as Map?)?.cast<String, dynamic>() ??
                  const <String, dynamic>{},
              key,
            ),
      );
      return total / available.length;
    }

    final avgAttack = averageStarterStat('hucum');
    final avgDefense = averageStarterStat('savunma');
    final avgPass = averageStarterStat('pas');
    final avgShot = averageStarterStat('sut');
    final avgSpeed = averageStarterStat('hiz');
    final avgStamina = averageStarterStat('dayaniklilik');
    final avgMorale = starters.isEmpty
        ? 5.0
        : starters.fold<double>(
                0,
                (acc, player) =>
                    acc + ((player['morale'] as num?)?.toDouble() ?? 5.0),
              ) /
              starters.length;
    final avgForm = starters.isEmpty
        ? 5.0
        : starters.fold<double>(
                0,
                (acc, player) =>
                    acc + ((player['form'] as num?)?.toDouble() ?? 5.0),
              ) /
              starters.length;
    final oppAttack = averageOpponentStat('hucum');
    final oppDefense = averageOpponentStat('savunma');
    final oppPass = averageOpponentStat('pas');
    final oppSpeed = averageOpponentStat('hiz');
    final ownPower =
        (avgAttack + avgDefense + avgPass + avgShot + avgSpeed + avgStamina) /
        6.0;
    final opponentPower = (oppAttack + oppDefense + oppPass + oppSpeed) / 4.0;
    final powerGap = ownPower - opponentPower;
    final nextMatch = _nextBotMatchInfo(currentTurn);
    final mustWinSoon = nextMatch.turnsUntil <= 1;
    final lowSpirit = avgMorale < 4.7 || avgForm < 4.7;

    var mentality = 'Dengeli';
    if (difficultyTier == 0) {
      mentality = const [
        'Ã‡ok Defansif',
        'Defansif',
        'Dengeli',
        'HÃ¼cum',
      ][_random.nextInt(4)];
      if (powerGap >= 9 && _random.nextDouble() > 0.40) {
        mentality = 'HÃ¼cum';
      } else if (powerGap <= -10 && _random.nextDouble() > 0.30) {
        mentality = 'Defansif';
      }
    } else if (difficultyTier == 1) {
      if (mustWinSoon && powerGap >= 2 && !lowSpirit) {
        mentality = 'HÃ¼cum';
      } else if (powerGap <= -8 || lowSpirit) {
        mentality = 'Defansif';
      } else if (powerGap >= 8 && avgAttack >= 78) {
        mentality = 'HÃ¼cum';
      }
      if (_random.nextDouble() < profile.randomness * 0.45) {
        mentality = const ['Defansif', 'Dengeli', 'HÃ¼cum'][_random.nextInt(3)];
      }
    } else {
      if (mustWinSoon &&
          powerGap >= 4 &&
          avgAttack >= 82 &&
          avgForm >= 5.2 &&
          avgMorale >= 5.1) {
        mentality = 'TopyekÃ»n HÃ¼cum';
      } else if (powerGap >= 9 && avgAttack >= avgDefense - 2) {
        mentality = 'HÃ¼cum';
      } else if (powerGap <= -8 || lowSpirit || oppAttack > avgDefense + 7) {
        mentality = 'Defansif';
      }
      if (_random.nextDouble() < profile.randomness * 0.25) {
        mentality = const ['Defansif', 'Dengeli', 'HÃ¼cum'][_random.nextInt(3)];
      }
    }

    var buildUpPlay = 'Dengeli';
    if (difficultyTier == 0) {
      buildUpPlay = const ['YavaÅŸ', 'Dengeli', 'HÄ±zlÄ±'][_random.nextInt(3)];
    } else if (avgPass >= 80 && avgSpeed <= 72) {
      buildUpPlay = 'YavaÅŸ';
    } else if (avgSpeed >= 78 || avgAttack > avgDefense + 10 || mustWinSoon) {
      buildUpPlay = 'HÄ±zlÄ±';
    }
    if (difficultyTier >= 2 &&
        oppPass >= 79 &&
        avgDefense >= 78 &&
        avgStamina >= 74) {
      buildUpPlay = 'YavaÅŸ';
    }

    var focusPlay = 'Karma';
    if (difficultyTier == 0) {
      focusPlay = const [
        'Karma',
        'Merkezden',
        'Kanatlardan',
      ][_random.nextInt(3)];
    } else if (avgPass >= 79 && avgShot >= 74) {
      focusPlay = 'Merkezden';
    } else if (avgSpeed >= 76 || formation == '2-2-2' || oppDefense >= 80) {
      focusPlay = 'Kanatlardan';
    }
    if (difficultyTier >= 2 && oppDefense >= 83 && avgSpeed >= 74) {
      focusPlay = 'Kanatlardan';
    }

    final crossingType = focusPlay == 'Kanatlardan'
        ? (avgShot >= 76 ? 'YÃ¼ksek Orta' : 'Yer Orta')
        : (avgPass >= 80 ? 'Yer Orta' : 'YÃ¼ksek Orta');
    final defensiveLine = difficultyTier == 0
        ? (avgDefense < 70 ? 'Derin Savunma' : 'Normal')
        : (avgDefense >= 80 &&
                  avgSpeed >= 75 &&
                  avgMorale >= 5 &&
                  powerGap >= -2) ||
              (difficultyTier >= 2 &&
                  oppAttack <= avgDefense - 3 &&
                  avgStamina >= 72)
        ? 'Ä°leride Kur'
        : (avgDefense <= 70 || oppSpeed > avgSpeed + 8
              ? 'Derin Savunma'
              : 'Normal');
    final pressingTrigger = difficultyTier == 0
        ? (avgStamina >= 76 && _random.nextDouble() < 0.24
              ? 'Top KaybÄ±ndan Sonra'
              : 'Dengeli')
        : difficultyTier == 1
        ? (avgStamina >= 75 && !lowSpirit ? 'Top KaybÄ±ndan Sonra' : 'Dengeli')
        : (avgStamina >= 82 && avgForm >= 5.0 && powerGap >= -5
              ? 'SÃ¼rekli BaskÄ±'
              : (avgStamina >= 73 ? 'Top KaybÄ±ndan Sonra' : 'Dengeli'));

    final enrichedSlots = <String, Map<String, dynamic>>{
      for (final entry in slots.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    for (final entry in enrichedSlots.entries) {
      final playerId = entry.value['player_id'] as String?;
      final playerData = playerId == null ? null : lookup[playerId];
      final instructions = playerData == null
          ? <String>[]
          : _botInstructionsForSlot(
              entry.key,
              playerData,
              mentality: mentality,
              buildUpPlay: buildUpPlay,
              focusPlay: focusPlay,
              pressingTrigger: pressingTrigger,
              difficultyTier: difficultyTier,
            );
      entry.value['instructions'] = instructions
          .take(1)
          .toList(growable: false);
    }

    return {
      'formation': formation,
      'formation_slots': enrichedSlots,
      'mentality': mentality,
      'build_up_play': buildUpPlay,
      'focus_play': focusPlay,
      'crossing_type': crossingType,
      'defensive_line': defensiveLine,
      'pressing_trigger': pressingTrigger,
      'offside_trap':
          defensiveLine == 'Ä°leride Kur' &&
          avgSpeed >= 74 &&
          difficultyTier >= 1 &&
          avgMorale >= 5,
      'captain_id': _pickBestBotStarterId(
        enrichedSlots,
        roster,
        (playerData) =>
            _botPlayerRating(playerData) +
            ((playerData['morale'] as num?)?.toDouble() ?? 5) * 1.5 +
            ((playerData['form'] as num?)?.toDouble() ?? 5) * 1.2 +
            _botStat(playerData, 'dayaniklilik') * 0.2,
      ),
      'set_piece_takers': {
        'pen': _pickBestBotStarterId(
          enrichedSlots,
          roster,
          (playerData) =>
              _botStat(playerData, 'sut') * 1.25 +
              _botStat(playerData, 'hucum') * 0.95 +
              ((playerData['form'] as num?)?.toDouble() ?? 5) * 0.8,
        ),
        'fk': _pickBestBotStarterId(
          enrichedSlots,
          roster,
          (playerData) =>
              _botStat(playerData, 'pas') * 1.05 +
              _botStat(playerData, 'sut') * 0.85 +
              _botStat(playerData, 'hucum') * 0.25,
        ),
        'cor': _pickBestBotStarterId(
          enrichedSlots,
          roster,
          (playerData) =>
              _botStat(playerData, 'pas') * 1.15 +
              _botStat(playerData, 'hiz') * 0.25,
        ),
      },
    };
  }

  Map<String, dynamic> _buildStrategicBotTacticsV2(
    String difficulty,
    List<Map<String, dynamic>> roster,
    String formation,
    Map<String, Map<String, dynamic>> slots,
    int currentTurn, {
    required List<Map<String, dynamic>> opponentRoster,
  }) {
    const mentalityVeryDef = '\u00c7ok Defansif';
    const mentalityDef = 'Defansif';
    const mentalityBal = 'Dengeli';
    const mentalityAtk = 'H\u00fccum';
    const mentalityAllOut = 'Topyek\u00fbn H\u00fccum';
    const buildUpSlow = 'Yava\u015f';
    const buildUpFast = 'H\u0131zl\u0131';
    const focusMix = 'Karma';
    const focusCenter = 'Merkezden';
    const focusWings = 'Kanatlardan';
    const crossingHigh = 'Y\u00fcksek Orta';
    const crossingLow = 'Yer Orta';
    const lineDeep = 'Derin Savunma';
    const lineNormal = 'Normal';
    const lineHigh = '\u0130leride Kur';
    const pressOnLoss = 'Top Kayb\u0131ndan Sonra';
    const pressAlways = 'S\u00fcrekli Bask\u0131';

    final profile = _botProfile(difficulty);
    final difficultyTier = profile.tier;
    final lookup = <String, Map<String, dynamic>>{
      for (final item in roster)
        item['id'] as String:
            (item['data'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
    };
    final starters = <Map<String, dynamic>>[];
    for (final entry in slots.entries) {
      if (entry.key.startsWith('BENCH')) continue;
      final playerId = entry.value['player_id'] as String?;
      final playerData = playerId == null ? null : lookup[playerId];
      if (playerData != null) starters.add(playerData);
    }

    double averageStarterStat(String key) {
      if (starters.isEmpty) return 0;
      final total = starters.fold<double>(
        0,
        (acc, player) => acc + _botStat(player, key),
      );
      return total / starters.length;
    }

    double averageOpponentStat(String key) {
      final available = opponentRoster
          .where((item) {
            final data =
                (item['data'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            return (data['status'] as String? ?? 'uygun') == 'uygun';
          })
          .toList(growable: false);
      if (available.isEmpty) return 0;
      final total = available.fold<double>(
        0,
        (acc, item) =>
            acc +
            _botStat(
              (item['data'] as Map?)?.cast<String, dynamic>() ??
                  const <String, dynamic>{},
              key,
            ),
      );
      return total / available.length;
    }

    final avgAttack = averageStarterStat('hucum');
    final avgDefense = averageStarterStat('savunma');
    final avgPass = averageStarterStat('pas');
    final avgShot = averageStarterStat('sut');
    final avgSpeed = averageStarterStat('hiz');
    final avgStamina = averageStarterStat('dayaniklilik');
    final avgMorale = starters.isEmpty
        ? 5.0
        : starters.fold<double>(
                0,
                (acc, player) =>
                    acc + ((player['morale'] as num?)?.toDouble() ?? 5.0),
              ) /
              starters.length;
    final avgForm = starters.isEmpty
        ? 5.0
        : starters.fold<double>(
                0,
                (acc, player) =>
                    acc + ((player['form'] as num?)?.toDouble() ?? 5.0),
              ) /
              starters.length;
    final oppAttack = averageOpponentStat('hucum');
    final oppDefense = averageOpponentStat('savunma');
    final oppPass = averageOpponentStat('pas');
    final oppSpeed = averageOpponentStat('hiz');
    final ownPower =
        (avgAttack + avgDefense + avgPass + avgShot + avgSpeed + avgStamina) /
        6.0;
    final opponentPower = (oppAttack + oppDefense + oppPass + oppSpeed) / 4.0;
    final powerGap = ownPower - opponentPower;
    final nextMatch = _nextBotMatchInfo(currentTurn);
    final mustWinSoon = nextMatch.turnsUntil <= 1;
    final lowSpirit = avgMorale < 4.7 || avgForm < 4.7;

    var mentality = mentalityBal;
    if (difficultyTier == 0) {
      mentality = const [
        mentalityVeryDef,
        mentalityDef,
        mentalityBal,
        mentalityAtk,
      ][_random.nextInt(4)];
      if (powerGap >= 9 && _random.nextDouble() > 0.40) {
        mentality = mentalityAtk;
      } else if (powerGap <= -10 && _random.nextDouble() > 0.30) {
        mentality = mentalityDef;
      }
    } else if (difficultyTier == 1) {
      if (mustWinSoon && powerGap >= 2 && !lowSpirit) {
        mentality = mentalityAtk;
      } else if (powerGap <= -8 || lowSpirit) {
        mentality = mentalityDef;
      } else if (powerGap >= 8 && avgAttack >= 78) {
        mentality = mentalityAtk;
      }
      if (_random.nextDouble() < profile.randomness * 0.45) {
        mentality = const [
          mentalityDef,
          mentalityBal,
          mentalityAtk,
        ][_random.nextInt(3)];
      }
    } else {
      if (mustWinSoon &&
          powerGap >= 4 &&
          avgAttack >= 82 &&
          avgForm >= 5.2 &&
          avgMorale >= 5.1) {
        mentality = mentalityAllOut;
      } else if (powerGap >= 9 && avgAttack >= avgDefense - 2) {
        mentality = mentalityAtk;
      } else if (powerGap <= -8 || lowSpirit || oppAttack > avgDefense + 7) {
        mentality = mentalityDef;
      }
      if (_random.nextDouble() < profile.randomness * 0.25) {
        mentality = const [
          mentalityDef,
          mentalityBal,
          mentalityAtk,
        ][_random.nextInt(3)];
      }
    }

    var buildUpPlay = mentalityBal;
    if (difficultyTier == 0) {
      buildUpPlay = const [
        buildUpSlow,
        mentalityBal,
        buildUpFast,
      ][_random.nextInt(3)];
    } else if (avgPass >= 80 && avgSpeed <= 72) {
      buildUpPlay = buildUpSlow;
    } else if (avgSpeed >= 78 || avgAttack > avgDefense + 10 || mustWinSoon) {
      buildUpPlay = buildUpFast;
    }
    if (difficultyTier >= 2 &&
        oppPass >= 79 &&
        avgDefense >= 78 &&
        avgStamina >= 74) {
      buildUpPlay = buildUpSlow;
    }

    var focusPlay = focusMix;
    if (difficultyTier == 0) {
      focusPlay = const [focusMix, focusCenter, focusWings][_random.nextInt(3)];
    } else if (avgPass >= 79 && avgShot >= 74) {
      focusPlay = focusCenter;
    } else if (avgSpeed >= 76 || formation == '2-2-2' || oppDefense >= 80) {
      focusPlay = focusWings;
    }
    if (difficultyTier >= 2 && oppDefense >= 83 && avgSpeed >= 74) {
      focusPlay = focusWings;
    }

    final crossingType = focusPlay == focusWings
        ? (avgShot >= 76 ? crossingHigh : crossingLow)
        : (avgPass >= 80 ? crossingLow : crossingHigh);
    final defensiveLine = difficultyTier == 0
        ? (avgDefense < 70 ? lineDeep : lineNormal)
        : (avgDefense >= 80 &&
                  avgSpeed >= 75 &&
                  avgMorale >= 5 &&
                  powerGap >= -2) ||
              (difficultyTier >= 2 &&
                  oppAttack <= avgDefense - 3 &&
                  avgStamina >= 72)
        ? lineHigh
        : (avgDefense <= 70 || oppSpeed > avgSpeed + 8 ? lineDeep : lineNormal);
    final pressingTrigger = difficultyTier == 0
        ? (avgStamina >= 76 && _random.nextDouble() < 0.24
              ? pressOnLoss
              : mentalityBal)
        : difficultyTier == 1
        ? (avgStamina >= 75 && !lowSpirit ? pressOnLoss : mentalityBal)
        : (avgStamina >= 82 && avgForm >= 5.0 && powerGap >= -5
              ? pressAlways
              : (avgStamina >= 73 ? pressOnLoss : mentalityBal));

    final enrichedSlots = <String, Map<String, dynamic>>{
      for (final entry in slots.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    for (final entry in enrichedSlots.entries) {
      final playerId = entry.value['player_id'] as String?;
      final playerData = playerId == null ? null : lookup[playerId];
      final instructions = playerData == null
          ? <String>[]
          : _botInstructionsForSlot(
              entry.key,
              playerData,
              mentality: mentality,
              buildUpPlay: buildUpPlay,
              focusPlay: focusPlay,
              pressingTrigger: pressingTrigger,
              difficultyTier: difficultyTier,
            );
      entry.value['instructions'] = instructions
          .take(1)
          .toList(growable: false);
    }

    return {
      'formation': formation,
      'formation_slots': enrichedSlots,
      'mentality': mentality,
      'build_up_play': buildUpPlay,
      'focus_play': focusPlay,
      'crossing_type': crossingType,
      'defensive_line': defensiveLine,
      'pressing_trigger': pressingTrigger,
      'offside_trap':
          defensiveLine == lineHigh &&
          avgSpeed >= 74 &&
          difficultyTier >= 1 &&
          avgMorale >= 5,
      'captain_id': _pickBestBotStarterId(
        enrichedSlots,
        roster,
        (playerData) =>
            _botPlayerRating(playerData) +
            ((playerData['morale'] as num?)?.toDouble() ?? 5) * 1.5 +
            ((playerData['form'] as num?)?.toDouble() ?? 5) * 1.2 +
            _botStat(playerData, 'dayaniklilik') * 0.2,
      ),
      'set_piece_takers': {
        'pen': _pickBestBotStarterId(
          enrichedSlots,
          roster,
          (playerData) =>
              _botStat(playerData, 'sut') * 1.25 +
              _botStat(playerData, 'hucum') * 0.95 +
              ((playerData['form'] as num?)?.toDouble() ?? 5) * 0.8,
        ),
        'fk': _pickBestBotStarterId(
          enrichedSlots,
          roster,
          (playerData) =>
              _botStat(playerData, 'pas') * 1.05 +
              _botStat(playerData, 'sut') * 0.85 +
              _botStat(playerData, 'hucum') * 0.25,
        ),
        'cor': _pickBestBotStarterId(
          enrichedSlots,
          roster,
          (playerData) =>
              _botStat(playerData, 'pas') * 1.15 +
              _botStat(playerData, 'hiz') * 0.25,
        ),
      },
    };
  }

  double _scoreBotAugment(
    String augmentId,
    Map<String, dynamic> botData,
    List<Map<String, dynamic>> botRoster,
    Map<String, dynamic> opponentData,
    List<Map<String, dynamic>> opponentRoster,
    int currentTurn,
  ) {
    final augment = augments[augmentId];
    if (augment == null) return -1000;

    final type = augment['type'] as String? ?? '';
    final details =
        (augment['details'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final nextMatch = _nextBotMatchInfo(currentTurn);
    final botGold = (botData['gold'] as num?)?.toInt() ?? 0;
    final opponentGold = (opponentData['gold'] as num?)?.toInt() ?? 0;
    final botAvg = _botAverageRating(botRoster);
    final oppAvg = _botAverageRating(opponentRoster);

    var score = 12.0;
    switch (type) {
      case 'gold_reward':
        score += ((details['amount'] as num?)?.toDouble() ?? 0) / 24;
        if (botGold < 120) score += 7;
        break;
      case 'player_reward':
      case 'gold_and_random_player':
      case 'gold_and_random_low_rating_player':
      case 'temporary_player':
        score += nextMatch.turnsUntil <= 1 ? 24 : 16;
        break;
      case 'stat_boost':
      case 'conditional_stat_boost':
        score += botAvg <= oppAvg ? 22 : 16;
        break;
      case 'persistent_self_buff':
      case 'persistent_multiplier':
      case 'persistent_passive_effect':
        score += currentTurn <= 8 ? 18 : 11;
        break;
      case 'persistent_match_effect':
        score += nextMatch.turnsUntil <= 1 ? 26 : 12;
        break;
      case 'opponent_debuff':
      case 'opponent_player_debuff':
      case 'opponent_delayed_gold_loss':
        score += opponentGold >= botGold ? 20 : 14;
        break;
      case 'steal_player':
      case 'fates_trade':
        score += oppAvg >= botAvg ? 22 : 10;
        break;
      default:
        score += 10;
        break;
    }
    return score + _random.nextDouble() * 4;
  }

  int _botEffectiveShopPrice(
    Map<String, dynamic> player,
    Map<String, dynamic> botData,
    int currentTurn,
  ) {
    var price = (player['price'] as num?)?.toInt() ?? 9999;
    final activeEffects =
        (botData['active_augment_effects'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final debuffs =
        (botData['active_debuffs'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final discountData =
        (activeEffects['player_discount_data'] as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final discountIds = List<String>.from(
      (discountData['player_ids'] as List?) ?? const [],
    );
    if (discountIds.contains(player['id'])) {
      price =
          (price *
                  ((discountData['discount_percent'] as num?)?.toDouble() ?? 1))
              .ceil();
    }
    if (((activeEffects['shop_discount_turns'] as num?)?.toInt() ?? 0) > 0) {
      price =
          (price *
                  ((activeEffects['shop_discount_percent'] as num?)
                          ?.toDouble() ??
                      1))
              .toInt();
    }
    final shopDebuff =
        (debuffs['shop_price_increase'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final priceIncrease =
        currentTurn <= ((shopDebuff['until_turn'] as num?)?.toInt() ?? 0)
        ? (shopDebuff['amount'] as num?)?.toInt() ?? 0
        : 0;
    return max(1, price + priceIncrease);
  }

  double _scoreBotShopPlayer(
    Map<String, dynamic> player,
    List<Map<String, dynamic>> roster,
    Map<String, dynamic> botData,
    int currentGold,
    _BotProfile profile,
    int currentTurn,
  ) {
    final mevki = player['mevki'] as String? ?? '';
    final price = _botEffectiveShopPrice(player, botData, currentTurn);
    final rating = (player['rating'] as num?)?.toDouble() ?? 0;
    if (price > currentGold || roster.length >= 15) return -1000;

    final difficultyTier = profile.tier;
    final reserve = profile.reserveGold;
    final formation = botData['formation'] as String? ?? '3-2-1';
    final desiredByPosition = _desiredStarterCounts(formation);
    final availableSamePosition = _countByPosition(
      roster,
      position: mevki,
      availableOnly: true,
    );
    final unavailableSamePosition = _countByPosition(
      roster,
      position: mevki,
      availableOnly: false,
    );
    final positionGap = max(
      0,
      (desiredByPosition[mevki] ?? 0) - availableSamePosition,
    );
    final weakestPositionRating = roster
        .where((item) {
          final data =
              (item['data'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          return (data['status'] as String? ?? 'uygun') == 'uygun' &&
              (data['mevki'] as String? ?? '') == mevki;
        })
        .map(
          (item) => _botPlayerRating(
            (item['data'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{},
          ),
        )
        .fold<double>(999, min);
    final weakest = weakestPositionRating == 999 ? 0 : weakestPositionRating;
    final nextMatch = _nextBotMatchInfo(currentTurn);
    final teamAverage = _botAverageRating(roster);
    final samePosAvgRating = _averagePositionRating(roster, mevki);
    final playerAttack = (player['stats'] as Map?)?['hucum'] as num? ?? 0;
    final playerDefense = (player['stats'] as Map?)?['savunma'] as num? ?? 0;
    final playerPass = (player['stats'] as Map?)?['pas'] as num? ?? 0;
    final playerShot = (player['stats'] as Map?)?['sut'] as num? ?? 0;
    final playerPace = (player['stats'] as Map?)?['hiz'] as num? ?? 0;
    final playerStamina =
        (player['stats'] as Map?)?['dayaniklilik'] as num? ?? 0;
    final coreFit = switch (mevki) {
      'Kaleci' => playerDefense * 1.20 + playerPass * 0.20,
      'Defans' =>
        playerDefense * 1.10 + playerStamina * 0.35 + playerPace * 0.20,
      'Orta Saha' =>
        playerPass * 1.00 + playerAttack * 0.35 + playerStamina * 0.25,
      _ => playerShot * 1.00 + playerAttack * 0.55 + playerPace * 0.30,
    };
    final teamWeakness =
        max(0.0, 74 - _averageRosterStat(roster, 'pas')) * 0.25 +
        max(0.0, 73 - _averageRosterStat(roster, 'hucum')) * 0.20 +
        max(0.0, 73 - _averageRosterStat(roster, 'savunma')) * 0.20;

    var score = rating * 1.55 + max(0, rating - weakest) * 4.6;
    score += coreFit * 0.20;
    score += max(0.0, rating - samePosAvgRating) * 1.8;
    score += positionGap * (difficultyTier >= 2 ? 34 : 22);
    score += unavailableSamePosition * (difficultyTier >= 2 ? 14 : 8);
    if (availableSamePosition == 0 && mevki == 'Kaleci') {
      score += difficultyTier >= 1 ? 28 : 14;
    }
    if (nextMatch.turnsUntil <= 1 && rating > weakest) {
      score += difficultyTier >= 2 ? 14 : 8;
    }
    if (difficultyTier >= 2 && rating > teamAverage) {
      score += (rating - teamAverage) * 1.4;
    }
    score -=
        price *
        (difficultyTier >= 2
            ? 0.06
            : difficultyTier == 1
            ? 0.08
            : 0.11);
    if (price < ((player['price'] as num?)?.toInt() ?? price)) {
      score += 10;
    }
    score += teamWeakness * (difficultyTier >= 2 ? 0.80 : 0.45);
    if (currentGold - price < reserve) {
      score -= difficultyTier >= 2 ? 8 : 16;
    }
    score += (_random.nextDouble() * 2 - 1) * (profile.randomness * 24);
    return score;
  }

  Future<void> _executeBotTurn(String difficulty, int currentTurn) async {
    final room = roomRef;
    if (room == null) return;
    final profile = _botProfile(difficulty);
    final difficultyTier = profile.tier;

    Future<List<Map<String, dynamic>>> loadRoster(
      DocumentReference<Map<String, dynamic>> playerRef,
    ) async {
      final query = await playerRef.collection('my_team').get();
      return query.docs
          .map((doc) => {'id': doc.id, 'data': doc.data()})
          .toList(growable: false);
    }

    final latestState =
        (await room.collection('game_state').doc('current').get()).data() ??
        currentGameState ??
        <String, dynamic>{};
    if (latestState['current_player_id'] != 'oyuncu_2') return;

    final botRef = room.collection('players').doc('oyuncu_2');
    final opponentRef = room.collection('players').doc('oyuncu_1');
    var botData = (await botRef.get()).data() ?? <String, dynamic>{};
    final opponentData =
        (await opponentRef.get()).data() ?? <String, dynamic>{};
    var botRoster = await loadRoster(botRef);
    final opponentRoster = await loadRoster(opponentRef);
    var botShopIds = List<String>.from(
      (botData['current_shop_pool'] as List?) ?? const [],
    );
    var botGold = (botData['gold'] as num?)?.toInt() ?? 0;

    final augmentTurns = List<int>.from(
      (gameConfig['augment_turns'] as List?) ?? const [1, 3, 6],
    );
    final completed = List<int>.from(
      (botData['augment_turns_completed'] as List?) ?? const [],
    );
    if (augmentTurns.contains(currentTurn) &&
        !completed.contains(currentTurn)) {
      final available = await RoomGameService.getAvailableAugmentsForPlayer(
        room,
        List<dynamic>.from((latestState['augment_pool'] as List?) ?? const []),
      );
      if (available.isNotEmpty) {
        final ranked =
            available
                .map(
                  (augmentId) => MapEntry(
                    augmentId,
                    _scoreBotAugment(
                      augmentId,
                      botData,
                      botRoster,
                      opponentData,
                      opponentRoster,
                      currentTurn,
                    ),
                  ),
                )
                .toList(growable: false)
              ..sort((a, b) => b.value.compareTo(a.value));
        final chosen = _pickRankedBotChoice(ranked, profile);
        await botRef.update({
          'augments_chosen': FieldValue.arrayUnion([chosen]),
          'augment_turns_completed': FieldValue.arrayUnion([currentTurn]),
        });
        await room.collection('game_state').doc('current').update({
          'augment_pool': FieldValue.arrayRemove([chosen]),
        });
        await RoomGameService.applyAugmentEffect(
          db: room.firestore,
          roomRef: room,
          gameConfig: gameConfig,
          currentTurn: currentTurn,
          playerId: 'oyuncu_2',
          opponentId: 'oyuncu_1',
          augmentId: chosen,
        );
        botData = (await botRef.get()).data() ?? botData;
        botRoster = await loadRoster(botRef);
        botShopIds = List<String>.from(
          (botData['current_shop_pool'] as List?) ?? botShopIds,
        );
        botGold = (botData['gold'] as num?)?.toInt() ?? botGold;
      }
    }

    if ((botData['income_taken_for_turn'] as num?)?.toInt() != currentTurn) {
      final nextMatch = _nextBotMatchInfo(currentTurn);
      final activeEffects =
          (botData['active_augment_effects'] as Map?)
              ?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final successChance =
          (activeEffects['risk_chance'] as num?)?.toDouble() ?? 0.25;
      final lowReserve = max(35, profile.reserveGold - 25);
      final riskyNeed = botGold <= lowReserve;
      final riskyWindow = nextMatch.turnsUntil > 1 || successChance >= 0.32;
      final riskyRoll =
          _random.nextDouble() <
          (0.06 + profile.riskAggression * 0.42 - profile.randomness * 0.10);
      final risky = riskyNeed && riskyWindow && riskyRoll;
      final income = risky
          ? (_random.nextDouble() < successChance
                ? (gameConfig['risk_success_amount'] as num?)?.toInt() ?? 300
                : (gameConfig['risk_failure_amount'] as num?)?.toInt() ?? 50)
          : ((gameConfig['income_amount'] as num?)?.toInt() ?? 175);
      botGold += income;
      await botRef.update({
        'gold': botGold,
        'income_taken_for_turn': currentTurn,
      });
      botData = (await botRef.get()).data() ?? botData;
    }

    final shopDocs = await Future.wait(
      botShopIds.map((id) => room.collection('player_pool').doc(id).get()),
    );
    final shopPlayers = shopDocs
        .where((doc) => doc.exists)
        .map((doc) => {'id': doc.id, ...?doc.data()})
        .toList(growable: false);
    if (shopPlayers.isNotEmpty && botRoster.length < 15) {
      final rankedShop =
          shopPlayers
              .map(
                (player) => MapEntry(
                  player,
                  _scoreBotShopPlayer(
                    player,
                    botRoster,
                    botData,
                    botGold,
                    profile,
                    currentTurn,
                  ),
                ),
              )
              .toList(growable: false)
            ..sort((a, b) => b.value.compareTo(a.value));
      final minimumScore = profile.shopScoreThreshold.toDouble();
      final maxBuys =
          profile.maxBuysBase +
          (botGold >= profile.highGoldBuyThreshold ? profile.maxBuysBonus : 0);
      final remainingShopIds = List<String>.from(botShopIds);
      final purchaseBatch = room.firestore.batch();
      var buys = 0;

      for (final entry in rankedShop) {
        if (buys >= maxBuys || botRoster.length >= 15) break;
        final player = entry.key;
        final score = entry.value;
        final playerId = player['id'] as String;
        final price = _botEffectiveShopPrice(player, botData, currentTurn);
        if (score < minimumScore || botGold < price) continue;
        if (difficultyTier == 0 &&
            buys == 0 &&
            botGold - price < profile.reserveGold &&
            _random.nextDouble() < 0.45) {
          continue;
        }

        final newPlayer = <String, dynamic>{
          'name': player['name'],
          'mevki': player['mevki'],
          'rating': player['rating'],
          'price': price,
          'owner_id': 'oyuncu_2',
          'stats': Map<String, dynamic>.from(
            (player['stats'] as Map?) ?? const <String, dynamic>{},
          ),
          'status': player['status'] ?? 'uygun',
          'status_duration': player['status_duration'] ?? 0,
          'form': player['form'] ?? 5,
          'morale': player['morale'] ?? 5,
        };
        purchaseBatch.set(
          botRef.collection('my_team').doc(playerId),
          newPlayer,
        );
        purchaseBatch.update(room.collection('player_pool').doc(playerId), {
          'owner_id': 'oyuncu_2',
        });
        remainingShopIds.remove(playerId);
        botGold -= price;
        buys += 1;
        botRoster = [
          ...botRoster,
          {'id': playerId, 'data': newPlayer},
        ];
      }

      if (buys > 0) {
        purchaseBatch.update(botRef, {
          'gold': botGold,
          'current_shop_pool': remainingShopIds,
        });
        await purchaseBatch.commit();
      }
    }

    final formation = _chooseBotFormation(botRoster, difficulty);
    final slots = _buildBotFormationSlots(formation, botRoster, difficulty);
    await botRef.update(
      _buildStrategicBotTacticsV2(
        difficulty,
        botRoster,
        formation,
        slots,
        currentTurn,
        opponentRoster: opponentRoster,
      ),
    );

    final nextMatch = _nextBotMatchInfo(currentTurn);
    final facilities = List<String>.from(
      (botData['facilities'] as List?) ?? const [],
    );
    String? facilityToBuy;
    if (difficultyTier >= 2 &&
        currentTurn <= 6 &&
        !facilities.contains('ticari_stadyum') &&
        botGold >= 400) {
      facilityToBuy = 'ticari_stadyum';
    } else if (nextMatch.turnsUntil <= 1 &&
        !facilities.contains('saglik_merkezi') &&
        botGold >= 350) {
      facilityToBuy = 'saglik_merkezi';
    } else if (difficultyTier >= 2 &&
        nextMatch.botIsHome &&
        !facilities.contains('vip_tribun') &&
        botGold >= 300) {
      facilityToBuy = 'vip_tribun';
    }
    if (facilityToBuy != null) {
      final cost =
          (facilitiesData[facilityToBuy]?['cost'] as num?)?.toInt() ?? 0;
      if (cost > 0 && !facilities.contains(facilityToBuy) && botGold >= cost) {
        facilities.add(facilityToBuy);
        botGold -= cost;
        await botRef.update({'gold': botGold, 'facilities': facilities});
      }
    }

    final matchTurns = List<int>.from(
      (gameConfig['match_turns'] as List?) ?? const [7, 14, 21],
    );
    if (matchTurns.contains(currentTurn)) {
      await _startSimulationLogic();
      return;
    }

    final nextTurn = currentTurn + 1;
    await RoomGameService.updatePlayerStatuses(room.firestore, room);
    await RoomGameService.generateNewShopForPlayer(
      roomRef: room,
      playerId: 'oyuncu_1',
      gameState: {'current_turn': nextTurn},
      gameConfig: gameConfig,
    );
    await room.collection('game_state').doc('current').update({
      'current_player_id': 'oyuncu_1',
      'current_turn': nextTurn,
      ...RoomGameService.buildTurnTimingUpdate(gameConfig),
    });
  }

  void _resetRoomState() {
    _stopRoomRuntime();
    roomCode = null;
    playerId = null;
    opponentId = null;
    isHost = false;
    gameConfig = _cloneDefaultGameConfig();
    pendingAugments = const [];
    pendingAugmentTurn = 0;
  }

  String _generateRoomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(6, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  @override
  void dispose() {
    _stopRoomRuntime();
    super.dispose();
  }
}

class _BotProfile {
  const _BotProfile({
    required this.tier,
    required this.reactionMinMs,
    required this.reactionMaxMs,
    required this.reserveGold,
    required this.maxBuysBase,
    required this.maxBuysBonus,
    required this.highGoldBuyThreshold,
    required this.shopScoreThreshold,
    required this.randomness,
    required this.riskAggression,
  });

  final int tier;
  final int reactionMinMs;
  final int reactionMaxMs;
  final int reserveGold;
  final int maxBuysBase;
  final int maxBuysBonus;
  final int highGoldBuyThreshold;
  final int shopScoreThreshold;
  final double randomness;
  final double riskAggression;
}
