// Lógica pura del importador de listas: sin Firebase, para poder probarla con `flutter test`.
// Es la "red de seguridad" para los CSV que guarda Excel (ver CLAUDE.md, Importación de CSV).

import 'dart:convert';

import 'package:csv/csv.dart';

import 'grupo.dart';

/// Una fila del archivo tal como se muestra en la vista previa.
class FilaCsv {
  FilaCsv({required this.fila, required this.numTexto, required this.nombre, this.num});

  /// Número de fila dentro del archivo (la primera es 1), para que el admin la encuentre en Excel.
  final int fila;

  /// El N.L tal como venía, para mostrarlo aunque no sea válido.
  final String numTexto;
  final String nombre;

  /// El N.L ya convertido; `null` si no es un entero positivo.
  final int? num;

  /// Por qué la fila no se puede guardar; vacío si está bien.
  final List<String> errores = [];

  bool get valida => errores.isEmpty;
}

/// Lo que salió de leer un archivo: las filas para la vista previa y si se puede guardar.
class ListaCsv {
  const ListaCsv({required this.filas, this.errorGeneral});
  final List<FilaCsv> filas;

  /// Problema del archivo completo (por ejemplo, que venga vacío).
  final String? errorGeneral;

  int get conError => filas.where((f) => !f.valida).length;

  /// Solo con esto en `true` se activa el botón "Subir".
  bool get valida => errorGeneral == null && filas.isNotEmpty && conError == 0;

  /// Los alumnos por guardar, ordenados por N.L. Solo tiene sentido si [valida].
  List<Alumno> get alumnos => [
        for (final f in filas)
          if (f.valida) Alumno(num: f.num!, nombre: f.nombre),
      ]..sort((a, b) => a.num.compareTo(b.num));
}

/// Pasos 1 y 2: quita el BOM e intenta UTF-8; si los bytes no son UTF-8 válido usa latin1, porque
/// Excel en Windows guarda en Windows-1252 y para á é í ó ú ü ñ usa los mismos bytes.
String decodificar(List<int> bytes) {
  final tieneBom =
      bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF;
  final datos = tieneBom ? bytes.sublist(3) : bytes;
  try {
    return utf8.decode(datos);
  } on FormatException {
    return latin1.decode(datos);
  }
}

/// Paso 3: el separador (`,` `;` o tabulador) que más aparece en la primera línea con texto, sin
/// contar lo que va entre comillas. En un empate gana el menos común dentro de un nombre
/// (tabulador, luego `;`), y si no hay ninguno se asume coma.
String detectarSeparador(String texto) {
  final primera = texto
      .split(RegExp(r'\r\n|\r|\n'))
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  final cuenta = {'\t': 0, ';': 0, ',': 0};
  var entreComillas = false;
  for (final c in primera.split('')) {
    if (c == '"') {
      entreComillas = !entreComillas;
    } else if (!entreComillas && cuenta.containsKey(c)) {
      cuenta[c] = cuenta[c]! + 1;
    }
  }
  var separador = ',';
  var maximo = 0;
  cuenta.forEach((s, n) {
    if (n > maximo) {
      separador = s;
      maximo = n;
    }
  });
  return separador;
}

final _entero = RegExp(r'^\d+$');
String _limpiar(Object? celda) => limpiarNombre('${celda ?? ''}');

/// Excel → "Texto Unicode" guarda en UTF-16 (empieza con `FF FE` o `FE FF`): no es UTF-8 y con
/// latin1 saldría basura, así que se avisa en vez de mostrar una vista previa ilegible.
bool _esUtf16(List<int> b) =>
    b.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF));

/// Lee los bytes de un CSV `N.L,Nombre completo` y devuelve las filas ya validadas (pasos 1 a 7).
ListaCsv leerCsv(List<int> bytes) {
  if (_esUtf16(bytes)) {
    return const ListaCsv(
      filas: [],
      errorGeneral: 'El archivo está guardado como "Texto Unicode" (UTF-16). '
          'En Excel usa Guardar como → "CSV UTF-8 (delimitado por comas)".',
    );
  }
  final texto = decodificar(bytes);
  // Paso 4: el paquete `csv` respeta las comillas (`3,"García Ruiz, Luis Fernando"`).
  final crudas = Csv(
    fieldDelimiter: detectarSeparador(texto),
    autoDetect: false,
    skipEmptyLines: false,
  ).decode(texto);

  final filas = <FilaCsv>[];
  var primeraConDatos = true;
  for (var i = 0; i < crudas.length; i++) {
    // Paso 6: limpiar espacios y saltar filas vacías (Excel deja filas con puras comas al final).
    final celdas = crudas[i].map(_limpiar).toList();
    if (celdas.every((c) => c.isEmpty)) continue;

    final numTexto = celdas[0];
    final esNumero = _entero.hasMatch(numTexto);
    // Paso 5: el encabezado es opcional; se reconoce porque su primera celda no es un número.
    if (primeraConDatos) {
      primeraConDatos = false;
      if (!esNumero) continue;
    }

    final num = esNumero ? int.tryParse(numTexto) : null;
    final fila = FilaCsv(
      fila: i + 1,
      numTexto: numTexto,
      nombre: celdas.length > 1 ? celdas[1] : '',
      num: num != null && num > 0 ? num : null,
    );
    // Paso 7: N.L entero positivo, nombre no vacío y nada después del nombre.
    if (fila.num == null) {
      fila.errores.add(numTexto.isEmpty ? 'Falta el N.L' : 'El N.L debe ser un entero positivo');
    }
    if (fila.nombre.isEmpty) fila.errores.add('Falta el nombre');
    if (celdas.skip(2).any((c) => c.isNotEmpty)) {
      fila.errores.add('Sobran columnas: si el nombre lleva coma, ponlo entre comillas');
    }
    filas.add(fila);
  }

  // Paso 7: N.L sin repetir. Se marcan todas las filas que comparten número, no solo la segunda.
  final porNum = <int, List<FilaCsv>>{};
  for (final f in filas) {
    if (f.num != null) porNum.putIfAbsent(f.num!, () => []).add(f);
  }
  for (final repetidas in porNum.values) {
    if (repetidas.length < 2) continue;
    for (final f in repetidas) {
      final otras = repetidas.where((o) => o != f).map((o) => o.fila).join(', ');
      f.errores.add('El N.L ${f.num} está repetido (fila $otras)');
    }
  }

  return ListaCsv(
    filas: filas,
    errorGeneral: filas.isEmpty ? 'El archivo no tiene alumnos.' : null,
  );
}
