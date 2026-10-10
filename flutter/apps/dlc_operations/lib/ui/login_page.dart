import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../haptics.dart';
import '../main.dart' show OperationsController;
import '../validators.dart';
import 'kit.dart';
import 'motion.dart';

/// Sign-in: the wordmark leads, a short promise, one card, one action.
class LoginPage extends StatefulWidget {
  const LoginPage({required this.controller, super.key});
  final OperationsController controller;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(), password = TextEditingController();
  bool showPassword = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (form.currentState?.validate() ?? false) {
      await widget.controller.signIn(email.text, password.text);
      if (widget.controller.error != null) Haptics.error();
    } else {
      Haptics.error();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final busy = widget.controller.busy;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Entrance(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: BrandWordmark(height: 72),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Entrance(
                    index: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Operaciones',
                          style: TextStyle(
                            color: c.brand,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Iniciar sesión',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Entra con la cuenta que te asignó tu organización. Tu perfil define qué sucursales y acciones ves.',
                          style: TextStyle(color: c.muted, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Entrance(
                    index: 2,
                    child: DlcCard(
                      padding: const EdgeInsets.all(18),
                      child: Form(
                        key: form,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              enableSuggestions: false,
                              autofillHints: const [AutofillHints.username],
                              decoration: const InputDecoration(
                                labelText: 'Correo electrónico',
                                prefixIcon: Icon(CupertinoIcons.envelope),
                              ),
                              validator: emailAddress,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: password,
                              obscureText: !showPassword,
                              textInputAction: TextInputAction.go,
                              onFieldSubmitted: (_) => submit(),
                              autofillHints: const [AutofillHints.password],
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                prefixIcon: const Icon(CupertinoIcons.lock),
                                suffixIcon: IconButton(
                                  tooltip: showPassword
                                      ? 'Ocultar contraseña'
                                      : 'Mostrar contraseña',
                                  onPressed: () => setState(
                                    () => showPassword = !showPassword,
                                  ),
                                  icon: Icon(
                                    showPassword
                                        ? CupertinoIcons.eye_slash
                                        : CupertinoIcons.eye,
                                  ),
                                ),
                              ),
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Escribe tu contraseña.'
                                  : null,
                            ),
                            if (widget.controller.error != null) ...[
                              const SizedBox(height: 14),
                              ErrorState(message: widget.controller.error!),
                            ],
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: busy ? null : submit,
                                icon: busy
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimary,
                                        ),
                                      )
                                    : const Icon(
                                        CupertinoIcons.arrow_right_circle,
                                        size: 20,
                                      ),
                                label: Text(
                                  busy ? 'Verificando acceso...' : 'Entrar',
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.lock_shield, size: 14, color: c.muted),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Acceso protegido',
                          style: TextStyle(color: c.muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
