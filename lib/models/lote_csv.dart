// Lectura y validación de CSV para las herramientas por lote del admin (invitar usuarios, importar
// grupos y dar de alta clases). Lógica pura, sin Firebase, para poder probarla con `flutter test`.
//
// Todas comparten la misma idea: el archivo se convierte en filas editables; cada fila se valida
// contra lo que ya existe y se marca como lista, con aviso, con error u "omitida" (ya existe). Nada
// se guarda hasta que el admin revisa la vista previa y corrige lo que haga falta.

import 'package:csv/csv.dart';

import 'csv_alumnos.dart' show decodificar, detectarSeparador;
import 'grupo.dart' show limpiarNombre, sinAcentos;

/// Una fila del archivo con sus celdas ya limpias (sin espacios de sobra).
class FilaTabla {
  const FilaTabla({required this.fila, required this.celdas});

  /// Número de fila dentro del archivo (la primera es 1), para encontrarla en Excel.
  final int fila;
  final List<String> celdas;

  /// La celda [i], o '' si la fila no llega hasta ahí.
  String celda(int i) => i >= 0 && i < celdas.length ? celdas[i] : '';
}

/// El archivo leído como tabla, sin interpretar qué es cada columna.
class TablaCsv {
  const TablaCsv({required this.filas, this.errorGeneral});
  final List<FilaTabla> filas;

  /// Problema del archivo completo (por ejemplo, que venga vacío).
  final String? errorGeneral;
}

/// Excel → "Texto Unicode" guarda en UTF-16: no es UTF-8 y con latin1 saldría basura.
bool _esUtf16(List<int> b) =>
    b.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF));

/// Lee los bytes de un CSV con la misma tolerancia que el importador de listas: quita el BOM, prueba
/// UTF-8 y si falla usa latin1 (Excel en Windows), detecta el separador (`,` `;` o tabulador) y respeta
/// las comillas. Salta las filas vacías.
TablaCsv leerTabla(List<int> bytes) {
  if (_esUtf16(bytes)) {
    return const TablaCsv(
      filas: [],
      errorGeneral: 'El archivo está guardado como "Texto Unicode" (UTF-16). '
          'En Excel usa Guardar como → "CSV UTF-8 (delimitado por comas)".',
    );
  }
  final texto = decodificar(bytes);
  final crudas = Csv(
    fieldDelimiter: detectarSeparador(texto),
    autoDetect: false,
    skipEmptyLines: false,
  ).decode(texto);
  final filas = <FilaTabla>[];
  for (var i = 0; i < crudas.length; i++) {
    final celdas = [for (final c in crudas[i]) limpiarNombre('${c ?? ''}')];
    if (celdas.every((c) => c.isEmpty)) continue;
    filas.add(FilaTabla(fila: i + 1, celdas: celdas));
  }
  return TablaCsv(
    filas: filas,
    errorGeneral: filas.isEmpty ? 'El archivo no tiene filas con datos.' : null,
  );
}

/// "N.L" → "nl", "Número de lista" → "numerodelista": para reconocer encabezados escritos de varias
/// formas.
String llaveEncabezado(String texto) => sinAcentos(texto).replaceAll(RegExp(r'[^a-z0-9]'), '');

/// La tabla con cada columna ya ubicada.
class TablaConColumnas {
  const TablaConColumnas({required this.columnas, required this.filas, this.errorGeneral});

  /// Nombre de la columna → posición en las filas.
  final Map<String, int> columnas;

  /// Solo filas de datos (sin el encabezado, si lo había).
  final List<FilaTabla> filas;
  final String? errorGeneral;

  /// El valor de [columna] en [fila]; '' si no viene.
  String valor(FilaTabla fila, String columna) {
    final i = columnas[columna];
    return i == null ? '' : fila.celda(i);
  }
}

