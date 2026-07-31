import 'dart:math';

int _intValue(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double _doubleValue(dynamic value, [double fallback = 0]) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

double _clampDouble(double value, double minValue, double maxValue) {
  if (value < minValue) return minValue;
  if (value > maxValue) return maxValue;
  return value;
}

double _amplifyBonus(
  double value,
  double baseline,
  double effectiveness, {
  bool lowerIsBetter = false,
}) {
  if (effectiveness <= 1.0) return value;
  if (lowerIsBetter) {
    if (value >= baseline) return value;
    return baseline - (baseline - value) * effectiveness;
  }
  if (value <= baseline) return value;
  return baseline + (value - baseline) * effectiveness;
}

Map<String, int> _statMap(dynamic value) {
  final source =
      (value as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  return source.map((key, val) => MapEntry(key, _intValue(val)));
}

Map<String, dynamic> _instructionProfile(List<String> instructions) {
  final statBoosts = <String, int>{};

  void addStat(String key, int amount) {
    statBoosts[key] = (statBoosts[key] ?? 0) + amount;
  }

  var staminaLoad = 0.0;
  var disciplineRisk = 0.0;
  var injuryRisk = 0.0;
  var chanceFreq = 0.0;
  var chanceQual = 0.0;
  var pressBonus = 0.0;
  var tempoDelta = 0.0;
  var offsideRisk = 0.0;
  var defensiveShape = 0.0;
  var crossFocus = 0.0;
  var passBonus = 0.0;
  var finishBonus = 0.0;
  var riskPass = 0.0;

  for (final instruction in instructions) {
    switch (instruction) {
      case 'Libero Kaleci':
        addStat('savunma', 4);
        addStat('hiz', 4);
        defensiveShape += 0.03;
        break;
      case 'Topu Kısa Kullan':
        addStat('pas', 6);
        passBonus += 0.04;
        tempoDelta -= 0.03;
        break;
      case 'Uzun Oyna':
        addStat('pas', 3);
        chanceFreq += 0.03;
        chanceQual -= 0.01;
        break;
      case 'Alanı Kapat':
        addStat('savunma', 6);
        defensiveShape += 0.08;
        offsideRisk -= 0.02;
        break;
      case 'Sert Müdahale':
        addStat('savunma', 4);
        disciplineRisk += 0.18;
        injuryRisk += 0.14;
        break;
      case 'Bindirme Yap':
        addStat('pas', 3);
        addStat('hucum', 4);
        chanceFreq += 0.03;
        staminaLoad += 0.10;
        defensiveShape -= 0.04;
        crossFocus += 0.05;
        break;
      case 'Oyunu Yavaşlat':
        addStat('pas', 6);
        tempoDelta -= 0.07;
        chanceQual += 0.05;
        passBonus += 0.05;
        break;
      case 'Riskli Pas':
        addStat('pas', 4);
        addStat('hucum', 3);
        chanceFreq += 0.05;
        chanceQual += 0.02;
        riskPass += 0.08;
        break;
      case 'Ceza Sahasına Koşu':
        addStat('hucum', 6);
        addStat('sut', 4);
        chanceFreq += 0.04;
        finishBonus += 0.05;
        staminaLoad += 0.10;
        break;
      case 'Önde Baskı':
        pressBonus += 0.10;
        staminaLoad += 0.10;
        disciplineRisk += 0.03;
        break;
      case 'Kanala Koş':
        addStat('hiz', 5);
        addStat('hucum', 3);
        offsideRisk += 0.08;
        chanceFreq += 0.03;
        break;
      case 'Hedef Santrfor':
        addStat('pas', 5);
        addStat('hucum', 2);
        chanceQual += 0.05;
        crossFocus += 0.08;
        finishBonus += 0.03;
        break;
    }
  }

  return {
    'stat_boosts': statBoosts,
    'stamina_load': staminaLoad,
    'discipline_risk': disciplineRisk,
    'injury_risk': injuryRisk,
    'chance_freq': chanceFreq,
    'chance_qual': chanceQual,
    'press_bonus': pressBonus,
    'tempo_delta': tempoDelta,
    'offside_risk': offsideRisk,
    'defensive_shape': defensiveShape,
    'cross_focus': crossFocus,
    'pass_bonus': passBonus,
    'finish_bonus': finishBonus,
    'risk_pass': riskPass,
  };
}

void _applyInstructionStatBoosts(
  Map<String, int> matchStats,
  Map<String, dynamic> profile,
) {
  final boosts =
      (profile['stat_boosts'] as Map?)?.cast<String, dynamic>() ??
      <String, dynamic>{};
  for (final entry in boosts.entries) {
    matchStats[entry.key] =
        (matchStats[entry.key] ?? 0) + _intValue(entry.value);
  }
}

int calculateRating(Map<String, dynamic> statsDict, String mevki) {
  final total = statsDict.values.fold<int>(
    0,
    (sum, value) => sum + _intValue(value),
  );
  if (mevki == 'Kaleci') {
    return (total / 4).floor();
  }
  return (total / 5.2).round();
}

int calculatePrice(int rating) {
  if (rating >= 85) return (rating * 5.8).toInt();
  if (rating >= 80) return (rating * 5.2).toInt();
  if (rating >= 70) return rating * 4;
  return rating * 3;
}

List<String> getPositionFromSlot(String slotName) {
  if (slotName.startsWith('GK')) return const ['Kaleci'];
  if (slotName.startsWith('DEF')) return const ['Defans'];
  if (slotName.startsWith('MID')) return const ['Orta Saha'];
  if (slotName.startsWith('FWD')) return const ['Forvet'];
  return const ['Forvet', 'Orta Saha', 'Defans', 'Kaleci'];
}

({Map<String, int> stats, bool isOutOfPosition}) getSlotStats(
  Map<String, dynamic> playerData,
  String slotName,
) {
  final stats = _statMap(playerData['stats']);
  if (slotName.startsWith('BENCH')) {
    return (stats: stats, isOutOfPosition: false);
  }

  final targetPositions = getPositionFromSlot(slotName);
  final isOutOfPosition = !targetPositions.contains(playerData['mevki']);
  if (isOutOfPosition) {
    final oopStats = <String, int>{};
    for (final entry in stats.entries) {
      oopStats[entry.key] = (entry.value * 0.6).toInt();
    }
    return (stats: oopStats, isOutOfPosition: true);
  }
  return (stats: stats, isOutOfPosition: false);
}

({int defenders, int midfielders, int forwards}) _formationNumbers(
  String formation,
) {
  final parts = formation
      .split('-')
      .map((value) => int.tryParse(value) ?? 0)
      .toList(growable: false);
  if (parts.length >= 3) {
    return (
      defenders: max(2, parts[0]),
      midfielders: max(2, parts[1]),
      forwards: max(1, parts[2]),
    );
  }
  return (defenders: 3, midfielders: 2, forwards: 1);
}

Map<String, double> _formationProfile(String formation) {
  final shape = _formationNumbers(formation);
  final defenders = shape.defenders.toDouble();
  final midfielders = shape.midfielders.toDouble();
  final forwards = shape.forwards.toDouble();
  return {
    'defenders': defenders,
    'midfielders': midfielders,
    'forwards': forwards,
    'width_bias': _clampDouble(
      0.38 + forwards * 0.11 + midfielders * 0.03,
      0.44,
      0.82,
    ),
    'central_density': _clampDouble(
      0.40 + midfielders * 0.12 + defenders * 0.03,
      0.48,
      0.84,
    ),
    'transition_threat': _clampDouble(
      0.36 + forwards * 0.16 + midfielders * 0.02,
      0.44,
      0.86,
    ),
    'rest_defense': _clampDouble(
      0.34 + defenders * 0.15 + midfielders * 0.03,
      0.46,
      0.88,
    ),
    'build_security': _clampDouble(
      0.34 + defenders * 0.08 + midfielders * 0.07,
      0.46,
      0.82,
    ),
    'box_presence': _clampDouble(0.34 + forwards * 0.18, 0.46, 0.86),
    'support_runs': _clampDouble(
      0.34 + midfielders * 0.12 + forwards * 0.05,
      0.46,
      0.84,
    ),
    'pressing_cover': _clampDouble(
      0.34 + midfielders * 0.10 + defenders * 0.06,
      0.44,
      0.84,
    ),
    'line_sync': _clampDouble(0.36 + defenders * 0.12, 0.46, 0.84),
  };
}

Map<String, dynamic> processTeamTactics(
  Map<String, dynamic> teamData, {
  bool isHome = false,
}) {
  final formation = teamData['formation'] as String? ?? '3-2-1';
  final formationProfile = _formationProfile(formation);
  final tactics = <String, dynamic>{
    'formation': formation,
    'mentality': teamData['mentality'] ?? 'Dengeli',
    'build_up': teamData['build_up_play'] ?? 'Dengeli',
    'focus': teamData['focus_play'] ?? 'Karma',
    'crossing': teamData['crossing_type'] ?? 'Yüksek Orta',
    'def_line': teamData['defensive_line'] ?? 'Normal',
    'pressing': teamData['pressing_trigger'] ?? 'Dengeli',
    'offside_trap': teamData['offside_trap'] ?? false,
    'set_piece_takers':
        (teamData['set_piece_takers'] as Map?)?.cast<String, dynamic>() ??
        {'pen': null, 'fk': null, 'cor': null},
  };
  final activeEffects =
      (teamData['active_augment_effects'] as Map?)?.cast<String, dynamic>() ??
      <String, dynamic>{};
  final tacticEffectiveness = _doubleValue(
    activeEffects['tactic_effectiveness'],
    1.0,
  );

  var attMod = 1.0;
  var midMod = 1.0;
  var defMod = 1.0;
  var chanceFreq = 0.16;
  var chanceQual = 1.0;
  var staminaDrain = 1.0;
  var widthBias = _doubleValue(formationProfile['width_bias'], 0.55);
  var centralDensity = _doubleValue(formationProfile['central_density'], 0.58);
  var transitionThreat = _doubleValue(
    formationProfile['transition_threat'],
    0.58,
  );
  var restDefense = _doubleValue(formationProfile['rest_defense'], 0.58);
  var buildSecurity = _doubleValue(formationProfile['build_security'], 0.58);
  var boxPresence = _doubleValue(formationProfile['box_presence'], 0.56);
  var supportRuns = _doubleValue(formationProfile['support_runs'], 0.60);
  var pressingCover = _doubleValue(formationProfile['pressing_cover'], 0.58);
  var lineSync = _doubleValue(formationProfile['line_sync'], 0.58);
  var assistBias = 0.40 + supportRuns * 0.28;
  var shotPatience = 0.42 + buildSecurity * 0.22;
  var foulPressure = 0.32 + pressingCover * 0.24;
  var setPieceEdge = 0.36 + boxPresence * 0.24;
  var counterThreat = 0.32 + transitionThreat * 0.26;

  attMod *= 0.92 + boxPresence * 0.16;
  midMod *= 0.92 + centralDensity * 0.16;
  defMod *= 0.92 + restDefense * 0.16;
  chanceFreq *= 0.92 + transitionThreat * 0.16;
  chanceQual *= 0.94 + boxPresence * 0.10;

  switch (tactics['mentality']) {
    case 'Çok Defansif':
      attMod = 0.65;
      midMod = 0.90;
      defMod = 1.40;
      chanceFreq *= 0.65;
      staminaDrain *= 0.8;
      restDefense += 0.14;
      buildSecurity += 0.08;
      shotPatience += 0.12;
      counterThreat += 0.06;
      foulPressure += 0.03;
      break;
    case 'Defansif':
      attMod = 0.80;
      midMod = 0.95;
      defMod = 1.20;
      chanceFreq *= 0.85;
      staminaDrain *= 0.9;
      restDefense += 0.08;
      buildSecurity += 0.04;
      shotPatience += 0.06;
      counterThreat += 0.04;
      break;
    case 'Hücum':
      attMod = 1.20;
      midMod = 1.05;
      defMod = 0.85;
      chanceFreq *= 1.25;
      staminaDrain *= 1.15;
      transitionThreat += 0.07;
      boxPresence += 0.08;
      supportRuns += 0.05;
      restDefense -= 0.06;
      foulPressure += 0.08;
      shotPatience -= 0.05;
      break;
    case 'Topyekûn Hücum':
      attMod = 1.40;
      midMod = 1.00;
      defMod = 0.65;
      chanceFreq *= 1.45;
      staminaDrain *= 1.3;
      transitionThreat += 0.12;
      boxPresence += 0.12;
      supportRuns += 0.08;
      restDefense -= 0.12;
      foulPressure += 0.12;
      shotPatience -= 0.08;
      break;
  }

  switch (tactics['build_up']) {
    case 'Hızlı':
      chanceFreq *= 1.2;
      chanceQual *= 0.85;
      staminaDrain *= 1.1;
      transitionThreat += 0.12;
      counterThreat += 0.10;
      shotPatience -= 0.10;
      buildSecurity -= 0.05;
      break;
    case 'Yavaş':
      chanceFreq *= 0.8;
      chanceQual *= 1.25;
      midMod *= 1.15;
      staminaDrain *= 0.9;
      buildSecurity += 0.12;
      assistBias += 0.06;
      shotPatience += 0.12;
      supportRuns += 0.04;
      break;
  }

  switch (tactics['focus']) {
    case 'Kanatlardan':
      widthBias += 0.24;
      centralDensity -= 0.08;
      assistBias += 0.08;
      setPieceEdge += 0.05;
      break;
    case 'Merkezden':
      centralDensity += 0.22;
      widthBias -= 0.08;
      supportRuns += 0.05;
      counterThreat += 0.05;
      break;
  }

  switch (tactics['crossing']) {
    case 'Yer Orta':
      widthBias += 0.06;
      boxPresence += 0.04;
      assistBias += 0.06;
      setPieceEdge -= 0.02;
      break;
    default:
      boxPresence += 0.05;
      setPieceEdge += 0.05;
      break;
  }

  switch (tactics['pressing']) {
    case 'Sürekli Baskı':
      midMod *= 1.20;
      defMod *= 0.85;
      chanceFreq *= 1.2;
      staminaDrain *= 1.4;
      pressingCover += 0.18;
      counterThreat += 0.08;
      foulPressure += 0.18;
      restDefense -= 0.04;
      break;
    case 'Top Kaybından Sonra':
      midMod *= 1.10;
      chanceFreq *= 1.1;
      staminaDrain *= 1.15;
      pressingCover += 0.10;
      counterThreat += 0.10;
      foulPressure += 0.08;
      break;
  }

  switch (tactics['def_line']) {
    case 'Derin Savunma':
      defMod *= 1.25;
      attMod *= 0.80;
      chanceQual *= 0.9;
      restDefense += 0.16;
      lineSync += 0.04;
      counterThreat += 0.10;
      buildSecurity -= 0.02;
      break;
    case 'İleride Kur':
      midMod *= 1.10;
      defMod *= 0.80;
      chanceFreq *= 1.1;
      lineSync += 0.12;
      restDefense -= 0.10;
      pressingCover += 0.06;
      foulPressure += 0.06;
      break;
  }

  if (tactics['offside_trap'] == true) {
    lineSync += 0.12;
    restDefense -= 0.04;
    foulPressure += 0.04;
  }

  final facilities =
      (teamData['facilities'] as List?)?.cast<String>() ?? const <String>[];
  if (isHome && facilities.contains('vip_tribun')) {
    attMod *= 1.10;
    midMod *= 1.05;
    transitionThreat += 0.04;
    assistBias += 0.04;
  }

  attMod = _amplifyBonus(attMod, 1.0, tacticEffectiveness);
  midMod = _amplifyBonus(midMod, 1.0, tacticEffectiveness);
  defMod = _amplifyBonus(defMod, 1.0, tacticEffectiveness);
  chanceFreq = _amplifyBonus(chanceFreq, 0.16, tacticEffectiveness);
  chanceQual = _amplifyBonus(chanceQual, 1.0, tacticEffectiveness);
  staminaDrain = _amplifyBonus(
    staminaDrain,
    1.0,
    tacticEffectiveness,
    lowerIsBetter: staminaDrain < 1.0,
  );

  tactics.addAll({
    'att_mod': attMod,
    'mid_mod': midMod,
    'def_mod': defMod,
    'chance_freq': chanceFreq,
    'chance_qual': chanceQual,
    'stamina_drain': staminaDrain,
    'width_bias': _clampDouble(widthBias, 0.28, 0.92),
    'central_density': _clampDouble(centralDensity, 0.28, 0.92),
    'transition_threat': _clampDouble(transitionThreat, 0.28, 0.96),
    'rest_defense': _clampDouble(restDefense, 0.28, 0.96),
    'build_security': _clampDouble(buildSecurity, 0.28, 0.92),
    'box_presence': _clampDouble(boxPresence, 0.28, 0.96),
    'support_runs': _clampDouble(supportRuns, 0.28, 0.92),
    'pressing_cover': _clampDouble(pressingCover, 0.28, 0.96),
    'assist_bias': _clampDouble(assistBias, 0.20, 0.96),
    'shot_patience': _clampDouble(shotPatience, 0.18, 0.96),
    'foul_pressure': _clampDouble(foulPressure, 0.18, 0.96),
    'set_piece_edge': _clampDouble(setPieceEdge, 0.18, 0.96),
    'counter_threat': _clampDouble(counterThreat, 0.18, 0.96),
    'line_sync': _clampDouble(lineSync, 0.20, 0.96),
    'defenders': formationProfile['defenders'],
    'midfielders': formationProfile['midfielders'],
    'forwards': formationProfile['forwards'],
  });
  return tactics;
}

Map<String, dynamic> parseTeamForMatch(
  Map<String, dynamic> playerDocData, {
  bool isHome = false,
}) {
  final teamList =
      (playerDocData['my_team_list'] as List?)?.cast<Map<String, dynamic>>() ??
      const [];
  final formationSlots =
      (playerDocData['formation_slots'] as Map?)?.cast<String, dynamic>() ??
      <String, dynamic>{};
  final captainId = playerDocData['captain_id'] as String?;
  final activeEffects =
      (playerDocData['active_augment_effects'] as Map?)
          ?.cast<String, dynamic>() ??
      <String, dynamic>{};
  final tactics = processTeamTactics(playerDocData, isHome: isHome);
  final formation = playerDocData['formation'] as String? ?? '3-2-1';
  final playersDict = <String, Map<String, dynamic>>{};

  for (final item in teamList) {
    final id = item['id'] as String?;
    final data = (item['data'] as Map?)?.cast<String, dynamic>();
    if (id != null && data != null) {
      playersDict[id] = data;
    }
  }

  final onPitch = <String, Map<String, dynamic>>{};
  final bench = <String, Map<String, dynamic>>{};
  final baseMoraleBonus = activeEffects['no_morale_loss'] == true ? 1.02 : 1.0;
  final chemistryBoost = activeEffects['synergy_boost'] == true ? 1.06 : 1.0;
  final facilities =
      (playerDocData['facilities'] as List?)?.cast<String>() ??
      const <String>[];
  var moraleFactorTotal = 0.0;
  var formFactorTotal = 0.0;
  var onPitchCount = 0;
  final teamInstructionTotals = <String, double>{
    'stamina_load': 0.0,
    'discipline_risk': 0.0,
    'injury_risk': 0.0,
    'chance_freq': 0.0,
    'chance_qual': 0.0,
    'press_bonus': 0.0,
    'tempo_delta': 0.0,
    'offside_risk': 0.0,
    'defensive_shape': 0.0,
    'cross_focus': 0.0,
    'pass_bonus': 0.0,
    'finish_bonus': 0.0,
    'risk_pass': 0.0,
  };

  for (final entry in formationSlots.entries) {
    final slot = entry.key;
    final slotData = (entry.value as Map?)?.cast<String, dynamic>();
    final playerId = slotData?['player_id'] as String?;
    if (playerId == null || !playersDict.containsKey(playerId)) {
      continue;
    }

    final playerData = Map<String, dynamic>.from(playersDict[playerId]!);
    final slotStats = getSlotStats({
      'mevki': playerData['mevki'],
      'stats': playerData['stats'],
    }, slot);
    final matchStats = Map<String, int>.from(slotStats.stats);
    final instructions = List<String>.from(
      (slotData?['instructions'] as List?) ?? const [],
    );
    final instructionProfile = _instructionProfile(instructions);
    _applyInstructionStatBoosts(matchStats, instructionProfile);

    if (playerId == captainId) {
      for (final key in matchStats.keys.toList()) {
        matchStats[key] = matchStats[key]! + 5;
      }
    }

    final morale = _clampDouble(
      _doubleValue(playerData['morale'], 5),
      1.0,
      10.0,
    );
    final form = _clampDouble(_doubleValue(playerData['form'], 5), 1.0, 10.0);
    final moraleFactor = baseMoraleBonus * (0.89 + morale * 0.022);
    final formFactor = 0.91 + form * 0.018;
    final playerFactor = _clampDouble(
      moraleFactor *
          formFactor *
          (slot.startsWith('BENCH') ? 1.0 : chemistryBoost),
      0.88,
      1.18,
    );

    for (final key in matchStats.keys.toList()) {
      matchStats[key] = max(1, (matchStats[key]! * playerFactor).round());
    }

    playerData['match_stats'] = matchStats;
    playerData['match_rating'] = calculateRating(
      matchStats,
      playerData['mevki'] as String? ?? 'Orta Saha',
    );

    if (playerData['status'] != 'uygun') {
      continue;
    }

    final endurance = _doubleValue(matchStats['dayaniklilik'], 60);
    final staminaBase = _clampDouble(
      68 + endurance * 0.22 + morale * 1.4 + form * 1.2,
      78,
      112,
    );

    final playerObj = <String, dynamic>{
      'id': playerId,
      'data': playerData,
      'current_stamina': staminaBase,
      'injured': false,
      'is_bench': slot.startsWith('BENCH'),
      'mevki': playerData['mevki'],
      'instructions': instructions,
      'instruction_profile': instructionProfile,
      'base_morale_factor': moraleFactor,
      'base_form_factor': formFactor,
      'morale': morale,
      'form': form,
      'slot': slot,
    };

    if (slot.startsWith('BENCH')) {
      bench[slot] = playerObj;
    } else {
      onPitch[slot] = playerObj;
      moraleFactorTotal += moraleFactor;
      formFactorTotal += formFactor;
      onPitchCount += 1;
      for (final key in teamInstructionTotals.keys) {
        teamInstructionTotals[key] =
            teamInstructionTotals[key]! + _doubleValue(instructionProfile[key]);
      }
    }
  }

  final normalizedInstructionProfile = {
    for (final entry in teamInstructionTotals.entries)
      entry.key: onPitchCount == 0 ? 0.0 : entry.value / onPitchCount,
  };
  final teamMoraleFactor = onPitchCount == 0
      ? baseMoraleBonus
      : moraleFactorTotal / onPitchCount;
  final teamFormFactor = onPitchCount == 0
      ? 1.0
      : formFactorTotal / onPitchCount;

  return {
    'on_pitch': onPitch,
    'bench': bench,
    'tactics': tactics,
    'formation': formation,
    'name': playerDocData['team_name'] ?? 'Takım',
    'sub_count': 0,
    'is_home': isHome,
    'facilities': facilities,
    'active_effects': activeEffects,
    'team_morale_factor': teamMoraleFactor,
    'team_form_factor': teamFormFactor,
    'team_chemistry': chemistryBoost,
    'match_morale_state': _clampDouble(teamMoraleFactor, 0.86, 1.14),
    'instruction_profile': normalizedInstructionProfile,
  };
}

class MatchChunkResult {
  const MatchChunkResult(this.logs, this.finished);

  final List<String> logs;
  final bool finished;
}

class MatchFinalData {
  const MatchFinalData({
    required this.score,
    required this.log,
    required this.mvp,
    required this.finalTeams,
    required this.events,
    required this.stats,
    required this.performance,
  });

  final Map<String, int> score;
  final List<String> log;
  final Map<String, dynamic>? mvp;
  final Map<String, dynamic> finalTeams;
  final Map<String, dynamic> events;
  final Map<String, dynamic> stats;
  final Map<String, double> performance;
}

class _PlayerPick {
  const _PlayerPick(this.player, this.slot);

  final Map<String, dynamic>? player;
  final String? slot;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class MatchEngine {
  MatchEngine(
    Map<String, dynamic> p1Data,
    Map<String, dynamic> p2Data,
    this.matchNumber,
    this.weather,
    String homeTeamId,
    Map<String, int>? initialScore,
    this.isBot, {
    Random? random,
    Map<String, dynamic>? specialEvent,
  }) : _random = random ?? Random(),
       specialEvent = specialEvent == null
           ? null
           : Map<String, dynamic>.from(specialEvent),
       t1 = parseTeamForMatch(p1Data, isHome: homeTeamId == 'oyuncu_1'),
       t2 = parseTeamForMatch(p2Data, isHome: homeTeamId == 'oyuncu_2'),
       score = initialScore ?? {'oyuncu_1': 0, 'oyuncu_2': 0} {
    _applySpecialMatchEvent();
    _applyConditionalPreMatchBoosts();
    _recalculateTeamPowers(t1);
    _recalculateTeamPowers(t2);
  }

  final Random _random;
  final int matchNumber;
  final String weather;
  final bool isBot;
  final Map<String, dynamic>? specialEvent;

  late Map<String, dynamic> t1;
  late Map<String, dynamic> t2;
  int minute = 0;
  int momentum = 50;
  Map<String, int> score;
  final Map<String, Map<String, dynamic>> stats = {
    'oyuncu_1': {
      'total_shots': 0,
      'shots_on_target': 0,
      'possession_count': 0,
      'attacks': 0,
      'dangerous_attacks': 0,
      'big_chances': 0,
      'saves': 0,
      'tackles': 0,
      'fouls': 0,
      'corners': 0,
      'crosses': 0,
      'set_pieces': 0,
      'counter_attacks': 0,
      'offsides': 0,
      'key_passes': 0,
      'passes': 0,
      'good_passes': 0,
      'expected_goals': 0.0,
    },
    'oyuncu_2': {
      'total_shots': 0,
      'shots_on_target': 0,
      'possession_count': 0,
      'attacks': 0,
      'dangerous_attacks': 0,
      'big_chances': 0,
      'saves': 0,
      'tackles': 0,
      'fouls': 0,
      'corners': 0,
      'crosses': 0,
      'set_pieces': 0,
      'counter_attacks': 0,
      'offsides': 0,
      'key_passes': 0,
      'passes': 0,
      'good_passes': 0,
      'expected_goals': 0.0,
    },
  };
  final Map<String, List<dynamic>> events = {
    'goals': [],
    'red_cards': [],
    'yellow_cards': [],
    'injuries': [],
  };
  final Map<String, double> performance = {};
  final List<String> log = [];
  final Map<String, int> _yellowCardCounts = {};
  int lastEventMinute = -5;

  Map<String, dynamic> getTeamState(Map<String, dynamic> team) {
    final onPitch = (team['on_pitch'] as Map).cast<String, dynamic>();
    final bench = (team['bench'] as Map).cast<String, dynamic>();
    return {
      'on_pitch': onPitch.map((slot, player) => MapEntry(slot, player['id'])),
      'bench': bench.map((slot, player) => MapEntry(slot, player['id'])),
      'stamina': {
        for (final player in [...onPitch.values, ...bench.values])
          player['id'] as String: _doubleValue(player['current_stamina']),
      },
      'sub_count': _intValue(team['sub_count']),
    };
  }

  double _teamAverageMatchRating(Map<String, dynamic> team) {
    final onPitch = (team['on_pitch'] as Map).cast<String, dynamic>();
    if (onPitch.isEmpty) return 0;
    final total = onPitch.values.fold<double>(
      0,
      (sum, player) => sum + _doubleValue(player['data']['match_rating']),
    );
    return total / onPitch.length;
  }

  void _applySpecialMatchEvent() {
    final event = specialEvent;
    if (event == null) {
      return;
    }

    switch (event['id'] as String? ?? '') {
      case 'derbi_atesi':
        _applyTeamEventBoost(
          t1,
          moraleDelta: 0.04,
          attScale: 1.04,
          chanceFreqScale: 1.05,
          foulPressureScale: 1.08,
        );
        _applyTeamEventBoost(
          t2,
          moraleDelta: 0.04,
          attScale: 1.04,
          chanceFreqScale: 1.05,
          foulPressureScale: 1.08,
        );
        break;
      case 'tribun_baskisi':
        _applyTeamEventBoost(
          t1,
          moraleDelta: 0.06,
          attScale: 1.06,
          midScale: 1.04,
          chanceQualScale: 1.04,
        );
        _applyTeamEventBoost(
          t2,
          moraleDelta: -0.04,
          attScale: 0.97,
          chanceQualScale: 0.96,
        );
        break;
      case 'kaygan_zemin':
        _applyTeamEventBoost(t1, staminaScale: 1.05, chanceQualScale: 0.97);
        _applyTeamEventBoost(t2, staminaScale: 1.05, chanceQualScale: 0.97);
        break;
      case 'sert_hakem':
        _applyTeamEventBoost(t1, foulPressureScale: 1.06);
        _applyTeamEventBoost(t2, foulPressureScale: 1.06);
        break;
      case 'erken_firtina':
        _applyTeamEventBoost(
          t1,
          moraleDelta: 0.02,
          attScale: 1.03,
          chanceFreqScale: 1.04,
          staminaScale: 1.04,
        );
        _applyTeamEventBoost(
          t2,
          moraleDelta: 0.02,
          attScale: 1.03,
          chanceFreqScale: 1.04,
          staminaScale: 1.04,
        );
        break;
    }
  }

  void _applyTeamEventBoost(
    Map<String, dynamic> team, {
    double moraleDelta = 0,
    double attScale = 1,
    double midScale = 1,
    double defScale = 1,
    double chanceFreqScale = 1,
    double chanceQualScale = 1,
    double staminaScale = 1,
    double foulPressureScale = 1,
  }) {
    final tactics = (team['tactics'] as Map).cast<String, dynamic>();
    tactics['att_mod'] = _doubleValue(tactics['att_mod'], 1.0) * attScale;
    tactics['mid_mod'] = _doubleValue(tactics['mid_mod'], 1.0) * midScale;
    tactics['def_mod'] = _doubleValue(tactics['def_mod'], 1.0) * defScale;
    tactics['chance_freq'] =
        _doubleValue(tactics['chance_freq'], 0.16) * chanceFreqScale;
    tactics['chance_qual'] =
        _doubleValue(tactics['chance_qual'], 1.0) * chanceQualScale;
    tactics['stamina_drain'] =
        _doubleValue(tactics['stamina_drain'], 1.0) * staminaScale;
    tactics['foul_pressure'] =
        _doubleValue(tactics['foul_pressure'], 0.50) * foulPressureScale;
    team['team_morale_factor'] = _clampDouble(
      _doubleValue(team['team_morale_factor'], 1.0) + moraleDelta,
      0.84,
      1.18,
    );
    team['match_morale_state'] = _clampDouble(
      _doubleValue(team['match_morale_state'], 1.0) + moraleDelta,
      0.84,
      1.18,
    );
  }

  void _applyConditionalPreMatchBoosts() {
    final t1Average = _teamAverageMatchRating(t1);
    final t2Average = _teamAverageMatchRating(t2);
    _applyGiantKillerBoost(t1, t1Average + 0.5 < t2Average);
    _applyGiantKillerBoost(t2, t2Average + 0.5 < t1Average);
  }

  void _applyGiantKillerBoost(Map<String, dynamic> team, bool shouldApply) {
    final activeEffects =
        (team['active_effects'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    if (!shouldApply || activeEffects['giant_killer_active'] != true) {
      team['giant_killer_triggered'] = false;
      return;
    }
    final onPitch = (team['on_pitch'] as Map).cast<String, dynamic>();
    for (final player in onPitch.values) {
      final matchStats = (player['data']['match_stats'] as Map)
          .cast<String, dynamic>();
      matchStats['sut'] = _intValue(matchStats['sut']) + 5;
      matchStats['hiz'] = _intValue(matchStats['hiz']) + 5;
      player['data']['match_rating'] = calculateRating(
        matchStats,
        player['data']['mevki'] as String? ?? 'Orta Saha',
      );
    }
    team['giant_killer_triggered'] = true;
    final tactics = (team['tactics'] as Map).cast<String, dynamic>();
    tactics['transition_threat'] =
        _doubleValue(tactics['transition_threat'], 0.58) + 0.04;
    tactics['counter_threat'] =
        _doubleValue(tactics['counter_threat'], 0.50) + 0.05;
  }

  void _recalculateTeamPowers(Map<String, dynamic> team) {
    var att = 0.0;
    var mid = 0.0;
    var df = 0.0;
    var gk = 0.0;

    final onPitch = (team['on_pitch'] as Map).cast<String, dynamic>();
    final tactics = (team['tactics'] as Map).cast<String, dynamic>();
    final instructionProfile = _teamInstructionProfile(team);
    final chemistry = _doubleValue(team['team_chemistry'], 1.0);
    final moralePulse = _matchMorale(team);
    final formPulse = _doubleValue(team['team_form_factor'], 1.0);
    final energyFactor = _teamEnergyFactor(team);
    for (final entry in onPitch.entries) {
      final slot = entry.key;
      final player = (entry.value as Map).cast<String, dynamic>();
      final statsMap = (player['data']['match_stats'] as Map)
          .cast<String, dynamic>();
      final mevki = player['data']['mevki'] as String?;
      final staminaFactor = max(
        0.30,
        _doubleValue(player['current_stamina']) / 100.0,
      );
      final injuryFactor = player['injured'] == true ? 0.55 : 1.0;
      final formBoost =
          0.96 + (_doubleValue(player['base_form_factor'], 1.0) - 1.0) * 0.40;
      final factor = staminaFactor * injuryFactor * formBoost;

      if (slot.startsWith('GK') || mevki == 'Kaleci') {
        gk +=
            statsMap.values.fold<double>(
              0,
              (sum, value) => sum + _doubleValue(value),
            ) *
            factor;
        df += _doubleValue(statsMap['savunma']) * factor;
      } else if (slot.startsWith('DEF')) {
        df +=
            (_doubleValue(statsMap['savunma']) * 3 +
                _doubleValue(statsMap['hiz'])) *
            factor;
      } else if (slot.startsWith('MID')) {
        mid +=
            (_doubleValue(statsMap['pas']) * 3 +
                _doubleValue(statsMap['dayaniklilik']) * 2) *
            factor;
        att += _doubleValue(statsMap['hucum']) * factor;
        df += _doubleValue(statsMap['savunma']) * factor;
      } else if (slot.startsWith('FWD')) {
        final focus = tactics['focus'] as String? ?? 'Karma';
        final speedWeight = focus == 'Kanatlardan' ? 2 : 1;
        final shotWeight = focus == 'Merkezden' ? 2 : 1;
        att +=
            (_doubleValue(statsMap['hucum']) * 2 +
                _doubleValue(statsMap['sut']) * shotWeight +
                _doubleValue(statsMap['hiz']) * speedWeight) *
            factor;
      }
    }

    final attackingEdge =
        chemistry *
        moralePulse *
        energyFactor *
        (1.0 + _doubleValue(instructionProfile['finish_bonus']) * 0.35) *
        (1.0 + max(0.0, formPulse - 1.0) * 0.45);
    final midfieldEdge =
        chemistry *
        max(0.88, energyFactor) *
        (1.0 + _doubleValue(instructionProfile['pass_bonus']) * 0.35);
    final defensiveEdge =
        chemistry *
        (0.94 + moralePulse * 0.06) *
        (1.0 + _doubleValue(instructionProfile['defensive_shape']) * 0.45);
    final attackShape =
        0.90 +
        _doubleValue(tactics['box_presence'], 0.58) * 0.18 +
        _doubleValue(tactics['support_runs'], 0.58) * 0.10;
    final midfieldShape =
        0.90 +
        _doubleValue(tactics['central_density'], 0.58) * 0.18 +
        _doubleValue(tactics['build_security'], 0.58) * 0.08;
    final defensiveShape =
        0.90 +
        _doubleValue(tactics['rest_defense'], 0.58) * 0.20 +
        _doubleValue(tactics['line_sync'], 0.58) * 0.10;

    team['att_power'] = max(
      1.0,
      att * _doubleValue(tactics['att_mod'], 1) * attackingEdge * attackShape,
    );
    team['mid_power'] = max(
      1.0,
      mid * _doubleValue(tactics['mid_mod'], 1) * midfieldEdge * midfieldShape,
    );
    team['def_power'] = max(
      1.0,
      df * _doubleValue(tactics['def_mod'], 1) * defensiveEdge * defensiveShape,
    );
    team['gk_power'] = max(
      1.0,
      gk *
          (0.94 +
              moralePulse * 0.04 +
              _doubleValue(tactics['line_sync'], 0.58) * 0.03),
    );
  }

  _PlayerPick _getRandomPlayerByStat(
    Map<String, dynamic> onPitch,
    String statName, {
    String? secondaryStat,
    double secondaryWeight = 0.35,
    bool isForwardBias = false,
    bool preferMidfielders = false,
  }) {
    final weightedPlayers =
        <({Map<String, dynamic> player, String slot, double weight})>[];
    for (final entry in onPitch.entries) {
      final player = (entry.value as Map).cast<String, dynamic>();
      final matchStats =
          (player['data']['match_stats'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      var weight = _doubleValue(matchStats[statName], 10);
      if (secondaryStat != null) {
        weight += _doubleValue(matchStats[secondaryStat], 10) * secondaryWeight;
      }
      final matchRating = _doubleValue(player['data']['match_rating'], 60);
      final stamina = _clampDouble(
        _doubleValue(player['current_stamina'], 90) / 100,
        0.70,
        1.08,
      );
      final morale = _clampDouble(_doubleValue(player['morale'], 5), 1.0, 10.0);
      final form = _clampDouble(_doubleValue(player['form'], 5), 1.0, 10.0);
      weight *= 0.76 + matchRating / 100 * 0.34;
      weight *= stamina;
      weight *= 0.93 + morale * 0.012 + form * 0.010;
      if (isForwardBias && entry.key.startsWith('FWD')) {
        weight *= 3;
      } else if (isForwardBias && entry.key.startsWith('MID')) {
        weight *= 1.5;
      }
      if (preferMidfielders && entry.key.startsWith('MID')) {
        weight *= 1.35;
      } else if (preferMidfielders && entry.key.startsWith('DEF')) {
        weight *= 0.92;
      }
      weightedPlayers.add((player: player, slot: entry.key, weight: weight));
    }

    if (weightedPlayers.isEmpty) {
      return const _PlayerPick(null, null);
    }

    final totalWeight = weightedPlayers.fold<double>(
      0,
      (sum, item) => sum + item.weight,
    );
    if (totalWeight <= 0) {
      final first = weightedPlayers.first;
      return _PlayerPick(first.player, first.slot);
    }

    final roll = _random.nextDouble() * totalWeight;
    var cursor = 0.0;
    for (final item in weightedPlayers) {
      cursor += item.weight;
      if (cursor >= roll) {
        return _PlayerPick(item.player, item.slot);
      }
    }

    final fallback = weightedPlayers.last;
    return _PlayerPick(fallback.player, fallback.slot);
  }

  String _opponentOf(String teamId) {
    return teamId == 'oyuncu_1' ? 'oyuncu_2' : 'oyuncu_1';
  }

  String _weightedChoice(Map<String, double> weights) {
    final positive = <String, double>{
      for (final entry in weights.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    if (positive.isEmpty) {
      return weights.keys.first;
    }
    final total = positive.values.fold<double>(0, (sum, value) => sum + value);
    var roll = _random.nextDouble() * total;
    for (final entry in positive.entries) {
      roll -= entry.value;
      if (roll <= 0) {
        return entry.key;
      }
    }
    return positive.keys.last;
  }

  double _scorePressure(String teamId) {
    final ownScore = _intValue(score[teamId]);
    final opponentScore = _intValue(score[_opponentOf(teamId)]);
    final delta = ownScore - opponentScore;
    if (minute < 25) return 1.0;
    if (delta < 0) {
      return minute >= 75 ? 1.16 : 1.08;
    }
    if (delta > 0) {
      return minute >= 75 ? 0.93 : 0.97;
    }
    return minute >= 75 ? 1.05 : 1.0;
  }

  double _matchRhythm(String teamId) {
    var rhythm = 1.0;
    if (minute < 12) {
      rhythm *= 0.92;
    } else if (minute > 75) {
      rhythm *= 1.10;
    } else if (minute > 60) {
      rhythm *= 1.04;
    }
    rhythm *= _scorePressure(teamId);
    return rhythm;
  }

  void _recordChance(String teamId, double xg, {bool setPiece = false}) {
    stats[teamId]!['expected_goals'] =
        (_doubleValue(stats[teamId]!['expected_goals']) + xg);
    if (xg >= 0.33) {
      stats[teamId]!['big_chances'] =
          _intValue(stats[teamId]!['big_chances']) + 1;
    }
    if (setPiece) {
      stats[teamId]!['set_pieces'] =
          _intValue(stats[teamId]!['set_pieces']) + 1;
    }
  }

  String _pickChanceStyle(
    Map<String, dynamic> attackingTeam, {
    required bool counterForDef,
    required bool wasPressed,
  }) {
    final profile = _tacticalProfile(attackingTeam);
    final instructions = _teamInstructionProfile(attackingTeam);
    final focus = attackingTeam['tactics']['focus'] as String? ?? 'Karma';
    final crossing =
        attackingTeam['tactics']['crossing'] as String? ?? 'Yüksek Orta';
    final weights = <String, double>{
      'counter':
          (counterForDef ? 0.44 : 0.06) +
          profile['counter_threat']! * 0.24 +
          profile['transition_threat']! * 0.18,
      'cross':
          0.08 +
          profile['width_bias']! * 0.42 +
          _doubleValue(instructions['cross_focus']) * 0.22 +
          (crossing == 'Yüksek Orta' ? 0.10 : 0.04),
      'wide_combination':
          0.12 +
          profile['width_bias']! * 0.30 +
          profile['assist_bias']! * 0.12 +
          _doubleValue(instructions['pass_bonus']) * 0.10,
      'through_ball':
          0.12 +
          profile['central_bias']! * 0.34 +
          _doubleValue(instructions['risk_pass']) * 0.22,
      'combination':
          0.18 +
          profile['assist_bias']! * 0.22 +
          profile['build_security']! * 0.10,
      'long_shot':
          0.05 +
          (1.0 - profile['shot_patience']!) * 0.28 +
          (wasPressed ? 0.10 : 0.0),
    };

    if (focus == 'Kanatlardan') {
      weights['cross'] = weights['cross']! + 0.14;
      weights['wide_combination'] = weights['wide_combination']! + 0.10;
      weights['through_ball'] = weights['through_ball']! * 0.82;
    } else if (focus == 'Merkezden') {
      weights['through_ball'] = weights['through_ball']! + 0.16;
      weights['combination'] = weights['combination']! + 0.08;
      weights['cross'] = weights['cross']! * 0.78;
    }

    if (crossing == 'Yer Orta') {
      weights['wide_combination'] = weights['wide_combination']! + 0.10;
      weights['combination'] = weights['combination']! + 0.05;
      weights['cross'] = weights['cross']! * 0.92;
    }

    if (counterForDef) {
      weights['counter'] = weights['counter']! + 0.10;
    }
    if (wasPressed) {
      weights['counter'] = weights['counter']! + 0.06;
      weights['long_shot'] = weights['long_shot']! + 0.04;
    }

    return _weightedChoice(weights);
  }

  String _buildUpNarration(
    String style,
    Map<String, dynamic> attackingTeam,
    Map<String, dynamic> shooter,
    Map<String, dynamic>? assister,
  ) {
    final shooterName = shooter['data']['name'] as String? ?? 'Oyuncu';
    final assistName = assister?['data']?['name'] as String? ?? 'arkadaşı';
    final shooterCue = _instructionCue(
      _primaryInstruction(shooter),
      style: style,
    );
    final assistCue = _instructionCue(
      _primaryInstruction(assister),
      style: style,
      isAssister: true,
    );
    final cue = shooterCue ?? assistCue;
    final options = switch (style) {
      'counter' => [
        "${attackingTeam['name']} topu kazandı ve çok hızlı çıktı. Son dokunuş için $shooterName ceza alanına koşuyor.",
        "${attackingTeam['name']} geçiş anını yakaladı. Savunma geriye kaçarken $shooterName boşluğu tehdit ediyor.",
      ],
      'cross' => [
        "${attackingTeam['name']} kanadı zorluyor. $assistName ortayı hazırladı, hedefte $shooterName var.",
        "${attackingTeam['name']} çizgide üstünlüğü aldı. $assistName kafasını kaldırdı, ceza alanında $shooterName bekliyor.",
      ],
      'through_ball' => [
        "$assistName savunma arasını düşündü. $shooterName derine değil, boşluğa koşu atıyor.",
        "$assistName tek pasla çizgiyi delmek istiyor. $shooterName zamanlamasını ayarladı.",
      ],
      'long_shot' => [
        "${attackingTeam['name']} yerleşik savunmaya karşı sabırlı. $shooterName uzaklardan şansını denemek istiyor.",
        "${attackingTeam['name']} rakibi ceza alanı önüne itti. $shooterName şut koridorunu kolluyor.",
      ],
      'wide_combination' => [
        "${attackingTeam['name']} kanatta kısa paslarla boşluk arıyor. Top şimdi $shooterName civarında.",
        "${attackingTeam['name']} çizgide üçgen kurdu. Son bağlantı için $shooterName hareketleniyor.",
      ],
      _ => [
        "${attackingTeam['name']} ceza alanı çevresinde pas yapıyor. Son vuruş için $shooterName hazırlanıyor.",
        "${attackingTeam['name']} sabırlı bir sekansla savunmanın dengesini bozdu. Top $shooterName'e yaklaşıyor.",
      ],
    };
    final base = options[_random.nextInt(options.length)];
    return cue == null ? base : '$base $cue';
  }

  String? _primaryInstruction(Map<String, dynamic>? player) {
    if (player == null) return null;
    final instructions = List<String>.from(
      (player['instructions'] as List?) ?? const [],
    );
    return instructions.firstWhere(
      (value) => value.isNotEmpty,
      orElse: () => '',
    );
  }

  String? _instructionCue(
    String? instruction, {
    required String style,
    bool isAssister = false,
  }) {
    if (instruction == null || instruction.isEmpty) return null;
    switch (instruction) {
      case 'Kanala Koş':
        if (!isAssister && (style == 'through_ball' || style == 'counter')) {
          return 'Kanala koşu talimatı savunmayı geriye sürüklüyor.';
        }
        break;
      case 'Ceza Sahasına Koşu':
        if (!isAssister) {
          return 'İkinci dalga koşusu ceza sahasında ekstra hedef yaratıyor.';
        }
        break;
      case 'Hedef Santrfor':
        if (!isAssister && (style == 'cross' || style == 'wide_combination')) {
          return 'Hedef santrfor rolü stoperleri üzerine çekti.';
        }
        break;
      case 'Önde Baskı':
        if (!isAssister && style == 'counter') {
          return 'Önde baskıdan doğan enerji rakibi hazırlıksız yakaladı.';
        }
        break;
      case 'Riskli Pas':
        if (isAssister && style == 'through_ball') {
          return 'Riskli pas tercihi çizgiyi tek hamlede deldi.';
        }
        break;
      case 'Topu Kısa Kullan':
        if (isAssister && style != 'counter') {
          return 'Kısa oyun sabırla boşluğu hazırladı.';
        }
        break;
      case 'Bindirme Yap':
        if (isAssister && (style == 'cross' || style == 'wide_combination')) {
          return 'Bindirme talimatı çizgiyi bir kez daha açtı.';
        }
        break;
      case 'Uzun Oyna':
        if (isAssister && (style == 'counter' || style == 'through_ball')) {
          return 'Uzun oyun tercihi savunmanın arkasına direkt indi.';
        }
        break;
    }
    return null;
  }

  String _missNarration(String style, String shooterName) {
    final options = switch (style) {
      'counter' => [
        "$shooterName karşı karşıya kaldı ama son vuruşu çerçeveyi bulmadı.",
        "$shooterName geçiş hücumunda fırsatı yakaladı, ancak final dokunuşu eksik kaldı.",
      ],
      'cross' => [
        "$shooterName gelen ortayı iyi karşıladı fakat top auta gitti.",
        "$shooterName ortayı tamamladı, vuruşu milimlerle dışarı çıktı.",
      ],
      'through_ball' => [
        "$shooterName savunma arkasına sarktı, bitirici dokunuşu yeterli olmadı.",
        "$shooterName çizgi arkasında topla buluştu ama kontrol sonrası şutu dışarı gitti.",
      ],
      'long_shot' => [
        "$shooterName uzaktan denedi ancak top üstten dışarı çıktı.",
        "$shooterName mesafeyi düşündü, sert vurdu ama yönü ayarlayamadı.",
      ],
      _ => [
        "$shooterName uygun durumda vurdu ama top auta çıktı.",
        "$shooterName son kararda isabeti sağlayamadı.",
      ],
    };
    return options[_random.nextInt(options.length)];
  }

  String _saveNarration(
    String style,
    String shooterName,
    String goalkeeperName,
  ) {
    final options = switch (style) {
      'counter' => [
        "Net pozisyon! $goalkeeperName zamanlamasıyla çıktı ve $shooterName'a geçit vermedi.",
        "$goalkeeperName bire birde çok erken çözüldü ve $shooterName'ın açısını kapattı.",
      ],
      'cross' => [
        "Ortadan gelen vuruşta $goalkeeperName refleksiyle çizgiyi kapattı.",
        "$goalkeeperName kalabalık arasından gelen teması son anda çıkardı.",
      ],
      'long_shot' => [
        "$shooterName çok sert vurdu ama $goalkeeperName köşeye giden topu çıkardı.",
        "$goalkeeperName uzaktan gelen mermiyi iki hamlede kontrol etti.",
      ],
      _ => [
        "$goalkeeperName gole izin vermedi, $shooterName bir kez daha duvara çarptı.",
        "$goalkeeperName pozisyonu iyi okudu ve vuruşu etkisiz hale getirdi.",
      ],
    };
    return options[_random.nextInt(options.length)];
  }

  String _goalNarration(
    String style,
    String shooterName, {
    String? assistName,
  }) {
    final options = switch (style) {
      'counter' =>
        assistName == null
            ? [
                "GOOOL! $shooterName hızlı hücumu tek başına bitirdi!",
                "GOOOL! $shooterName geçiş hücumunu soğukkanlı bir vuruşla tamamladı!",
              ]
            : [
                "GOOOL! $assistName geçişi başlattı, $shooterName boş kaleye işi tamamladı!",
                "GOOOL! $assistName savunmayı koşturdu, $shooterName finali yaptı!",
              ],
      'cross' =>
        assistName == null
            ? [
                "GOOOL! $shooterName havadan gelen topu müthiş tamamladı!",
                "GOOOL! $shooterName yükseldi ve ortayı kusursuz bitirdi!",
              ]
            : [
                "GOOOL! $assistName ortayı kesti, $shooterName dokunuşu yaptı!",
                "GOOOL! $assistName servis etti, $shooterName ceza sahasında affetmedi!",
              ],
      'through_ball' =>
        assistName == null
            ? [
                "GOOOL! $shooterName savunma arkasına sarktı ve fırsatı değerlendirdi!",
                "GOOOL! $shooterName çizgi arkasında topla buluştu, işi sakin bitirdi!",
              ]
            : [
                "GOOOL! $assistName savunmayı yardı, $shooterName soğukkanlı bitirdi!",
                "GOOOL! $assistName kilidi açtı, $shooterName yüzdesini kullandı!",
              ],
      'long_shot' => [
        "GOOOL! $shooterName uzaklardan öyle bir vurdu ki kalecinin yapacak şeyi kalmadı!",
        "GOOOL! $shooterName mesafeyi umursamadı, topu doksana gönderdi!",
      ],
      _ =>
        assistName == null
            ? [
                "GOOOL! $shooterName kaleciyi avlıyor!",
                "GOOOL! $shooterName fırsatı gördü ve cezayı kesti!",
              ]
            : [
                "GOOOL! $assistName hazırladı, $shooterName affetmedi!",
                "GOOOL! $assistName servis etti, $shooterName tamamladı!",
              ],
    };
    return options[_random.nextInt(options.length)];
  }

  String _openingTacticalLine(Map<String, dynamic> team) {
    final tactics = (team['tactics'] as Map).cast<String, dynamic>();
    final mentality = tactics['mentality'] as String? ?? 'Dengeli';
    final buildUp = tactics['build_up'] as String? ?? 'Dengeli';
    final focus = tactics['focus'] as String? ?? 'Karma';
    final formation = team['formation'] as String? ?? '3-2-1';
    final focusLine = switch (focus) {
      'Kanatlardan' => 'kanat koridorlarını zorlamayı planlıyor.',
      'Merkezden' => 'merkezden çizgi kırmayı hedefliyor.',
      _ => 'atak yönünü rakibin zaafına göre değiştirecek.',
    };
    final tempoLine = switch (buildUp) {
      'Hızlı' => 'Tempo yüksek tutulacak.',
      'Yavaş' => 'Topa sahip olup ritmi kontrol etmek isteyecek.',
      _ => 'Tempo dengeli kurulacak.',
    };
    final giantKillerLine = team['giant_killer_triggered'] == true
        ? ' Dev Katili etkisiyle şut ve hız seviyesi artmış durumda.'
        : '';
    return "${team['name']} $formation dizilişiyle $mentality oynuyor; $tempoLine $focusLine$giantKillerLine";
  }

  Map<String, double> _getWeatherMods() {
    final mods = <String, double>{
      'pass_success': 1.00,
      'shot_acc': 1.00,
      'stamina_drain': 1.00,
      'foul_rate': 1.00,
      'injury_rate': 1.00,
      'press_bonus': 1.00,
      'cross_success': 1.00,
    };
    switch (weather.trim()) {
      case 'Yağmurlu':
        mods['pass_success'] = 0.92;
        mods['shot_acc'] = 0.94;
        mods['stamina_drain'] = 1.10;
        mods['foul_rate'] = 1.10;
        mods['injury_rate'] = 1.20;
        mods['cross_success'] = 0.92;
        break;
      case 'Sıcak':
        mods['pass_success'] = 0.97;
        mods['shot_acc'] = 0.98;
        mods['stamina_drain'] = 1.25;
        mods['foul_rate'] = 1.02;
        mods['injury_rate'] = 1.10;
        mods['press_bonus'] = 0.92;
        break;
      case 'Güneşli':
        mods['pass_success'] = 1.01;
        mods['shot_acc'] = 1.01;
        break;
    }
    switch (specialEvent?['id'] as String? ?? '') {
      case 'derbi_atesi':
        mods['foul_rate'] = mods['foul_rate']! * 1.16;
        mods['press_bonus'] = mods['press_bonus']! * 1.05;
        break;
      case 'tribun_baskisi':
        mods['pass_success'] = mods['pass_success']! * 0.99;
        mods['press_bonus'] = mods['press_bonus']! * 1.03;
        break;
      case 'kaygan_zemin':
        mods['pass_success'] = mods['pass_success']! * 0.93;
        mods['shot_acc'] = mods['shot_acc']! * 0.95;
        mods['injury_rate'] = mods['injury_rate']! * 1.14;
        mods['cross_success'] = mods['cross_success']! * 0.92;
        break;
      case 'sert_hakem':
        mods['foul_rate'] = mods['foul_rate']! * 1.08;
        break;
      case 'erken_firtina':
        mods['stamina_drain'] = mods['stamina_drain']! * 1.08;
        mods['press_bonus'] = mods['press_bonus']! * 1.04;
        break;
    }
    return mods;
  }

  double _specialCardRiskMultiplier() {
    return switch (specialEvent?['id'] as String? ?? '') {
      'derbi_atesi' => 1.14,
      'sert_hakem' => 1.28,
      _ => 1.0,
    };
  }

  Map<String, double> _tacticalProfile(Map<String, dynamic> team) {
    final tactics = (team['tactics'] as Map).cast<String, dynamic>();
    final pressIntensity = switch (tactics['pressing']) {
      'Top Kaybından Sonra' => 0.65,
      'Sürekli Baskı' => 0.85,
      _ => 0.50,
    };
    final lineHeight = switch (tactics['def_line']) {
      'Derin Savunma' => 0.30,
      'İleride Kur' => 0.75,
      _ => 0.50,
    };
    final tempo = switch (tactics['build_up']) {
      'Yavaş' => 0.35,
      'Hızlı' => 0.75,
      _ => 0.55,
    };
    final risk = switch (tactics['mentality']) {
      'Çok Defansif' => 0.25,
      'Defansif' => 0.35,
      'Hücum' => 0.65,
      'Topyekûn Hücum' => 0.80,
      _ => 0.50,
    };
    return {
      'press_intensity': pressIntensity,
      'line_height': lineHeight,
      'tempo': tempo,
      'risk': risk,
      'width_bias': _doubleValue(tactics['width_bias'], 0.55),
      'central_bias': _doubleValue(tactics['central_density'], 0.58),
      'transition_threat': _doubleValue(tactics['transition_threat'], 0.58),
      'rest_defense': _doubleValue(tactics['rest_defense'], 0.58),
      'build_security': _doubleValue(tactics['build_security'], 0.58),
      'box_presence': _doubleValue(tactics['box_presence'], 0.58),
      'support_runs': _doubleValue(tactics['support_runs'], 0.58),
      'assist_bias': _doubleValue(tactics['assist_bias'], 0.58),
      'shot_patience': _doubleValue(tactics['shot_patience'], 0.58),
      'foul_pressure': _doubleValue(tactics['foul_pressure'], 0.58),
      'set_piece_edge': _doubleValue(tactics['set_piece_edge'], 0.58),
      'counter_threat': _doubleValue(tactics['counter_threat'], 0.58),
      'line_sync': _doubleValue(tactics['line_sync'], 0.58),
    };
  }

  bool _autoSubstitute(
    Map<String, dynamic> team,
    String outPlayerId, {
    String reason = 'Sakatlık',
  }) {
    final onPitch = (team['on_pitch'] as Map).cast<String, dynamic>();
    final bench = (team['bench'] as Map).cast<String, dynamic>();
    final outSlot = onPitch.entries
        .where((entry) => entry.value['id'] == outPlayerId)
        .map((entry) => entry.key)
        .firstOrNull;
    if (outSlot == null) {
      return false;
    }
    if (_intValue(team['sub_count']) >= 4 || bench.isEmpty) {
      onPitch[outSlot]['injured'] = true;
      return false;
    }

    final targetPositions = getPositionFromSlot(outSlot);
    String? bestSlot;
    var bestScore = -1.0;
    for (final entry in bench.entries) {
      final player = (entry.value as Map).cast<String, dynamic>();
      final mevki = player['data']['mevki'] as String?;
      if (mevki != null && targetPositions.contains(mevki)) {
        final score =
            _doubleValue(player['data']['match_rating']) +
            (_doubleValue(player['current_stamina']) / 100.0) * 5;
        if (score > bestScore) {
          bestScore = score;
          bestSlot = entry.key;
        }
      }
    }

    bestSlot ??= bench.entries.reduce((best, current) {
      final bestRating = _doubleValue(best.value['data']['match_rating']);
      final currentRating = _doubleValue(current.value['data']['match_rating']);
      return currentRating > bestRating ? current : best;
    }).key;

    final playerOut = Map<String, dynamic>.from(onPitch[outSlot]);
    final playerIn = Map<String, dynamic>.from(bench[bestSlot]!);
    onPitch[outSlot] = playerIn;
    bench.remove(bestSlot);
    bench[outSlot] = playerOut;
    team['sub_count'] = _intValue(team['sub_count']) + 1;
    log.add(
      "[sub]$minute' - Mecburi Değişiklik (${team['name']}): ${playerOut['data']['name']} çıktı ($reason), ${playerIn['data']['name']} oyunda.[/sub]",
    );
    _recalculateTeamPowers(team);
    return true;
  }

  MapEntry<String, Map<String, dynamic>>? _pickGoalkeeper(
    Map<String, dynamic> team,
  ) {
    final onPitch = (team['on_pitch'] as Map).cast<String, dynamic>();
    for (final entry in onPitch.entries) {
      if (entry.key.startsWith('GK')) {
        return MapEntry(
          entry.key,
          (entry.value as Map).cast<String, dynamic>(),
        );
      }
    }
    return null;
  }

  Map<String, dynamic> _teamInstructionProfile(Map<String, dynamic> team) {
    return (team['instruction_profile'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
  }

  double _teamAverageStamina(Map<String, dynamic> team) {
    final onPitch = (team['on_pitch'] as Map).cast<String, dynamic>();
    if (onPitch.isEmpty) return 100.0;
    final total = onPitch.values.fold<double>(
      0,
      (sum, player) => sum + _doubleValue(player['current_stamina'], 100),
    );
    return total / onPitch.length;
  }

  double _teamEnergyFactor(Map<String, dynamic> team) {
    final averageStamina = _teamAverageStamina(team);
    if (averageStamina >= 85) return 1.02;
    if (averageStamina >= 70) return 0.96 + (averageStamina - 70) * 0.004;
    if (averageStamina >= 50) return 0.84 + (averageStamina - 50) * 0.006;
    return 0.72 + averageStamina * 0.0024;
  }

  double _matchMorale(Map<String, dynamic> team) {
    return _doubleValue(
      team['match_morale_state'],
      _doubleValue(team['team_morale_factor'], 1.0),
    );
  }

  void _adjustMatchMorale(Map<String, dynamic> team, double delta) {
    team['match_morale_state'] = _clampDouble(
      _matchMorale(team) + delta,
      0.82,
      1.18,
    );
  }

  Map<String, dynamic>? _findOnPitchPlayerById(
    Map<String, dynamic> team,
    String? playerId,
  ) {
    if (playerId == null) return null;
    final onPitch = (team['on_pitch'] as Map).cast<String, dynamic>();
    for (final player in onPitch.values) {
      if (player['id'] == playerId) {
        return (player as Map).cast<String, dynamic>();
      }
    }
    return null;
  }

  Map<String, dynamic> _resolveSetPieceTaker(
    Map<String, dynamic> team,
    String key,
    Map<String, dynamic> fallback,
  ) {
    final takers =
        (team['tactics']['set_piece_takers'] as Map?)
            ?.cast<String, dynamic>() ??
        <String, dynamic>{};
    return _findOnPitchPlayerById(team, takers[key] as String?) ?? fallback;
  }

  void _playCornerChance({
    required List<String> chunkLog,
    required String possessingTeam,
    required String defendingTeam,
    required Map<String, dynamic> attackingTeam,
    required Map<String, dynamic> defendingTeamData,
    required MapEntry<String, Map<String, dynamic>> goalkeeper,
  }) {
    stats[possessingTeam]!['set_pieces'] =
        _intValue(stats[possessingTeam]!['set_pieces']) + 1;
    stats[possessingTeam]!['crosses'] =
        _intValue(stats[possessingTeam]!['crosses']) + 1;

    final passer = _getRandomPlayerByStat(
      (attackingTeam['on_pitch'] as Map).cast<String, dynamic>(),
      'pas',
    );
    final target = _getRandomPlayerByStat(
      (attackingTeam['on_pitch'] as Map).cast<String, dynamic>(),
      'hucum',
      isForwardBias: true,
    );
    if (passer.player == null || target.player == null) return;

    final taker = _resolveSetPieceTaker(attackingTeam, 'cor', passer.player!);
    stats[possessingTeam]!['total_shots'] =
        _intValue(stats[possessingTeam]!['total_shots']) + 1;

    final delivery =
        _doubleValue(taker['data']['match_stats']['pas'], 60) * 0.60 +
        _doubleValue(taker['data']['match_stats']['sut'], 40) * 0.20 +
        _doubleValue(taker['data']['match_stats']['hucum'], 45) * 0.20;
    final aerial =
        _doubleValue(target.player!['data']['match_stats']['hucum'], 60) *
            0.50 +
        _doubleValue(target.player!['data']['match_stats']['sut'], 55) * 0.25 +
        _doubleValue(
              target.player!['data']['match_stats']['dayaniklilik'],
              60,
            ) *
            0.25;
    final defendingShape =
        1.0 +
        _doubleValue(
              _teamInstructionProfile(defendingTeamData)['defensive_shape'],
            ) *
            0.6;
    final setPieceEdge = _doubleValue(
      attackingTeam['tactics']['set_piece_edge'],
      0.58,
    );
    final defense =
        (_doubleValue(defendingTeamData['def_power']) * 0.18 +
            _doubleValue(defendingTeamData['gk_power']) * 0.92) *
        defendingShape;
    final cornerPower =
        (delivery + aerial) *
        (0.84 + _random.nextDouble() * 0.28) *
        (0.94 + setPieceEdge * 0.10) *
        _matchMorale(attackingTeam);
    final cornerXg = _clampDouble(
      0.20 + (cornerPower / max(1.0, defense) - 1) * 0.14,
      0.12,
      0.42,
    );
    _recordChance(possessingTeam, cornerXg, setPiece: true);

    if (cornerPower > defense * 1.04) {
      stats[possessingTeam]!['shots_on_target'] =
          _intValue(stats[possessingTeam]!['shots_on_target']) + 1;
      score[possessingTeam] = _intValue(score[possessingTeam]) + 1;
      final assistName = taker['id'] == target.player!['id']
          ? null
          : taker['data']['name'];
      chunkLog.add(
        "[goal]$minute' - Kornerden gol! ${target.player!['data']['name']} iyi yükseldi ve fileleri buldu![/goal]",
      );
      events['goals']!.add({
        'scorer_name': target.player!['data']['name'],
        'assist_name': assistName,
      });
      performance[target.player!['id'] as String] =
          (performance[target.player!['id'] as String] ?? 0) + 18;
      if (assistName != null) {
        performance[taker['id'] as String] =
            (performance[taker['id'] as String] ?? 0) + 10;
      }
      _adjustMatchMorale(attackingTeam, 0.03);
      _adjustMatchMorale(defendingTeamData, -0.04);
      momentum = 50;
      return;
    }

    if (cornerPower > defense * 0.90) {
      stats[possessingTeam]!['shots_on_target'] =
          _intValue(stats[possessingTeam]!['shots_on_target']) + 1;
      stats[defendingTeam]!['saves'] =
          _intValue(stats[defendingTeam]!['saves']) + 1;
      chunkLog.add(
        "[chance]$minute' - Kornerden tehlike! ${goalkeeper.value['data']['name']} çizgide çok iyi reaksiyon verdi.[/chance]",
      );
      performance[goalkeeper.value['id'] as String] =
          (performance[goalkeeper.value['id'] as String] ?? 0) + 11;
      return;
    }

    chunkLog.add(
      "[normal]$minute' - Korner etkili kullanıldı ama savunma topu uzaklaştırdı.[/normal]",
    );
  }

  void _playFreeKickChance({
    required List<String> chunkLog,
    required String possessingTeam,
    required String defendingTeam,
    required Map<String, dynamic> attackingTeam,
    required Map<String, dynamic> defendingTeamData,
    required Map<String, dynamic> foulWinner,
    required MapEntry<String, Map<String, dynamic>> goalkeeper,
  }) {
    stats[possessingTeam]!['set_pieces'] =
        _intValue(stats[possessingTeam]!['set_pieces']) + 1;

    final taker = _resolveSetPieceTaker(attackingTeam, 'fk', foulWinner);
    stats[possessingTeam]!['total_shots'] =
        _intValue(stats[possessingTeam]!['total_shots']) + 1;

    final fkSkill =
        _doubleValue(taker['data']['match_stats']['sut'], 60) * 0.65 +
        _doubleValue(taker['data']['match_stats']['pas'], 60) * 0.35;
    final setPieceEdge = _doubleValue(
      attackingTeam['tactics']['set_piece_edge'],
      0.58,
    );
    final shotTargetProbability = _clampDouble(
      0.18 + fkSkill / 320.0 + setPieceEdge * 0.05,
      0.18,
      0.46,
    );
    _recordChance(
      possessingTeam,
      _clampDouble(0.09 + fkSkill / 820.0, 0.08, 0.21),
      setPiece: true,
    );

    chunkLog.add(
      "[event]$minute' - Tehlikeli serbest vuruş! Topun başında ${taker['data']['name']} var.[/event]",
    );

    if (_random.nextDouble() > shotTargetProbability) {
      chunkLog.add(
        "[normal]$minute' - ${taker['data']['name']} barajı aşamadı ya da top auta gitti.[/normal]",
      );
      return;
    }

    stats[possessingTeam]!['shots_on_target'] =
        _intValue(stats[possessingTeam]!['shots_on_target']) + 1;

    final wallAndKeeper =
        _doubleValue(defendingTeamData['def_power']) * 0.18 +
        _doubleValue(defendingTeamData['gk_power']) * 0.90;
    final fkRoll =
        fkSkill *
        (0.86 + _random.nextDouble() * 0.30) *
        (0.94 + setPieceEdge * 0.10) *
        _matchMorale(attackingTeam);
    final saveRoll = wallAndKeeper * (0.88 + _random.nextDouble() * 0.26);

    if (fkRoll > saveRoll * 1.03) {
      score[possessingTeam] = _intValue(score[possessingTeam]) + 1;
      chunkLog.add(
        "[goal]$minute' - Mükemmel serbest vuruş! ${taker['data']['name']} topu köşeye gönderdi![/goal]",
      );
      events['goals']!.add({
        'scorer_name': taker['data']['name'],
        'assist_name': null,
      });
      performance[taker['id'] as String] =
          (performance[taker['id'] as String] ?? 0) + 22;
      _adjustMatchMorale(attackingTeam, 0.03);
      _adjustMatchMorale(defendingTeamData, -0.04);
      momentum = 50;
      return;
    }

    stats[defendingTeam]!['saves'] =
        _intValue(stats[defendingTeam]!['saves']) + 1;
    chunkLog.add(
      "[chance]$minute' - ${goalkeeper.value['data']['name']} iyi uzandı ve frikiği çıkardı.[/chance]",
    );
    performance[goalkeeper.value['id'] as String] =
        (performance[goalkeeper.value['id'] as String] ?? 0) + 12;
  }

  void _applyStaminaDrain(
    Map<String, dynamic> team,
    double baseDrain,
    Map<String, double> weatherMods,
  ) {
    final facilities =
        (team['facilities'] as List?)?.cast<String>() ?? const <String>[];
    final facilityModifier = facilities.contains('saglik_merkezi') ? 0.8 : 1.0;
    final tactics = (team['tactics'] as Map).cast<String, dynamic>();
    final instructionProfile = _teamInstructionProfile(team);
    final teamMorale = _matchMorale(team);
    final drain =
        baseDrain *
        _doubleValue(tactics['stamina_drain'], 1.0) *
        facilityModifier *
        weatherMods['stamina_drain']! *
        (1.0 + _doubleValue(instructionProfile['stamina_load']) * 0.30) *
        (teamMorale < 1.0 ? 1.0 + (1.0 - teamMorale) * 0.35 : 1.0);
    final onPitch = (team['on_pitch'] as Map).cast<String, dynamic>();
    for (final player in onPitch.values) {
      final endurance = _doubleValue(
        player['data']['match_stats']['dayaniklilik'],
        60,
      );
      final morale = _doubleValue(player['morale'], 5);
      final form = _doubleValue(player['form'], 5);
      final playerInstruction =
          (player['instruction_profile'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final enduranceFactor = _clampDouble(
        1.12 - endurance / 360.0,
        0.78,
        1.12,
      );
      final roleLoad =
          1.0 + _doubleValue(playerInstruction['stamina_load']) * 0.45;
      final fatigueLoad = _doubleValue(player['current_stamina']) < 45
          ? 1.08
          : 1.0;
      final moraleRecovery = 1.0 - max(0.0, morale - 5) * 0.015;
      final formRecovery = 1.0 - max(0.0, form - 5) * 0.012;
      final totalDrain =
          drain *
          enduranceFactor *
          roleLoad *
          fatigueLoad *
          moraleRecovery *
          formRecovery;
      player['current_stamina'] = max(
        5.0,
        _doubleValue(player['current_stamina']) - totalDrain,
      );
    }
  }

  ({int passes, int goodPasses}) _estimatePasses(
    Map<String, dynamic> team,
    Map<String, double> weatherMods, {
    bool hadAttack = false,
    bool wasPressed = false,
  }) {
    final profile = _tacticalProfile(team);
    final instructionProfile = _teamInstructionProfile(team);
    var base =
        5 +
        ((1.0 - profile['tempo']!) * 5).round() +
        (profile['build_security']! * 2.5).round();
    if (hadAttack) {
      base += 1;
    }
    if (profile['shot_patience']! > 0.68) {
      base += 1;
    }
    if (profile['width_bias']! > 0.70) {
      base += 1;
    }

    var passSuccess =
        0.78 +
        (_doubleValue(team['mid_power']) /
                (_doubleValue(team['mid_power']) + 1200.0)) *
            0.18;
    passSuccess *= weatherMods['pass_success']!;
    passSuccess *= _matchMorale(team);
    passSuccess *= 1.0 + _doubleValue(instructionProfile['pass_bonus']) * 0.35;
    passSuccess *= 0.95 + profile['build_security']! * 0.08;
    passSuccess *= 0.95 + profile['assist_bias']! * 0.06;
    if (wasPressed) {
      passSuccess *= 0.92;
    }

    final passes = max(1, base + _random.nextInt(4) - 1);
    final good = (passes * max(0.45, min(0.95, passSuccess))).round();
    return (passes: passes, goodPasses: good);
  }

  void processSubstitutions(String playerId, List<dynamic> substitutions) {
    final team = playerId == 'oyuncu_1' ? t1 : t2;
    final onPitch = (team['on_pitch'] as Map).cast<String, dynamic>();
    final bench = (team['bench'] as Map).cast<String, dynamic>();

    for (final dynamic sub in substitutions) {
      if (_intValue(team['sub_count']) >= 4) {
        break;
      }
      final data = (sub as Map).cast<String, dynamic>();
      final slotOut = data['slot_out'] as String?;
      final slotIn = data['slot_in'] as String?;
      if (slotOut == null || slotIn == null) {
        continue;
      }

      if (onPitch.containsKey(slotOut) && bench.containsKey(slotIn)) {
        final playerOut = Map<String, dynamic>.from(onPitch[slotOut]);
        final playerIn = Map<String, dynamic>.from(bench[slotIn]);
        onPitch[slotOut] = playerIn;
        bench.remove(slotIn);
        bench[slotOut] = playerOut;
        team['sub_count'] = _intValue(team['sub_count']) + 1;
        log.add(
          "[sub]$minute' - Değişiklik (${team['name']}): ${playerOut['data']['name']} çıktı, ${playerIn['data']['name']} oyunda.[/sub]",
        );
      }
    }

    _recalculateTeamPowers(team);
  }

  MatchChunkResult playChunk([int minutesToPlay = 1]) {
    if (minute >= 90) {
      return const MatchChunkResult([], true);
    }

    final chunkLog = <String>[];
    final targetMinute = min(90, minute + minutesToPlay);
    final weatherMods = _getWeatherMods();

    while (minute < targetMinute) {
      minute += 1;

      if (minute == 1) {
        chunkLog.add("[event]1' - ${_openingTacticalLine(t1)}[/event]");
        chunkLog.add("[event]1' - ${_openingTacticalLine(t2)}[/event]");
      }

      if (minute == 45) {
        chunkLog.add(
          "[event]45' - Hakem ilk yarıyı bitiren düdüğü çalıyor.[/event]",
        );
      } else if (minute == 46) {
        chunkLog.add("[event]46' - İkinci yarı başladı![/event]");
      }

      _recalculateTeamPowers(t1);
      _recalculateTeamPowers(t2);

      if (isBot && (minute == 60 || minute == 75)) {
        final t2Bench = (t2['bench'] as Map).cast<String, dynamic>();
        if (_intValue(t2['sub_count']) < 4 && t2Bench.isNotEmpty) {
          final t2OnPitch = (t2['on_pitch'] as Map).cast<String, dynamic>();
          final worstSlot = t2OnPitch.entries.reduce((best, current) {
            final bestStamina = _doubleValue(best.value['current_stamina']);
            final currentStamina = _doubleValue(
              current.value['current_stamina'],
            );
            return currentStamina < bestStamina ? current : best;
          }).key;
          String? bestSubSlot;
          var bestSubRating = 0.0;
          final targetPositions = getPositionFromSlot(worstSlot);
          for (final entry in t2Bench.entries) {
            final player = (entry.value as Map).cast<String, dynamic>();
            if (targetPositions.contains(player['data']['mevki'])) {
              final rating = _doubleValue(player['data']['match_rating']);
              if (rating > bestSubRating) {
                bestSubRating = rating;
                bestSubSlot = entry.key;
              }
            }
          }
          if (bestSubSlot != null) {
            processSubstitutions('oyuncu_2', [
              {'slot_out': worstSlot, 'slot_in': bestSubSlot},
            ]);
          }
        }
      }

      final t1Control =
          _doubleValue(t1['mid_power']) *
          _matchMorale(t1) *
          _teamEnergyFactor(t1);
      final t2Control =
          _doubleValue(t2['mid_power']) *
          _matchMorale(t2) *
          _teamEnergyFactor(t2);
      final totalMid = t1Control + t2Control;
      final t1MidShare = totalMid > 0 ? t1Control / totalMid : 0.5;

      if (_random.nextDouble() < t1MidShare) {
        momentum = min(100, momentum + _random.nextInt(4) + 1);
      } else {
        momentum = max(0, momentum - (_random.nextInt(4) + 1));
      }

      final effectiveT1Chance = (momentum / 100.0) * 0.6 + t1MidShare * 0.4;
      var possessingTeam = _random.nextDouble() < effectiveT1Chance
          ? 'oyuncu_1'
          : 'oyuncu_2';
      var defendingTeam = possessingTeam == 'oyuncu_1'
          ? 'oyuncu_2'
          : 'oyuncu_1';
      var attackingTeam = possessingTeam == 'oyuncu_1' ? t1 : t2;
      var defendingTeamData = possessingTeam == 'oyuncu_1' ? t2 : t1;

      stats[possessingTeam]!['possession_count'] =
          _intValue(stats[possessingTeam]!['possession_count']) + 1;
      stats[possessingTeam]!['attacks'] =
          _intValue(stats[possessingTeam]!['attacks']) + 1;

      _applyStaminaDrain(t1, 0.60, weatherMods);
      _applyStaminaDrain(t2, 0.60, weatherMods);

      var attackingProfile = _tacticalProfile(attackingTeam);
      var defendingProfile = _tacticalProfile(defendingTeamData);
      var attackingInstructions = _teamInstructionProfile(attackingTeam);
      var defendingInstructions = _teamInstructionProfile(defendingTeamData);
      var attackingMorale = _matchMorale(attackingTeam);
      var defendingMorale = _matchMorale(defendingTeamData);
      var attackingEnergy = _teamEnergyFactor(attackingTeam);
      var defendingEnergy = _teamEnergyFactor(defendingTeamData);
      final tempoRhythm = _matchRhythm(possessingTeam);
      final defensiveRhythm = _matchRhythm(defendingTeam);
      final earlyStormActive =
          (specialEvent?['id'] as String? ?? '') == 'erken_firtina' &&
          minute <= 30;

      final pressTakeProbability =
          (0.035 +
              (defendingProfile['press_intensity']! - 0.5) * 0.05 +
              _doubleValue(defendingInstructions['press_bonus']) * 0.03) *
          weatherMods['press_bonus']! *
          defendingEnergy *
          max(0.88, defendingMorale) *
          defensiveRhythm *
          (earlyStormActive ? 1.08 : 1.0);
      final turnoverProbability =
          (0.03 +
              attackingProfile['tempo']! * 0.035 +
              attackingProfile['risk']! * 0.02 +
              _doubleValue(attackingInstructions['risk_pass']) * 0.04) *
          (1.0 + (defendingProfile['press_intensity']! - 0.5) * 0.6) *
          (1.0 + max(0.0, 1.0 - attackingEnergy) * 0.35);

      var wasPressed = false;
      var forcedTurnover = false;
      var counterForDef = false;

      if (_random.nextDouble() < pressTakeProbability) {
        wasPressed = true;
        if (_random.nextDouble() < turnoverProbability) {
          forcedTurnover = true;
          counterForDef =
              defendingProfile['line_height']! < 0.45 ||
              attackingProfile['line_height']! > 0.65;
          final newPossessing = defendingTeam;
          defendingTeam = possessingTeam;
          possessingTeam = newPossessing;
          final newAttacking = defendingTeamData;
          defendingTeamData = attackingTeam;
          attackingTeam = newAttacking;
          final newAttackingProfile = defendingProfile;
          defendingProfile = attackingProfile;
          attackingProfile = newAttackingProfile;
          final newAttackingInstructions = defendingInstructions;
          defendingInstructions = attackingInstructions;
          attackingInstructions = newAttackingInstructions;
          final newAttackingMorale = defendingMorale;
          defendingMorale = attackingMorale;
          attackingMorale = newAttackingMorale;
          final newAttackingEnergy = defendingEnergy;
          defendingEnergy = attackingEnergy;
          attackingEnergy = newAttackingEnergy;
          stats[possessingTeam]!['counter_attacks'] =
              _intValue(stats[possessingTeam]!['counter_attacks']) + 1;
          if (minute - lastEventMinute > 1) {
            final ballWinner = _getRandomPlayerByStat(
              (attackingTeam['on_pitch'] as Map).cast<String, dynamic>(),
              'savunma',
            );
            if (ballWinner.player != null) {
              chunkLog.add(
                "[normal]$minute' - ${ballWinner.player!['data']['name']} önde baskıyla topu kapıyor, ${attackingTeam['name']} geçişi başlatıyor.[/normal]",
              );
              lastEventMinute = minute;
            }
          }
        }
      }

      final passesNow = _estimatePasses(
        attackingTeam,
        weatherMods,
        wasPressed: wasPressed,
      );
      stats[possessingTeam]!['passes'] =
          _intValue(stats[possessingTeam]!['passes']) + passesNow.passes;
      stats[possessingTeam]!['good_passes'] =
          _intValue(stats[possessingTeam]!['good_passes']) +
          passesNow.goodPasses;

      if (_random.nextDouble() < 0.10 && minute - lastEventMinute > 2) {
        final midfielder = _getRandomPlayerByStat(
          (attackingTeam['on_pitch'] as Map).cast<String, dynamic>(),
          'pas',
        );
        if (midfielder.player != null) {
          final focus = attackingTeam['tactics']['focus'] as String? ?? 'Karma';
          final message = switch (focus) {
            'Kanatlardan' => 'kanatlara doğru açılıp savunmayı esnetiyor.',
            'Merkezden' => 'göbekte üçgenler kurup oyunu dikine taşıyor.',
            _ => 'oyunu rakip yarı alana yıkmaya çalışıyor.',
          };
          chunkLog.add(
            "[normal]$minute' - ${attackingTeam['name']} $message Top ${midfielder.player!['data']['name']}'da.[/normal]",
          );
          lastEventMinute = minute;
        }
      }

      var baseFrequency = _doubleValue(
        attackingTeam['tactics']['chance_freq'],
        0.16,
      );
      baseFrequency *= attackingMorale;
      baseFrequency *= tempoRhythm;
      baseFrequency *=
          1.0 + _doubleValue(attackingInstructions['chance_freq']) * 0.45;
      baseFrequency *= 0.92 + attackingProfile['transition_threat']! * 0.16;
      baseFrequency *= 0.93 + attackingProfile['support_runs']! * 0.12;
      baseFrequency *= 0.92 + attackingEnergy * 0.10;
      if (counterForDef) {
        baseFrequency *= 1.25;
      }
      if (wasPressed && !forcedTurnover) {
        baseFrequency *= 0.92;
      }
      if (weather == 'Yağmurlu') {
        baseFrequency *= 0.95;
      }
      baseFrequency *=
          1.0 - max(0.0, defendingProfile['rest_defense']! - 0.62) * 0.12;
      baseFrequency = _clampDouble(baseFrequency, 0.06, 0.42);

      if (_random.nextDouble() >= baseFrequency) {
        continue;
      }

      lastEventMinute = minute;
      stats[possessingTeam]!['dangerous_attacks'] =
          _intValue(stats[possessingTeam]!['dangerous_attacks']) + 1;

      var creationAttack =
          (_doubleValue(attackingTeam['mid_power']) * 0.55 +
              _doubleValue(attackingTeam['att_power']) * 0.45) *
          _doubleValue(attackingTeam['tactics']['chance_qual'], 1.0);
      var creationDefense =
          (_doubleValue(defendingTeamData['mid_power']) * 0.35 +
          _doubleValue(defendingTeamData['def_power']) * 0.65);
      creationAttack *= attackingMorale;
      creationAttack *= tempoRhythm * (earlyStormActive ? 1.06 : 1.0);
      creationAttack *=
          1.0 + _doubleValue(attackingInstructions['chance_qual']) * 0.55;
      creationAttack *=
          1.0 + _doubleValue(attackingInstructions['finish_bonus']) * 0.30;
      creationAttack *= 0.92 + attackingProfile['box_presence']! * 0.16;
      creationAttack *= 0.92 + attackingProfile['assist_bias']! * 0.12;
      creationAttack *= 0.94 + attackingProfile['support_runs']! * 0.10;
      creationAttack *= 0.92 + attackingEnergy * 0.12;
      creationDefense *= max(0.88, defendingMorale);
      creationDefense *= defensiveRhythm * (earlyStormActive ? 1.04 : 1.0);
      creationDefense *=
          1.0 + _doubleValue(defendingInstructions['defensive_shape']) * 0.55;
      creationDefense *= 0.92 + defendingProfile['rest_defense']! * 0.16;
      creationDefense *= 0.92 + defendingProfile['line_sync']! * 0.10;
      creationDefense *= 0.92 + defendingEnergy * 0.10;

      if (counterForDef) {
        creationAttack *= 1.12;
        creationDefense *= defendingProfile['line_height']! > 0.65
            ? 0.95
            : 1.05;
      }

      final crossType =
          attackingTeam['tactics']['crossing'] as String? ?? 'Yüksek Orta';
      final chanceStyle = _pickChanceStyle(
        attackingTeam,
        counterForDef: counterForDef,
        wasPressed: wasPressed,
      );
      if (chanceStyle == 'cross' || chanceStyle == 'wide_combination') {
        stats[possessingTeam]!['crosses'] =
            _intValue(stats[possessingTeam]!['crosses']) + 1;
      }
      creationAttack *=
          (crossType == 'Yüksek Orta' ? 1.02 : 1.03) *
          weatherMods['cross_success']!;
      creationDefense *=
          1.0 + (defendingProfile['press_intensity']! - 0.5) * 0.20;

      switch (chanceStyle) {
        case 'counter':
          creationAttack *= 1.12;
          creationDefense *= 0.95;
          break;
        case 'cross':
          creationAttack *=
              1.04 + _doubleValue(attackingInstructions['cross_focus']) * 0.18;
          creationDefense *= crossType == 'Yüksek Orta' ? 1.01 : 0.98;
          break;
        case 'through_ball':
          creationAttack *=
              1.06 + _doubleValue(attackingInstructions['risk_pass']) * 0.12;
          creationDefense *= 0.98;
          break;
        case 'long_shot':
          creationAttack *= 0.92;
          creationDefense *= 1.02;
          break;
        case 'wide_combination':
          creationAttack *= 1.01;
          break;
      }

      final onPitch = (attackingTeam['on_pitch'] as Map)
          .cast<String, dynamic>();
      var shooter = switch (chanceStyle) {
        'through_ball' => _getRandomPlayerByStat(
          onPitch,
          'hiz',
          secondaryStat: 'hucum',
          secondaryWeight: 0.46,
          isForwardBias: true,
        ),
        'long_shot' => _getRandomPlayerByStat(
          onPitch,
          'sut',
          secondaryStat: 'hucum',
          secondaryWeight: 0.28,
        ),
        _ => _getRandomPlayerByStat(
          onPitch,
          'sut',
          secondaryStat: 'hucum',
          secondaryWeight: 0.42,
          isForwardBias: true,
        ),
      };
      var assister = switch (chanceStyle) {
        'cross' || 'wide_combination' => _getRandomPlayerByStat(
          onPitch,
          'pas',
          secondaryStat: 'hiz',
          secondaryWeight: 0.24,
          preferMidfielders: true,
        ),
        'counter' => _getRandomPlayerByStat(
          onPitch,
          'hiz',
          secondaryStat: 'pas',
          secondaryWeight: 0.24,
        ),
        _ => _getRandomPlayerByStat(
          onPitch,
          'pas',
          secondaryStat: 'hucum',
          secondaryWeight: 0.18,
          preferMidfielders: true,
        ),
      };
      if (shooter.player != null &&
          assister.player != null &&
          shooter.player!['id'] == assister.player!['id']) {
        assister = const _PlayerPick(null, null);
      }
      final shooterInstruction = _primaryInstruction(shooter.player);
      final assistInstruction = _primaryInstruction(assister.player);
      if (shooterInstruction == 'Kanala Koş' &&
          (chanceStyle == 'through_ball' || chanceStyle == 'counter')) {
        creationAttack *= 1.05;
      }
      if (shooterInstruction == 'Hedef Santrfor' &&
          (chanceStyle == 'cross' || chanceStyle == 'wide_combination')) {
        creationAttack *= 1.04;
      }
      if (shooterInstruction == 'Ceza Sahasına Koşu' &&
          shooter.slot?.startsWith('MID') == true) {
        creationAttack *= 1.05;
      }
      if (shooterInstruction == 'Önde Baskı' && counterForDef) {
        creationAttack *= 1.03;
      }
      if (assistInstruction == 'Riskli Pas' && chanceStyle == 'through_ball') {
        creationAttack *= 1.06;
      }
      if (assistInstruction == 'Topu Kısa Kullan' &&
          chanceStyle == 'combination') {
        creationAttack *= 1.02;
      }
      if (assistInstruction == 'Bindirme Yap' &&
          (chanceStyle == 'cross' || chanceStyle == 'wide_combination')) {
        creationAttack *= 1.04;
      }
      if (shooter.player != null) {
        creationAttack *=
            0.94 +
            (_doubleValue(shooter.player!['data']['match_stats']['sut'], 60) /
                    100.0) *
                0.18;
      }
      if (assister.player != null) {
        creationAttack *=
            0.96 +
            (_doubleValue(assister.player!['data']['match_stats']['pas'], 60) /
                    100.0) *
                0.14;
      }

      final creationRoll =
          (_random.nextDouble() * (1.25 - 0.70) + 0.70) * creationAttack;
      final resistRoll =
          (_random.nextDouble() * (1.25 - 0.75) + 0.75) * creationDefense;
      final marker = _getRandomPlayerByStat(
        (defendingTeamData['on_pitch'] as Map).cast<String, dynamic>(),
        'savunma',
        secondaryStat: 'dayaniklilik',
        secondaryWeight: 0.30,
      );
      final goalkeeper = _pickGoalkeeper(defendingTeamData);

      if (shooter.player != null && _random.nextDouble() < 0.82) {
        chunkLog.add(
          "[event]$minute' - ${_buildUpNarration(chanceStyle, attackingTeam, shooter.player!, assister.player)}[/event]",
        );
      }

      final disciplinePressure =
          1.0 +
          _doubleValue(defendingInstructions['discipline_risk']) * 0.65 +
          max(0.0, 1.0 - defendingMorale) * 0.30;
      final injuryProbability =
          0.0045 *
          weatherMods['injury_rate']! *
          (1.0 + max(0.0, 1.0 - attackingEnergy) * 0.45) *
          disciplinePressure *
          ((((attackingTeam['facilities'] as List?)?.cast<String>() ??
                      const <String>[])
                  .contains('saglik_merkezi'))
              ? 0.84
              : 1.0);
      if (_random.nextDouble() < injuryProbability &&
          shooter.player != null &&
          marker.player != null &&
          _random.nextDouble() < (0.24 + weatherMods['foul_rate']! * 0.08)) {
        final markerInstruction = _primaryInstruction(marker.player);
        chunkLog.add(
          markerInstruction == 'Sert Müdahale'
              ? "[injury]$minute' - EYVAH! ${marker.player!['data']['name']} sert müdahale talimatını fazla kaçırdı. ${shooter.player!['data']['name']} yerde, sedye isteniyor.[/injury]"
              : "[injury]$minute' - EYVAH! ${marker.player!['data']['name']} çok sert girdi! ${shooter.player!['data']['name']} yerde, sedye isteniyor.[/injury]",
        );
        events['injuries']!.add(shooter.player!['id']);
        _autoSubstitute(
          attackingTeam,
          shooter.player!['id'] as String,
          reason: 'Sakatlık',
        );
        continue;
      }

      if (defendingTeamData['tactics']['offside_trap'] == true &&
          defendingProfile['line_height']! > 0.60 &&
          _random.nextDouble() <
              (0.14 +
                  attackingProfile['tempo']! * 0.06 +
                  _doubleValue(attackingInstructions['offside_risk']) * 0.12 +
                  max(0.0, defendingProfile['line_height']! - 0.60) * 0.18 +
                  defendingProfile['line_sync']! * 0.06)) {
        if (shooter.player != null) {
          stats[possessingTeam]!['offsides'] =
              _intValue(stats[possessingTeam]!['offsides']) + 1;
          chunkLog.add(
            "[normal]$minute' - Bayrak havada! ${attackingTeam['name']} hücumunda ${shooter.player!['data']['name']} ofsayta düşüyor.[/normal]",
          );
        }
        continue;
      }

      final foulProbability =
          0.11 *
          weatherMods['foul_rate']! *
          (1.0 + (defendingProfile['press_intensity']! - 0.5) * 0.22) *
          (1.0 + max(0.0, defendingProfile['foul_pressure']! - 0.50) * 0.35) *
          (1.0 +
              _doubleValue(defendingInstructions['discipline_risk']) * 0.55) *
          (1.0 + max(0.0, 1.0 - defendingEnergy) * 0.35) *
          max(0.92, 1.0 + (1.0 - defendingMorale) * 0.18);
      if (_random.nextDouble() < foulProbability &&
          marker.player != null &&
          shooter.player != null) {
        stats[defendingTeam]!['fouls'] =
            _intValue(stats[defendingTeam]!['fouls']) + 1;
        final isPenalty = _random.nextDouble() < 0.07;
        final cardRoll = _random.nextDouble();
        final markerInstruction = _primaryInstruction(marker.player);
        final markerId = marker.player!['id'] as String;
        final priorYellowCount = _yellowCardCounts[markerId] ?? 0;
        final cardRiskMultiplier = _specialCardRiskMultiplier();
        final redThreshold =
            (0.018 +
                _doubleValue(defendingInstructions['discipline_risk']) * 0.045 +
                max(0.0, 1.0 - defendingMorale) * 0.020) *
            cardRiskMultiplier;
        final yellowThreshold =
            redThreshold +
            (0.17 +
                    _doubleValue(defendingInstructions['discipline_risk']) *
                        0.06) *
                cardRiskMultiplier;

        if (cardRoll < redThreshold) {
          chunkLog.add(
            markerInstruction == 'Sert Müdahale'
                ? "[card_red]$minute' - DİREKT KIRMIZI! ${marker.player!['data']['name']} sert müdahale talimatının bedelini ödüyor, ${defendingTeamData['name']} 10 kişi![/card_red]"
                : "[card_red]$minute' - DİREKT KIRMIZI! ${marker.player!['data']['name']} rakibini biçti! ${defendingTeamData['name']} 10 kişi![/card_red]",
          );
          if (!events['red_cards']!.contains(markerId)) {
            events['red_cards']!.add(markerId);
          }
          if (marker.slot != null) {
            (defendingTeamData['on_pitch'] as Map).remove(marker.slot);
          }
          _adjustMatchMorale(defendingTeamData, -0.07);
          _adjustMatchMorale(attackingTeam, 0.02);
          _recalculateTeamPowers(defendingTeamData);
        } else if (cardRoll < yellowThreshold) {
          _yellowCardCounts[markerId] = priorYellowCount + 1;
          if (!events['yellow_cards']!.contains(markerId)) {
            events['yellow_cards']!.add(markerId);
          }
          if (_yellowCardCounts[markerId]! >= 2) {
            chunkLog.add(
              "[card_red]$minute' - İKİNCİ SARI! ${marker.player!['data']['name']} bu kez affedilmiyor ve oyun dışı kalıyor.[/card_red]",
            );
            if (!events['red_cards']!.contains(markerId)) {
              events['red_cards']!.add(markerId);
            }
            if (marker.slot != null) {
              (defendingTeamData['on_pitch'] as Map).remove(marker.slot);
            }
            performance[markerId] = (performance[markerId] ?? 0) - 8;
            _adjustMatchMorale(defendingTeamData, -0.06);
            _adjustMatchMorale(attackingTeam, 0.02);
            _recalculateTeamPowers(defendingTeamData);
          } else {
            chunkLog.add(
              markerInstruction == 'Sert Müdahale'
                  ? "[card_yellow]$minute' - Sarı Kart! ${marker.player!['data']['name']} sert müdahale ayarını abarttı.[/card_yellow]"
                  : "[card_yellow]$minute' - Sarı Kart! ${marker.player!['data']['name']} taktik faul yapıyor.[/card_yellow]",
            );
            performance[markerId] = (performance[markerId] ?? 0) - 5;
          }
        } else {
          chunkLog.add(
            "[normal]$minute' - Hakem faulü çaldı. ${marker.player!['data']['name']} uyarılıyor.[/normal]",
          );
        }

        if (isPenalty && shooter.player != null && goalkeeper != null) {
          final penaltyTakerId =
              attackingTeam['tactics']['set_piece_takers']['pen'] as String?;
          Map<String, dynamic> penaltyTaker = shooter.player!;
          if (penaltyTakerId != null) {
            final players = (attackingTeam['on_pitch'] as Map)
                .cast<String, dynamic>();
            for (final player in players.values) {
              if (player['id'] == penaltyTakerId) {
                penaltyTaker = (player as Map).cast<String, dynamic>();
                break;
              }
            }
          }

          chunkLog.add(
            "[event]$minute' - PENALTI! ${attackingTeam['name']} beyaz noktaya gidiyor. Topun başında ${penaltyTaker['data']['name']}.[/event]",
          );
          stats[possessingTeam]!['total_shots'] =
              _intValue(stats[possessingTeam]!['total_shots']) + 1;
          _recordChance(possessingTeam, 0.76, setPiece: true);

          final penaltyShot = _doubleValue(
            penaltyTaker['data']['match_stats']['sut'],
            70,
          );
          final penaltyRating = _doubleValue(
            penaltyTaker['data']['match_rating'],
            60,
          );
          final gkReflex =
              (_doubleValue(defendingTeamData['gk_power']) +
                  _doubleValue(goalkeeper.value['data']['match_rating'], 60) *
                      8) /
              (_doubleValue(defendingTeamData['gk_power']) +
                  _doubleValue(goalkeeper.value['data']['match_rating'], 60) *
                      8 +
                  1400.0);
          final scoreProbability = min(
            0.92,
            max(
              0.55,
              (penaltyShot / 100.0) +
                  (penaltyRating / 1000.0) +
                  0.12 -
                  gkReflex * 0.30,
            ),
          );

          if (_random.nextDouble() < scoreProbability) {
            stats[possessingTeam]!['shots_on_target'] =
                _intValue(stats[possessingTeam]!['shots_on_target']) + 1;
            score[possessingTeam] = _intValue(score[possessingTeam]) + 1;
            chunkLog.add(
              "[goal]$minute' - GOOOOOOOL! ${penaltyTaker['data']['name']} kaleciyi ters köşeye yatırdı! (Penaltı)[/goal]",
            );
            events['goals']!.add({
              'scorer_name': penaltyTaker['data']['name'],
              'assist_name': null,
            });
            performance[penaltyTaker['id'] as String] =
                (performance[penaltyTaker['id'] as String] ?? 0) + 25;
            _adjustMatchMorale(attackingTeam, 0.04);
            _adjustMatchMorale(defendingTeamData, -0.05);
          } else {
            stats[defendingTeam]!['saves'] =
                _intValue(stats[defendingTeam]!['saves']) + 1;
            chunkLog.add(
              "[chance]$minute' - KAÇTI! Kaleci ${goalkeeper.value['data']['name']} harika uzandı ve penaltıyı çıkardı![/chance]",
            );
            performance[goalkeeper.value['id'] as String] =
                (performance[goalkeeper.value['id'] as String] ?? 0) + 25;
          }
        } else if (goalkeeper != null && _random.nextDouble() < 0.24) {
          _playFreeKickChance(
            chunkLog: chunkLog,
            possessingTeam: possessingTeam,
            defendingTeam: defendingTeam,
            attackingTeam: attackingTeam,
            defendingTeamData: defendingTeamData,
            foulWinner: shooter.player!,
            goalkeeper: goalkeeper,
          );
        }
        continue;
      }

      if (resistRoll > creationRoll) {
        stats[defendingTeam]!['tackles'] =
            _intValue(stats[defendingTeam]!['tackles']) + 1;
        if (marker.player != null) {
          if (_random.nextDouble() < 0.26) {
            stats[possessingTeam]!['corners'] =
                _intValue(stats[possessingTeam]!['corners']) + 1;
            chunkLog.add(
              "[normal]$minute' - ${marker.player!['data']['name']} son anda ayak koydu, korner.[/normal]",
            );
            if (goalkeeper != null && _random.nextDouble() < 0.34) {
              _playCornerChance(
                chunkLog: chunkLog,
                possessingTeam: possessingTeam,
                defendingTeam: defendingTeam,
                attackingTeam: attackingTeam,
                defendingTeamData: defendingTeamData,
                goalkeeper: goalkeeper,
              );
            }
          } else {
            chunkLog.add(
              "[normal]$minute' - ${marker.player!['data']['name']} savunmada geçit vermedi.[/normal]",
            );
          }
          performance[marker.player!['id'] as String] =
              (performance[marker.player!['id'] as String] ?? 0) + 10;
        }
        continue;
      }

      if (shooter.player == null || goalkeeper == null) {
        continue;
      }

      stats[possessingTeam]!['total_shots'] =
          _intValue(stats[possessingTeam]!['total_shots']) + 1;
      final qualityRatio = creationRoll / max(1.0, resistRoll);
      var xg = max(0.05, min(0.65, 0.18 + (qualityRatio - 1.0) * 0.22));
      xg *= 0.94 + attackingProfile['box_presence']! * 0.10;
      xg *= 0.95 + attackingProfile['shot_patience']! * 0.08;
      xg *= 1.0 - max(0.0, defendingProfile['rest_defense']! - 0.64) * 0.10;
      final shooterAttack = _doubleValue(
        shooter.player!['data']['match_stats']['hucum'],
        55,
      );
      final shooterRating = _doubleValue(
        shooter.player!['data']['match_rating'],
        60,
      );
      final shot = _doubleValue(
        shooter.player!['data']['match_stats']['sut'],
        50,
      );
      final shooterStamina = _clampDouble(
        _doubleValue(shooter.player!['current_stamina'], 90) / 100,
        0.72,
        1.08,
      );
      final shooterThreat =
          (shot * 0.44 + shooterAttack * 0.30 + shooterRating * 0.26) / 100;
      xg *= _clampDouble(0.84 + shooterThreat * 0.22, 0.86, 1.15);
      xg *= _clampDouble(0.92 + shooterStamina * 0.10, 0.90, 1.04);
      switch (chanceStyle) {
        case 'counter':
          xg = min(0.74, xg + 0.08);
          break;
        case 'cross':
          xg = min(0.70, xg + 0.03);
          break;
        case 'through_ball':
          xg = min(0.74, xg + 0.05);
          break;
        case 'long_shot':
          xg = _clampDouble(0.07 + (qualityRatio - 0.9) * 0.10, 0.06, 0.22);
          break;
        case 'wide_combination':
          xg = min(0.68, xg + 0.02);
          break;
      }
      if (counterForDef) {
        xg = min(0.76, xg + 0.04);
      }
      if (xg > 0.40 && _random.nextDouble() < 0.32) {
        chunkLog.add(
          "[chance]$minute' - Savunma çizgisi bir anlığına dağıldı, ${attackingTeam['name']} çok net bir boşluk yakaladı![/chance]",
        );
      }
      _recordChance(possessingTeam, xg);

      final shooterName =
          shooter.player!['data']['name'] as String? ?? 'Oyuncu';
      final goalkeeperName =
          goalkeeper.value['data']['name'] as String? ?? 'Kaleci';
      var accuracy = (shot / 120.0) * 0.55 + 0.25;
      accuracy *= weatherMods['shot_acc']!;
      accuracy *= attackingMorale;
      accuracy *= 0.92 + attackingEnergy * 0.10;
      accuracy *=
          1.0 + _doubleValue(attackingInstructions['finish_bonus']) * 0.18;
      if (chanceStyle == 'through_ball') {
        accuracy *= 1.04;
      } else if (chanceStyle == 'long_shot') {
        accuracy *= 0.88;
      }
      if (wasPressed) {
        accuracy *= 0.95;
      }
      accuracy *= 0.90 + xg * 0.25;

      if (_random.nextDouble() > min(0.88, max(0.15, accuracy))) {
        chunkLog.add(
          "[normal]$minute' - ${_missNarration(chanceStyle, shooterName)}[/normal]",
        );
        performance[shooter.player!['id'] as String] =
            (performance[shooter.player!['id'] as String] ?? 0) - 2;
        continue;
      }

      stats[possessingTeam]!['shots_on_target'] =
          _intValue(stats[possessingTeam]!['shots_on_target']) + 1;

      final finishingBase =
          shot * 16 +
          shooterAttack * 10 +
          shooterRating * 8 +
          _doubleValue(shooter.player!['data']['match_stats']['pas'], 45) * 3 +
          _doubleValue(attackingInstructions['finish_bonus']) * 120;
      final finishingRoll =
          (_random.nextDouble() * (1.30 - 0.85) + 0.85) *
          finishingBase *
          (0.70 + xg * 1.15) *
          shooterStamina;
      final goalkeeperRating = _doubleValue(
        goalkeeper.value['data']['match_rating'],
        60,
      );
      final goalkeeperDefense = _doubleValue(
        goalkeeper.value['data']['match_stats']['savunma'],
        70,
      );
      final goalkeeperBase =
          _doubleValue(defendingTeamData['gk_power']) * 0.82 +
          goalkeeperDefense * 11 +
          goalkeeperRating * 7 +
          _doubleValue(defendingTeamData['def_power']) * 0.20 +
          _doubleValue(defendingInstructions['defensive_shape']) * 90;
      final assisterPass = assister.player == null
          ? 0.0
          : _doubleValue(assister.player!['data']['match_stats']['pas'], 60);
      final assisterRating = assister.player == null
          ? 0.0
          : _doubleValue(assister.player!['data']['match_rating'], 60);
      var assistProbability =
          assister.player == null || chanceStyle == 'long_shot'
          ? 0.0
          : 0.28 +
                min(0.22, xg * 0.42) +
                attackingProfile['assist_bias']! * 0.16 +
                assisterPass / 320.0 +
                assisterRating / 420.0;
      if (chanceStyle == 'cross') {
        assistProbability += 0.12;
      } else if (chanceStyle == 'through_ball') {
        assistProbability += 0.08;
      } else if (chanceStyle == 'counter') {
        assistProbability += 0.05;
      }
      if (assistInstruction == 'Riskli Pas' && chanceStyle == 'through_ball') {
        assistProbability += 0.10;
      }
      if (assistInstruction == 'Bindirme Yap' &&
          (chanceStyle == 'cross' || chanceStyle == 'wide_combination')) {
        assistProbability += 0.08;
      }
      if (assistInstruction == 'Hedef Santrfor' &&
          chanceStyle == 'wide_combination') {
        assistProbability += 0.05;
      }
      final goalkeeperRoll =
          (_random.nextDouble() * (1.30 - 0.85) + 0.85) * goalkeeperBase;
      final creditedAssist =
          assister.player != null &&
              _random.nextDouble() < assistProbability.clamp(0.0, 0.92)
          ? assister.player
          : null;
      final assistName = creditedAssist?['data']?['name'] as String?;
      if (creditedAssist != null) {
        stats[possessingTeam]!['key_passes'] =
            _intValue(stats[possessingTeam]!['key_passes']) + 1;
      }

      if (finishingRoll > goalkeeperRoll * 1.02) {
        score[possessingTeam] = _intValue(score[possessingTeam]) + 1;
        chunkLog.add(
          "[goal]$minute' - ${_goalNarration(chanceStyle, shooterName, assistName: assistName)}[/goal]",
        );
        events['goals']!.add({
          'scorer_name': shooterName,
          'assist_name': assistName,
        });
        if (creditedAssist != null) {
          performance[creditedAssist['id'] as String] =
              (performance[creditedAssist['id'] as String] ?? 0) + 14;
        }
        performance[shooter.player!['id'] as String] =
            (performance[shooter.player!['id'] as String] ?? 0) +
            (22 + xg * 25).toInt();
        performance[goalkeeper.value['id'] as String] =
            (performance[goalkeeper.value['id'] as String] ?? 0) - 12;
        _adjustMatchMorale(attackingTeam, 0.04);
        _adjustMatchMorale(defendingTeamData, -0.06);
        momentum = 50;
      } else {
        stats[defendingTeam]!['saves'] =
            _intValue(stats[defendingTeam]!['saves']) + 1;
        if (_random.nextDouble() < 0.60) {
          stats[possessingTeam]!['corners'] =
              _intValue(stats[possessingTeam]!['corners']) + 1;
        }
        chunkLog.add(
          "[chance]$minute' - ${_saveNarration(chanceStyle, shooterName, goalkeeperName)}[/chance]",
        );
        performance[goalkeeper.value['id'] as String] =
            (performance[goalkeeper.value['id'] as String] ?? 0) +
            (10 + xg * 18).toInt();
        performance[shooter.player!['id'] as String] =
            (performance[shooter.player!['id'] as String] ?? 0) + 4;
        if (_random.nextDouble() < 0.10 && xg > 0.35) {
          chunkLog.add(
            "[chance]$minute' - İnanılmaz! ${shooter.player!['data']['name']} vurdu, top direkten döndü![/chance]",
          );
        }
      }

      final additionalPasses = _estimatePasses(
        attackingTeam,
        weatherMods,
        hadAttack: true,
        wasPressed: wasPressed,
      );
      stats[possessingTeam]!['passes'] =
          _intValue(stats[possessingTeam]!['passes']) +
          max(0, additionalPasses.passes - passesNow.passes);
      stats[possessingTeam]!['good_passes'] =
          _intValue(stats[possessingTeam]!['good_passes']) +
          max(0, additionalPasses.goodPasses - passesNow.goodPasses);
    }

    log.addAll(chunkLog);
    final finished = minute >= 90;
    if (finished) {
      _finalizeMatch();
      chunkLog.add(
        "[event]MAÇ SONUCU: ${t1['name']} ${score['oyuncu_1']} - ${score['oyuncu_2']} ${t2['name']}[/event]",
      );
    }
    return MatchChunkResult(chunkLog, finished);
  }

  void _finalizeMatch() {
    for (final teamKey in ['oyuncu_1', 'oyuncu_2']) {
      final totalPasses = max(1, _intValue(stats[teamKey]!['passes']));
      final goodPasses = min(
        totalPasses,
        _intValue(stats[teamKey]!['good_passes']),
      );
      stats[teamKey]!['pass_percentage'] = ((goodPasses / totalPasses) * 100)
          .toInt();
      if (_intValue(stats[teamKey]!['possession_count']) == 0) {
        stats[teamKey]!['possession_count'] = 1;
      }
    }

    final totalPossession =
        _intValue(stats['oyuncu_1']!['possession_count']) +
        _intValue(stats['oyuncu_2']!['possession_count']);
    if (totalPossession > 0) {
      stats['oyuncu_1']!['possession_percent'] =
          ((_intValue(stats['oyuncu_1']!['possession_count']) /
                      totalPossession) *
                  100)
              .toInt();
      stats['oyuncu_2']!['possession_percent'] =
          100 - _intValue(stats['oyuncu_1']!['possession_percent']);
    } else {
      stats['oyuncu_1']!['possession_percent'] = 50;
      stats['oyuncu_2']!['possession_percent'] = 50;
    }

    final team1Players = (t1['on_pitch'] as Map).cast<String, dynamic>();
    for (final player in team1Players.values) {
      final id = player['id'] as String;
      performance[id] =
          (performance[id] ?? 0) +
          _doubleValue(player['data']['match_rating']) / 10;
    }
    final team2Players = (t2['on_pitch'] as Map).cast<String, dynamic>();
    for (final player in team2Players.values) {
      final id = player['id'] as String;
      performance[id] =
          (performance[id] ?? 0) +
          _doubleValue(player['data']['match_rating']) / 10;
    }
  }

  MatchFinalData getFinalData() {
    String? mvpId;
    if (performance.isNotEmpty) {
      mvpId = performance.entries
          .reduce(
            (best, current) => current.value > best.value ? current : best,
          )
          .key;
    }
    Map<String, dynamic>? mvpData;
    if (mvpId != null) {
      for (final team in [t1, t2]) {
        final onPitch = (team['on_pitch'] as Map).cast<String, dynamic>();
        for (final player in onPitch.values) {
          if (player['id'] == mvpId) {
            mvpData = {'id': mvpId, 'name': player['data']['name']};
            break;
          }
        }
        if (mvpData != null) {
          break;
        }
      }
    }

    final finalTeams = {
      'oyuncu_1': {
        'slots': {
          for (final player
              in (t1['on_pitch'] as Map).cast<String, dynamic>().values)
            player['id'] as String: player['data'],
        },
      },
      'oyuncu_2': {
        'slots': {
          for (final player
              in (t2['on_pitch'] as Map).cast<String, dynamic>().values)
            player['id'] as String: player['data'],
        },
      },
    };

    return MatchFinalData(
      score: Map<String, int>.from(score),
      log: List<String>.from(log),
      mvp: mvpData,
      finalTeams: finalTeams,
      events: {
        'goals': List<Map<String, dynamic>>.from(
          events['goals']!.cast<Map<String, dynamic>>(),
        ),
        'red_cards': List<String>.from(events['red_cards']!.cast<String>()),
        'yellow_cards': List<String>.from(
          events['yellow_cards']!.cast<String>(),
        ),
        'injuries': List<String>.from(events['injuries']!.cast<String>()),
      },
      stats: {
        'oyuncu_1': Map<String, dynamic>.from(stats['oyuncu_1']!),
        'oyuncu_2': Map<String, dynamic>.from(stats['oyuncu_2']!),
      },
      performance: Map<String, double>.from(performance),
    );
  }
}
