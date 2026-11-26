// Exportar el registro de asistencia de una clase: .xlsx con formato o .csv plano.
// Lógica pura, sin Firebase, para poder probarla con `flutter test`.

import 'dart:convert';
import 'dart:typed_data';

import 'pase.dart';
import 'xlsx.dart';

const _nombresMes = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];
const _diasSemana = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

/// Letra de cada estado en los archivos exportados.
const letraEstado = {presente: 'P', falta: 'F', justificada: 'J', dual: 'D'};

const _leyenda = 'P = Presente · F = Falta · J = Falta justificada · D = Dual';

final _formatoFecha = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// "AAAA-MM" de una fecha "AAAA-MM-DD".
String _mes(String fecha) => fecha.substring(0, 7);

/// "AAAA-MM" → cuántos días con pase tiene ese mes, en orden. Ignora fechas mal formadas.
Map<String, int> diasPorMes(Iterable<String> fechas) {
  final dias = <String, int>{};
  for (final f in columnasDelMes(fechas.where(_formatoFecha.hasMatch))) {
    dias.update(_mes(f), (n) => n + 1, ifAbsent: () => 1);
  }
  return dias;
}

/// "2026-11" → "noviembre de 2026".
String nombreMes(String mes) => '${_nombresMes[int.parse(mes.substring(5, 7)) - 1]} de ${mes.substring(0, 4)}';

/// "2026-11" → "nov 2026".
String _mesCorto(String mes) =>
    '${_nombresMes[int.parse(mes.substring(5, 7)) - 1].substring(0, 3)} ${mes.substring(0, 4)}';

/// "2026-11-03" → "mar 03". También es la cabecera de las fechas en la vista mensual del teléfono.
String encabezadoDia(String fecha) => '${_diasSemana[DateTime.parse(fecha).weekday - 1]} ${fecha.substring(8)}';

