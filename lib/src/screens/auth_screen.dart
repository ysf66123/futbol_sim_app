import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/session_controller.dart';
import '../theme/app_theme.dart';
import '../utils/dialogs.dart';
import '../utils/game_exception.dart';
import '../widgets/ui.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _rememberMe = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _runAction(Future<void> Function() action) async {
    final session = context.read<SessionController>();
    session.playClickSound();
    try {
      await action();
    } on GameException catch (error) {
      if (!mounted) return;
      await showGameDialog(context, title: error.title, message: error.message);
    } catch (error) {
      if (!mounted) return;
      await showGameDialog(
        context,
        title: 'Bağlantı Hatası',
        message: '$error',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return GamePageScaffold(
      title: 'Kulüp Girişi',
      subtitle: session.firebaseReady
          ? 'Gir veya yeni kulüp oluştur.'
          : session.dbError,
      bottomBar: session.busy
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: LinearProgressIndicator(minHeight: 4),
            )
          : null,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kulüp Girişi',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-posta'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Şifre'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Kullanıcı adı (kayıt için)',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _rememberMe,
                  activeTrackColor: AppColors.accent,
                  title: const Text('Beni hatırla'),
                  subtitle: const Text('Giriş bilgileri bu cihazda saklanır.'),
                  onChanged: (value) => setState(() => _rememberMe = value),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GameFilledButton(
                        onPressed: session.busy
                            ? null
                            : () => _runAction(
                                () => session.login(
                                  email: _emailController.text.trim(),
                                  password: _passwordController.text.trim(),
                                  rememberMe: _rememberMe,
                                ),
                              ),
                        child: const Text('Giriş Yap'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GameOutlinedButton(
                        onPressed: session.busy
                            ? null
                            : () => _runAction(
                                () => session.register(
                                  email: _emailController.text.trim(),
                                  password: _passwordController.text.trim(),
                                  username: _usernameController.text.trim(),
                                  rememberMe: _rememberMe,
                                ),
                              ),
                        child: const Text('Kayıt Ol'),
                      ),
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
}
