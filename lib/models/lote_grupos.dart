// Importar varios grupos a la vez desde un CSV `grupo,N.L,nombre`: lectura, agrupación y validación.
// Lógica pura, sin Firebase, para poder probarla con `flutter test`.

import 'grupo.dart';
import 'lote_csv.dart';

/// Largo máximo del nombre de un grupo (el mismo del importador de un solo grupo).
const maxNombreGrupo = 40;

/// Una fila editable de la vista previa: un alumno de un grupo.
class FilaAlumnoLote {
  FilaAlumnoLote({
    required this.fila,
    required this.grupo,
    required this.numTexto,
    required this.nombre,
  });

  /// Fila del archivo; 0 si se agregó a mano.
  final int fila;
  String grupo;

  /// El N.L tal como se escribió, para mostrarlo aunque no sea válido.
  String numTexto;
  String nombre;

  /// El N.L como entero positivo; `null` si no lo es.
  int? get num {
    final t = numTexto.trim();
    if (!RegExp(r'^\d+$').hasMatch(t)) return null;
    final n = int.tryParse(t);
    return n != null && n > 0 ? n : null;
  }
}

class LecturaAlumnosLote {
  const LecturaAlumnosLote({required this.filas, this.errorGeneral});
  final List<FilaAlumnoLote> filas;
  final String? errorGeneral;
}

const _aliasAlumnos = {
  'grupo': ['grupo', 'nombre del grupo', 'grupos'],
  'nl': ['nl', 'n.l', 'n l', 'num', 'numero', 'numero de lista', 'no', 'no. de lista', 'lista'],
  'nombre': ['nombre', 'alumno', 'nombre completo', 'nombre del alumno', 'nombre alumno'],
};

/// Lee un CSV `grupo,N.L,nombre` con varios grupos en el mismo archivo (el encabezado es opcional).
LecturaAlumnosLote leerAlumnosLote(List<int> bytes) {
  final t = leerConColumnas(
    bytes,
    orden: const ['grupo', 'nl', 'nombre'],
    alias: _aliasAlumnos,
    obligatorias: const ['grupo', 'nl', 'nombre'],
  );
  if (t.errorGeneral != null) return LecturaAlumnosLote(filas: const [], errorGeneral: t.errorGeneral);
  return LecturaAlumnosLote(filas: [
    for (final f in t.filas)
      FilaAlumnoLote(
        fila: f.fila,
        grupo: t.valor(f, 'grupo'),
        numTexto: t.valor(f, 'nl'),
        nombre: t.valor(f, 'nombre'),
      ),
  ]);
}

/// Las filas de un mismo grupo. Dos nombres que dan el mismo ID ("IA 3A", "ia 3a", "IA-3A") son el
/// mismo grupo: se juntan y se avisa.
class GrupoLote {
  GrupoLote({required this.id, required this.nombre});

  /// `idGrupo(nombre)`; '' si el nombre no deja nada utilizable.
  final String id;

  /// Cómo se escribió la primera vez, ya limpio. Es el nombre con el que se guardaría.
  final String nombre;
  final List<FilaAlumnoLote> filas = [];

  /// Otras formas en que aparece escrito el mismo grupo en el archivo.
  final Set<String> variantes = {};
}

/// Agrupa las filas por grupo, en orden alfabético.
List<GrupoLote> agruparPorGrupo(List<FilaAlumnoLote> filas) {
  final grupos = <String, GrupoLote>{};
  for (final f in filas) {
    final nombre = limpiarNombre(f.grupo);
    final id = idGrupo(nombre);
    final g = grupos.putIfAbsent(id, () => GrupoLote(id: id, nombre: nombre));
    g.filas.add(f);
    if (nombre != g.nombre) g.variantes.add(nombre);
  }
  return grupos.values.toList()..sort((a, b) => sinAcentos(a.nombre).compareTo(sinAcentos(b.nombre)));
}

/// Lo que se sabe de un grupo del lote después de validarlo.
class ValidacionGrupo {
  const ValidacionGrupo({
    required this.grupo,
    required this.errores,
    required this.avisos,
    required this.filas,
    required this.actualizar,
    this.existenteId,
    this.existenteNombre,
    this.cambios,
  });

  final GrupoLote grupo;

  /// Problemas del grupo completo (nombre vacío o demasiado largo…).
  final List<String> errores;
  final List<String> avisos;

  /// Una por fila de `grupo.filas`, en el mismo orden.
  final List<ResultadoFila> filas;

  /// ID y nombre del grupo que ya existe con este nombre o ID; `null` si el grupo es nuevo.
  final String? existenteId;
  final String? existenteNombre;

  /// El admin eligió actualizar la lista de un grupo que ya existe (si no, se omite).
  final bool actualizar;

  /// Qué cambia en la lista del grupo existente; solo si [actualizar] y no hay errores.
  final CambiosLista? cambios;

  bool get nuevo => existenteId == null;

  /// Se escribirá en Firestore: es nuevo, o ya existe y se eligió actualizarlo.
  bool get seGuarda => nuevo || actualizar;
  bool get hayErrores => errores.isNotEmpty || filas.any((f) => f.errores.isNotEmpty);

  /// Impide subir el lote hasta corregirlo o quitarlo.
  bool get bloquea => seGuarda && hayErrores;

  /// Los alumnos del archivo ordenados por N.L. Solo tiene sentido si no hay errores.
  List<Alumno> get alumnos => [
        for (final f in grupo.filas)
          if (f.num != null) Alumno(num: f.num!, nombre: limpiarNombre(f.nombre)),
      ]..sort((a, b) => a.num.compareTo(b.num));
}

