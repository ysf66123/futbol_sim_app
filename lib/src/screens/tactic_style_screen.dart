import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/session_controller.dart';
import '../data/game_data.dart';
import '../services/match_engine.dart';
import '../theme/app_theme.dart';
import '../utils/dialogs.dart';
import '../widgets/ui.dart';

class TacticStyleScreen extends StatefulWidget {
  const TacticStyleScreen({super.key});

  @override
  State<TacticStyleScreen> createState() => _TacticStyleScreenState();
}

class _TacticStyleScreenState extends State<TacticStyleScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _playerSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _teamSub;

  List<Map<String, dynamic>> myTeam = const [];
  Map<String, dynamic> formationSlots = {};
  String? captainId;
  Map<String, dynamic> setPieceTakers = {'pen': null, 'fk': null, 'cor': null};

  String mentality = 'Dengeli';
  String buildUpPlay = 'Dengeli';
  String focusPlay = 'Karma';
  String crossingType = 'Yüksek Orta';
  String defensiveLine = 'Normal';
  bool offsideTrap = false;
  String pressingTrigger = 'Dengeli';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startListeners());
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _teamSub?.cancel();
    super.dispose();
  }

  void _startListeners() {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null || session.playerId == null) return;

    _playerSub = roomRef.collection('players').doc(session.playerId).snapshots().listen((snapshot) {
      final data = snapshot.data();
      if (data == null || !mounted) return;
      setState(() {
        mentality = data['mentality'] as String? ?? 'Dengeli';
        buildUpPlay = data['build_up_play'] as String? ?? 'Dengeli';
        focusPlay = data['focus_play'] as String? ?? 'Karma';
        crossingType = data['crossing_type'] as String? ?? 'Yüksek Orta';
        defensiveLine = data['defensive_line'] as String? ?? 'Normal';
        offsideTrap = data['offside_trap'] == true;
        pressingTrigger = data['pressing_trigger'] as String? ?? 'Dengeli';
        captainId = data['captain_id'] as String?;
        setPieceTakers = Map<String, dynamic>.from((data['set_piece_takers'] as Map?) ?? {'pen': null, 'fk': null, 'cor': null});
        formationSlots = Map<String, dynamic>.from((data['formation_slots'] as Map?) ?? {});
      });
    });
    _teamSub = roomRef.collection('players').doc(session.playerId).collection('my_team').snapshots().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        myTeam = snapshot.docs.map((doc) => {'id': doc.id, 'data': doc.data()}).toList(growable: false);
      });
    });
  }

  Future<void> _save() async {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null || session.playerId == null) return;
    await roomRef.collection('players').doc(session.playerId).update({
      'mentality': mentality,
      'build_up_play': buildUpPlay,
      'focus_play': focusPlay,
      'crossing_type': crossingType,
      'defensive_line': defensiveLine,
      'offside_trap': offsideTrap,
      'pressing_trigger': pressingTrigger,
      'captain_id': captainId,
      'set_piece_takers': setPieceTakers,
    });
  }

  List<DropdownMenuItem<String?>> _playerItems(String placeholder) {
    final items = <DropdownMenuItem<String?>>[
      DropdownMenuItem<String?>(value: null, child: Text(placeholder)),
    ];
    for (final player in myTeam) {
      final data = player['data'] as Map;
      if ((data['status'] as String? ?? 'uygun') == 'uygun') {
        items.add(DropdownMenuItem<String?>(value: player['id'] as String, child: Text(data['name'] as String? ?? 'Oyuncu')));
      }
    }
    return items;
  }

  int get _averageRating {
    final active = formationSlots.entries.where((entry) => !entry.key.startsWith('BENCH')).toList();
    if (active.isEmpty) return 0;
    var total = 0;
    for (final entry in active) {
      final playerId = (entry.value as Map?)?['player_id'] as String?;
      final player = myTeam.where((item) => item['id'] == playerId).cast<Map<String, dynamic>?>().firstOrNull;
      if (player == null) continue;
      final data = player['data'] as Map<String, dynamic>;
      var rating = (data['rating'] as num?)?.toInt() ?? 0;
      if (playerId == captainId) {
        final boosted = Map<String, dynamic>.from(data['stats'] as Map);
        for (final key in boosted.keys.toList()) {
          boosted[key] = ((boosted[key] as num?)?.toInt() ?? 0) + 5;
        }
        rating = calculateRating(boosted, data['mevki'] as String? ?? 'Orta Saha');
      }
      total += rating;
    }
    return (total / active.length).floor();
  }

  @override
  Widget build(BuildContext context) {
    return GamePageScaffold(
      title: 'Taktik',
      subtitle: 'Ortalama reyting $_averageRating',
      actions: [
        GameIconButton(onPressed: () => context.read<SessionController>().switchView(GameView.draft), icon: const Icon(Icons.close_rounded)),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mentalite', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: ['Çok Defansif', 'Defansif', 'Dengeli', 'Hücum', 'Topyekûn Hücum']
                      .map((value) => GameFilledButton(
                            onPressed: () {
                              setState(() => mentality = value);
                              _save();
                            },
                            style: FilledButton.styleFrom(backgroundColor: mentality == value ? AppColors.accent : AppColors.panel),
                            child: Text(value),
                          ))
                      .toList(growable: false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            child: Column(
              children: [
                _dropdown('Oyun Kurma', buildUpPlay, ['Yavaş', 'Dengeli', 'Hızlı'], (value) {
                  setState(() => buildUpPlay = value!);
                  _save();
                }),
                const SizedBox(height: 12),
                _dropdown('Pas Odağı', focusPlay, ['Karma', 'Merkezden', 'Kanatlardan'], (value) {
                  setState(() => focusPlay = value!);
                  _save();
                }),
                const SizedBox(height: 12),
                _dropdown('Orta Tipi', crossingType, ['Yüksek Orta', 'Yer Orta'], (value) {
                  setState(() => crossingType = value!);
                  _save();
                }),
                const SizedBox(height: 12),
                _dropdown('Savunma Çizgisi', defensiveLine, ['Derin Savunma', 'Normal', 'İleride Kur'], (value) {
                  setState(() => defensiveLine = value!);
                  _save();
                }),
                const SizedBox(height: 12),
                _dropdown('Pres', pressingTrigger, ['Dengeli', 'Top Kaybından Sonra', 'Sürekli Baskı'], (value) {
                  setState(() => pressingTrigger = value!);
                  _save();
                }),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: offsideTrap,
                  title: const Text('Ofsayt Taktiği'),
                  onChanged: (value) {
                    setState(() => offsideTrap = value);
                    _save();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kaptan ve Duran Toplar', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: captainId,
                  items: _playerItems('Kaptan Seç'),
                  onChanged: (value) {
                    setState(() => captainId = value);
                    _save();
                  },
                  decoration: const InputDecoration(labelText: 'Kaptan'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: setPieceTakers['pen'] as String?,
                  items: _playerItems('Penaltıcı Seç'),
                  onChanged: (value) {
                    setPieceTakers['pen'] = value;
                    _save();
                  },
                  decoration: const InputDecoration(labelText: 'Penaltı'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: setPieceTakers['fk'] as String?,
                  items: _playerItems('Frikikçi Seç'),
                  onChanged: (value) {
                    setPieceTakers['fk'] = value;
                    _save();
                  },
                  decoration: const InputDecoration(labelText: 'Serbest Vuruş'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: setPieceTakers['cor'] as String?,
                  items: _playerItems('Kornerci Seç'),
                  onChanged: (value) {
                    setPieceTakers['cor'] = value;
                    _save();
                  },
                  decoration: const InputDecoration(labelText: 'Korner'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Taktik Bilgileri', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: infoTexts.entries
                      .map((entry) => GameOutlinedButton(
                            onPressed: () => showGameDialog(context, title: 'Taktik Bilgisi', message: entry.value),
                            child: Text(entry.key),
                          ))
                      .toList(growable: false),
                ),
                const SizedBox(height: 12),
                const InfoBadge(label: 'Uyum, oyun planı ile hesaplanır', color: AppColors.info),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(
    String label,
    String value,
    List<String> items,
    void Function(String?) onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items.map((item) => DropdownMenuItem<String>(value: item, child: Text(item))).toList(growable: false),
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
