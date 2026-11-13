// Lógica pura del pase de lista: sin Firebase, para poder probarla con `flutter test`.

import 'package:intl/intl.dart';

/// Estados de asistencia tal como se guardan en `pases.estados`. No hay otros valores.
const presente = 0;
const falta = 1;
const justificada = 2;

/// 0 → 1 → 2 → 0. Un valor desconocido vuelve a presente, así nunca se escribe otro valor.
int siguienteEstado(int e) => switch (e) {
      presente => falta,
      falta => justificada,
      _ => presente,
    };

/// Días hacia atrás (además de hoy) en que el profe puede crear o editar un pase.
const diasEditables = 28;

/// "AAAA-MM-DD" con la fecha local del dispositivo (México).
String fechaLocal(DateTime d) => DateFormat('yyyy-MM-dd').format(d.toLocal());

/// Igual que `editable()` de firestore.rules: de hoy hasta [diasEditables] días atrás, nunca futura.
/// Las reglas usan fechas en UTC y la app la fecha local. Como México va detrás de UTC, la fecha local
/// nunca queda en el futuro para el servidor, y el margen de un día de las reglas (29 contra la fecha
/// UTC) cubre hoy−28 local a cualquier hora.
bool esEditable(String fecha, DateTime hoy) {
  final f = DateTime.tryParse(fecha);
  if (f == null) return false;
  final h = hoy.toLocal();
  // En UTC para que un cambio de horario no deje un día de 23 o 25 horas.
  final dias = DateTime.utc(h.year, h.month, h.day).difference(DateTime.utc(f.year, f.month, f.day)).inDays;
  return dias >= 0 && dias <= diasEditables;
}

String claseId(String profesorUid, String grupoId) => '${profesorUid}_$grupoId';

String paseId(String claseId, String fecha) => '${claseId}_$fecha';

bool _activo(Map<dynamic, dynamic> alumno) => alumno['activo'] != false;

/// Estados de un pase nuevo: cada alumno activo del grupo en presente, con su N.L en texto como llave.
/// [alumnos] es `grupos.alumnos` tal como llega de Firestore: `[{num, nombre, activo}]`.
Map<String, int> estadosIniciales(List<dynamic> alumnos) => {
      for (final a in alumnos.cast<Map<dynamic, dynamic>>())
        if (_activo(a)) '${a['num']}': presente,
    };

typedef Fila = ({String nl, String nombre, bool baja});

/// Alumnos activos del grupo más cualquier N.L que ya tenga estado aunque hoy esté dado de baja,
/// ordenados por N.L.
List<Fila> filasDelPase(List<dynamic> alumnos, Map<String, dynamic> estados) {
  final porNl = {for (final a in alumnos.cast<Map<dynamic, dynamic>>()) '${a['num']}': a};
  final nls = {
    for (final a in porNl.values)
      if (_activo(a)) '${a['num']}',
    ...estados.keys,
  }.toList()
    ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
  return [
    for (final nl in nls)
      (
        nl: nl,
        nombre: '${porNl[nl]?['nombre'] ?? ''}',
        baja: porNl[nl] == null || !_activo(porNl[nl]!),
      ),
  ];
}

/// Campos del `update()` de un pase existente: `'estados.<N.L>': valor` solo de lo que cambió.
Map<String, int> camposEditados(Map<String, dynamic> estados, Map<String, int> cambios) => {
      for (final e in cambios.entries)
        if (estados[e.key] != e.value) 'estados.${e.key}': e.value,
    };
