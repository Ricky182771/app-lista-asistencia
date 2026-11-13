import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/rol.dart';
import '../services/sesion.dart';
import 'inicio.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key, required this.usuario});
  final Map<String, dynamic> usuario;

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  final _miUid = FirebaseAuth.instance.currentUser?.uid;
  // Suscripciones en el estado: el ListView de Inicio construye perezosamente y un StreamBuilder
  // creado tarde se perdería el primer snapshot.
  QuerySnapshot<Map<String, dynamic>>? _usuarios, _invitaciones;
  Object? _errorUsuarios, _errorInvitaciones;
  late final List<StreamSubscription<void>> _subs;

  @override
  void initState() {
    super.initState();
    _subs = [
      usuarios().listen(
        (s) => setState(() => _usuarios = s),
        onError: (Object e) => setState(() => _errorUsuarios = e),
      ),
      invitaciones().listen(
        (s) => setState(() => _invitaciones = s),
        onError: (Object e) => setState(() => _errorInvitaciones = e),
      ),
    ];
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titulo = Theme.of(context).textTheme.titleMedium;
    final usuariosOrdenados = [...?_usuarios?.docs]
      ..sort((a, b) => '${a.data()['nombre']}'.compareTo('${b.data()['nombre']}'));
    final conUsuario = {for (final d in usuariosOrdenados) '${d.data()['email']}'};
    return Inicio(
      usuario: widget.usuario,
      children: [
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _DialogoInvitar(),
            ),
            icon: const Icon(Icons.person_add),
            label: const Text('Invitar usuario'),
          ),
        ),
        const SizedBox(height: 16),
        Text('Usuarios', style: titulo),
        ..._seccion(_usuarios, _errorUsuarios, 'Aún no hay usuarios.', [
          for (final d in usuariosOrdenados) _filaUsuario(d),
        ]),
        const SizedBox(height: 16),
        Text('Invitaciones', style: titulo),
        ..._seccion(_invitaciones, _errorInvitaciones, 'Aún no hay invitaciones.', [
          for (final d in [...?_invitaciones?.docs])
            ListTile(
              leading: Icon(
                d.metadata.hasPendingWrites ? Icons.cloud_upload_outlined : Icons.mail_outline,
              ),
              title: Text(d.id),
              subtitle: Text([
                parseRol(d.data()['rol'])?.etiqueta ?? '${d.data()['rol']}',
                if (conUsuario.contains(d.id)) 'en uso',
                if (d.metadata.hasPendingWrites) 'pendiente de sincronizar',
              ].join(' · ')),
              // Sin la lista de usuarios no se sabe si está en uso: no se ofrece cancelar.
              trailing: _usuarios == null || conUsuario.contains(d.id)
                  ? null
                  : IconButton(
                      tooltip: 'Cancelar invitación',
                      icon: const Icon(Icons.close),
                      onPressed: () => _avisarSiFalla(
                        cancelarInvitacion(d.id),
                        'No se canceló la invitación de ${d.id}',
                      ),
                    ),
            ),
        ]),
      ],
    );
  }

  /// Carga, error, vacío o las filas; con aviso si hay cambios sin sincronizar.
  List<Widget> _seccion(
    QuerySnapshot<Map<String, dynamic>>? snap,
    Object? error,
    String vacia,
    List<Widget> filas,
  ) {
    if (error != null) return [Text('Error al cargar: $error')];
    if (snap == null) {
      return const [
        Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      ];
    }
    return [
      // Un borrado pendiente ya no tiene documento que marcar: se avisa en la consulta.
      if (snap.metadata.hasPendingWrites)
        const ListTile(
          leading: Icon(Icons.cloud_upload_outlined),
          title: Text('Hay cambios pendientes de sincronizar'),
        ),
      if (filas.isEmpty) ListTile(title: Text(vacia)) else ...filas,
    ];
  }

  Widget _filaUsuario(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final datos = d.data();
    final nombre = '${datos['nombre'] ?? ''}';
    final correo = '${datos['email'] ?? ''}';
    final soyYo = d.id == _miUid;
    return ListTile(
      leading: Avatar(fotoUrl: datos['fotoUrl'] as String?, nombre: nombre),
      title: Text(nombre),
      subtitle: Text([
        correo,
        parseRol(datos['rol'])?.etiqueta ?? '${datos['rol']}',
        if (d.metadata.hasPendingWrites) 'pendiente de sincronizar',
      ].join(' · ')),
      trailing: TextButton(
        // Un admin no puede quitarse el acceso a sí mismo.
        onPressed: soyYo ? null : () => _confirmarQuitar(d.id, nombre, correo),
        child: const Text('Quitar acceso'),
      ),
    );
  }

  Future<void> _confirmarQuitar(String uid, String nombre, String correo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar acceso'),
        content: Text('$nombre ($correo) ya no podrá entrar a PaseLista '
            'hasta que lo vuelvas a invitar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitar acceso'),
          ),
        ],
      ),
    );
    if (ok == true) _avisarSiFalla(quitarAcceso(uid, correo), 'No se quitó el acceso a $correo');
  }

  /// Sin `await`: sin internet el Future no se completa (ver CLAUDE.md); solo avisa si falla.
  void _avisarSiFalla(Future<void> escritura, String mensaje) {
    final avisos = ScaffoldMessenger.of(context);
    escritura.catchError((Object e) {
      avisos.showSnackBar(SnackBar(content: Text('$mensaje: $e')));
    });
  }
}

class _DialogoInvitar extends StatefulWidget {
  const _DialogoInvitar();

  @override
  State<_DialogoInvitar> createState() => _DialogoInvitarState();
}

class _DialogoInvitarState extends State<_DialogoInvitar> {
  final _correo = TextEditingController();
  Rol _rol = Rol.profesor;
  String? _error;

  @override
  void dispose() {
    _correo.dispose();
    super.dispose();
  }

  void _guardar() {
    final correo = normalizarCorreo(_correo.text);
    if (!RegExp(r'^[^@\s/]+@[^@\s/]+\.[^@\s/]+$').hasMatch(correo)) {
      setState(() => _error = 'Escribe un correo válido.');
      return;
    }
    final avisos = ScaffoldMessenger.of(context);
    invitar(correo, _rol).catchError((Object e) {
      avisos.showSnackBar(SnackBar(content: Text('No se guardó la invitación de $correo: $e')));
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invitar usuario'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _correo,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'Correo de Google', errorText: _error),
            onSubmitted: (_) => _guardar(),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<Rol>(
            initialValue: _rol,
            decoration: const InputDecoration(labelText: 'Rol'),
            items: [
              for (final r in Rol.values) DropdownMenuItem(value: r, child: Text(r.etiqueta)),
            ],
            onChanged: (r) => setState(() => _rol = r!),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Invitar')),
      ],
    );
  }
}
