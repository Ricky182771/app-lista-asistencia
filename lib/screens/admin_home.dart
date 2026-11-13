import 'package:flutter/material.dart';

import '../models/rol.dart';
import '../services/sesion.dart';
import 'inicio.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key, required this.usuario});
  final Map<String, dynamic> usuario;

  @override
  Widget build(BuildContext context) {
    return Inicio(
      usuario: usuario,
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
        Text('Invitaciones', style: Theme.of(context).textTheme.titleMedium),
        StreamBuilder(
          stream: invitaciones(),
          builder: (context, snap) {
            if (snap.hasError) return Text('Error al cargar: ${snap.error}');
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) return const ListTile(title: Text('Aún no hay invitaciones.'));
            return Column(
              children: [
                for (final d in docs)
                  ListTile(
                    leading: Icon(
                      d.metadata.hasPendingWrites ? Icons.cloud_upload_outlined : Icons.mail_outline,
                    ),
                    title: Text(d.id),
                    subtitle: Text([
                      parseRol(d.data()['rol'])?.etiqueta ?? '${d.data()['rol']}',
                      if (d.metadata.hasPendingWrites) 'pendiente de sincronizar',
                    ].join(' · ')),
                  ),
              ],
            );
          },
        ),
      ],
    );
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
