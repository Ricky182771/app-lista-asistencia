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

/// Crea la clase y agrega al profe a `grupos.profesores` en el mismo `WriteBatch`: si no se
/// escriben juntos, el profe ve la clase pero las reglas no lo dejan leer su grupo.
/// Sin `await` a propósito: sin internet el Future no se completa (ver CLAUDE.md).
/// Quien llama revisa antes que ese profe no tenga ya clase con el grupo: `set()` la reemplazaría.
Future<void> darDeAltaClase(Clase clase) => (_db.batch()
      ..set(_db.doc('clases/${clase.id}'), clase.toMap())
      ..update(_db.doc('grupos/${clase.grupoId}'), {
        'profesores': FieldValue.arrayUnion([clase.profesorUid]),
      }))
    .commit();

/// Borra la clase y quita al profe de `grupos.profesores` en el mismo `WriteBatch`. Como una clase
/// es profesor + grupo, ese profe ya no tiene otra clase con el grupo. Los pases ya hechos se
/// conservan. Sin `await` a propósito (ver [darDeAltaClase]).
Future<void> borrarClase(Clase clase) => (_db.batch()
      ..delete(_db.doc('clases/${clase.id}'))
      ..update(_db.doc('grupos/${clase.grupoId}'), {
        'profesores': FieldValue.arrayRemove([clase.profesorUid]),
      }))
    .commit();
