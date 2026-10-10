import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/session_controllers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../connection_screen.dart';
import 'register_screen.dart';

/// Screen that fills the viewport but scrolls when the keyboard needs room,
/// keeping its last child pinned to the bottom.
class FullHeightScroll extends StatelessWidget {
  const FullHeightScroll({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - (padding?.vertical ?? 0),
            ),
            child: IntrinsicHeight(child: child),
          ),
        ),
      );
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: c.line)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('o', style: AppText.text(14, color: c.ink3)),
          ),
          Expanded(child: Container(height: 1, color: c.line)),
        ],
      ),
    );
  }
}

/// "¿No tienes cuenta? Crear cuenta".
class AuthSwitchLine extends StatelessWidget {
  const AuthSwitchLine({
    super.key,
    required this.question,
    required this.action,
    required this.onTap,
  });

  final String question;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$question ', style: AppText.text(16, color: c.ink2)),
        TextAction(
          label: action,
          onPressed: onTap,
          color: c.ink,
          weight: FontWeight.w600,
          underline: true,
        ),
      ],
    );
  }
}

void goToConnectionAfterAuth(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const ConnectionScreen()),
    (_) => false,
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.app.auth.sessionExpired) {
        showMessage(context, 'Tu sesión terminó. Vuelve a iniciar sesión.');
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(AuthController auth) action) async {
    setState(() => _busy = true);
    try {
      await action(context.app.auth);
      if (mounted) goToConnectionAfterAuth(context);
    } on AuthException catch (error) {
      if (mounted) showMessage(context, error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: AutofillGroup(
          child: FullHeightScroll(
            padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 72),
                Text('Inicia sesión',
                    style: AppText.text(40,
                        weight: FontWeight.w500, height: 1.1, color: c.ink)),
                const SizedBox(height: 8),
                Text('Tus rutinas y tu historial se guardan en tu cuenta.',
                    style: AppText.text(17, color: c.ink2)),
                const SizedBox(height: 40),
                AppTextField(
                  label: 'Correo',
                  hint: 'nombre@correo.com',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: 20),
                AppTextField(
                  label: 'Contraseña',
                  hint: 'Tu contraseña',
                  controller: _password,
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _run(
                      (auth) => auth.signIn(_email.text, _password.text)),
                  trailing: TextAction(
                    label: '¿La olvidaste?',
                    size: 14,
                    underline: true,
                    onPressed: () => showMessage(
                      context,
                      'Recuperar la contraseña todavía no está disponible: '
                      'falta configurar el envío de correos.',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Entrar',
                  busy: _busy,
                  onPressed: () => _run(
                      (auth) => auth.signIn(_email.text, _password.text)),
                ),
                const OrDivider(),
                SecondaryButton(
                  label: 'Continuar con Google',
                  onPressed: _busy
                      ? null
                      : () => _run((auth) => auth.signInWithGoogle()),
                ),
                const Spacer(),
                const SizedBox(height: 24),
                AuthSwitchLine(
                  question: '¿No tienes cuenta?',
                  action: 'Crear cuenta',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const RegisterScreen()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
