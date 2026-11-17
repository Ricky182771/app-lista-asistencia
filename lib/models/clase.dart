// Lógica pura de las clases: sin Firebase, para poder probarla con `flutter test`.

import 'grupo.dart';

/// Una clase = un profesor + un grupo + una materia. El ID lo genera Firestore al dar de alta, así
/// la materia y el salón se pueden corregir sin cambiarlo (los pases `{claseId}_{fecha}` dependen de
/// él). Las clases viejas con ID `{profesorUid}_{grupoId}` siguen sirviendo: todo usa el ID del documento.
class Clase {
  const Clase({
    required this.id,
    required this.profesorUid,
    required this.grupoId,
    required this.materia,
    required this.salon,
  });

  /// `''` en una clase que aún no se da de alta.
  final String id;
  final String profesorUid;
  final String grupoId;
  final String materia;
  final String salon;

  Map<String, dynamic> toMap() =>
      {'profesorUid': profesorUid, 'grupoId': grupoId, 'materia': materia, 'salon': salon};
}

/// Convierte el documento `clases/{id}`; `null` si le falta el profesor o el grupo.
Clase? claseDe(String id, Map<String, dynamic>? datos) {
  final profesorUid = datos?['profesorUid'];
  final grupoId = datos?['grupoId'];
  if (profesorUid is! String || profesorUid.isEmpty || grupoId is! String || grupoId.isEmpty) {
    return null;
  }
  return Clase(
    id: id,
    profesorUid: profesorUid,
    grupoId: grupoId,
    materia: '${datos?['materia'] ?? ''}',
    salon: '${datos?['salon'] ?? ''}',
  );
}

/// ¿Otra de [clases] ya es de ese profe con esa materia? Compara sin espacios de sobra, mayúsculas
/// ni acentos ("matematicas " = "Matemáticas"). Ignora la que tiene el ID de [clase]: al editarla no
/// choca consigo misma.
bool materiaRepetida(Iterable<Clase> clases, Clase clase) {
  String llave(String materia) => sinAcentos(limpiarNombre(materia));
  return clases.any((c) =>
      c.id != clase.id && c.profesorUid == clase.profesorUid && llave(c.materia) == llave(clase.materia));
}

/// Al borrar [borrada], ¿se quita al profe de `grupos.profesores`? Solo si ya no le queda otra clase
/// con el grupo; si no, dejaría de ver el grupo de la otra. [delGrupo] = las clases de ese grupo.
bool quitarProfeDelGrupo(Iterable<Clase> delGrupo, Clase borrada) =>
    !delGrupo.any((c) => c.id != borrada.id && c.profesorUid == borrada.profesorUid);

/// Largo máximo de la materia y del salón: son etiquetas que se ven en una línea.
const maxEtiqueta = 40;

/// Por qué no sirve una materia o un salón ya limpio; `null` si está bien.
/// [campo] es "la materia" o "el salón", para el mensaje.
String? errorEtiqueta(String valor, String campo) {
  final limpio = limpiarNombre(valor);
  if (limpio.isEmpty) return 'Escribe $campo.';
  if (limpio.length > maxEtiqueta) return 'Usa $maxEtiqueta caracteres o menos.';
  return null;
}

/// Las clases en el orden en que se listan: por nombre del profesor y luego por materia.
/// [nombres] es uid → nombre; un profesor que ya no está en la lista va al final.
List<Clase> ordenarClases(Iterable<Clase> clases, Map<String, String> nombres) {
  String llave(Clase c) => '${nombres[c.profesorUid]?.toLowerCase() ?? '￿'}\n'
      '${c.materia.toLowerCase()}\n${c.profesorUid}';
  return clases.toList()..sort((a, b) => llave(a).compareTo(llave(b)));
}