/// Lee un CSV de varias columnas. El encabezado es opcional: si la primera fila trae el nombre de al
/// menos una columna conocida ([alias]: columna → nombres con los que puede venir), se usa para ubicar
/// las columnas en cualquier orden; si no, se toman por posición según [orden]. Con encabezado deben
/// estar todas las [obligatorias].
TablaConColumnas leerConColumnas(
  List<int> bytes, {
  required List<String> orden,
  required Map<String, List<String>> alias,
  List<String> obligatorias = const [],
}) {
  final tabla = leerTabla(bytes);
  if (tabla.errorGeneral != null) {
    return TablaConColumnas(columnas: const {}, filas: const [], errorGeneral: tabla.errorGeneral);
  }
  final llaves = [for (final c in tabla.filas.first.celdas) llaveEncabezado(c)];
  final encontradas = <String, int>{};
  alias.forEach((columna, nombres) {
    final buscados = {for (final n in nombres) llaveEncabezado(n)};
    final i = llaves.indexWhere((l) => buscados.contains(l));
    if (i >= 0) encontradas[columna] = i;
  });
  if (encontradas.isEmpty) {
    // Sin encabezado: por posición.
    return TablaConColumnas(
      columnas: {for (var i = 0; i < orden.length; i++) orden[i]: i},
      filas: tabla.filas,
    );
  }
  final faltan = [for (final c in obligatorias) if (!encontradas.containsKey(c)) c];
  if (faltan.isNotEmpty) {
    return TablaConColumnas(
      columnas: encontradas,
      filas: const [],
      errorGeneral: 'En la primera fila falta la columna ${faltan.map((c) => '"$c"').join(', ')}.',
    );
  }
  final datos = tabla.filas.skip(1).toList();
  return TablaConColumnas(
    columnas: encontradas,
    filas: datos,
    errorGeneral: datos.isEmpty ? 'El archivo solo tiene el encabezado.' : null,
  );
}

/// Lo que se sabe de una fila después de validarla.
class ResultadoFila {
  const ResultadoFila({this.errores = const [], this.avisos = const [], this.omitida});

  /// Impiden guardar: hay que corregir la fila o quitarla del lote.
  final List<String> errores;

  /// Se guarda, pero conviene revisarla (un posible duplicado, una errata en el correo…).
  final List<String> avisos;

  /// Motivo por el que se salta sin ser un error (lo que ya existe). Se muestra en gris.
  final String? omitida;

  /// Se guardará al subir el lote.
  bool get seGuarda => errores.isEmpty && omitida == null;
}

/// De dónde salió una fila, para los mensajes: "la fila 5" o "una fila agregada a mano" (fila 0).
String dondeFila(int fila) => fila > 0 ? 'la fila $fila' : 'una fila agregada a mano';

/// Cuántas filas hay de cada tipo, para el encabezado de la vista previa.
typedef ConteoLote = ({int seGuardan, int omitidas, int conError, int conAviso});

ConteoLote contarLote(Iterable<ResultadoFila> resultados) {
  var seGuardan = 0, omitidas = 0, conError = 0, conAviso = 0;
  for (final r in resultados) {
    if (r.errores.isNotEmpty) {
      conError++;
    } else if (r.omitida != null) {
      omitidas++;
    } else {
      seGuardan++;
      if (r.avisos.isNotEmpty) conAviso++;
    }
  }
  return (seGuardan: seGuardan, omitidas: omitidas, conError: conError, conAviso: conAviso);
}

/// "3 se guardarán · 1 omitida · 2 con error", para el resumen de la vista previa.
String resumenLote(ConteoLote c) {
  String parte(int n, String uno, String varios) => n == 1 ? '1 $uno' : '$n $varios';
  return [
    parte(c.seGuardan, 'se guardará', 'se guardarán'),
    if (c.omitidas > 0) parte(c.omitidas, 'omitida', 'omitidas'),
    if (c.conError > 0) parte(c.conError, 'con error', 'con error'),
  ].join(' · ');
}
