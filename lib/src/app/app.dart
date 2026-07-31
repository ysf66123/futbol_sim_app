import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/session_controller.dart';
import '../screens/augment_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/admin_screen.dart';
import '../screens/draft_screen.dart';
import '../screens/lobby_screen.dart';
import '../screens/pre_game_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/simulation_screen.dart';
import '../screens/tactic_style_screen.dart';
import '../screens/team_formation_screen.dart';
import '../screens/trade_center_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

class FootballSimApp extends StatelessWidget {
  const FootballSimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SessionController()..initialize(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Futbol Menajeri',
        theme: buildAppTheme(),
        home: const _AppShell(),
      ),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    if (session.isInitializing) {
      return const GamePageScaffold(
        title: 'Yükleniyor',
        child: LoadingView(message: 'Oyun verileri hazırlanıyor...'),
      );
    }

    final screen = switch (session.view) {
      GameView.auth => const AuthScreen(),
      GameView.lobby => const LobbyScreen(),
      GameView.admin => const AdminScreen(),
      GameView.preGame => const PreGameScreen(),
      GameView.settings => const SettingsScreen(),
      GameView.draft => const DraftScreen(),
      GameView.augment => const AugmentScreen(),
      GameView.formation => const TeamFormationScreen(),
      GameView.tactics => const TacticStyleScreen(),
      GameView.trade => const TradeCenterScreen(),
      GameView.simulation => const SimulationScreen(),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: KeyedSubtree(key: ValueKey(session.view.name), child: screen),
    );
  }
}
