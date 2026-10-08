import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/session_controllers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
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

  void _submit() => _run(
        (auth) => auth.signUp(_name.text, _email.text, _password.text),
      );

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
                SizedBox(
                  height: 56,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Transform.translate(
                      offset: const Offset(-12, 0),
                      child: IconTapTarget(
                        icon: AppIconKind.back,
                        label: 'Volver a iniciar sesión',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Crea tu cuenta',
                    style: AppText.text(40,
                        weight: FontWeight.w500, height: 1.1, color: c.ink)),
                const SizedBox(height: 32),
                AppTextField(
                  label: 'Nombre',
                  hint: 'Cómo te llamas',
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                ),
                const SizedBox(height: 20),
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
                  hint: 'Mínimo 8 caracteres',
                  controller: _password,
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Crear cuenta',
                  busy: _busy,
                  onPressed: _submit,
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
                  question: '¿Ya tienes cuenta?',
                  action: 'Inicia sesión',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
