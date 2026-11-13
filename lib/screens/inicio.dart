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
    final nombre = usuario['nombre'] as String? ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('PaseLista')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: Avatar(fotoUrl: usuario['fotoUrl'] as String?, nombre: nombre),
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

/// Foto de Google o, si no hay o no carga (pasa en web, sobre todo en incógnito), la inicial.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.fotoUrl, required this.nombre});
  final String? fotoUrl;
  final String nombre;

  @override
  Widget build(BuildContext context) {
    final inicial = Text(nombre.isEmpty ? '?' : nombre.characters.first.toUpperCase());
    final foto = fotoUrl;
    return CircleAvatar(
      child: foto == null
          ? inicial
          : ClipOval(
              child: Image.network(foto,
                  width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, _, _) => inicial),
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
