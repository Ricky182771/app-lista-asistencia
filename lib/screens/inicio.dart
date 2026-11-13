import 'package:flutter/material.dart';

import '../models/rol.dart';
import '../services/sesion.dart';

/// Base común de los inicios por rol: foto, nombre, rol y cerrar sesión.
class Inicio extends StatelessWidget {
  const Inicio({super.key, required this.usuario, this.children = const []});
  final Map<String, dynamic> usuario;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final foto = usuario['fotoUrl'] as String?;
    final nombre = usuario['nombre'] as String? ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('PaseLista')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundImage: foto == null ? null : NetworkImage(foto),
              child: foto == null ? Text(nombre.isEmpty ? '?' : nombre[0]) : null,
            ),
            title: Text(nombre),
            subtitle: Text(parseRol(usuario['rol'])?.etiqueta ?? ''),
            trailing: IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: cerrarSesion,
              icon: const Icon(Icons.logout),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class ProfesorHome extends StatelessWidget {
  const ProfesorHome({super.key, required this.usuario});
  final Map<String, dynamic> usuario;

  @override
  Widget build(BuildContext context) => Inicio(usuario: usuario);
}

class OrdenHome extends StatelessWidget {
  const OrdenHome({super.key, required this.usuario});
  final Map<String, dynamic> usuario;

  @override
  Widget build(BuildContext context) => Inicio(usuario: usuario);
}
