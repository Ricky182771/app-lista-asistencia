import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/pase.dart';
import 'inicio.dart';

// Solo en depuración, mientras no exista el alta de grupos y clases (hito 2).
// Nombres inventados: los de test/fixtures/csv/01_utf8_bom_excel.csv. Nada de datos reales.
const _alumnos = [
  'Ana María Hernández López',
  'José Ángel Muñoz Pérez',
  'Luis Fernando García Ruiz',
  'María José Torres Vega',
  'Diego Ramírez Castillo',
  'Ximena Peña Núñez',
  'Jesús Güemes Ordóñez',
  'Sofía Íñiguez Ávila',
];
const _grupoId = 'prueba-3a';

final _db = FirebaseFirestore.instance;

/// Grupo "Prueba 3A", su clase de Matemáticas y el profe en `grupos.profesores`, en un solo batch.
/// IDs fijos y `arrayUnion`: repetirlo o hacerlo para otro profe no duplica ni quita a nadie.
Future<void> crearDatosPrueba(String profesorUid) => (_db.batch()
      ..set(
        _db.doc('grupos/$_grupoId'),
        {
          'nombre': 'Prueba 3A',
          'alumnos': [
            for (var i = 0; i < _alumnos.length; i++) {'num': i + 1, 'nombre': _alumnos[i], 'activo': true},
          ],
          'profesores': FieldValue.arrayUnion([profesorUid]),
        },
        SetOptions(merge: true),
      )
      ..set(_db.doc('clases/${claseId(profesorUid, _grupoId)}'), {
        'profesorUid': profesorUid,
        'grupoId': _grupoId,
        'materia': 'Matemáticas',
        'salon': 'A1',
      }))
    .commit();

class BotonDatosPrueba extends StatelessWidget {
  const BotonDatosPrueba({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _DialogoDatosPrueba(
            _db.collection('usuarios').where('rol', isEqualTo: 'profesor').get(),
          ),
        ),
        icon: const Icon(Icons.science_outlined),
        label: const Text('Crear datos de prueba'),
      ),
    );
  }
}

class _DialogoDatosPrueba extends StatelessWidget {
  const _DialogoDatosPrueba(this.profesores);
  final Future<QuerySnapshot<Map<String, dynamic>>> profesores;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Crear datos de prueba'),
      content: SizedBox(
        width: double.maxFinite,
        child: FutureBuilder(
          future: profesores,
          builder: (context, snap) {
            if (snap.hasError) return Text('Error al cargar profesores: ${snap.error}');
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;
            if (docs.isEmpty) return const Text('No hay usuarios con rol de profesor.');
            return ListView(
              shrinkWrap: true,
              children: [
                const Text('Crea el grupo "Prueba 3A" (8 alumnos inventados) y su clase de '
                    'Matemáticas en el salón A1 para:'),
                for (final d in docs)
                  ListTile(
                    title: Text('${d.data()['nombre'] ?? d.id}'),
                    subtitle: Text('${d.data()['email'] ?? ''}'),
                    onTap: () {
                      avisarSiFalla(context, crearDatosPrueba(d.id), 'No se crearon los datos de prueba');
                      Navigator.pop(context);
                    },
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      ],
    );
  }
}
