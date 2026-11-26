// Lógica pura del resumen del día del administrativo: sin Firebase, para poder probarla con
// `flutter test`.

import 'clase.dart';
import 'grupo.dart' show sinAcentos;
import 'pase.dart';

/// Qué clases se listan en el resumen.
enum FiltroDia {
  todas('Todas'),
  sinPase('Sin pase'),
  conPase('Con pase');

  const FiltroDia(this.etiqueta);
  final String etiqueta;
}

/// Una clase junto con su pase de ese día, si ya lo hay.
class ClaseDelDia {
  const ClaseDelDia({required this.clase, this.pase});
  final Clase clase;

  /// El documento `pases/{claseId}_{fecha}`; `null` si todavía no pasan lista.
  final Map<String, dynamic>? pase;

  bool get conPase => pase != null;

  Map<dynamic, dynamic> get _estados => (pase?['estados'] as Map?) ?? const {};

  /// Faltas sin justificar del pase.
  int get faltas => _estados.values.where((e) => e == falta).length;

  /// Faltas justificadas del pase.
  int get justificadas => _estados.values.where((e) => e == justificada).length;
}

/// Todas las clases de la escuela con su pase de un día.
class ResumenDelDia {
  const ResumenDelDia(this.clases);
  final List<ClaseDelDia> clases;

  int get total => clases.length;
  int get conPase => clases.where((c) => c.conPase).length;
  int get sinPase => total - conPase;
  int get faltas => clases.fold(0, (suma, c) => suma + c.faltas);
  int get justificadas => clases.fold(0, (suma, c) => suma + c.justificadas);

  /// Alguien pasó lista ese día. Si nadie lo hizo en toda la escuela (fin de semana, día festivo),
  /// no se resalta ninguna clase: no tiene caso marcarlas todas.
  bool get huboPases => conPase > 0;

  /// Resaltar la clase para ir a revisarla: no tiene pase en un día en que otros sí pasaron lista.
  /// La app no guarda horarios, así que es un aviso, no una falta del profe.
  bool resaltar(ClaseDelDia c) => huboPases && !c.conPase;

  /// UID de los profes que tienen clases y no pasaron lista en ninguna ese día. Vacío si
  /// [huboPases] es `false`.
  Set<String> get profesSinPase {
    if (!huboPases) return {};
    final conPases = {
      for (final c in clases)
        if (c.conPase) c.clase.profesorUid,
    };
    return {
      for (final c in clases)
        if (!conPases.contains(c.clase.profesorUid)) c.clase.profesorUid,
    };
  }
}

/// Une cada clase con su pase del día. [pases] son los documentos de `pases` de una misma fecha; los
/// de clases que ya no existen no cuentan.
ResumenDelDia resumenDelDia(Iterable<Clase> clases, Iterable<Map<String, dynamic>> pases) {
  final porClase = <String, Map<String, dynamic>>{};
  for (final p in pases) {
    final id = p['claseId'];
    if (id is String) porClase[id] = p;
  }
  return ResumenDelDia([
    for (final c in clases) ClaseDelDia(clase: c, pase: porClase[c.id]),
  ]);
}

/// Las clases del [resumen] que pasan el [filtro] y el grupo, en el orden en que se listan: primero
/// las que no tienen pase, luego por grupo, profe y materia. [nombresGrupo] y [nombresProfe] son
/// ID → nombre; sin nombre se usa el ID del grupo y el `profesorNombre` de la clase.
List<ClaseDelDia> listarDelDia(
  ResumenDelDia resumen, {
  FiltroDia filtro = FiltroDia.todas,
  String? grupoId,
  Map<String, String> nombresGrupo = const {},
  Map<String, String> nombresProfe = const {},
}) {
  bool pasa(ClaseDelDia c) => switch (filtro) {
        FiltroDia.todas => true,
        FiltroDia.sinPase => !c.conPase,
        FiltroDia.conPase => c.conPase,
      };
  String grupo(ClaseDelDia c) => sinAcentos(nombresGrupo[c.clase.grupoId] ?? c.clase.grupoId);
  String profe(ClaseDelDia c) =>
      sinAcentos(nombresProfe[c.clase.profesorUid] ?? c.clase.profesorNombre);
  String llave(ClaseDelDia c) =>
      '${c.conPase ? 1 : 0}\n${grupo(c)}\n${profe(c)}\n${sinAcentos(c.clase.materia)}\n${c.clase.id}';

  return [
    for (final c in resumen.clases)
      if ((grupoId == null || c.clase.grupoId == grupoId) && pasa(c)) c,
  ]..sort((a, b) => llave(a).compareTo(llave(b)));
}
