import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/session_controller.dart';
import '../utils/dialogs.dart';
import '../utils/game_exception.dart';
import '../widgets/ui.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _roomCodeController = TextEditingController();

  @override
  void dispose() {
    _roomCodeController.dispose();
    super.dispose();
  }

  Future<void> _handle(Future<void> Function() action) async {
    final session = context.read<SessionController>();
    session.playClickSound();
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

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return GamePageScaffold(
      title: 'Lobi',
      subtitle: 'Hoş geldin, ${session.username ?? 'Menajer'}',
      actions: [
        if (session.isAdmin)
          IconButton(
            tooltip: 'Admin Paneli',
            onPressed: session.busy
                ? null
                : () => session.switchView(GameView.admin),
            icon: const Icon(Icons.admin_panel_settings_rounded),
          ),
        IconButton(
          tooltip: 'Çıkış yap',
          onPressed: session.busy ? null : () => _handle(session.logout),
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
      bottomBar: session.busy
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: LinearProgressIndicator(minHeight: 4),
            )
          : null,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Yeni Oda',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('Kendi odanı kur, bot ekle veya rakibini bekle.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: session.busy
                        ? null
                        : () => _handle(session.createRoom),
                    icon: const Icon(Icons.stadium_rounded),
                    label: const Text('Oda Oluştur'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Odaya Katıl',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _roomCodeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: '6 haneli oda kodu',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: session.busy
                        ? null
                        : () => _handle(
                            () => session.joinRoom(_roomCodeController.text),
                          ),
                    icon: const Icon(Icons.group_add_rounded),
                    label: const Text('Bağlan'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
