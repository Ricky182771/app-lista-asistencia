import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/grupo.dart';

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

/// Un grupo, para editarlo. Lo pendiente se ve con `metadata.hasPendingWrites`.
Stream<DocumentSnapshot<Map<String, dynamic>>> grupo(String id) =>
    _db.doc('grupos/$id').snapshots(includeMetadataChanges: true);

/// Guarda la lista completa de un grupo que ya existe; solo toca `alumnos`.
/// Sin `await` a propósito (ver [crearGrupo]). `update()` falla si el grupo ya no existe.
Future<void> guardarAlumnos(String id, List<Alumno> alumnos) =>
    _db.doc('grupos/$id').update({
      'alumnos': [for (final a in alumnos) a.toMap()],
    });
