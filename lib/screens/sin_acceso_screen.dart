import 'package:flutter/material.dart';

import '../services/sesion.dart';

class SinAccesoScreen extends StatelessWidget {
  const SinAccesoScreen({super.key, required this.correo});
  final String correo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 16),
              Text(
                'La cuenta $correo no tiene acceso.\n'
                'Pide a un administrativo que te invite y vuelve a entrar.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const BotonCerrarSesion(),
            ],
          ),
        ),
      ),
    );
  }
}

class BotonCerrarSesion extends StatelessWidget {
  const BotonCerrarSesion({super.key});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: cerrarSesion,
      icon: const Icon(Icons.logout),
      label: const Text('Cerrar sesión'),
    );
  }
}
