import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/pases.dart';
import 'inicio.dart';
import 'pase_dia.dart';

class ProfesorHome extends StatefulWidget {
  const ProfesorHome({super.key, required this.usuario});
  final Map<String, dynamic> usuario;

  @override
  State<ProfesorHome> createState() => _ProfesorHomeState();
}

class _ProfesorHomeState extends State<ProfesorHome> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  // Se escuchan desde que entra el profe para que queden en caché y la app funcione sin internet.
  QuerySnapshot<Map<String, dynamic>>? _clases, _grupos;
  Object? _error;
  late final List<StreamSubscription<void>> _subs;

  @override
  void initState() {
    super.initState();
    void error(Object e) => setState(() => _error = e);
    _subs = [
      clasesDe(_uid).listen((s) => setState(() => _clases = s), onError: error),
      gruposDe(_uid).listen((s) => setState(() => _grupos = s), onError: error),
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
    final grupos = {for (final g in [...?_grupos?.docs]) g.id: g};
    String etiqueta(QueryDocumentSnapshot<Map<String, dynamic>> c) =>
        '${grupos[c['grupoId']]?['nombre'] ?? c['grupoId']} · ${c['materia']}';
    final clases = [...?_clases?.docs]..sort((a, b) => etiqueta(a).compareTo(etiqueta(b)));

    return Inicio(
      usuario: widget.usuario,
      children: [
        const SizedBox(height: 8),
        Text('Mis clases', style: Theme.of(context).textTheme.titleMedium),
        if (_error != null)
          Text('Error al cargar: $_error')
        else if (_clases == null || _grupos == null)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else if (clases.isEmpty)
          const ListTile(title: Text('Aún no tienes clases asignadas.'))
        else
          for (final c in clases)
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: Text(etiqueta(c)),
              // Sin el grupo (falta el uid en grupos.profesores) no hay lista de alumnos.
              subtitle: Text(grupos[c['grupoId']] == null ? 'Grupo no disponible' : 'Salón ${c['salon']}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: grupos[c['grupoId']] == null
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => PaseDia(
                            clase: c,
                            grupo: grupos[c['grupoId']]!,
                            titulo: etiqueta(c),
                          ),
                        ),
                      ),
            ),
      ],
    );
  }
}
