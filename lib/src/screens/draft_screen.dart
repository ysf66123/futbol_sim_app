import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/session_controller.dart';
import '../data/game_data.dart';
import '../services/match_engine.dart';
import '../services/room_game_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialogs.dart';
import '../utils/game_exception.dart';
import '../widgets/ui.dart';

class DraftScreen extends StatefulWidget {
  const DraftScreen({super.key});

  @override
  State<DraftScreen> createState() => _DraftScreenState();
}

class _DraftScreenState extends State<DraftScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _gameStateSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _playerDataSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _myTeamSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _p1NameSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _p2NameSub;
  final _random = Random();

  String p1Name = 'Mavi Takım';
  String p2Name = 'Kırmızı Takım';
  Map<String, dynamic>? gameState;
  Map<String, dynamic>? playerData;
  List<Map<String, dynamic>> myTeamData = const [];
  List<Map<String, dynamic>> shopPlayers = const [];
  bool wasMyTurn = false;
  int _activeInventoryTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startListeners());
  }

  @override
  void dispose() {
    _gameStateSub?.cancel();
    _playerDataSub?.cancel();
    _myTeamSub?.cancel();
    _p1NameSub?.cancel();
    _p2NameSub?.cancel();
    super.dispose();
  }

  int _turnOf(Map<String, dynamic>? state) {
    return (state?['current_turn'] as num?)?.toInt() ?? 0;
  }

  String _phaseOf(Map<String, dynamic>? state) {
    return state?['phase'] as String? ?? 'drafting';
  }

  Map<String, dynamic>? _effectiveGameState(SessionController session) {
    final local = gameState;
    final shared = session.currentGameState;
    if (local == null) return shared;
    if (shared == null) return local;

    final localTurn = _turnOf(local);
    final sharedTurn = _turnOf(shared);
    final localPhase = _phaseOf(local);
    final sharedPhase = _phaseOf(shared);
    if (sharedTurn > localTurn) return shared;
    if (localTurn > sharedTurn) return local;
    if (sharedPhase == 'drafting' && localPhase != 'drafting') return shared;
    if (localPhase == 'drafting' && sharedPhase != 'drafting') return local;
    if (sharedPhase == 'match_countdown' && localPhase != 'match_countdown') {
      return shared;
    }
    return shared;
  }

  Map<String, dynamic>? _effectivePlayerData(
    SessionController session, {
    Map<String, dynamic>? effectiveGameState,
  }) {
    final local = playerData;
    final shared = session.currentPlayerState;
    if (local == null) return shared;
    if (shared == null) return local;

    final effective = effectiveGameState ?? _effectiveGameState(session);
    final effectiveTurn = _turnOf(effective);
    final localTurn = _turnOf(gameState);
    final localPhase = _phaseOf(gameState);
    final effectivePhase = _phaseOf(effective);
    final sharedShopTurn =
        (shared['shop_generated_turn'] as num?)?.toInt() ?? 0;
    final localShopTurn = (local['shop_generated_turn'] as num?)?.toInt() ?? 0;
    if (effectiveTurn > localTurn) return shared;
    if (effectivePhase == 'drafting' && localPhase != 'drafting') return shared;
    if (sharedShopTurn > localShopTurn) return shared;
    return local;
  }

  bool _isMyTurnFor(
    SessionController session, {
    Map<String, dynamic>? effectiveGameState,
  }) {
    final resolved = effectiveGameState ?? _effectiveGameState(session);
    return resolved?['current_player_id'] == session.playerId;
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on GameException catch (error) {
      if (!mounted) return;
      await showGameDialog(context, title: error.title, message: error.message);
    } catch (error) {
      if (!mounted) return;
      await showGameDialog(context, title: 'Hata', message: '$error');
    }
  }

  void _startListeners() {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null || session.playerId == null) return;
    if (mounted) {
      setState(() {
        gameState = session.currentGameState == null
            ? gameState
            : Map<String, dynamic>.from(session.currentGameState!);
        playerData = session.currentPlayerState == null
            ? playerData
            : Map<String, dynamic>.from(session.currentPlayerState!);
      });
    }
    if (session.currentPlayerState != null) {
      unawaited(
        _processPlayerData(
          Map<String, dynamic>.from(session.currentPlayerState!),
        ),
      );
    }

    _gameStateSub = roomRef
        .collection('game_state')
        .doc('current')
        .snapshots()
        .listen((snapshot) async {
          final data = snapshot.data();
          if (data == null || !mounted) return;
          setState(() => gameState = data);
          await _processGameState();
        });
    _playerDataSub = roomRef
        .collection('players')
        .doc(session.playerId)
        .snapshots()
        .listen((snapshot) async {
          final data = snapshot.data();
          if (data == null || !mounted) return;
          setState(() => playerData = data);
          await _processPlayerData(data);
        });
    _myTeamSub = roomRef
        .collection('players')
        .doc(session.playerId)
        .collection('my_team')
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          setState(() {
            myTeamData = snapshot.docs
                .map((doc) => {'id': doc.id, 'data': doc.data()})
                .toList(growable: false);
          });
        });
    _p1NameSub = roomRef
        .collection('players')
        .doc('oyuncu_1')
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          setState(() {
            p1Name = snapshot.data()?['team_name'] as String? ?? 'Oyuncu 1';
          });
        });
    _p2NameSub = roomRef
        .collection('players')
        .doc('oyuncu_2')
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          setState(() {
            p2Name = snapshot.data()?['team_name'] as String? ?? 'Oyuncu 2';
          });
        });
  }

  Future<void> _processGameState() async {
    if (!mounted) return;
    final session = context.read<SessionController>();
    final isMyTurn = _isMyTurnFor(session);
    if (isMyTurn && !wasMyTurn) {
      showGameSnack(context, 'Sıra sende.');
    }
    wasMyTurn = isMyTurn;
  }

  Future<void> _processPlayerData(Map<String, dynamic> data) async {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null) return;
    final effectiveGameState = _effectiveGameState(session);
    final currentTurn = _turnOf(effectiveGameState);
    final shopIds = List<String>.from(
      (data['current_shop_pool'] as List?) ?? const [],
    );

    final activeEffects =
        (data['active_augment_effects'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final debuffs =
        (data['active_debuffs'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final discountData =
        (activeEffects['player_discount_data'] as Map?)
            ?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final discountIds = List<String>.from(
      (discountData['player_ids'] as List?) ?? const [],
    );
    final shopDebuff =
        (debuffs['shop_price_increase'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final priceIncrease =
        currentTurn <= ((shopDebuff['until_turn'] as num?)?.toInt() ?? 0)
        ? (shopDebuff['amount'] as num?)?.toInt() ?? 0
        : 0;
    final docs = await Future.wait(
      shopIds.map((id) => roomRef.collection('player_pool').doc(id).get()),
    );
    final nextShopPlayers = docs
        .where((doc) => doc.exists)
        .map((doc) {
          final shopData = Map<String, dynamic>.from(
            doc.data() ?? <String, dynamic>{},
          );
          var price = (shopData['price'] as num?)?.toInt() ?? 0;
          if (discountIds.contains(doc.id)) {
            price =
                (price *
                        ((discountData['discount_percent'] as num?)
                                ?.toDouble() ??
                            1))
                    .ceil();
          }
          if (((activeEffects['shop_discount_turns'] as num?)?.toInt() ?? 0) >
              0) {
            price =
                (price *
                        ((activeEffects['shop_discount_percent'] as num?)
                                ?.toDouble() ??
                            1))
                    .toInt();
          }
          shopData['price'] = price + priceIncrease;
          return {'id': doc.id, 'data': shopData};
        })
        .toList(growable: false);
    if (mounted) {
      setState(() => shopPlayers = nextShopPlayers);
    }
  }

  Future<void> _buyPlayer(String id, Map<String, dynamic> data) async {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    final effectiveGameState = _effectiveGameState(session);
    final effectivePlayerData = _effectivePlayerData(
      session,
      effectiveGameState: effectiveGameState,
    );
    if (roomRef == null ||
        !_isMyTurnFor(session, effectiveGameState: effectiveGameState) ||
        effectivePlayerData == null) {
      return;
    }
    if (myTeamData.length >=
        ((effectivePlayerData['max_capacity'] as num?)?.toInt() ?? 15)) {
      throw GameException('Hata', 'Takım kapasiten dolu.');
    }
    final price = (data['price'] as num?)?.toInt() ?? 9999;
    if (((effectivePlayerData['gold'] as num?)?.toInt() ?? 0) < price) {
      throw GameException('Hata', 'Yetersiz altın.');
    }
    final batch = roomRef.firestore.batch();
    final playerRef = roomRef.collection('players').doc(session.playerId);
    batch.update(playerRef, {
      'gold': FieldValue.increment(-price),
      'current_shop_pool': FieldValue.arrayRemove([id]),
    });
    batch.set(playerRef.collection('my_team').doc(id), data);
    batch.update(roomRef.collection('player_pool').doc(id), {
      'owner_id': session.playerId,
    });
    await batch.commit();
  }

  Future<void> _sellPlayer(String id, Map<String, dynamic> data) async {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    final effectiveGameState = _effectiveGameState(session);
    final effectivePlayerData = _effectivePlayerData(
      session,
      effectiveGameState: effectiveGameState,
    );
    if (roomRef == null ||
        !_isMyTurnFor(session, effectiveGameState: effectiveGameState) ||
        effectivePlayerData == null ||
        data['is_loan'] == true) {
      return;
    }
    final activeEffects =
        (effectivePlayerData['active_augment_effects'] as Map?)
            ?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final multiplier =
        (activeEffects['sale_multiplier'] as num?)?.toDouble() ?? 0.5;
    final price = _saleValueForPlayer(data, multiplierOverride: multiplier);
    final batch = roomRef.firestore.batch();
    final playerRef = roomRef.collection('players').doc(session.playerId);
    batch.update(playerRef, {
      'gold': FieldValue.increment(price),
      ...RoomGameService.buildRosterCleanupUpdate(effectivePlayerData, [id]),
    });
    batch.delete(playerRef.collection('my_team').doc(id));
    batch.update(roomRef.collection('player_pool').doc(id), {
      'owner_id': 'pool',
    });
    await batch.commit();
  }

  int _marketPriceForPlayer(Map<String, dynamic> data) {
    final stats = Map<String, dynamic>.from(
      (data['stats'] as Map?) ?? const <String, dynamic>{},
    );
    final rating =
        (data['rating'] as num?)?.toInt() ??
        calculateRating(stats, data['mevki'] as String? ?? 'Orta Saha');
    return calculatePrice(rating);
  }

  int _saleValueForPlayer(
    Map<String, dynamic> data, {
    double? multiplierOverride,
  }) {
    final activeEffects =
        (playerData?['active_augment_effects'] as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final multiplier =
        multiplierOverride ??
        (activeEffects['sale_multiplier'] as num?)?.toDouble() ??
        0.5;
    return (_marketPriceForPlayer(data) * multiplier).round();
  }

  Future<void> _getIncome(bool risky) async {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    final effectiveGameState = _effectiveGameState(session);
    final effectivePlayerData = _effectivePlayerData(
      session,
      effectiveGameState: effectiveGameState,
    );
    if (roomRef == null ||
        effectivePlayerData == null ||
        effectiveGameState == null) {
      return;
    }
    final currentTurn = _turnOf(effectiveGameState);
    final playerRef = roomRef.collection('players').doc(session.playerId);
    final activeEffects =
        (effectivePlayerData['active_augment_effects'] as Map?)
            ?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final success =
        (session.gameConfig['risk_success_amount'] as num?)?.toInt() ?? 300;
    final failure =
        (session.gameConfig['risk_failure_amount'] as num?)?.toInt() ?? 50;
    final normal =
        (session.gameConfig['income_amount'] as num?)?.toInt() ?? 175;
    final updates = <String, dynamic>{'income_taken_for_turn': currentTurn};
    late final int income;
    if (risky) {
      income =
          _random.nextDouble() <
              ((activeEffects['risk_chance'] as num?)?.toDouble() ?? 0.25)
          ? success
          : failure;
    } else if (((activeEffects['income_boost_turns'] as num?)?.toInt() ?? 0) >
        0) {
      income = (activeEffects['income_boost_value'] as num?)?.toInt() ?? normal;
      final remaining =
          ((activeEffects['income_boost_turns'] as num?)?.toInt() ?? 1) - 1;
      updates['active_augment_effects.income_boost_turns'] = remaining;
      if (remaining == 0) {
        updates['active_augment_effects.income_boost_value'] =
            FieldValue.delete();
      }
    } else {
      income = normal;
    }
    updates['gold'] = FieldValue.increment(income);
    await playerRef.update(updates);
    if (!mounted) return;
    showGameSnack(context, '+$income altın alındı.');
  }

  Future<void> _showMyAugments() async {
    final chosen = List<String>.from(
      (playerData?['augments_chosen'] as List?) ?? const [],
    );
    final session = context.read<SessionController>();
    final text = chosen.isEmpty
        ? 'Henüz eklenti seçmedin.'
        : chosen
              .map((id) {
                final data =
                    session.augmentCatalog[id] ??
                    const <String, dynamic>{
                      'name': 'Eklenti',
                      'description': '',
                    };
                return '${data['name']}\n${data['description']}';
              })
              .join('\n\n');
    await showGameDialog(context, title: 'Seçilen Eklentiler', message: text);
  }

  Future<void> _showMatchHistory() async {
    final scores =
        (gameState?['match_scores'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final text = scores.isEmpty
        ? 'Henüz oynanmış maç yok.'
        : scores.entries
              .map((entry) => '${entry.key}: ${entry.value}')
              .join('\n');
    await showGameDialog(context, title: 'Maç Geçmişi', message: text);
  }

  Future<void> _showFacilities() async {
    final facilities = List<String>.from(
      (playerData?['facilities'] as List?) ?? const [],
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: facilitiesData.entries
                .map((entry) {
                  final owned = facilities.contains(entry.key);
                  return ListTile(
                    title: Text(entry.value['name'] as String),
                    subtitle: Text(entry.value['desc'] as String),
                    trailing: owned
                        ? const InfoBadge(
                            label: 'Sahip',
                            color: AppColors.accent,
                          )
                        : GameFilledButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _guard(
                                () => _buyFacility(
                                  entry.key,
                                  (entry.value['cost'] as num).toInt(),
                                ),
                              );
                            },
                            child: Text('${entry.value['cost']} G'),
                          ),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ),
    );
  }

  Future<void> _buyFacility(String facilityId, int cost) async {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null || playerData == null) return;
    if (((playerData!['gold'] as num?)?.toInt() ?? 0) < cost) {
      throw GameException('Hata', 'Yeterli altının yok.');
    }
    await roomRef.collection('players').doc(session.playerId).update({
      'gold': FieldValue.increment(-cost),
      'facilities': FieldValue.arrayUnion([facilityId]),
    });
  }

  Widget _scoutingSoonButton() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const GameOutlinedButton(onPressed: null, child: Text('Gözlemci')),
        const Positioned(
          top: -10,
          right: -6,
          child: InfoBadge(label: 'Yakında', color: AppColors.warning),
        ),
      ],
    );
  }

  Widget _inventoryTabButton({
    required int index,
    required String label,
    required String countLabel,
    required IconData icon,
  }) {
    final selected = _activeInventoryTab == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _activeInventoryTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.16)
                : AppColors.panelSoft,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.34)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppColors.accent : AppColors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? AppColors.text : AppColors.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      countLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? AppColors.accent : AppColors.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryPanel({required bool showShop}) {
    final items = showShop ? shopPlayers : myTeamData;
    final title = showShop ? 'Mağaza' : 'Kadrom';
    final emptyMessage = showShop
        ? 'Bu tur için mağazada oyuncu görünmüyor.'
        : 'Kadron henüz boş. Mağazadan oyuncu satın alabilirsin.';

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            showShop
                ? 'Satın alabileceğin oyuncular burada.'
                : 'Satabileceğin ve yönetebileceğin mevcut oyuncular burada.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Text(
                emptyMessage,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: items
                  .map((item) => _playerCard(item, showShop))
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }

  String _formatCountdown(int seconds) {
    final safe = max(0, seconds);
    final minutes = (safe ~/ 60).toString().padLeft(2, '0');
    final remainingSeconds = (safe % 60).toString().padLeft(2, '0');
    return '$minutes:$remainingSeconds';
  }

  Widget _buildMatchCountdownScreen(
    BuildContext context, {
    required SessionController session,
    required Map<String, dynamic>? effectiveGameState,
    required Map<String, dynamic>? effectivePlayerData,
  }) {
    final remaining = session.matchCountdownSecondsRemaining ?? 0;
    return GamePageScaffold(
      title: 'Ma\u00e7 Oynan\u0131yor',
      subtitle: 'Ma\u00e7 sim\u00fclasyonu s\u00fcr\u00fcyor.',
      showTurnHud: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    InfoBadge(label: 'Tur ${_turnOf(effectiveGameState)}'),
                    InfoBadge(
                      label: 'Kalan S\u00fcre ${_formatCountdown(remaining)}',
                      color: AppColors.warning,
                    ),
                    InfoBadge(
                      label:
                          'Alt\u0131n ${(effectivePlayerData?['gold'] as num?)?.toInt() ?? 0}',
                      color: AppColors.gold,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ma\u00e7 oynan\u0131yor',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'S\u00fcre bitince canl\u0131 ma\u00e7 ekran\u0131na ge\u00e7ilecek.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 18),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 10,
                          value: (60 - remaining).clamp(0, 60) / 60,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final effectiveGameState = _effectiveGameState(session);
    final effectivePlayerData = _effectivePlayerData(
      session,
      effectiveGameState: effectiveGameState,
    );
    final currentTurn = _turnOf(effectiveGameState);
    final incomeTaken =
        (effectivePlayerData?['income_taken_for_turn'] as num?)?.toInt() ==
        currentTurn;
    final timeLeft = session.turnSecondsRemaining;
    final isMyTurn = _isMyTurnFor(
      session,
      effectiveGameState: effectiveGameState,
    );
    final phase = _phaseOf(effectiveGameState);

    if (phase == 'match_countdown') {
      return _buildMatchCountdownScreen(
        context,
        effectiveGameState: effectiveGameState,
        effectivePlayerData: effectivePlayerData,
        session: session,
      );
    }

    return GamePageScaffold(
      title: 'Draft Merkezi',
      subtitle: isMyTurn ? 'Sıra sende' : 'Rakip oynuyor',
      showTurnHud: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          SectionCard(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                InfoBadge(label: 'Tur $currentTurn'),
                InfoBadge(
                  label:
                      'Altın ${(effectivePlayerData?['gold'] as num?)?.toInt() ?? 0}',
                  color: AppColors.gold,
                ),
                InfoBadge(
                  label: isMyTurn
                      ? 'Süre ${timeLeft ?? '-'}'
                      : 'Rakip ${timeLeft ?? '-'}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                GameFilledButton(
                  onPressed: !isMyTurn || incomeTaken
                      ? null
                      : () => _guard(() => _getIncome(false)),
                  child: const Text('Gelir Al'),
                ),
                GameFilledButton(
                  onPressed: !isMyTurn || incomeTaken
                      ? null
                      : () => _guard(() => _getIncome(true)),
                  child: const Text('Risk Al'),
                ),
                _scoutingSoonButton(),
                GameOutlinedButton(
                  onPressed: () => _guard(_showFacilities),
                  child: const Text('Tesisler'),
                ),
                GameOutlinedButton(
                  onPressed: _showMyAugments,
                  child: const Text('Eklentilerim'),
                ),
                GameOutlinedButton(
                  onPressed: _showMatchHistory,
                  child: const Text('Geçmiş'),
                ),
                GameOutlinedButton(
                  onPressed: () => session.switchView(GameView.formation),
                  child: const Text('Diziliş'),
                ),
                GameOutlinedButton(
                  onPressed: () => session.switchView(GameView.tactics),
                  child: const Text('Taktik'),
                ),
                GameOutlinedButton(
                  onPressed: () => session.switchView(GameView.trade),
                  child: const Text('Takas'),
                ),
                GameFilledButton(
                  onPressed: !isMyTurn
                      ? null
                      : () => _guard(session.advanceCurrentTurn),
                  child: const Text('Turu Bitir'),
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
                  'Oyuncu Pazarı',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Kadron ve mağaza aynı merkezde. Sekmeler arasında anında geçiş yapabilirsin.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _inventoryTabButton(
                      index: 0,
                      label: 'Kadrom',
                      countLabel: '${myTeamData.length}/15 oyuncu',
                      icon: Icons.shield_rounded,
                    ),
                    const SizedBox(width: 10),
                    _inventoryTabButton(
                      index: 1,
                      label: 'Mağaza',
                      countLabel: '${shopPlayers.length} oyuncu',
                      icon: Icons.storefront_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey(_activeInventoryTab),
                    child: _buildInventoryPanel(
                      showShop: _activeInventoryTab == 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerCard(Map<String, dynamic> item, bool isShop) {
    final session = context.read<SessionController>();
    final canInteract = _isMyTurnFor(session);
    final data = Map<String, dynamic>.from(item['data'] as Map);
    final stats =
        (data['stats'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final displayPrice = isShop
        ? ((data['price'] as num?)?.toInt() ?? _marketPriceForPlayer(data))
        : _saleValueForPlayer(data);
    final priceLabel = isShop ? '$displayPrice G' : 'Satış $displayPrice G';
    final screenWidth = MediaQuery.sizeOf(context).width;
    final columns = screenWidth >= 760
        ? 3
        : screenWidth >= 520
        ? 2
        : 1;
    final usableWidth = screenWidth - 40 - ((columns - 1) * 12);
    final cardWidth = min(228.0, usableWidth / columns);

    return SizedBox(
      width: cardWidth,
      child: SectionCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    data['name'] as String? ?? 'Oyuncu',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Text(
                    '${data['rating'] ?? 0}',
                    style: const TextStyle(
                      color: AppColors.accentSoft,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InfoBadge(
                  label: data['mevki'] as String? ?? '-',
                  color: AppColors.info,
                ),
                InfoBadge(label: priceLabel, color: AppColors.gold),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Özellikler',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statChip('HÜC', stats['hucum']),
                _statChip('SAV', stats['savunma']),
                _statChip('ŞUT', stats['sut']),
                _statChip('PAS', stats['pas']),
                _statChip('DAY', stats['dayaniklilik']),
                _statChip('HIZ', stats['hiz']),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: GameFilledButton(
                onPressed: !canInteract
                    ? null
                    : () => _guard(
                        () => isShop
                            ? _buyPlayer(item['id'] as String, data)
                            : _sellPlayer(item['id'] as String, data),
                      ),
                style: FilledButton.styleFrom(
                  backgroundColor: isShop ? AppColors.accent : AppColors.danger,
                ),
                child: Text(isShop ? 'Satın Al' : 'Sat'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, dynamic value) {
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(value as num?)?.toInt() ?? 0}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
