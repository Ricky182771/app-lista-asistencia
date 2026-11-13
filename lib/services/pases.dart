import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pase.dart';

final _db = FirebaseFirestore.instance;

// Las consultas filtran igual que las reglas; si no, Firestore rechaza la consulta completa.

Stream<QuerySnapshot<Map<String, dynamic>>> clasesDe(String uid) =>
    _db.collection('clases').where('profesorUid', isEqualTo: uid).snapshots();

Stream<QuerySnapshot<Map<String, dynamic>>> gruposDe(String uid) =>
    _db.collection('grupos').where('profesores', arrayContains: uid).snapshots();

/// Consulta y no `pases/{paseId}`: las reglas niegan leer un pase que todavía no existe (ver CLAUDE.md).
/// Devuelve cero o un documento.
Stream<QuerySnapshot<Map<String, dynamic>>> paseDelDia(String uid, String claseId, String fecha) =>
    _db
        .collection('pases')
        .where('profesorUid', isEqualTo: uid)
        .where('claseId', isEqualTo: claseId)
        .where('fecha', isEqualTo: fecha)
        .snapshots(includeMetadataChanges: true);

/// Pases de una clase en el mes: `fecha` en [desde, hasta). Usa el índice de firestore.indexes.json.
Stream<QuerySnapshot<Map<String, dynamic>>> pasesDelMes(
  String uid,
  String claseId,
  ({String desde, String hasta}) rango,
) =>
    _db
        .collection('pases')
        .where('profesorUid', isEqualTo: uid)
        .where('claseId', isEqualTo: claseId)
        .where('fecha', isGreaterThanOrEqualTo: rango.desde)
        .where('fecha', isLessThan: rango.hasta)
        .snapshots(includeMetadataChanges: true);

// Orden (y admin) leen grupos, clases y pases sin depender del documento, así que pueden consultar
// colecciones completas.

Stream<QuerySnapshot<Map<String, dynamic>>> todosLosGrupos() =>
    _db.collection('grupos').snapshots(includeMetadataChanges: true);

Stream<QuerySnapshot<Map<String, dynamic>>> todasLasClases() =>
    _db.collection('clases').snapshots(includeMetadataChanges: true);

Stream<QuerySnapshot<Map<String, dynamic>>> pasesDeLaFecha(String fecha) =>
    _db.collection('pases').where('fecha', isEqualTo: fecha).snapshots(includeMetadataChanges: true);

/// Sin `await` a propósito: sin internet el Future no se completa (ver CLAUDE.md).
/// [clase] es `clases/{claseId}`; el salón se fija aquí y las reglas ya no dejan cambiarlo.
Future<void> enviarPase({
  required String claseId,
  required Map<String, dynamic> clase,
  required String fecha,
  required String salon,
  required Map<String, int> estados,
}) =>
    _db.doc('pases/${paseId(claseId, fecha)}').set({
      'claseId': claseId,
      'grupoId': clase['grupoId'],
      'profesorUid': clase['profesorUid'],
      'materia': clase['materia'],
      'salon': salon,
      'fecha': fecha,
      // Hora del dispositivo: sin internet sigue siendo la hora real del pase (orden la usa para
      // saber cuál fue el de la mañana).
      'marcadoEn': Timestamp.now(),
      'enviadoEn': FieldValue.serverTimestamp(),
      'estados': estados,
    });

/// Un solo `update()` con lo que cambió; no toca `marcadoEn`. Sin `await` (ver [enviarPase]).
Future<void> guardarCambios(String paseId, Map<String, int> campos) =>
    _db.doc('pases/$paseId').update({...campos, 'editadoEn': FieldValue.serverTimestamp()});

/// Aviso cuando falla [enviarPase]. permission-denied sale si ya existía el pase de ese día (otra hora
/// en `marcadoEn`) pero también si le quitaron el acceso, así que no se afirma ninguna de las dos.
String mensajeErrorEnvio(Object e, String fecha) =>
    e is FirebaseException && e.code == 'permission-denied'
        ? 'El servidor no aceptó el pase del $fecha. Si ya habías pasado lista ese día desde otro '
            'dispositivo, se conservó ese.'
        : 'No se envió el pase del $fecha: $e';
