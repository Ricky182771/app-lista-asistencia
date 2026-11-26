import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/grupo.dart';
import '../models/lote_grupos.dart' show GrupoPorGuardar;

final _db = FirebaseFirestore.instance;

/// Todos los grupos, ordenados por ID. Lo pendiente se ve con `metadata.hasPendingWrites`.
Stream<QuerySnapshot<Map<String, dynamic>>> grupos() =>
    _db.collection('grupos').snapshots(includeMetadataChanges: true);

/// Crea `grupos/{id}` con la lista importada y sin profesores (se agregan al dar de alta una clase).
/// Sin `await` a propósito: sin internet el Future no se completa (ver CLAUDE.md).
/// Quien llama revisa antes que el ID no exista: `set()` reemplazaría el grupo completo.
Future<void> crearGrupo(String id, String nombre, List<Alumno> alumnos) =>
    _db.doc('grupos/$id').set({
      'nombre': nombre,
      'alumnos': [for (final a in alumnos) a.toMap()],
      'profesores': <String>[],
    });

/// Crea o actualiza varios grupos a la vez (Herramientas avanzadas), en lotes de 400 (límite de un
/// `WriteBatch`: 500). Con `nombre` crea el grupo (sin profesores; se agregan al dar de alta una
/// clase); sin `nombre` solo reemplaza `alumnos` de un grupo que ya existe. Quien llama revisa antes
/// que los IDs nuevos no existan (`validarGrupos`): `set()` reemplazaría el grupo completo.
/// Devuelve un Future por lote; sin `await` a propósito (ver [crearGrupo]).
List<Future<void>> guardarGrupos(List<GrupoPorGuardar> grupos) {
  final lotes = <Future<void>>[];
  for (final lote in enLotes(grupos, 400)) {
    final batch = _db.batch();
    for (final g in lote) {
      final ref = _db.doc('grupos/${g.id}');
      final alumnos = [for (final a in g.alumnos) a.toMap()];
      final nombre = g.nombre;
      if (nombre == null) {
        batch.update(ref, {'alumnos': alumnos});
      } else {
        batch.set(ref, {'nombre': nombre, 'alumnos': alumnos, 'profesores': <String>[]});
      }
    }
    lotes.add(batch.commit());
  }
  return lotes;
}

/// Un grupo, para editarlo. Lo pendiente se ve con `metadata.hasPendingWrites`.
Stream<DocumentSnapshot<Map<String, dynamic>>> grupo(String id) =>
    _db.doc('grupos/$id').snapshots(includeMetadataChanges: true);

/// Guarda la lista completa de un grupo que ya existe; solo toca `alumnos`.
/// Sin `await` a propósito (ver [crearGrupo]). `update()` falla si el grupo ya no existe.
Future<void> guardarAlumnos(String id, List<Alumno> alumnos) =>
    _db.doc('grupos/$id').update({
      'alumnos': [for (final a in alumnos) a.toMap()],
    });

/// Cambia solo el nombre que se muestra. El ID no cambia (de él dependen `clases.grupoId` y
/// `pases.grupoId`), así que un grupo renombrado conserva el ID de su nombre original.
/// Sin `await` a propósito (ver [crearGrupo]). Quien llama revisa antes con `errorRenombrar`.
Future<void> renombrarGrupo(String id, String nombre) =>
    _db.doc('grupos/$id').update({'nombre': nombre});

/// Lo que se borra junto con el grupo.
typedef ContenidoGrupo = ({
  List<DocumentReference<Map<String, dynamic>>> clases,
  List<DocumentReference<Map<String, dynamic>>> pases,
});

const _servidor = GetOptions(source: Source.server);

/// Clases y pases del grupo, leídos del **servidor**: sin internet falla (`unavailable`) en vez de
/// responder con la caché, que podría no tener todos los pases y dejaría huérfanos al borrar.
Future<ContenidoGrupo> contenidoDelGrupo(String id) async {
  final clases = await _db.collection('clases').where('grupoId', isEqualTo: id).get(_servidor);
  final pases = await _db.collection('pases').where('grupoId', isEqualTo: id).get(_servidor);
  return (
    clases: [for (final d in clases.docs) d.reference],
    pases: [for (final d in pases.docs) d.reference],
  );
}

/// Borra el grupo, sus clases y todos sus pases. Necesita internet: aquí sí se espera cada lote.
///
/// Orden: primero los pases, luego las clases y el grupo al final, en lotes de 400 (el límite de un
/// `WriteBatch` es 500). Si algo falla a medio camino, el grupo sigue en la lista y se puede volver a
/// intentar. Al final se repasa: un pase enviado sin internet que llegó mientras se borraba (después
/// de borrar las clases ya no puede entrar ninguno: las reglas piden que la clase exista).
/// [progreso] recibe (borrados, total) después de cada lote.
Future<void> borrarGrupo(
  String id,
  ContenidoGrupo contenido, {
  void Function(int hechos, int total)? progreso,
}) async {
  final refs = [...contenido.pases, ...contenido.clases, _db.doc('grupos/$id')];
  var hechos = 0;
  for (final lote in enLotes(refs, 400)) {
    final batch = _db.batch();
    for (final r in lote) {
      batch.delete(r);
    }
    await batch.commit();
    hechos += lote.length;
    progreso?.call(hechos, refs.length);
  }
  final rezagados = await _db.collection('pases').where('grupoId', isEqualTo: id).get(_servidor);
  for (final lote in enLotes(rezagados.docs, 400)) {
    final batch = _db.batch();
    for (final d in lote) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }
}
