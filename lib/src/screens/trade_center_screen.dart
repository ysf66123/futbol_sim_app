import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/session_controller.dart';
import '../services/room_game_service.dart';
import '../utils/dialogs.dart';
import '../utils/game_exception.dart';
import '../widgets/ui.dart';

class TradeCenterScreen extends StatefulWidget {
  const TradeCenterScreen({super.key});

  @override
  State<TradeCenterScreen> createState() => _TradeCenterScreenState();
}

class _TradeCenterScreenState extends State<TradeCenterScreen> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _myTeamSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _opponentTeamSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tradeSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _playerSub;

  final _offerGoldController = TextEditingController();
  final _requestGoldController = TextEditingController();

  Map<String, Map<String, dynamic>> myTeam = {};
  Map<String, Map<String, dynamic>> opponentTeam = {};
  Map<String, String> myOfferPlayers = {};
  Map<String, String> myRequestPlayers = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> incomingOffers = const [];
  int myGold = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startListeners());
  }

  @override
  void dispose() {
    _myTeamSub?.cancel();
    _opponentTeamSub?.cancel();
    _tradeSub?.cancel();
    _playerSub?.cancel();
    _offerGoldController.dispose();
    _requestGoldController.dispose();
    super.dispose();
  }

  void _startListeners() {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null ||
        session.playerId == null ||
        session.opponentId == null) {
      return;
    }

    _myTeamSub = roomRef
        .collection('players')
        .doc(session.playerId)
        .collection('my_team')
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          setState(
            () =>
                myTeam = {for (final doc in snapshot.docs) doc.id: doc.data()},
          );
        });
    _playerSub = roomRef
        .collection('players')
        .doc(session.playerId)
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          setState(
            () => myGold = (snapshot.data()?['gold'] as num?)?.toInt() ?? 0,
          );
        });
    _opponentTeamSub = roomRef
        .collection('players')
        .doc(session.opponentId)
        .collection('my_team')
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          setState(
            () => opponentTeam = {
              for (final doc in snapshot.docs) doc.id: doc.data(),
            },
          );
        });
    _tradeSub = roomRef
        .collection('trades')
        .where('to_player_id', isEqualTo: session.playerId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          setState(() => incomingOffers = snapshot.docs);
        });
  }

  void _toggleOffer(String id) {
    setState(() {
      if (myOfferPlayers.containsKey(id)) {
        myOfferPlayers.remove(id);
      } else {
        myOfferPlayers[id] = myTeam[id]?['name'] as String? ?? 'Oyuncu';
      }
    });
  }

  void _toggleRequest(String id) {
    setState(() {
      if (myRequestPlayers.containsKey(id)) {
        myRequestPlayers.remove(id);
      } else {
        myRequestPlayers[id] = opponentTeam[id]?['name'] as String? ?? 'Oyuncu';
      }
    });
  }

  Future<void> _sendOffer() async {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null ||
        session.playerId == null ||
        session.opponentId == null) {
      return;
    }

    final offerGold = int.tryParse(_offerGoldController.text) ?? 0;
    final requestGold = int.tryParse(_requestGoldController.text) ?? 0;
    final currentState =
        (await roomRef.collection('game_state').doc('current').get()).data() ??
        <String, dynamic>{};
    final currentTurn = (currentState['current_turn'] as num?)?.toInt() ?? 0;
    if (myOfferPlayers.isEmpty && offerGold == 0) {
      throw GameException(
        'Hata',
        'Teklifinde en az bir oyuncu veya altın olmalı.',
      );
    }
    if (offerGold > myGold) {
      throw GameException('Hata', 'Teklif edecek kadar altının yok.');
    }

    await roomRef.collection('trades').add({
      'from_player_id': session.playerId,
      'to_player_id': session.opponentId,
      'offer_players': myOfferPlayers,
      'offer_gold': offerGold,
      'request_players': myRequestPlayers,
      'request_gold': requestGold,
      'status': 'pending',
      'turn': currentTurn,
    });

    setState(() {
      myOfferPlayers = {};
      myRequestPlayers = {};
      _offerGoldController.clear();
      _requestGoldController.clear();
    });
    if (!mounted) return;
    showGameSnack(context, 'Teklif rakibe iletildi.');
  }

  Future<void> _sendOfferFromUi() async {
    try {
      await _sendOffer();
    } on GameException catch (error) {
      if (!mounted) return;
      await showGameDialog(context, title: error.title, message: error.message);
    }
  }

  Future<void> _declineOffer(String id) async {
    final roomRef = context.read<SessionController>().roomRef;
    if (roomRef == null) return;
    await roomRef.collection('trades').doc(id).update({'status': 'declined'});
  }

  Future<void> _acceptOffer(String id) async {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null || session.playerId == null) return;

    final offerDoc = await roomRef.collection('trades').doc(id).get();
    final offer = offerDoc.data();
    if (offer == null) return;

    final me = offer['to_player_id'] as String;
    final opponent = offer['from_player_id'] as String;
    final myDoc =
        (await roomRef.collection('players').doc(me).get()).data() ??
        <String, dynamic>{};
    final oppDoc =
        (await roomRef.collection('players').doc(opponent).get()).data() ??
        <String, dynamic>{};
    if (((myDoc['gold'] as num?)?.toInt() ?? 0) <
        ((offer['request_gold'] as num?)?.toInt() ?? 0)) {
      throw GameException('Hata', 'Teklifi karşılayacak altının yok.');
    }
    if (((oppDoc['gold'] as num?)?.toInt() ?? 0) <
        ((offer['offer_gold'] as num?)?.toInt() ?? 0)) {
      throw GameException(
        'Hata',
        'Teklifi gönderen oyuncunun yeterli altını kalmamış.',
      );
    }

    final batch = roomRef.firestore.batch();
    final myRef = roomRef.collection('players').doc(me);
    final oppRef = roomRef.collection('players').doc(opponent);
    final myDepartingPlayers = <String>[];
    final opponentDepartingPlayers = <String>[];
    batch.update(myRef, {
      'gold': FieldValue.increment(
        ((offer['offer_gold'] as num?)?.toInt() ?? 0) -
            ((offer['request_gold'] as num?)?.toInt() ?? 0),
      ),
    });
    batch.update(oppRef, {
      'gold': FieldValue.increment(
        ((offer['request_gold'] as num?)?.toInt() ?? 0) -
            ((offer['offer_gold'] as num?)?.toInt() ?? 0),
      ),
    });

    for (final playerId in (offer['offer_players'] as Map).keys) {
      final playerRef = oppRef.collection('my_team').doc(playerId);
      final playerData = (await playerRef.get()).data();
      if (playerData != null) {
        opponentDepartingPlayers.add(playerId.toString());
        batch.delete(playerRef);
        batch.set(myRef.collection('my_team').doc(playerId), playerData);
        batch.update(roomRef.collection('player_pool').doc(playerId), {
          'owner_id': me,
        });
      }
    }
    for (final playerId in (offer['request_players'] as Map).keys) {
      final playerRef = myRef.collection('my_team').doc(playerId);
      final playerData = (await playerRef.get()).data();
      if (playerData != null) {
        myDepartingPlayers.add(playerId.toString());
        batch.delete(playerRef);
        batch.set(oppRef.collection('my_team').doc(playerId), playerData);
        batch.update(roomRef.collection('player_pool').doc(playerId), {
          'owner_id': opponent,
        });
      }
    }
    final myCleanupUpdate = RoomGameService.buildRosterCleanupUpdate(
      myDoc,
      myDepartingPlayers,
    );
    if (myCleanupUpdate.isNotEmpty) {
      batch.update(myRef, myCleanupUpdate);
    }
    final opponentCleanupUpdate = RoomGameService.buildRosterCleanupUpdate(
      oppDoc,
      opponentDepartingPlayers,
    );
    if (opponentCleanupUpdate.isNotEmpty) {
      batch.update(oppRef, opponentCleanupUpdate);
    }
    batch.update(roomRef.collection('trades').doc(id), {'status': 'accepted'});
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return GamePageScaffold(
      title: 'Takas Merkezi',
      actions: [
        GameIconButton(
          onPressed: () =>
              context.read<SessionController>().switchView(GameView.draft),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yeni Teklif',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _offerGoldController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Teklif edeceğin altın',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _requestGoldController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'İstediğin altın',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: myTeam.entries
                      .where((entry) => entry.value['is_loan'] != true)
                      .map(
                        (entry) => FilterChip(
                          label: Text(
                            entry.value['name'] as String? ?? entry.key,
                          ),
                          selected: myOfferPlayers.containsKey(entry.key),
                          onSelected: (_) => _toggleOffer(entry.key),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: opponentTeam.entries
                      .where((entry) => entry.value['is_loan'] != true)
                      .map(
                        (entry) => FilterChip(
                          label: Text(
                            entry.value['name'] as String? ?? entry.key,
                          ),
                          selected: myRequestPlayers.containsKey(entry.key),
                          onSelected: (_) => _toggleRequest(entry.key),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 16),
                GameFilledButton(
                  onPressed: _sendOfferFromUi,
                  child: const Text('Teklif Gönder'),
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
                  'Gelen Teklifler (${incomingOffers.length})',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (incomingOffers.isEmpty)
                  const Text('Bekleyen teklif yok.')
                else
                  ...incomingOffers.map(
                    (offerDoc) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _offerTile(context, offerDoc),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _offerTile(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Teklif Eden: ${data['from_player_id']}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Teklif Oyuncuları: ${((data['offer_players'] as Map?)?.values.join(', ')) ?? 'Yok'}',
          ),
          Text('Teklif Altını: ${data['offer_gold'] ?? 0}'),
          Text(
            'İstenen Oyuncular: ${((data['request_players'] as Map?)?.values.join(', ')) ?? 'Yok'}',
          ),
          Text('İstenen Altın: ${data['request_gold'] ?? 0}'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GameFilledButton(
                  onPressed: () async {
                    try {
                      await _acceptOffer(doc.id);
                    } on GameException catch (error) {
                      if (!context.mounted) return;
                      await showGameDialog(
                        context,
                        title: error.title,
                        message: error.message,
                      );
                    }
                  },
                  child: const Text('Kabul Et'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GameOutlinedButton(
                  onPressed: () => _declineOffer(doc.id),
                  child: const Text('Reddet'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
