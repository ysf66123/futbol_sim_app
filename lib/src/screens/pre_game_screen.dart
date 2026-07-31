import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/session_controller.dart';
import '../theme/app_theme.dart';
import '../utils/dialogs.dart';
import '../widgets/ui.dart';

class PreGameScreen extends StatefulWidget {
  const PreGameScreen({super.key});

  @override
  State<PreGameScreen> createState() => _PreGameScreenState();
}

class _PreGameScreenState extends State<PreGameScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roomSubscription;

  String p1Name = 'Bekleniyor...';
  String p2Name = 'Bekleniyor...';
  bool p1Ready = false;
  bool p2Ready = false;
  bool isReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startListening());
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    super.dispose();
  }

  void _startListening() {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null) return;
    _roomSubscription?.cancel();
    _roomSubscription = roomRef.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (!mounted || data == null) return;
      setState(() {
        p1Name = data['p1_name'] as String? ?? 'Mavi Takım';
        p2Name = data['p2_name'] as String? ?? 'Bekleniyor...';
        p1Ready = data['p1_ready'] == true;
        p2Ready = data['p2_ready'] == true;
      });

      final started = data['is_started'] == true;
      if (started) {
        await session.loadGameConfig();
        if (!mounted) return;
        session.switchView(GameView.draft);
        return;
      }

      if (p1Ready && p2Ready && session.isHost) {
        await roomRef.update({'is_started': true});
      }
    });
  }

  Future<void> _toggleReady() async {
    final session = context.read<SessionController>();
    session.playClickSound();
    final roomRef = session.roomRef;
    if (roomRef == null) return;
    setState(() => isReady = !isReady);
    if (session.playerId == 'oyuncu_1') {
      await roomRef.update({'p1_ready': isReady});
    } else {
      await roomRef.update({'p2_ready': isReady});
    }
  }

  Future<void> _addBot(String difficulty) async {
    final session = context.read<SessionController>();
    session.playClickSound();
    final roomRef = session.roomRef;
    if (roomRef == null) return;
    await roomRef.update({
      'p2_name': 'BOT ($difficulty)',
      'p2_ready': true,
      'is_bot': true,
      'bot_difficulty': difficulty,
    });
    await roomRef.collection('players').doc('oyuncu_2').update({
      'team_name': 'BOT ($difficulty)',
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return GamePageScaffold(
      title: 'Maç Öncesi',
      subtitle: 'Oda Kodu: ${session.roomCode ?? '-'}',
      actions: [
        GameIconButton(
          tooltip: 'Lobi',
          onPressed: () => session.switchView(GameView.lobby),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _playerPanel(context, 'Ev Sahibi', p1Name, p1Ready, AppColors.info),
          const SizedBox(height: 14),
          _playerPanel(context, 'Rakip', p2Name, p2Ready, AppColors.danger),
          const SizedBox(height: 18),
          if (session.isHost) ...[
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Oda Kontrolü',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      GameFilledButton(
                        onPressed: () => session.switchView(GameView.settings),
                        child: const Text('Ayarlar'),
                      ),
                      GameOutlinedButton(
                        onPressed: () => _addBot('Kolay'),
                        child: const Text('Kolay Bot'),
                      ),
                      GameOutlinedButton(
                        onPressed: () => _addBot('Orta'),
                        child: const Text('Orta Bot'),
                      ),
                      GameOutlinedButton(
                        onPressed: () => _addBot('Zor'),
                        child: const Text('Zor Bot'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          GameFilledButton(
            onPressed: _toggleReady,
            style: FilledButton.styleFrom(
              backgroundColor: isReady ? AppColors.accent : AppColors.danger,
            ),
            child: Text(isReady ? 'Hazırım' : 'Hazır Değilim'),
          ),
          const SizedBox(height: 12),
          GameOutlinedButton(
            onPressed: () => showGameDialog(
              context,
              title: 'Bilgi',
              message:
                  'İki taraf da hazır olduğunda oyun otomatik olarak draft ekranına geçer.',
            ),
            child: const Text('Akış Bilgisi'),
          ),
        ],
      ),
    );
  }

  Widget _playerPanel(
    BuildContext context,
    String label,
    String name,
    bool ready,
    Color color,
  ) {
    return SectionCard(
      child: Row(
        children: [
          Container(
            width: 14,
            height: 64,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 6),
                Text(
                  name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          InfoBadge(
            label: ready ? 'Hazır' : 'Bekliyor',
            color: ready ? AppColors.accent : AppColors.warning,
          ),
        ],
      ),
    );
  }
}
