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
const letraEstado = {presente: 'P', falta: 'F', justificada: 'J'};

const _leyenda = 'P = Presente · F = Falta · J = Falta justificada';

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

/// "2026-11-03" → "mar 03".
String _encabezadoDia(String fecha) => '${_diasSemana[DateTime.parse(fecha).weekday - 1]} ${fecha.substring(8)}';

String _capital(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

typedef Conteo = ({int presentes, int faltas, int justificadas});

/// Asistencias entre días con registro (0 a 1); las faltas justificadas cuentan como falta.
/// `null` si no hay ningún registro.
double? porcentajeAsistencia(Conteo c) {
  final total = c.presentes + c.faltas + c.justificadas;
  return total == 0 ? null : c.presentes / total;
}

/// Los pases de una clase en los meses elegidos, listos para exportar.
class Registro {
  /// [pases]: fecha "AAAA-MM-DD" → `pases.estados` de ese día. [alumnos]: `grupos.alumnos`.
  /// [meses]: los "AAAA-MM" a exportar.
  Registro({
    required this.titulo,
    required Map<String, Map<String, dynamic>> pases,
    required List<dynamic> alumnos,
    required Set<String> meses,
  })  : _alumnos = alumnos,
        _estados = {
          for (final f in columnasDelMes(pases.keys.where(_formatoFecha.hasMatch)))
            if (meses.contains(_mes(f))) f: pases[f]!,
        };

  /// "Grupo · Materia", como en la app.
  final String titulo;
  final List<dynamic> _alumnos;

  /// Fecha → estados, en orden de fecha.
  final Map<String, Map<String, dynamic>> _estados;

  List<String> get fechas => _estados.keys.toList();
  List<String> get meses => diasPorMes(_estados.keys).keys.toList();
  List<String> fechasDe(String mes) => [for (final f in _estados.keys) if (_mes(f) == mes) f];

  /// Igual que la vista mensual: activos más quien tenga registro en esas fechas aunque esté de baja.
  List<Fila> filas(List<String> fechas) => filasDelPase(_alumnos, {for (final f in fechas) ...?_estados[f]});

  /// `null` si no hay registro o el valor no es un estado conocido.
  int? estado(String fecha, String nl) {
    final v = _estados[fecha]?[nl];
    return v is num && letraEstado.containsKey(v.toInt()) ? v.toInt() : null;
  }

  Conteo conteo(String nl, List<String> fechas) {
    var p = 0, f = 0, j = 0;
    for (final fecha in fechas) {
      switch (estado(fecha, nl)) {
        case presente:
          p++;
        case falta:
          f++;
        case justificada:
          j++;
      }
    }
    return (presentes: p, faltas: f, justificadas: j);
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

/// Una sola tabla sin formato: N.L, nombre, estatus, una columna por fecha (P, F o J; vacío = sin
/// registro) y los totales del periodo. Separado por comas, fin de línea CRLF y con BOM para que
/// Excel lea bien los acentos.
String csvRegistro(Registro r) {
  final fechas = r.fechas;
  final lineas = <List<String>>[
    ['N.L', 'Nombre', 'Estatus', ...fechas, 'Asistencias', 'Faltas', 'Faltas justificadas', '% asistencia'],
  ];
  for (final f in r.filas(fechas)) {
    final c = r.conteo(f.nl, fechas);
    final pct = porcentajeAsistencia(c);
    lineas.add([
      _sinFormula(f.nl),
      _sinFormula(f.nombre),
      f.baja ? 'Baja' : 'Activo',
      for (final fecha in fechas) letraEstado[r.estado(fecha, f.nl)] ?? '',
      '${c.presentes}',
      '${c.faltas}',
      '${c.justificadas}',
      pct == null ? '' : (pct * 100).toStringAsFixed(1),
    ]);
  }
  return '﻿${lineas.map((l) => l.map(_campoCsv).join(',')).join('\r\n')}\r\n';
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
      _ => const CeldaXlsx.vacia(),
    };

CeldaXlsx _celdaPorcentaje(double? p) =>
    p == null ? const CeldaXlsx.vacia() : CeldaXlsx.numero(p, EstiloXlsx.porcentaje);

String _dias(int n) => n == 1 ? '1 día con pase' : '$n días con pase';

HojaXlsx _hojaMes(Registro r, String mes) {
  final fechas = r.fechasDe(mes);
  final filas = r.filas(fechas);
  final colTotales = 2 + fechas.length; // Asistencias, Faltas, Justificadas, % asistencia
  final ultimaCol = colTotales + 3;
  final primera = _filaEncabezado + 1;
  final ultima = primera + filas.length - 1;

  final datos = <List<CeldaXlsx?>>[];
  for (var i = 0; i < filas.length; i++) {
    final f = filas[i];
    final fila = primera + i;
    final dias = '${celdaXlsx(fila, 2)}:${celdaXlsx(fila, colTotales - 1)}';
    final p = celdaXlsx(fila, colTotales);
    final j = celdaXlsx(fila, colTotales + 2);
    final c = r.conteo(f.nl, fechas);
    datos.add([
      _celdaNl(f.nl),
      _celdaNombre(f),
      for (final fecha in fechas) _celdaEstado(r.estado(fecha, f.nl)),
      CeldaXlsx.formula('COUNTIF($dias,"P")', c.presentes),
      CeldaXlsx.formula('COUNTIF($dias,"F")', c.faltas),
      CeldaXlsx.formula('COUNTIF($dias,"J")', c.justificadas),
      CeldaXlsx.formula('IF(SUM($p:$j)=0,"",$p/SUM($p:$j))', porcentajeAsistencia(c) ?? '', EstiloXlsx.porcentaje),
    ]);
  }

  return HojaXlsx(
    nombre: nombreHoja(nombreMes(mes)),
    filas: [
      [CeldaXlsx.texto(r.titulo, EstiloXlsx.titulo)],
      [CeldaXlsx.texto('${_capital(nombreMes(mes))} · ${_dias(fechas.length)} · $_leyenda', EstiloXlsx.nota)],
      [],
      [
        const CeldaXlsx.texto('N.L', EstiloXlsx.encabezado),
        const CeldaXlsx.texto('Nombre', EstiloXlsx.encabezado),
        for (final f in fechas) CeldaXlsx.texto(_encabezadoDia(f), EstiloXlsx.encabezado),
        for (final t in ['Asistencias', 'Faltas', 'Justificadas', '% asistencia']) CeldaXlsx.texto(t, EstiloXlsx.total),
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
      colTotales + 3: 12,
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
    _celdaPorcentaje(porcentajeAsistencia(c)),
    for (final m in meses) _celdaPorcentaje(porcentajeAsistencia(r.conteo(f.nl, r.fechasDe(m)))),
  ];
}

HojaXlsx _hojaResumen(Registro r, List<String> meses) {
  final fechas = r.fechas;
  final ultimaCol = 5 + meses.length;
  return HojaXlsx(
    nombre: 'Resumen',
    filas: [
      [CeldaXlsx.texto(r.titulo, EstiloXlsx.titulo)],
      [
        CeldaXlsx.texto(
          'De ${nombreMes(meses.first)} a ${nombreMes(meses.last)} · ${_dias(fechas.length)}',
          EstiloXlsx.nota,
        ),
      ],
      [
        const CeldaXlsx.texto(
          '% asistencia = asistencias entre días con registro; la falta justificada cuenta como falta',
          EstiloXlsx.nota,
        ),
      ],
      [
        const CeldaXlsx.texto('N.L', EstiloXlsx.encabezado),
        const CeldaXlsx.texto('Nombre', EstiloXlsx.encabezado),
        for (final t in ['Asistencias', 'Faltas', 'Justificadas', '% asistencia']) CeldaXlsx.texto(t, EstiloXlsx.total),
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
      5: 12,
      for (var i = 0; i < meses.length; i++) 6 + i: 13,
    },
    combinadas: [for (var i = 0; i < 3; i++) 'A${i + 1}:${celdaXlsx(i, ultimaCol)}'],
    fijarFilas: _filaEncabezado + 1,
    fijarColumnas: 2,
  );
}
