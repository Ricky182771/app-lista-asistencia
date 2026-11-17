import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/clase.dart';

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
/// IDs fijos y `arrayUnion`: repetirlo o hacerlo para otro profe no duplica ni quita a nadie. La clase
/// usa un ID fijo de prueba por profe (las de verdad tienen un ID generado por Firestore).
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
      ..set(_db.doc('clases/prueba-matematicas-$profesorUid'), {
        'profesorUid': profesorUid,
        'grupoId': _grupoId,
        'materia': 'Matemáticas',
        'salon': 'A1',
      }))
    .commit();

/// ¿El profe ya tiene Matemáticas en Prueba 3A, con cualquier ID (viejo, nuevo o de prueba)? Sin
/// internet `get()` responde con la caché.
Future<bool> yaTieneMatematicas(String profesorUid) async {
  final clases = await _db.collection('clases').where('grupoId', isEqualTo: _grupoId).get();
  return materiaRepetida(
    [for (final d in clases.docs) ?claseDe(d.id, d.data())],
    Clase(id: '', profesorUid: profesorUid, grupoId: _grupoId, materia: 'Matemáticas', salon: 'A1'),
  );
}

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
                    onTap: () async {
                      final avisos = ScaffoldMessenger.of(context);
                      void avisar(String m) => avisos.showSnackBar(SnackBar(content: Text(m)));
                      Navigator.pop(context);
                      try {
                        if (await yaTieneMatematicas(d.id)) {
                          return avisar('Ese profe ya tiene Matemáticas en Prueba 3A');
                        }
                      } catch (e) {
                        return avisar('No se crearon los datos de prueba: $e');
                      }
                      // Sin `await`: sin internet el Future no se completa (ver CLAUDE.md).
                      crearDatosPrueba(d.id)
                          .catchError((Object e) => avisar('No se crearon los datos de prueba: $e'));
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
