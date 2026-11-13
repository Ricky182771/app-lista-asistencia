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

  Future<void> _entrar() async {
    setState(() {
      _entrando = true;
      _error = null;
    });
    final reloj = Stopwatch()..start();
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
