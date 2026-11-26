import 'package:flutter/material.dart';

import '../models/rol.dart';
import '../services/sesion.dart';
import 'aviso_actualizacion.dart';

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
          const AvisoActualizacionTarjeta(),
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

/// Para escrituras sin `await` (sin internet el Future no se completa; ver CLAUDE.md): solo avisa si falla.
void avisarSiFalla(BuildContext context, Future<void> escritura, String mensaje) {
  final avisos = ScaffoldMessenger.of(context);
  escritura.catchError((Object e) {
    avisos.showSnackBar(SnackBar(content: Text('$mensaje: $e')));
  });
}

/// Igual que [avisarSiFalla], para escrituras por lote (varios `WriteBatch`): avisa una sola vez
/// cuántos lotes fallaron, aunque hayan sido varios. Los lotes que sí se guardaron no se deshacen.
void avisarSiFallan(BuildContext context, List<Future<void>> escrituras, String mensaje) {
  final avisos = ScaffoldMessenger.of(context);
  Object? primero;
  var fallaron = 0;
  Future.wait([
    for (final e in escrituras)
      e.catchError((Object error) {
        fallaron++;
        primero ??= error;
      }),
  ]).then((_) {
    if (fallaron == 0) return;
    avisos.showSnackBar(SnackBar(
      content: Text('$mensaje ($fallaron de ${escrituras.length} lotes): $primero. '
          'Revisa la lista y vuelve a intentarlo: lo que ya existe se omite.'),
    ));
  });
}