/// Lo que se escribe en Firestore por cada grupo: [nombre] `null` = el grupo ya existe y solo se
/// actualiza su lista; si no, se crea con ese nombre.
typedef GrupoPorGuardar = ({String id, String? nombre, List<Alumno> alumnos});

/// El grupo listo para escribir; `null` si se omite o tiene errores.
GrupoPorGuardar? porGuardar(ValidacionGrupo v) {
  if (!v.seGuarda || v.hayErrores) return null;
  if (v.nuevo) return (id: v.grupo.id, nombre: v.grupo.nombre, alumnos: v.alumnos);
  final cambios = v.cambios;
  if (cambios == null || cambios.sinCambios) return null;
  return (id: v.existenteId!, nombre: null, alumnos: cambios.resultado);
}

/// Valida los grupos del lote.
/// - [existentes]: ID → nombre de los grupos que ya hay;
/// - [alumnosExistentes]: ID → su lista actual (`null` si trae entradas que la app no reconoce);
/// - [actualizar]: IDs del lote (`GrupoLote.id`) cuya lista se va a actualizar en vez de omitirse.
List<ValidacionGrupo> validarGrupos(
  List<FilaAlumnoLote> filas, {
  required Map<String, String> existentes,
  required Map<String, List<Alumno>?> alumnosExistentes,
  Set<String> actualizar = const {},
}) {
  final resultado = <ValidacionGrupo>[];
  for (final g in agruparPorGrupo(filas)) {
    final errores = <String>[];
    final avisos = <String>[];
    String? existenteId;
    if (g.id.isEmpty) {
      errores.add(g.nombre.isEmpty ? 'Falta el nombre del grupo' : 'Usa letras o números en el nombre del grupo');
    } else {
      if (g.nombre.length > maxNombreGrupo) {
        errores.add('El nombre del grupo debe tener $maxNombreGrupo caracteres o menos');
      }
      // Un grupo renombrado conserva el ID de su nombre original: se revisan nombres e IDs.
      existenteId = existentes.containsKey(g.id)
          ? g.id
          : existentes.entries.where((e) => idGrupo(e.value) == g.id).map((e) => e.key).firstOrNull;
    }
    final existenteNombre = existenteId == null ? null : existentes[existenteId];
    if (existenteId != null && idGrupo(existenteNombre ?? '') != g.id) {
      avisos.add('Ya existe un grupo con el ID "$existenteId" (hoy se llama "$existenteNombre").');
    }
    if (g.variantes.isNotEmpty) {
      avisos.add('En el archivo aparece escrito de varias formas (${(g.variantes.toList()..sort()).join(', ')}): '
          'se juntaron como "${g.nombre}".');
    }

    final porNum = <int, List<FilaAlumnoLote>>{};
    for (final f in g.filas) {
      final n = f.num;
      if (n != null) porNum.putIfAbsent(n, () => []).add(f);
    }
    final porNombre = <String, List<FilaAlumnoLote>>{};
    for (final f in g.filas) {
      final llave = sinAcentos(limpiarNombre(f.nombre));
      if (llave.isNotEmpty) porNombre.putIfAbsent(llave, () => []).add(f);
    }
    final filasRes = <ResultadoFila>[];
    for (final f in g.filas) {
      final errs = <String>[];
      final avs = <String>[];
      final n = f.num;
      if (f.numTexto.trim().isEmpty) {
        errs.add('Falta el N.L');
      } else if (n == null) {
        errs.add('El N.L debe ser un entero positivo');
      } else if (porNum[n]!.length > 1) {
        final otras = [for (final o in porNum[n]!) if (o != f) dondeFila(o.fila)];
        errs.add('El N.L $n está repetido en ${otras.join(', ')}');
      }
      final nombre = limpiarNombre(f.nombre);
      if (nombre.isEmpty) {
        errs.add('Falta el nombre');
      } else {
        final iguales = porNombre[sinAcentos(nombre)]!;
        if (iguales.length > 1) {
          final otros = [for (final o in iguales) if (o != f) 'N.L ${o.numTexto.trim().isEmpty ? '?' : o.numTexto.trim()}'];
          avs.add('Posible duplicado: el mismo nombre está en ${otros.join(', ')}');
        }
        if (!nombre.contains(' ')) avs.add('Solo trae una palabra: ¿falta el apellido?');
        if (RegExp(r'\d').hasMatch(nombre)) avs.add('El nombre trae números');
      }
      filasRes.add(ResultadoFila(errores: errs, avisos: avs));
    }

    final actualizarEste = existenteId != null && actualizar.contains(g.id);
    CambiosLista? cambios;
    if (actualizarEste) {
      final actual = alumnosExistentes[existenteId];
      if (actual == null) {
        errores.add('El grupo que ya existe tiene alumnos con datos que la app no reconoce: '
            'no se puede actualizar desde aquí.');
      } else if (errores.isEmpty && filasRes.every((r) => r.errores.isEmpty)) {
        cambios = compararListas(actual, [
          for (final f in g.filas) Alumno(num: f.num!, nombre: limpiarNombre(f.nombre)),
        ]);
      }
    }
    resultado.add(ValidacionGrupo(
      grupo: g,
      errores: errores,
      avisos: avisos,
      filas: filasRes,
      actualizar: actualizarEste,
      existenteId: existenteId,
      existenteNombre: existenteNombre,
      cambios: cambios,
    ));
  }
  return resultado;
}
