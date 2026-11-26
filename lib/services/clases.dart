import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/clase.dart';
import '../models/grupo.dart' show enLotes;

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

/// Da de alta varias clases a la vez (Herramientas avanzadas), cada una con su ID nuevo y agregando
/// al profe a `grupos.profesores` en el mismo `WriteBatch`, como [darDeAltaClase]. Cada clase son dos
/// escrituras, así que van en lotes de 200 (límite de un `WriteBatch`: 500). Devuelve un Future por
/// lote; sin `await` a propósito (ver [darDeAltaClase]). Quien llama revisa antes con `validarClases`.
List<Future<void>> darDeAltaClases(List<Clase> clases) {
  final lotes = <Future<void>>[];
  for (final lote in enLotes(clases, 200)) {
    final batch = _db.batch();
    for (final c in lote) {
      batch
        ..set(_db.collection('clases').doc(), c.toMap())
        ..update(_db.doc('grupos/${c.grupoId}'), {
          'profesores': FieldValue.arrayUnion([c.profesorUid]),
        });
    }
    lotes.add(batch.commit());
  }
  return lotes;
}

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

const _servidor = GetOptions(source: Source.server);

/// Pasa la clase a otro profe. A diferencia del resto, **espera con `await` y pide internet**: lee del
/// servidor las clases del grupo y los pases de la clase, y al final repasa que no quede ninguno a
/// nombre del profe anterior (puede pasar con un pase creado mientras corría el primer lote).
///
/// En el primer `WriteBatch` van la clase (profe nuevo, su nombre, materia y salón), `grupos.profesores`
/// (entra el nuevo; sale el anterior si ya no le queda otra clase con ese grupo) y los primeros pases;
/// el resto de los pases, en lotes de 400 después. Los pases ya hechos pasan al profe nuevo (cambia su
/// `profesorUid`) para que vea todo el historial de la clase y pueda corregir el pase de hoy si el
/// anterior ya lo había hecho; las reglas solo dejan al admin cambiar ese campo, y solo al profe que
/// la clase tiene al terminar el batch. Si algo falla a medio camino, volver a llamarla termina el
/// trabajo: lee el estado actual del servidor y solo mueve los pases que aún no son del profe nuevo.
/// [progreso] recibe (hechos, total) después de cada lote.
Future<void> reasignarClase({
  required Clase clase,
  required String profesorUid,
  required String profesorNombre,
  void Function(int hechos, int total)? progreso,
}) async {
  final claseRef = _db.doc('clases/${clase.id}');
  final actual = await claseRef.get(_servidor);
  if (!actual.exists) throw StateError('La clase ya no existe.');
  final anterior = '${actual.data()?['profesorUid']}';
  final delGrupo = await _db.collection('clases').where('grupoId', isEqualTo: clase.grupoId).get(_servidor);
  final pases = await _db.collection('pases').where('claseId', isEqualTo: clase.id).get(_servidor);

  final quitarAnterior = anterior != profesorUid &&
      !delGrupo.docs.any((d) => d.id != clase.id && d.data()['profesorUid'] == anterior);
  final porMover = [
    for (final d in pases.docs)
      if (d.data()['profesorUid'] != profesorUid) d.reference,
  ];
  // La clase, el grupo (hasta 2 escrituras) y hasta 395 pases en el primer lote: 398 como máximo (límite 500).
  final primeros = porMover.take(395).toList();
  final resto = porMover.skip(395).toList();
  var total = 1 + porMover.length;

  final primer = _db.batch()
    ..update(claseRef, {
      'profesorUid': profesorUid,
      'profesorNombre': profesorNombre,
      'materia': clase.materia,
      'salon': clase.salon,
    })
    ..update(_db.doc('grupos/${clase.grupoId}'), {
      'profesores': FieldValue.arrayUnion([profesorUid]),
    });
  if (quitarAnterior) {
    primer.update(_db.doc('grupos/${clase.grupoId}'), {
      'profesores': FieldValue.arrayRemove([anterior]),
    });
  }
  for (final ref in primeros) {
    primer.update(ref, {'profesorUid': profesorUid});
  }
  await primer.commit();
  var hechos = 1 + primeros.length;
  progreso?.call(hechos, total);

  Future<void> mover(List<DocumentReference<Map<String, dynamic>>> refs) async {
    for (final lote in enLotes(refs, 400)) {
      final batch = _db.batch();
      for (final ref in lote) {
        batch.update(ref, {'profesorUid': profesorUid});
      }
      await batch.commit();
      hechos += lote.length;
      progreso?.call(hechos, total);
    }
  }

  await mover(resto);

  // Repaso final, como el de `borrarGrupo`: un pase que el profe anterior creó entre la lectura de los
  // pases y el primer commit se quedó con su nombre. Desde el commit de la clase las reglas ya no dejan
  // crear pases a nombre del profe anterior, así que basta repasar unas pocas veces (por si el servidor
  // aún estaba poniéndose al día) y la lista se vacía.
  for (var vuelta = 0; vuelta < 3; vuelta++) {
    final de = await _db.collection('pases').where('claseId', isEqualTo: clase.id).get(_servidor);
    final rezagados = [
      for (final d in de.docs)
        if (d.data()['profesorUid'] != profesorUid) d.reference,
    ];
    if (rezagados.isEmpty) return;
    total += rezagados.length;
    await mover(rezagados);
  }
}
