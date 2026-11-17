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
  // La caché de Firestore se configuró al cargar la página con este valor.
  final bool _compartidaAlCargar = kIsWeb && computadoraCompartida();
  late bool _compartida = _compartidaAlCargar;

  Future<void> _entrar() async {
    setState(() {
      _entrando = true;
      _error = null;
    });
    final reloj = Stopwatch()..start();
    try {
      await entrarConGoogle(compartida: _compartida); // authStateChanges() cambia la pantalla
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
                            guardarComputadoraCompartida(v!);
                            setState(() => _compartida = v);
                          },
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Computadora compartida'),
                    subtitle: Text([
                      if (_compartida)
                        'Tu sesión se cerrará al cerrar el navegador y no se guardarán datos '
                            'en esta computadora.',
                      if (_compartida != _compartidaAlCargar)
                        'Recarga la página para aplicar el cambio a los datos guardados.',
                    ].join(' ')),
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
