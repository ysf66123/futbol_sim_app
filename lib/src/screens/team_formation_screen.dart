import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/session_controller.dart';
import '../data/game_data.dart';
import '../theme/app_theme.dart';
import '../utils/dialogs.dart';
import '../widgets/ui.dart';

const Map<String, Map<String, Alignment>> _formationAlignments = {
  '3-2-1': {
    'GK': Alignment(0, 0.8),
    'DEF1': Alignment(-0.58, 0.48),
    'DEF2': Alignment(0, 0.38),
    'DEF3': Alignment(0.58, 0.48),
    'MID1': Alignment(-0.28, -0.02),
    'MID2': Alignment(0.28, -0.02),
    'FWD1': Alignment(0, -0.42),
  },
  '2-3-1': {
    'GK': Alignment(0, 0.8),
    'DEF1': Alignment(-0.36, 0.48),
    'DEF2': Alignment(0.36, 0.48),
    'MID1': Alignment(-0.56, -0.02),
    'MID2': Alignment(0, -0.12),
    'MID3': Alignment(0.56, -0.02),
    'FWD1': Alignment(0, -0.42),
  },
  '2-2-2': {
    'GK': Alignment(0, 0.8),
    'DEF1': Alignment(-0.36, 0.48),
    'DEF2': Alignment(0.36, 0.48),
    'MID1': Alignment(-0.28, -0.01),
    'MID2': Alignment(0.28, -0.01),
    'FWD1': Alignment(-0.24, -0.42),
    'FWD2': Alignment(0.24, -0.42),
  },
};

class TeamFormationScreen extends StatefulWidget {
  const TeamFormationScreen({super.key});

  @override
  State<TeamFormationScreen> createState() => _TeamFormationScreenState();
}

