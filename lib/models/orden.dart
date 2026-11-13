// Lógica pura de la vista del encargado de orden: sin Firebase, para poder probarla con `flutter test`.

import 'package:intl/intl.dart';

import 'pase.dart';

/// El pase con `marcadoEn` más temprano (la hora en que el profe pasó lista, no la de envío).
/// `marcadoEn` es un `Timestamp` de Firestore; basta con que sea `Comparable`. Uno sin hora va al final.
Map<String, dynamic>? paseDeLaManana(Iterable<Map<String, dynamic>> pases) {
  Map<String, dynamic>? primero;
  for (final p in pases) {
    final hora = p['marcadoEn'] as Comparable<Object>?;
    final actual = primero?['marcadoEn'];
    if (primero == null || (hora != null && (actual == null || hora.compareTo(actual) < 0))) primero = p;
  }
  return primero;
}

/// Nombres de los alumnos con [valor] (`falta` o `justificada`) en [estados], ordenados por N.L.
/// Incluye a los dados de baja que tengan registro.
List<String> alumnosConEstado(List<dynamic> alumnos, Map<String, dynamic> estados, int valor) => [
  for (final f in filasDelPase(alumnos, estados))
    if (estados[f.nl] == valor) f.nombre.isEmpty ? 'N.L ${f.nl}' : f.nombre,
];

/// Texto para el grupo de padres. [fecha] "AAAA-MM-DD"; [nombres] = faltas sin justificar del pase
/// de la mañana. La redacción vive solo aquí.
String mensajeParaPadres(String grupo, String fecha, DateTime hoy, List<String> nombres) {
  final dia = DateFormat("EEEE d 'de' MMMM 'de' y", 'es_MX').format(DateTime.parse(fecha));
  final cuando = fecha == fechaLocal(hoy) ? 'hoy, $dia' : 'el $dia';
  final saludo = 'Buenos días, estimados padres de familia del grupo $grupo.';
  const firma = 'Atentamente,\nEncargados de orden';
  if (nombres.isEmpty) {
    return '$saludo\n\nLes informamos que $cuando, no hubo faltas sin justificar en el grupo.\n\n$firma';
  }
  return '$saludo\n\n'
      'Les informamos que $cuando, los siguientes alumnos no se presentaron a clase:\n\n'
      '${nombres.map((n) => '• $n').join('\n')}\n\n'
      'Les pedimos su apoyo para dar seguimiento. Para cualquier aclaración, pueden comunicarse con '
      'el área de orden.\n\n'
      '$firma';
}

typedef Resumen = ({int conPase, int clases, Map<String, dynamic>? manana, int faltas});

/// [claseIds] = clases del grupo; [pases] = pases del grupo ese día. `conPase` solo cuenta clases que
/// siguen existiendo; `faltas` = faltas sin justificar del pase de la mañana.
Resumen resumenDelGrupo(Set<String> claseIds, List<Map<String, dynamic>> pases) {
  final manana = paseDeLaManana(pases);
  final estados = (manana?['estados'] as Map?) ?? const {};
  return (
    conPase: {for (final p in pases) p['claseId']}.where(claseIds.contains).length,
    clases: claseIds.length,
    manana: manana,
    faltas: estados.values.where((e) => e == falta).length,
  );
}
