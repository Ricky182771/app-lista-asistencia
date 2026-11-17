import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/sesion.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _entrando = false;
  String? _error;
  // Siempre empieza marcada: lo guardado solo lo usa configurarWeb() al cargar la página.
  bool _compartida = true;

  @override
  void initState() {
    super.initState();
    _aplicarPersistencia();
  }

  // Aquí y no en entrarConGoogle(): un `await` antes del popup hace que Safari lo bloquee.
  void _aplicarPersistencia() {
    if (kIsWeb) FirebaseAuth.instance.setPersistence(configuracionWeb(_compartida).auth);
  }

  Future<void> _entrar() async {
    setState(() {
      _entrando = true;
      _error = null;
    });
    final reloj = Stopwatch()..start();
    if (kIsWeb) guardarComputadoraCompartida(_compartida);
    try {
      await entrarConGoogle(); // authStateChanges() cambia la pantalla
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e, reloj.elapsed));
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('PaseLista', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              _entrando
                  ? const CircularProgressIndicator()
                  : FilledButton.icon(
                      onPressed: _entrar,
                      icon: const Icon(Icons.login),
                      label: const Text('Entrar con Google'),
                    ),
              if (kIsWeb) ...[
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: CheckboxListTile(
                    value: _compartida,
                    onChanged: _entrando
                        ? null
                        : (v) {
                            setState(() => _compartida = v!);
                            _aplicarPersistencia();
                          },
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Computadora compartida'),
                    subtitle: _compartida
                        ? const Text('Tu sesión se cerrará al cerrar el navegador y no se guardarán '
                            'datos en esta computadora.')
                        : null,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
