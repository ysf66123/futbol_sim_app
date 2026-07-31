import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/session_controller.dart';
import '../utils/dialogs.dart';
import '../utils/game_exception.dart';
import '../widgets/ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _maxTurns = TextEditingController();
  final _matchTurns = TextEditingController();
  final _augmentTurns = TextEditingController();
  final _incomeAmount = TextEditingController();
  final _riskSuccess = TextEditingController();
  final _riskFailure = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final config = context.read<SessionController>().gameConfig;
    _maxTurns.text = '${config['max_turns'] ?? 21}';
    _matchTurns.text = (config['match_turns'] as List? ?? const []).join(', ');
    _augmentTurns.text = (config['augment_turns'] as List? ?? const []).join(', ');
    _incomeAmount.text = '${config['income_amount'] ?? 175}';
    _riskSuccess.text = '${config['risk_success_amount'] ?? 300}';
    _riskFailure.text = '${config['risk_failure_amount'] ?? 50}';
  }

  @override
  void dispose() {
    _maxTurns.dispose();
    _matchTurns.dispose();
    _augmentTurns.dispose();
    _incomeAmount.dispose();
    _riskSuccess.dispose();
    _riskFailure.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = context.read<SessionController>();
    session.playClickSound();
    try {
      final updated = {
        'max_turns': int.parse(_maxTurns.text.trim()),
        'match_turns': _parseList(_matchTurns.text),
        'augment_turns': _parseList(_augmentTurns.text),
        'income_amount': int.parse(_incomeAmount.text.trim()),
        'risk_success_amount': int.parse(_riskSuccess.text.trim()),
        'risk_failure_amount': int.parse(_riskFailure.text.trim()),
        'turn_time_seconds': session.gameConfig['turn_time_seconds'] ?? 60,
        'shop_pool_size': session.gameConfig['shop_pool_size'] ?? 4,
        'shop_probabilities': session.gameConfig['shop_probabilities'],
      };
      await session.saveGameConfig(updated);
      if (!mounted) return;
      showGameSnack(context, 'Oda ayarları güncellendi.');
      session.switchView(GameView.preGame);
    } on FormatException {
      await showGameDialog(context, title: 'Hata', message: 'Lütfen sayısal değerleri doğru girin.');
    } on GameException catch (error) {
      await showGameDialog(context, title: error.title, message: error.message);
    }
  }

  List<int> _parseList(String raw) {
    return raw
        .split(',')
        .map((entry) => int.parse(entry.trim()))
        .toList()
      ..sort();
  }

  @override
  Widget build(BuildContext context) {
    return GamePageScaffold(
      title: 'Oda Ayarları',
      subtitle: 'Sadece ev sahibi düzenleyebilir',
      actions: [
        IconButton(
          onPressed: () => context.read<SessionController>().switchView(GameView.preGame),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          SectionCard(
            child: Column(
              children: [
                _numberField(_maxTurns, 'Toplam Tur'),
                const SizedBox(height: 12),
                _numberField(_matchTurns, 'Maç Turları (örn: 7, 14, 21)', keyboard: TextInputType.text),
                const SizedBox(height: 12),
                _numberField(_augmentTurns, 'Eklenti Turları (örn: 1, 3, 6)', keyboard: TextInputType.text),
                const SizedBox(height: 12),
                _numberField(_incomeAmount, 'Normal Gelir'),
                const SizedBox(height: 12),
                _numberField(_riskSuccess, 'Risk Başarı Ödülü'),
                const SizedBox(height: 12),
                _numberField(_riskFailure, 'Risk Başarısız Ödülü'),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Kaydet ve Geri Dön'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField(TextEditingController controller, String label, {TextInputType keyboard = TextInputType.number}) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
    );
  }
}
