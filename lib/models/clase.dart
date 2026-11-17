// Lógica pura de las clases: sin Firebase, para poder probarla con `flutter test`.

import 'grupo.dart';

/// Una clase = un profesor + un grupo. La materia es solo una etiqueta y el salón es el de siempre
/// (el profe lo puede corregir al pasar lista), así que ninguno de los dos forma parte del ID.
class Clase {
  const Clase({
    required this.profesorUid,
    required this.grupoId,
    required this.materia,
    required this.salon,
  });
  final String profesorUid;
  final String grupoId;
  final String materia;
  final String salon;

  /// ID determinístico de `clases/{id}`: repetir el alta sin internet no duplica la clase.
  String get id => idClase(profesorUid, grupoId);

  Map<String, dynamic> toMap() =>
      {'profesorUid': profesorUid, 'grupoId': grupoId, 'materia': materia, 'salon': salon};
}

/// `{profesorUid}_{grupoId}`. Es la misma fórmula que `claseId` de `pase.dart` (las reglas y los
/// pases dependen de ella); `clase_test.dart` comprueba que no se separen.
String idClase(String profesorUid, String grupoId) => '${profesorUid}_$grupoId';

/// Convierte un documento de `clases`; `null` si le falta el profesor o el grupo.
Clase? claseDe(Map<String, dynamic>? datos) {
  final profesorUid = datos?['profesorUid'];
  final grupoId = datos?['grupoId'];
  if (profesorUid is! String || profesorUid.isEmpty || grupoId is! String || grupoId.isEmpty) {
    return null;
  }
  return Clase(
    profesorUid: profesorUid,
    grupoId: grupoId,
    materia: '${datos?['materia'] ?? ''}',
    salon: '${datos?['salon'] ?? ''}',
  );
}

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