String _capital(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

typedef Conteo = ({int presentes, int faltas, int justificadas, int duales});

/// Asistencias y días en dual entre días con registro (0 a 1); las faltas justificadas cuentan como
/// falta. `null` si no hay ningún registro.
double? porcentajeAsistencia(Conteo c) {
  final total = c.presentes + c.faltas + c.justificadas + c.duales;
  return total == 0 ? null : (c.presentes + c.duales) / total;
}

/// "Activo", "Baja", "Activo · Dual"…
String _estatus(Fila f, Set<String> duales) =>
    [f.baja ? 'Baja' : 'Activo', if (duales.contains(f.nl)) 'Dual'].join(' · ');

/// Los pases de una clase en los meses elegidos, listos para exportar.
class Registro {
  /// [pases]: fecha "AAAA-MM-DD" → `pases.estados` de ese día. [alumnos]: `grupos.alumnos`.
  /// [meses]: los "AAAA-MM" a exportar.
  Registro({
    required this.titulo,
    required Map<String, Map<String, dynamic>> pases,
    required this.alumnos,
    required Set<String> meses,
    this.subtitulo = '',
    this.duales = const {},
  }) : _estados = {
          for (final f in columnasDelMes(pases.keys.where(_formatoFecha.hasMatch)))
            if (meses.contains(_mes(f))) f: pases[f]!,
        };

  /// "Grupo · Materia", como en la app.
  final String titulo;

  /// "Prof. Nombre · Salón A7", como bajo el título de la vista mensual; `''` si no hay.
  final String subtitulo;

  /// Lo que va en la primera fila de cada hoja del .xlsx.
  String get encabezado => subtitulo.isEmpty ? titulo : '$titulo · $subtitulo';

  /// `grupos.alumnos`: `[{num, nombre, activo}]`.
  final List<dynamic> alumnos;

  /// N.L de los alumnos en modo dual hoy (`dualesDe(grupos.duales)`), para el estatus del .csv.
  final Set<String> duales;

  /// Fecha → estados, en orden de fecha.
  final Map<String, Map<String, dynamic>> _estados;

  List<String> get fechas => _estados.keys.toList();
  List<String> get meses => diasPorMes(_estados.keys).keys.toList();
  List<String> fechasDe(String mes) => [for (final f in _estados.keys) if (_mes(f) == mes) f];

  /// Igual que la vista mensual: activos más quien tenga registro en esas fechas aunque esté de baja.
  List<Fila> filas(List<String> fechas) => filasDelPase(alumnos, {for (final f in fechas) ...?_estados[f]});

  /// `null` si no hay registro o el valor no es un estado conocido.
  int? estado(String fecha, String nl) {
    final v = _estados[fecha]?[nl];
    return v is num && letraEstado.containsKey(v.toInt()) ? v.toInt() : null;
  }

  Conteo conteo(String nl, List<String> fechas) {
    var p = 0, f = 0, j = 0, d = 0;
    for (final fecha in fechas) {
      switch (estado(fecha, nl)) {
        case presente:
          p++;
        case falta:
          f++;
        case justificada:
          j++;
        case dual:
          d++;
      }
    }
    return (presentes: p, faltas: f, justificadas: j, duales: d);
  }
}

/// "PaseLista - 3A - Matemáticas - 2026-09 a 2026-11.xlsx", sin caracteres que Windows o Android no
/// acepten en un nombre de archivo.
String nombreArchivo(String titulo, List<String> meses, String extension) {
  final periodo = switch (meses) {
    [] => '',
    [final m] => m,
    _ => '${meses.first} a ${meses.last}',
  };
  final base = 'PaseLista - ${titulo.replaceAll('·', '-')} - $periodo'
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '$base.$extension';
}

// ── CSV ──────────────────────────────────────────────────────────────────────────────────────────

/// Excel ejecuta como fórmula un campo que empieza con `= + - @`: se antepone un apóstrofo.
String _sinFormula(String s) => RegExp(r'^[=+\-@\t\r]').hasMatch(s) ? "'$s" : s;

String _campoCsv(String s) =>
    RegExp(r'[",\r\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;

/// Una sola tabla sin formato: N.L, nombre, estatus, una columna por fecha (P, F, J o D; vacío = sin
/// registro) y los totales del periodo. Separado por comas, fin de línea CRLF y con BOM para que
/// Excel lea bien los acentos.
String csvRegistro(Registro r) {
  final fechas = r.fechas;
  final lineas = <List<String>>[
    ['N.L', 'Nombre', 'Estatus', ...fechas, 'Asistencias', 'Faltas', 'Faltas justificadas', 'Dual', '% asistencia'],
  ];
  for (final f in r.filas(fechas)) {
    final c = r.conteo(f.nl, fechas);
    final pct = porcentajeAsistencia(c);
    lineas.add([
      _sinFormula(f.nl),
      _sinFormula(f.nombre),
      _estatus(f, r.duales),
      for (final fecha in fechas) letraEstado[r.estado(fecha, f.nl)] ?? '',
      '${c.presentes}',
      '${c.faltas}',
      '${c.justificadas}',
      '${c.duales}',
      pct == null ? '' : (pct * 100).toStringAsFixed(1),
    ]);
  }
  return '\uFEFF${lineas.map((l) => l.map(_campoCsv).join(',')).join('\r\n')}\r\n';
}

Uint8List csvRegistroBytes(Registro r) => Uint8List.fromList(utf8.encode(csvRegistro(r)));

// ── XLSX ─────────────────────────────────────────────────────────────────────────────────────────

/// Una hoja por mes (colores como en la app, totales con fórmulas y faltas por día) y, si hay más de
/// un mes, una hoja de resumen al principio.
Uint8List xlsxRegistro(Registro r) {
  final meses = r.meses;
  if (meses.isEmpty) throw ArgumentError('No hay pases en los meses elegidos.');
  return crearXlsx([
    if (meses.length > 1) _hojaResumen(r, meses),
    for (final m in meses) _hojaMes(r, m),
  ]);
}

/// Filas 1 a 3: título, nota y una vacía. La 4 es el encabezado, fija al desplazarse.
const _filaEncabezado = 3;

CeldaXlsx _celdaNl(String nl) {
  final n = int.tryParse(nl);
  return n == null ? CeldaXlsx.texto(nl, EstiloXlsx.texto) : CeldaXlsx.numero(n);
}

CeldaXlsx _celdaNombre(Fila f) => f.baja
    ? CeldaXlsx.texto('${f.nombre} (baja)', EstiloXlsx.baja)
    : CeldaXlsx.texto(f.nombre, EstiloXlsx.texto);

CeldaXlsx _celdaEstado(int? e) => switch (e) {
      presente => const CeldaXlsx.texto('P', EstiloXlsx.presente),
      falta => const CeldaXlsx.texto('F', EstiloXlsx.falta),
      justificada => const CeldaXlsx.texto('J', EstiloXlsx.justificada),
      dual => const CeldaXlsx.texto('D', EstiloXlsx.dual),
      _ => const CeldaXlsx.vacia(),
    };

CeldaXlsx _celdaPorcentaje(double? p) =>
    p == null ? const CeldaXlsx.vacia() : CeldaXlsx.numero(p, EstiloXlsx.porcentaje);

String _dias(int n) => n == 1 ? '1 día con pase' : '$n días con pase';

HojaXlsx _hojaMes(Registro r, String mes) {
  final fechas = r.fechasDe(mes);
  final filas = r.filas(fechas);
  final colTotales = 2 + fechas.length; // Asistencias, Faltas, Justificadas, Dual, % asistencia
  final ultimaCol = colTotales + 4;
  final primera = _filaEncabezado + 1;
  final ultima = primera + filas.length - 1;

  final datos = <List<CeldaXlsx?>>[];
  for (var i = 0; i < filas.length; i++) {
    final f = filas[i];
    final fila = primera + i;
    final dias = '${celdaXlsx(fila, 2)}:${celdaXlsx(fila, colTotales - 1)}';
    final p = celdaXlsx(fila, colTotales);
    final d = celdaXlsx(fila, colTotales + 3);
    final c = r.conteo(f.nl, fechas);
    datos.add([
      _celdaNl(f.nl),
      _celdaNombre(f),
      for (final fecha in fechas) _celdaEstado(r.estado(fecha, f.nl)),
      CeldaXlsx.formula('COUNTIF($dias,"P")', c.presentes),
      CeldaXlsx.formula('COUNTIF($dias,"F")', c.faltas),
      CeldaXlsx.formula('COUNTIF($dias,"J")', c.justificadas),
      CeldaXlsx.formula('COUNTIF($dias,"D")', c.duales),
      CeldaXlsx.formula('IF(SUM($p:$d)=0,"",($p+$d)/SUM($p:$d))', porcentajeAsistencia(c) ?? '', EstiloXlsx.porcentaje),
    ]);
  }

  return HojaXlsx(
    nombre: nombreHoja(nombreMes(mes)),
    filas: [
      [CeldaXlsx.texto(r.encabezado, EstiloXlsx.titulo)],
      [CeldaXlsx.texto('${_capital(nombreMes(mes))} · ${_dias(fechas.length)} · $_leyenda', EstiloXlsx.nota)],
      [],
      [
        const CeldaXlsx.texto('N.L', EstiloXlsx.encabezado),
        const CeldaXlsx.texto('Nombre', EstiloXlsx.encabezado),
        for (final f in fechas) CeldaXlsx.texto(encabezadoDia(f), EstiloXlsx.encabezado),
        for (final t in ['Asistencias', 'Faltas', 'Justificadas', 'Dual', '% asistencia']) CeldaXlsx.texto(t, EstiloXlsx.total),
      ],
      ...datos,
      if (filas.isNotEmpty)
        [
          null,
          const CeldaXlsx.texto('Faltas del día', EstiloXlsx.total),
          for (var c = 0; c < fechas.length; c++)
            CeldaXlsx.formula(
              'COUNTIF(${celdaXlsx(primera, 2 + c)}:${celdaXlsx(ultima, 2 + c)},"F")',
              filas.where((f) => r.estado(fechas[c], f.nl) == falta).length,
              EstiloXlsx.total,
            ),
        ],
    ],
    anchos: {
      0: 6,
      1: 34,
      for (var c = 0; c < fechas.length; c++) 2 + c: 7.5,
      colTotales: 12,
      colTotales + 1: 9,
      colTotales + 2: 12,
      colTotales + 3: 8,
      colTotales + 4: 12,
    },
    combinadas: [for (var i = 0; i < 3; i++) 'A${i + 1}:${celdaXlsx(i, ultimaCol)}'],
    fijarFilas: _filaEncabezado + 1,
    fijarColumnas: 2,
  );
}

List<CeldaXlsx?> _filaResumen(Registro r, Fila f, List<String> fechas, List<String> meses) {
  final c = r.conteo(f.nl, fechas);
  return [
    _celdaNl(f.nl),
    _celdaNombre(f),
    CeldaXlsx.numero(c.presentes),
    CeldaXlsx.numero(c.faltas),
    CeldaXlsx.numero(c.justificadas),
    CeldaXlsx.numero(c.duales),
    _celdaPorcentaje(porcentajeAsistencia(c)),
    for (final m in meses) _celdaPorcentaje(porcentajeAsistencia(r.conteo(f.nl, r.fechasDe(m)))),
  ];
}

HojaXlsx _hojaResumen(Registro r, List<String> meses) {
  final fechas = r.fechas;
  final ultimaCol = 6 + meses.length;
  return HojaXlsx(
    nombre: 'Resumen',
    filas: [
      [CeldaXlsx.texto(r.encabezado, EstiloXlsx.titulo)],
      [
        CeldaXlsx.texto(
          'De ${nombreMes(meses.first)} a ${nombreMes(meses.last)} · ${_dias(fechas.length)}',
          EstiloXlsx.nota,
        ),
      ],
      [
        const CeldaXlsx.texto(
          '% asistencia = (asistencias + dual) entre días con registro; la falta justificada cuenta como falta',
          EstiloXlsx.nota,
        ),
      ],
      [
        const CeldaXlsx.texto('N.L', EstiloXlsx.encabezado),
        const CeldaXlsx.texto('Nombre', EstiloXlsx.encabezado),
        for (final t in ['Asistencias', 'Faltas', 'Justificadas', 'Dual', '% asistencia']) CeldaXlsx.texto(t, EstiloXlsx.total),
        for (final m in meses) CeldaXlsx.texto('% ${_mesCorto(m)}', EstiloXlsx.encabezado),
      ],
      for (final f in r.filas(fechas)) _filaResumen(r, f, fechas, meses),
    ],
    anchos: {
      0: 6,
      1: 34,
      2: 12,
      3: 9,
      4: 12,
      5: 8,
      6: 12,
      for (var i = 0; i < meses.length; i++) 7 + i: 13,
    },
    combinadas: [for (var i = 0; i < 3; i++) 'A${i + 1}:${celdaXlsx(i, ultimaCol)}'],
    fijarFilas: _filaEncabezado + 1,
    fijarColumnas: 2,
  );
}

// ── Grupo completo ───────────────────────────────────────────────────────────────────────────────
// El admin exporta la asistencia de un grupo con todas sus clases: una fila por alumno y, por cada
// clase, sus asistencias, faltas, faltas justificadas y días en dual, más los totales del grupo. Las fechas se
// resumen (no hay una columna por día): para el detalle día por día está el registro de cada clase.

/// Una clase del grupo con sus pases: fecha "AAAA-MM-DD" → `pases.estados` de ese día.
typedef ClaseDelGrupo = ({
  String materia,
  String profesor,
  String salon,
  Map<String, Map<String, dynamic>> pases,
});

/// Una clase con pases en el periodo elegido.
class ColumnaClase {
  const ColumnaClase({required this.etiqueta, required this.registro});

  /// "Matemáticas (Prof. Ana López)", lo que encabeza sus columnas.
  final String etiqueta;
  final Registro registro;
}

/// Las clases de un grupo en los meses elegidos. Las clases sin ningún pase en esos meses no tienen
/// columnas.
class RegistroGrupo {
  RegistroGrupo({
    required this.titulo,
    required this.alumnos,
    required List<ClaseDelGrupo> delGrupo,
    required Set<String> meses,
    this.duales = const {},
  }) {
    final ordenadas = [...delGrupo]
      ..sort((a, b) => '${a.materia}\n${a.profesor}'.toLowerCase().compareTo('${b.materia}\n${b.profesor}'.toLowerCase()));
    for (final c in ordenadas) {
      final r = Registro(titulo: c.materia, pases: c.pases, alumnos: alumnos, meses: meses, duales: duales);
      if (r.fechas.isEmpty) continue;
      final profe = c.profesor.trim();
      clases.add(ColumnaClase(
        etiqueta: profe.isEmpty ? c.materia : '${c.materia} (Prof. $profe)',
        registro: r,
      ));
    }
  }

  /// "Grupo · Grupo completo", para el título y el nombre del archivo.
  final String titulo;

  /// `grupos.alumnos`: `[{num, nombre, activo}]`.
  final List<dynamic> alumnos;

  /// N.L de los alumnos en modo dual hoy, para el estatus del .csv.
  final Set<String> duales;

  /// Las clases con pases en el periodo, por materia.
  final List<ColumnaClase> clases = [];

  /// "AAAA-MM" con al menos un pase de alguna clase, en orden.
  List<String> get meses => {for (final c in clases) ...c.registro.meses}.toList()..sort();

  /// Días distintos con pase de alguna clase.
  int get diasConPase => {for (final c in clases) ...c.registro.fechas}.length;

  /// Activos más quien tenga registro en alguna clase aunque ya esté de baja.
  List<Fila> get filas => filasDelPase(alumnos, {
        for (final c in clases)
          for (final f in c.registro.filas(c.registro.fechas)) f.nl: 0,
      });

  Conteo conteoDe(String nl, ColumnaClase c) => c.registro.conteo(nl, c.registro.fechas);

  /// La suma de todas las clases.
  Conteo total(String nl) {
    var p = 0, f = 0, j = 0, d = 0;
    for (final c in clases) {
      final k = conteoDe(nl, c);
      p += k.presentes;
      f += k.faltas;
      j += k.justificadas;
      d += k.duales;
    }
    return (presentes: p, faltas: f, justificadas: j, duales: d);
  }
}

/// Una sola tabla sin formato: N.L, nombre, estatus, por cada clase sus asistencias, faltas,
/// justificadas y dual, y los totales del grupo con el % de asistencia. Mismo formato que [csvRegistro]
/// (UTF-8 con BOM, comas y CRLF).
String csvGrupo(RegistroGrupo g) {
  final lineas = <List<String>>[
    [
      'N.L',
      'Nombre',
      'Estatus',
      for (final c in g.clases) ...[
        '${c.etiqueta} - Asistencias',
        '${c.etiqueta} - Faltas',
        '${c.etiqueta} - Justificadas',
        '${c.etiqueta} - Dual',
      ],
      'Total asistencias',
      'Total faltas',
      'Total justificadas',
      'Total dual',
      '% asistencia',
    ],
  ];
  for (final f in g.filas) {
    final t = g.total(f.nl);
    final pct = porcentajeAsistencia(t);
    lineas.add([
      _sinFormula(f.nl),
      _sinFormula(f.nombre),
      _estatus(f, g.duales),
      for (final c in g.clases) ...[
        '${g.conteoDe(f.nl, c).presentes}',
        '${g.conteoDe(f.nl, c).faltas}',
        '${g.conteoDe(f.nl, c).justificadas}',
        '${g.conteoDe(f.nl, c).duales}',
      ],
      '${t.presentes}',
      '${t.faltas}',
      '${t.justificadas}',
      '${t.duales}',
      pct == null ? '' : (pct * 100).toStringAsFixed(1),
    ]);
  }
  return '﻿${lineas.map((l) => l.map(_campoCsv).join(',')).join('\r\n')}\r\n';
}

Uint8List csvGrupoBytes(RegistroGrupo g) => Uint8List.fromList(utf8.encode(csvGrupo(g)));

/// Una sola hoja: la clase por columnas (con su nombre combinado arriba) y los totales con fórmulas.
Uint8List xlsxGrupo(RegistroGrupo g) {
  if (g.clases.isEmpty) throw ArgumentError('No hay pases en los meses elegidos.');
  final filas = g.filas;
  final n = g.clases.length;
  final colTotales = 2 + 4 * n; // Asistencias, Faltas, Justificadas, Dual, % asistencia
  final ultimaCol = colTotales + 4;
  const filaGrupos = 3; // nombres de las clases
  const filaTitulos = 4; // Asist., Faltas, Just., Dual
  final primera = filaTitulos + 1;

  final datos = <List<CeldaXlsx?>>[];
  for (var i = 0; i < filas.length; i++) {
    final f = filas[i];
    final fila = primera + i;
    final t = g.total(f.nl);
    String suma(int desplazamiento) =>
        [for (var k = 0; k < n; k++) celdaXlsx(fila, 2 + 4 * k + desplazamiento)].join('+');
    final p = celdaXlsx(fila, colTotales);
    final d = celdaXlsx(fila, colTotales + 3);
    datos.add([
      _celdaNl(f.nl),
      _celdaNombre(f),
      for (final c in g.clases) ...[
        CeldaXlsx.numero(g.conteoDe(f.nl, c).presentes),
        CeldaXlsx.numero(g.conteoDe(f.nl, c).faltas),
        CeldaXlsx.numero(g.conteoDe(f.nl, c).justificadas),
        CeldaXlsx.numero(g.conteoDe(f.nl, c).duales),
      ],
      CeldaXlsx.formula(suma(0), t.presentes),
      CeldaXlsx.formula(suma(1), t.faltas),
      CeldaXlsx.formula(suma(2), t.justificadas),
      CeldaXlsx.formula(suma(3), t.duales),
      CeldaXlsx.formula('IF(SUM($p:$d)=0,"",($p+$d)/SUM($p:$d))', porcentajeAsistencia(t) ?? '', EstiloXlsx.porcentaje),
    ]);
  }

  final hoja = HojaXlsx(
    nombre: nombreHoja('Grupo completo'),
    filas: [
      [CeldaXlsx.texto(g.titulo, EstiloXlsx.titulo)],
      [
        CeldaXlsx.texto(
          '${g.meses.length == 1 ? _capital(nombreMes(g.meses.first)) : 'De ${nombreMes(g.meses.first)} a ${nombreMes(g.meses.last)}'}'
          ' · ${_dias(g.diasConPase)} · ${g.clases.length == 1 ? '1 clase' : '${g.clases.length} clases'}',
          EstiloXlsx.nota,
        ),
      ],
      [
        const CeldaXlsx.texto(
          '% asistencia = (asistencias + dual) entre pases registrados de todas las clases; la falta justificada cuenta como falta',
          EstiloXlsx.nota,
        ),
      ],
      [
        null,
        null,
        for (final c in g.clases) ...[
          CeldaXlsx.texto(c.etiqueta, EstiloXlsx.encabezado),
          const CeldaXlsx.vacia(EstiloXlsx.encabezado),
          const CeldaXlsx.vacia(EstiloXlsx.encabezado),
          const CeldaXlsx.vacia(EstiloXlsx.encabezado),
        ],
        const CeldaXlsx.texto('Todo el grupo', EstiloXlsx.total),
        const CeldaXlsx.vacia(EstiloXlsx.total),
        const CeldaXlsx.vacia(EstiloXlsx.total),
        const CeldaXlsx.vacia(EstiloXlsx.total),
        const CeldaXlsx.vacia(EstiloXlsx.total),
      ],
      [
        const CeldaXlsx.texto('N.L', EstiloXlsx.encabezado),
        const CeldaXlsx.texto('Nombre', EstiloXlsx.encabezado),
        for (var k = 0; k < n; k++) ...[
          const CeldaXlsx.texto('Asist.', EstiloXlsx.encabezado),
          const CeldaXlsx.texto('Faltas', EstiloXlsx.encabezado),
          const CeldaXlsx.texto('Just.', EstiloXlsx.encabezado),
          const CeldaXlsx.texto('Dual', EstiloXlsx.encabezado),
        ],
        for (final t in ['Asistencias', 'Faltas', 'Justificadas', 'Dual', '% asistencia']) CeldaXlsx.texto(t, EstiloXlsx.total),
      ],
      ...datos,
    ],
    anchos: {
      0: 6,
      1: 34,
      for (var c = 2; c < colTotales; c++) c: 8,
      colTotales: 12,
      colTotales + 1: 9,
      colTotales + 2: 12,
      colTotales + 3: 8,
      colTotales + 4: 12,
    },
    combinadas: [
      for (var i = 0; i < 3; i++) 'A${i + 1}:${celdaXlsx(i, ultimaCol)}',
      for (var k = 0; k < n; k++) '${celdaXlsx(filaGrupos, 2 + 4 * k)}:${celdaXlsx(filaGrupos, 5 + 4 * k)}',
      '${celdaXlsx(filaGrupos, colTotales)}:${celdaXlsx(filaGrupos, ultimaCol)}',
    ],
    fijarFilas: filaTitulos + 1,
    fijarColumnas: 2,
  );
  return crearXlsx([hoja]);
}
