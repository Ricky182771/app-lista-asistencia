import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/clase.dart';

final _db = FirebaseFirestore.instance;

/// Las clases de un grupo. Lo pendiente se ve con `metadata.hasPendingWrites`.
Stream<QuerySnapshot<Map<String, dynamic>>> clasesDelGrupo(String grupoId) => _db
    .collection('clases')
    .where('grupoId', isEqualTo: grupoId)
    .snapshots(includeMetadataChanges: true);

/// Los usuarios con rol de profesor, para elegir a quién se le da la clase.
Stream<QuerySnapshot<Map<String, dynamic>>> profesores() =>
    _db.collection('usuarios').where('rol', isEqualTo: 'profesor').snapshots();

/// Crea la clase con un ID nuevo de Firestore (se genera en el cliente, una sola vez: un reintento
/// sin internet no la duplica) y agrega al profe a `grupos.profesores` en el mismo `WriteBatch`: si no
/// se escriben juntos, el profe ve la clase pero las reglas no lo dejan leer su grupo.
/// Sin `await` a propósito: sin internet el Future no se completa (ver CLAUDE.md).
/// Quien llama revisa antes con `materiaRepetida`.
Future<void> darDeAltaClase(Clase clase) => (_db.batch()
      ..set(_db.collection('clases').doc(), clase.toMap())
      ..update(_db.doc('grupos/${clase.grupoId}'), {
        'profesores': FieldValue.arrayUnion([clase.profesorUid]),
      }))
    .commit();

/// Corrige la materia y el salón; el ID, el profe y el grupo no cambian, así que los pases siguen
/// ligados a la clase. Sin `await` a propósito (ver [darDeAltaClase]).
Future<void> editarClase(Clase clase) =>
    _db.doc('clases/${clase.id}').update({'materia': clase.materia, 'salon': clase.salon});

/// Pone al día `profesorNombre` en las clases de [cambios] (claseId → nombre, de
/// `nombresDesactualizados`), en lotes de 400 (límite de `WriteBatch`: 500).
/// Sin `await` a propósito (ver [darDeAltaClase]).
List<Future<void>> ponerNombresDeProfes(Map<String, String> cambios) {
  final ids = cambios.keys.toList();
  final lotes = <Future<void>>[];
  for (var i = 0; i < ids.length; i += 400) {
    final batch = _db.batch();
    for (final id in ids.skip(i).take(400)) {
      batch.update(_db.doc('clases/$id'), {'profesorNombre': cambios[id]});
    }
    lotes.add(batch.commit());
  }
  return lotes;
}

/// Borra la clase y, en el mismo `WriteBatch`, quita al profe de `grupos.profesores` si
/// [quitarProfe] (ver `quitarProfeDelGrupo`). Los pases ya hechos se conservan.
/// Sin `await` a propósito (ver [darDeAltaClase]).
Future<void> borrarClase(Clase clase, {required bool quitarProfe}) {
  final batch = _db.batch()..delete(_db.doc('clases/${clase.id}'));
  if (quitarProfe) {
    batch.update(_db.doc('grupos/${clase.grupoId}'), {
      'profesores': FieldValue.arrayRemove([clase.profesorUid]),
    });
  }
  return batch.commit();
}