class _TeamFormationScreenState extends State<TeamFormationScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _playerSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _teamSub;

  String teamName = 'Kulübüm';
  String formation = '3-2-1';
  Map<String, dynamic> formationSlots = {};
  List<Map<String, dynamic>> myTeam = const [];
  String? selectedPlayerId;
  String? captainId;

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

    _playerSub = roomRef
        .collection('players')
        .doc(session.playerId)
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data();
          if (data == null || !mounted) return;
          setState(() {
            teamName = data['team_name'] as String? ?? 'Kulübüm';
            formation = data['formation'] as String? ?? '3-2-1';
            formationSlots = Map<String, dynamic>.from(
              (data['formation_slots'] as Map?) ?? <String, dynamic>{},
            );
            captainId = data['captain_id'] as String?;
          });
        });

    _teamSub = roomRef
        .collection('players')
        .doc(session.playerId)
        .collection('my_team')
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          setState(() {
            myTeam = snapshot.docs
                .map((doc) => {'id': doc.id, 'data': doc.data()})
                .toList(growable: false);
          });
        });
  }

  List<String> get _activeSlots =>
      activeSlotsByFormation[formation] ?? const <String>[];

  List<String> get _pitchSlots => _activeSlots
      .where((slot) => !slot.startsWith('BENCH'))
      .toList(growable: false);

  List<String> get _benchSlots => _activeSlots
      .where((slot) => slot.startsWith('BENCH'))
      .toList(growable: false);

  List<String> _slotInstructions(String slot) {
    return List<String>.from(
      (((formationSlots[slot] as Map?)?['instructions']) as List?) ?? const [],
    );
  }

  String? _primaryInstructionForSlot(String slot) {
    return _slotInstructions(slot).firstOrNull;
  }

  double _playerMetric(Map<String, dynamic> player, String key) {
    final data = (player['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final value = (data[key] as num?)?.toDouble() ?? 5;
    return value.clamp(1.0, 10.0).toDouble();
  }

  double _playerMetricDelta(Map<String, dynamic> player, String key) {
    final data = (player['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ((data['${key}_last_delta'] as num?)?.toDouble() ?? 0)
        .clamp(-3.0, 3.0)
        .toDouble();
  }

  List<double> _playerHistory(Map<String, dynamic> player, String key) {
    final data = (player['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final raw = (data['${key}_history'] as List?) ?? const [];
    final values = raw
        .map((value) => (value as num?)?.toDouble() ?? 5)
        .where((value) => value > 0)
        .toList(growable: false);
    if (values.isNotEmpty) {
      return values.map((value) => value.clamp(1.0, 10.0).toDouble()).toList();
    }
    return [_playerMetric(player, key)];
  }

  String? _assignedSlotForPlayer(String playerId) {
    return formationSlots.entries
        .where((entry) => (entry.value as Map?)?['player_id'] == playerId)
        .map((entry) => entry.key)
        .firstOrNull;
  }

  double _averageMetric(String key) {
    if (myTeam.isEmpty) return 5;
    final total = myTeam.fold<double>(
      0,
      (totalValue, player) => totalValue + _playerMetric(player, key),
    );
    return total / myTeam.length;
  }

  int get _averageRating {
    final starters = _pitchSlots
        .map((slot) => (formationSlots[slot] as Map?)?['player_id'])
        .whereType<String>()
        .toList(growable: false);
    if (starters.isEmpty) return 0;
    var total = 0;
    for (final playerId in starters) {
      final player = _playerById(playerId);
      if (player == null) continue;
      total += (((player['data'] as Map)['rating'] as num?)?.toInt() ?? 0);
    }
    return (total / starters.length).round();
  }

  int get _outOfPositionCount {
    var total = 0;
    for (final slot in _pitchSlots) {
      final playerId = (formationSlots[slot] as Map?)?['player_id'] as String?;
      final player = _playerById(playerId);
      final mevki = ((player?['data'] as Map?)?['mevki'] as String?) ?? '';
      if (player != null && !(slotMevkiMap[slot] ?? const []).contains(mevki)) {
        total += 1;
      }
    }
    return total;
  }

  int get _starterCount => _pitchSlots
      .where((slot) => ((formationSlots[slot] as Map?)?['player_id']) != null)
      .length;

  int get _benchCount => _benchSlots
      .where((slot) => ((formationSlots[slot] as Map?)?['player_id']) != null)
      .length;

  int get _assignedInstructionCount => _pitchSlots
      .where((slot) => _primaryInstructionForSlot(slot) != null)
      .length;

  double get _lineupReadiness {
    final fillScore = _pitchSlots.isEmpty
        ? 0.0
        : _starterCount / _pitchSlots.length;
    final positionPenalty = _pitchSlots.isEmpty
        ? 0.0
        : _outOfPositionCount / _pitchSlots.length;
    final moraleBoost = ((_averageMetric('morale') - 5) / 10).clamp(-0.2, 0.2);
    final formBoost = ((_averageMetric('form') - 5) / 10).clamp(-0.2, 0.2);
    return (0.58 +
            fillScore * 0.34 -
            positionPenalty * 0.22 +
            moraleBoost +
            formBoost)
        .clamp(0.25, 0.98);
  }

  Future<void> _save() async {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null || session.playerId == null) return;

    final cleanSlots = <String, dynamic>{};
    for (final entry in formationSlots.entries) {
      final slotData = Map<String, dynamic>.from(
        (entry.value as Map?) ?? const <String, dynamic>{},
      );
      final playerId = slotData['player_id'];
      if (playerId != null) {
        final instructions = List<String>.from(
          (slotData['instructions'] as List?) ?? const [],
        );
        cleanSlots[entry.key] = {
          ...slotData,
          'instructions': instructions.isEmpty
              ? <String>[]
              : <String>[instructions.first],
        };
      }
    }

    await roomRef.collection('players').doc(session.playerId).update({
      'formation': formation,
      'formation_slots': cleanSlots,
      'captain_id': captainId,
    });
  }

  void _setFormation(String value) {
    if (formation == value) return;
    setState(() => formation = value);
    _save();
  }

  void _autoAssign() {
    final available =
        myTeam
            .where(
              (player) =>
                  ((player['data'] as Map)['status'] as String? ?? 'uygun') ==
                  'uygun',
            )
            .toList()
          ..sort(
            (a, b) => (((b['data'] as Map)['rating'] as num?)?.toInt() ?? 0)
                .compareTo(
                  ((a['data'] as Map)['rating'] as num?)?.toInt() ?? 0,
                ),
          );

    final newSlots = <String, Map<String, dynamic>>{
      for (final slot in _activeSlots)
        slot: {'player_id': null, 'instructions': <String>[]},
    };
    final placed = <String>{};

    for (final slot in _pitchSlots) {
      for (final player in available) {
        final id = player['id'] as String;
        final mevki = ((player['data'] as Map)['mevki'] as String?) ?? '';
        if (!placed.contains(id) &&
            (slotMevkiMap[slot] ?? const []).contains(mevki)) {
          newSlots[slot] = {'player_id': id, 'instructions': <String>[]};
          placed.add(id);
          break;
        }
      }
    }

    final remaining = available
        .where((player) => !placed.contains(player['id']))
        .toList(growable: false);
    for (
      var index = 0;
      index < remaining.length && index < _benchSlots.length;
      index++
    ) {
      newSlots[_benchSlots[index]] = {
        'player_id': remaining[index]['id'],
        'instructions': <String>[],
      };
    }

    captainId ??=
        newSlots['MID1']?['player_id'] as String? ??
        newSlots['FWD1']?['player_id'] as String? ??
        newSlots['GK']?['player_id'] as String?;

    setState(() => formationSlots = newSlots);
    _save();
  }

  void _selectPlayer(String id) {
    context.read<SessionController>().playClickSound();
    setState(() {
      selectedPlayerId = selectedPlayerId == id ? null : id;
    });
  }

  Map<String, dynamic>? _playerById(String? playerId) {
    return myTeam
        .where((item) => item['id'] == playerId)
        .cast<Map<String, dynamic>?>()
        .firstOrNull;
  }

  Future<void> _handleSlotTap(String slot) async {
    context.read<SessionController>().playClickSound();
    final current = Map<String, dynamic>.from(
      (formationSlots[slot] as Map?) ??
          {'player_id': null, 'instructions': <String>[]},
    );
    final currentPlayer = current['player_id'] as String?;

    if (selectedPlayerId != null) {
      final oldSlot = formationSlots.entries
          .where(
            (entry) => (entry.value as Map?)?['player_id'] == selectedPlayerId,
          )
          .map((entry) => entry.key)
          .firstOrNull;
      final selectedCurrent = oldSlot == null
          ? <String, dynamic>{
              'player_id': selectedPlayerId,
              'instructions': <String>[],
            }
          : Map<String, dynamic>.from(
              (formationSlots[oldSlot] as Map?) ??
                  {'player_id': selectedPlayerId, 'instructions': <String>[]},
            );

      if (oldSlot != null) {
        formationSlots[oldSlot] = {
          'player_id': null,
          'instructions': <String>[],
        };
      }
      if (currentPlayer != null && oldSlot != null) {
        formationSlots[oldSlot] = current;
      }
      formationSlots[slot] = {
        'player_id': selectedPlayerId,
        'instructions': selectedCurrent['instructions'] ?? <String>[],
      };
      setState(() => selectedPlayerId = null);
      await _save();
      return;
    }

    if (currentPlayer == null) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.midnight,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Talimatları Düzenle'),
                onTap: () {
                  Navigator.of(context).pop();
                  _editInstructions(slot, currentPlayer);
                },
              ),
              ListTile(
                title: Text(
                  currentPlayer == captainId
                      ? 'Kaptanlığı Kaldır'
                      : 'Kaptan Yap',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() {
                    captainId = currentPlayer == captainId
                        ? null
                        : currentPlayer;
                  });
                  _save();
                },
              ),
              ListTile(
                title: const Text('Sahadan Çek'),
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() {
                    if (captainId == currentPlayer) {
                      captainId = null;
                    }
                    formationSlots[slot] = {
                      'player_id': null,
                      'instructions': <String>[],
                    };
                  });
                  _save();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editInstructions(String slot, String playerId) async {
    final player = _playerById(playerId);
    if (player == null) return;

    final mevki = ((player['data'] as Map)['mevki'] as String?) ?? '';
    final bucket = mevki == 'Kaleci' ? 'GK' : slot.substring(0, 3);
    final options = playerInstructions[bucket] ?? const <String, String>{};

    if (options.isEmpty) {
      await showGameDialog(
        context,
        title: 'Bilgi',
        message: 'Bu pozisyon için özel talimat yok.',
      );
      return;
    }

    final current = List<String>.from(
      (((formationSlots[slot] as Map?)?['instructions']) as List?) ?? const [],
    );
    String? selected = current.firstOrNull;

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
            child: StatefulBuilder(
              builder: (context, setModalState) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _instructionChoiceTile(
                    title: 'Talimat Yok',
                    subtitle:
                        'Oyuncu temel rolünde kalsın, ekstra bireysel yönlendirme uygulanmasın.',
                    selected: selected == null,
                    onTap: () => setModalState(() => selected = null),
                  ),
                  ...options.entries.map(
                    (entry) => _instructionChoiceTile(
                      title: entry.key,
                      subtitle: entry.value,
                      selected: selected == entry.key,
                      onTap: () => setModalState(() => selected = entry.key),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: GameFilledButton(
                      onPressed: () {
                        formationSlots[slot] = {
                          'player_id': playerId,
                          'instructions': selected == null
                              ? <String>[]
                              : <String>[selected!],
                        };
                        _save();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Kaydet'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _instructionChoiceTile({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppColors.accent
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? AppColors.accent : AppColors.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
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

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final compact = viewportWidth < 480;
    final pitchAspectRatio = compact ? 1.02 : 1.12;
    final selectedPlayer = _playerById(selectedPlayerId);
    final selectedPlayerName = selectedPlayer == null
        ? null
        : ((selectedPlayer['data'] as Map)['name'] as String? ?? 'Oyuncu');
    final selectedPlayerSlot = selectedPlayerId == null
        ? null
        : _assignedSlotForPlayer(selectedPlayerId!);
    final captain = _playerById(captainId);
    final captainName = captain == null
        ? 'Belirlenmedi'
        : ((captain['data'] as Map)['name'] as String? ?? 'Oyuncu');
    final avgMorale = _averageMetric('morale');
    final avgForm = _averageMetric('form');
    final readinessPercent = (_lineupReadiness * 100).round();

    return GamePageScaffold(
      title: 'Diziliş',
      subtitle: selectedPlayerId == null
          ? 'İlk 11, kulübe ve roller tek ekranda sade biçimde düzenlenir.'
          : '$selectedPlayerName seçili. Uygun bir slota dokun.',
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
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                children: [
                  _broadcastHeroCard(
                    compact: compact,
                    captainName: captainName,
                    avgMorale: avgMorale,
                    avgForm: avgForm,
                    readinessPercent: readinessPercent,
                    selectedPlayerName: selectedPlayerName,
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Takım Planı',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Dizilişi seç, sonra oyuncuları sahaya veya kulübeye yerleştir.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final value in ['3-2-1', '2-3-1', '2-2-2'])
                              ChoiceChip(
                                label: Text(value),
                                selected: formation == value,
                                onSelected: (_) => _setFormation(value),
                                selectedColor: AppColors.accent.withValues(
                                  alpha: 0.22,
                                ),
                                backgroundColor: AppColors.panelSoft,
                                labelStyle: TextStyle(
                                  color: formation == value
                                      ? AppColors.accent
                                      : AppColors.text,
                                  fontWeight: FontWeight.w800,
                                ),
                                side: BorderSide(
                                  color: formation == value
                                      ? AppColors.accent.withValues(alpha: 0.34)
                                      : Colors.white.withValues(alpha: 0.08),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            GameOutlinedButton(
                              onPressed: _autoAssign,
                              child: const Text('Otomatik Yerleştir'),
                            ),
                            if (selectedPlayerId != null)
                              GameFilledButton(
                                onPressed: () =>
                                    setState(() => selectedPlayerId = null),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.info.withValues(
                                    alpha: 0.18,
                                  ),
                                  foregroundColor: AppColors.info,
                                ),
                                child: const Text('Seçimi Temizle'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 14 : 18,
                      compact ? 14 : 18,
                      compact ? 14 : 18,
                      compact ? 16 : 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Saha Yerleşimi',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            InfoBadge(label: formation, color: AppColors.info),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sahada yalnızca kritik bilgi görünür. Detaylı oyuncu kartları aşağıdadır.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            InfoBadge(
                              label: 'Ortalama $_averageRating OVR',
                              color: AppColors.gold,
                            ),
                            InfoBadge(
                              label: 'Hazırlık %$readinessPercent',
                              color: AppColors.accent,
                            ),
                            InfoBadge(
                              label: 'Moral ${avgMorale.toStringAsFixed(1)}',
                              color: AppColors.info,
                            ),
                            InfoBadge(
                              label: 'Form ${avgForm.toStringAsFixed(1)}',
                              color: AppColors.warning,
                            ),
                            InfoBadge(
                              label:
                                  '$_starterCount / ${_pitchSlots.length} ilk 11',
                              color: AppColors.info,
                            ),
                            InfoBadge(
                              label: _outOfPositionCount == 0
                                  ? 'Pozisyon uyumu tam'
                                  : 'Uyumsuz $_outOfPositionCount',
                              color: _outOfPositionCount == 0
                                  ? AppColors.accent
                                  : AppColors.warning,
                            ),
                          ],
                        ),
                        if (selectedPlayerName != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.info.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.info.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.touch_app_rounded,
                                  color: AppColors.info,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    selectedPlayerSlot == null
                                        ? '$selectedPlayerName için uygun bir saha slotu seç.'
                                        : '$selectedPlayerName şu anda $selectedPlayerSlot bölgesinde.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        AspectRatio(
                          aspectRatio: pitchAspectRatio,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final slotWidth =
                                  (constraints.maxWidth *
                                          (compact ? 0.17 : 0.142))
                                      .clamp(52.0, 68.0)
                                      .toDouble();
                              final slotHeight = compact ? 76.0 : 82.0;

                              return ClipRRect(
                                borderRadius: BorderRadius.circular(26),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF1F8B56),
                                        Color(0xFF0E5032),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: RadialGradient(
                                              center: Alignment.topLeft,
                                              radius: 1.4,
                                              colors: [
                                                Colors.white.withValues(
                                                  alpha: 0.16,
                                                ),
                                                Colors.transparent,
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const Positioned.fill(
                                        child: _PitchLines(),
                                      ),
                                      Positioned(
                                        left: 12,
                                        top: 12,
                                        child: Text(
                                          'HÜCUM',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.72,
                                            ),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: 12,
                                        bottom: 12,
                                        child: Text(
                                          'SAVUNMA',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.72,
                                            ),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ),
                                      ..._pitchSlots.map(
                                        (slot) => Align(
                                          alignment:
                                              _formationAlignments[formation]?[slot] ??
                                              Alignment.center,
                                          child: _pitchSlot(
                                            slot,
                                            compact: compact,
                                            width: slotWidth,
                                            height: slotHeight,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Kaptan: $captainName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.muted),
                              ),
                            ),
                            Text(
                              '$_assignedInstructionCount rol aktif',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: InfoBadge(
                                label: 'Kulübe',
                                color: AppColors.warning,
                              ),
                            ),
                            Text(
                              '$_benchCount / ${_benchSlots.length} dolu',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.muted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: compact ? 148 : 164,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _benchSlots.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) => _benchCard(
                              _benchSlots[index],
                              compact: compact,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Oyuncu Havuzu',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Kartı seç, sonra sahadaki uygun slotu güncelle.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: AppColors.muted),
                                  ),
                                ],
                              ),
                            ),
                            InfoBadge(
                              label: '${myTeam.length} oyuncu',
                              color: AppColors.info,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: myTeam
                              .map(
                                (player) =>
                                    _playerChip(player, compact: compact),
                              )
                              .toList(growable: false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _broadcastHeroCard({
    required bool compact,
    required String captainName,
    required double avgMorale,
    required double avgForm,
    required int readinessPercent,
    required String? selectedPlayerName,
  }) {
    final theme = Theme.of(context);
    final readiness = _lineupReadiness;
    final readinessColor = readiness >= 0.84
        ? AppColors.accent
        : readiness >= 0.68
        ? AppColors.gold
        : AppColors.warning;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF11243B), Color(0xFF091728)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 18,
        compact ? 16 : 18,
        compact ? 16 : 18,
        compact ? 18 : 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MATCHDAY STÜDYO',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.info,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      teamName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      selectedPlayerName == null
                          ? 'Sahadaki kartlar sade, detaylar aşağıda. Mobil kullanım için temiz tutuldu.'
                          : '$selectedPlayerName seçili. Uygun bir saha slotuna dokun.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(
                width: compact ? 88 : 96,
                height: compact ? 88 : 96,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border.all(
                    color: readinessColor.withValues(alpha: 0.45),
                    width: 2,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: readiness,
                        strokeWidth: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          readinessColor,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$readinessPercent%',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'hazır',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _broadcastStatCard(
                label: 'Diziliş',
                value: formation,
                hint: 'aktif saha planı',
                color: AppColors.info,
              ),
              _broadcastStatCard(
                label: 'Kaptan',
                value: captainName,
                hint: 'saha lideri',
                color: AppColors.gold,
                wide: true,
              ),
              _broadcastStatCard(
                label: 'Moral',
                value: avgMorale.toStringAsFixed(1),
                hint: 'takım ort.',
                color: AppColors.accent,
              ),
              _broadcastStatCard(
                label: 'Form',
                value: avgForm.toStringAsFixed(1),
                hint: 'takım ort.',
                color: AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hızlı Durum',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '$_averageRating OVR',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.gold,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: readiness,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    valueColor: AlwaysStoppedAnimation<Color>(readinessColor),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    InfoBadge(
                      label:
                          '$_starterCount / ${_pitchSlots.length} ilk 11 dolu',
                      color: AppColors.info,
                    ),
                    InfoBadge(
                      label: '$_benchCount / ${_benchSlots.length} kulübe dolu',
                      color: AppColors.warning,
                    ),
                    InfoBadge(
                      label: '$_assignedInstructionCount rol aktif',
                      color: AppColors.accent,
                    ),
                    InfoBadge(
                      label: _outOfPositionCount == 0
                          ? 'Pozisyon uyumu tam'
                          : '$_outOfPositionCount oyuncu uyumsuz',
                      color: _outOfPositionCount == 0
                          ? AppColors.accent
                          : AppColors.warning,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _broadcastStatCard({
    required String label,
    required String value,
    required String hint,
    required Color color,
    bool wide = false,
  }) {
    return Container(
      width: wide ? 180 : 132,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _compactName(String name) {
    final trimmed = name.trim();
    if (trimmed.length <= 10) return trimmed;
    final parts = trimmed.split(' ');
    if (parts.length >= 2 && parts.first.length <= 9) {
      return parts.first;
    }
    return '${trimmed.substring(0, 9)}…';
  }

  String _positionShortLabel(String mevki) {
    return switch (mevki) {
      'Kaleci' => 'KL',
      'Defans' => 'DF',
      'Orta Saha' => 'OS',
      'Forvet' => 'FV',
      _ => mevki,
    };
  }

  String _instructionBadge(String instruction) {
    return switch (instruction) {
      'Libero Kaleci' => 'LK',
      'Topu Kısa Kullan' => 'TK',
      'Uzun Oyna' => 'UO',
      'Alanı Kapat' => 'AK',
      'Sert Müdahale' => 'SM',
      'Bindirme Yap' => 'BY',
      'Oyunu Yavaşlat' => 'OY',
      'Riskli Pas' => 'RP',
      'Ceza Sahasına Koşu' => 'CK',
      'Önde Baskı' => 'ÖB',
      'Kanala Koş' => 'KK',
      'Hedef Santrfor' => 'HS',
      _ => instruction.characters.take(2).toString().toUpperCase(),
    };
  }

  Widget _pitchSlot(
    String slot, {
    required bool compact,
    required double width,
    required double height,
  }) {
    final slotData =
        (formationSlots[slot] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final playerId = slotData['player_id'] as String?;
    final player = _playerById(playerId);
    final name = player == null
        ? 'Boş'
        : ((player['data'] as Map)['name'] as String? ?? 'Oyuncu');
    final mevki = player == null
        ? slot
        : ((player['data'] as Map)['mevki'] as String? ?? '');
    final outOfPosition =
        player != null && !(slotMevkiMap[slot] ?? const []).contains(mevki);
    final highlighted = selectedPlayerId != null && playerId == null;
    final instruction = _primaryInstructionForSlot(slot);
    final rating =
        (((player?['data'] as Map?)?['rating'] as num?)?.toInt() ?? 0);
    final shortName = player == null ? 'Ekle' : _compactName(name);
    final shortPosition = player == null
        ? _positionShortLabel(
            (slotMevkiMap[slot] ?? const ['-']).firstOrNull ?? '-',
          )
        : _positionShortLabel(mevki);
    final accentColor = outOfPosition
        ? AppColors.warning
        : playerId == captainId
        ? AppColors.gold
        : highlighted
        ? AppColors.info
        : AppColors.accent;

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleSlotTap(slot),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 8,
              vertical: compact ? 6 : 7,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(
                alpha: player == null ? 0.14 : 0.24,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: accentColor.withValues(
                  alpha: player == null ? 0.40 : 0.82,
                ),
                width: playerId == captainId ? 1.7 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: player == null ? 0.10 : 0.18,
                  ),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        slot,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 8.8 : 9.2,
                        ),
                      ),
                    ),
                    if (instruction != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Text(
                          _instructionBadge(instruction),
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: compact ? 28 : 32,
                          height: compact ? 28 : 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: player == null
                                ? Colors.white.withValues(alpha: 0.06)
                                : accentColor.withValues(alpha: 0.18),
                            border: Border.all(
                              color: accentColor.withValues(
                                alpha: player == null ? 0.28 : 0.74,
                              ),
                              width: 1.2,
                            ),
                          ),
                          child: Icon(
                            player == null
                                ? Icons.add_rounded
                                : playerId == captainId
                                ? Icons.workspace_premium_rounded
                                : Icons.sports_soccer_rounded,
                            size: compact ? 15 : 17,
                            color: playerId == captainId
                                ? AppColors.gold
                                : accentColor,
                          ),
                        ),
                        if (player != null)
                          Positioned(
                            right: -2,
                            top: -5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.midnight,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.10),
                                ),
                              ),
                              child: Text(
                                '$rating',
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 8.6,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            shortName,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: compact ? 9.2 : 9.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            shortPosition,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 8.2 : 8.8,
                              color: outOfPosition
                                  ? AppColors.warning
                                  : Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (playerId == captainId) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Kaptan',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: compact ? 7.8 : 8.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ] else if (player == null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Boş Slot',
                    style: TextStyle(
                      color: highlighted ? AppColors.info : Colors.white54,
                      fontSize: compact ? 7.8 : 8.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ] else
                  const SizedBox(height: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _benchCard(String slot, {required bool compact}) {
    final slotData =
        (formationSlots[slot] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final playerId = slotData['player_id'] as String?;
    final player = _playerById(playerId);
    final name = player == null
        ? 'Boş'
        : ((player['data'] as Map)['name'] as String? ?? 'Oyuncu');
    final mevki = player == null
        ? 'Yedek'
        : ((player['data'] as Map)['mevki'] as String? ?? '');
    final instruction = _primaryInstructionForSlot(slot);
    final morale = player == null ? 5.0 : _playerMetric(player, 'morale');
    final form = player == null ? 5.0 : _playerMetric(player, 'form');

    return SizedBox(
      width: compact ? 152 : 168,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleSlotTap(slot),
          borderRadius: BorderRadius.circular(18),
          child: SectionCard(
            padding: EdgeInsets.all(compact ? 12 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(mevki, style: const TextStyle(color: AppColors.muted)),
                if (instruction != null) ...[
                  const SizedBox(height: 8),
                  _pillLabel(instruction, color: AppColors.accent),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _metricMiniBox('Moral', morale, AppColors.info),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricMiniBox('Form', form, AppColors.accent),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerChip(Map<String, dynamic> player, {required bool compact}) {
    final data = (player['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final status = data['status'] as String? ?? 'uygun';
    final disabled = status != 'uygun';
    final assignedSlot = _assignedSlotForPlayer(player['id'] as String);
    final instruction = assignedSlot == null
        ? null
        : _primaryInstructionForSlot(assignedSlot);
    final morale = _playerMetric(player, 'morale');
    final form = _playerMetric(player, 'form');
    final moraleDelta = _playerMetricDelta(player, 'morale');
    final formDelta = _playerMetricDelta(player, 'form');
    final selected = selectedPlayerId == player['id'];

    return SizedBox(
      width: compact ? 168 : 188,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : () => _selectPlayer(player['id'] as String),
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.all(compact ? 12 : 14),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.info.withValues(alpha: 0.14)
                  : AppColors.panelSoft,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected
                    ? AppColors.info
                    : disabled
                    ? AppColors.warning.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.08),
                width: selected ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: selected ? 0.24 : 0.16),
                  blurRadius: selected ? 22 : 16,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        data['name'] as String? ?? 'Oyuncu',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${data['rating'] ?? 0}',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pillLabel(
                      data['mevki'] as String? ?? '-',
                      color: AppColors.text,
                    ),
                    if (assignedSlot != null)
                      _pillLabel(assignedSlot, color: AppColors.info),
                    if (instruction != null)
                      _pillLabel(instruction, color: AppColors.accent),
                    if (disabled)
                      _pillLabel(
                        status,
                        color: status == 'sakat'
                            ? AppColors.warning
                            : status == 'cezalı'
                            ? AppColors.danger
                            : AppColors.muted,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _statPill('HÜC', '${data['stats']?['hucum'] ?? 0}'),
                    _statPill('SAV', '${data['stats']?['savunma'] ?? 0}'),
                    _statPill('PAS', '${data['stats']?['pas'] ?? 0}'),
                    _statPill('ŞUT', '${data['stats']?['sut'] ?? 0}'),
                    _statPill('HIZ', '${data['stats']?['hiz'] ?? 0}'),
                    _statPill('DYN', '${data['stats']?['dayaniklilik'] ?? 0}'),
                  ],
                ),
                const SizedBox(height: 12),
                _metricTrendCard(
                  label: 'Moral',
                  value: morale,
                  delta: moraleDelta,
                  history: _playerHistory(player, 'morale'),
                  color: AppColors.info,
                ),
                const SizedBox(height: 8),
                _metricTrendCard(
                  label: 'Form',
                  value: form,
                  delta: formDelta,
                  history: _playerHistory(player, 'form'),
                  color: AppColors.accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricMiniBox(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$label ${value.toStringAsFixed(1)}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 10.5,
          ),
        ),
      ),
    );
  }

  Widget _pillLabel(String text, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: color == AppColors.text ? 0.08 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color == AppColors.text
              ? Colors.white.withValues(alpha: 0.08)
              : color.withValues(alpha: 0.26),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color == AppColors.text ? Colors.white70 : color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _statPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 10.8),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricTrendCard({
    required String label,
    required double value,
    required double delta,
    required List<double> history,
    required Color color,
  }) {
    final tone = delta > 0.05
        ? AppColors.accent
        : delta < -0.05
        ? AppColors.danger
        : AppColors.muted;
    final deltaPrefix = delta > 0 ? '+' : '';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                value.toStringAsFixed(1),
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Text(
                '$deltaPrefix${delta.toStringAsFixed(1)}',
                style: TextStyle(
                  color: tone,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 30,
            child: _TrendSparkline(values: history, color: color),
          ),
        ],
      ),
    );
  }
}

class _TrendSparkline extends StatelessWidget {
  const _TrendSparkline({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrendSparklinePainter(values: values, color: color),
      child: const SizedBox.expand(),
    );
  }
}

class _TrendSparklinePainter extends CustomPainter {
  const _TrendSparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final normalized = values
        .map((value) => value.clamp(1.0, 10.0).toDouble())
        .toList(growable: false);
    final minValue = normalized.reduce(math.min);
    final maxValue = normalized.reduce(math.max);
    final range = math.max(0.6, maxValue - minValue);
    final step = normalized.length == 1
        ? 0.0
        : size.width / (normalized.length - 1);
    final points = <Offset>[
      for (var index = 0; index < normalized.length; index++)
        Offset(
          step * index,
          size.height -
              (((normalized[index] - minValue) / range) * (size.height - 4)) -
              2,
        ),
    ];

    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath
      ..lineTo(points.last.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.26), color.withValues(alpha: 0.02)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final strokePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      strokePath.lineTo(points[index].dx, points[index].dy);
    }
    canvas.drawPath(strokePath, strokePaint);

    final endPaint = Paint()..color = color;
    canvas.drawCircle(points.last, 3.2, endPaint);
  }

  @override
  bool shouldRepaint(covariant _TrendSparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}

class _PitchLines extends StatelessWidget {
  const _PitchLines();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var index = 0; index < 6; index++)
          Positioned.fill(
            child: Align(
              alignment: Alignment(0, -1 + (index * 0.4)),
              child: Container(
                height: 30,
                color: Colors.white.withValues(
                  alpha: index.isEven ? 0.025 : 0.055,
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.58),
                width: 2,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Align(
            alignment: Alignment.center,
            child: Container(
              width: 2,
              color: Colors.white.withValues(alpha: 0.58),
            ),
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.54),
                width: 2,
              ),
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, 0.86),
          child: Container(
            width: 130,
            height: 58,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.54),
                width: 2,
              ),
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, -0.86),
          child: Container(
            width: 130,
            height: 58,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.54),
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
