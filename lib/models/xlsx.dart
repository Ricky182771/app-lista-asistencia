// Escritor mínimo de .xlsx (Office Open XML), sin paquetes: un ZIP sin compresión (método "store")
// con su CRC-32, cadenas en línea y un juego fijo de estilos. Es Dart puro, así que funciona igual en
// web y en Android y se puede probar con `flutter test`.

import 'dart:convert';
import 'dart:typed_data';

const mimeXlsx = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Estilos de celda. El índice de cada valor es su posición en `cellXfs` de styles.xml (ver [_estilos]).
enum EstiloXlsx {
  normal,
  titulo,
  nota,
  encabezado,
  texto,
  presente,
  falta,
  justificada,
  vacia,
  baja,
  numero,
  porcentaje,
  total,
  dual,
}

/// Una celda: texto, número o fórmula (con su resultado ya calculado, para los visores que no
/// recalculan). Sin valor = celda vacía con estilo (bordes).
class CeldaXlsx {
  const CeldaXlsx.texto(String this.texto, [this.estilo = EstiloXlsx.normal])
      : numero = null,
        formula = null;
  const CeldaXlsx.numero(num this.numero, [this.estilo = EstiloXlsx.numero])
      : texto = null,
        formula = null;

  /// [resultado] es `num` o `String`.
  CeldaXlsx.formula(String this.formula, Object resultado, [this.estilo = EstiloXlsx.numero])
      : numero = resultado is num ? resultado : null,
        texto = resultado is num ? null : '$resultado';
  const CeldaXlsx.vacia([this.estilo = EstiloXlsx.vacia])
      : texto = null,
        numero = null,
        formula = null;

  final String? texto;
  final num? numero;
  final String? formula;
  final EstiloXlsx estilo;
}

class HojaXlsx {
  HojaXlsx({
    required this.nombre,
    required this.filas,
    this.anchos = const {},
    this.combinadas = const [],
    this.fijarFilas = 0,
    this.fijarColumnas = 0,
  });

  /// Máximo 31 caracteres y sin `\ / ? * [ ] :` (lo limpia [nombreHoja]).
  final String nombre;

  /// `null` = no escribir esa celda.
  final List<List<CeldaXlsx?>> filas;

  /// Columna (desde 0) → ancho en caracteres.
  final Map<int, double> anchos;

  /// Rangos combinados, por ejemplo `A1:F1`.
  final List<String> combinadas;

  /// Filas y columnas fijas al desplazarse; también se repiten al imprimir.
  final int fijarFilas, fijarColumnas;
}

/// 0 → A, 25 → Z, 26 → AA.
String columnaXlsx(int i) {
  var n = i + 1;
  var letras = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    letras = '${String.fromCharCode(65 + r)}$letras';
    n = (n - 1) ~/ 26;
  }
  return letras;
}

/// Referencia de celda, con fila y columna desde 0: (0, 0) → A1.
String celdaXlsx(int fila, int columna) => '${columnaXlsx(columna)}${fila + 1}';

/// Excel no acepta `\ / ? * [ ] :` en el nombre de una hoja, ni más de 31 caracteres.
String nombreHoja(String nombre) {
  final limpio = nombre.replaceAll(RegExp(r'[\\/?*\[\]:]'), '-').trim();
  final corto = limpio.length > 31 ? limpio.substring(0, 31) : limpio;
  return corto.isEmpty ? 'Hoja' : corto;
}

/// Escapa para XML y quita los caracteres de control que XML 1.0 no permite.
String _xml(String s) => s
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Número como lo espera el XML: sin notación científica ni separadores.
String _num(num n) => n is int || n == n.roundToDouble() ? '${n.toInt()}' : '$n';

const _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _nsR = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _cabeceraXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

String _celdaXml(String ref, CeldaXlsx c) {
  final s = c.estilo.index;
  final f = c.formula;
  if (f != null) {
    final resultado = c.numero;
    return resultado != null
        ? '<c r="$ref" s="$s"><f>${_xml(f)}</f><v>${_num(resultado)}</v></c>'
        : '<c r="$ref" s="$s" t="str"><f>${_xml(f)}</f><v>${_xml(c.texto ?? '')}</v></c>';
  }
  final numero = c.numero;
  if (numero != null) return '<c r="$ref" s="$s"><v>${_num(numero)}</v></c>';
  final texto = c.texto;
  if (texto != null) {
    return '<c r="$ref" s="$s" t="inlineStr"><is><t xml:space="preserve">${_xml(texto)}</t></is></c>';
  }
  return '<c r="$ref" s="$s"/>';
}

/// XML de una hoja. Público para las pruebas.
String hojaXml(HojaXlsx h, {bool activa = false}) {
  final b = StringBuffer(_cabeceraXml)
    ..write('<worksheet xmlns="$_ns" xmlns:r="$_nsR">')
    // Al imprimir: horizontal y a lo ancho de una página.
    ..write('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>')
    ..write('<sheetViews><sheetView workbookViewId="0"${activa ? ' tabSelected="1"' : ''}>');
  if (h.fijarFilas > 0 || h.fijarColumnas > 0) {
    final esquina = celdaXlsx(h.fijarFilas, h.fijarColumnas);
    final panel = h.fijarFilas > 0 && h.fijarColumnas > 0
        ? 'bottomRight'
        : h.fijarFilas > 0
            ? 'bottomLeft'
            : 'topRight';
    b
      ..write('<pane')
      ..write(h.fijarColumnas > 0 ? ' xSplit="${h.fijarColumnas}"' : '')
      ..write(h.fijarFilas > 0 ? ' ySplit="${h.fijarFilas}"' : '')
      ..write(' topLeftCell="$esquina" activePane="$panel" state="frozen"/>')
      ..write('<selection pane="$panel" activeCell="$esquina" sqref="$esquina"/>');
  }
  b.write('</sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/>');
  if (h.anchos.isNotEmpty) {
    b.write('<cols>');
    for (final e in (h.anchos.entries.toList()..sort((x, y) => x.key.compareTo(y.key)))) {
      b.write('<col min="${e.key + 1}" max="${e.key + 1}" width="${e.value}" customWidth="1"/>');
    }
    b.write('</cols>');
  }
  b.write('<sheetData>');
  for (var r = 0; r < h.filas.length; r++) {
    b.write('<row r="${r + 1}">');
    for (var c = 0; c < h.filas[r].length; c++) {
      final celda = h.filas[r][c];
      if (celda != null) b.write(_celdaXml(celdaXlsx(r, c), celda));
    }
    b.write('</row>');
  }
  b.write('</sheetData>');
  if (h.combinadas.isNotEmpty) {
    b.write('<mergeCells count="${h.combinadas.length}">');
    for (final m in h.combinadas) {
      b.write('<mergeCell ref="$m"/>');
    }
    b.write('</mergeCells>');
  }
  b
    ..write('<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>')
    ..write('<pageSetup orientation="landscape" fitToWidth="1" fitToHeight="0"/>')
    ..write('</worksheet>');
  return b.toString();
}

String _libroXml(List<HojaXlsx> hojas) {
  final b = StringBuffer(_cabeceraXml)
    ..write('<workbook xmlns="$_ns" xmlns:r="$_nsR">')
    ..write('<bookViews><workbookView activeTab="0"/></bookViews><sheets>');
  for (var i = 0; i < hojas.length; i++) {
    b.write('<sheet name="${_xml(hojas[i].nombre)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
  }
  b.write('</sheets>');
  // Al imprimir, repetir en cada página las filas y columnas fijas.
  final titulos = <String>[];
  for (var i = 0; i < hojas.length; i++) {
    final h = hojas[i];
    final nombre = "'${h.nombre.replaceAll("'", "''")}'";
    final partes = [
      if (h.fijarColumnas > 0) '$nombre!\$A:\$${columnaXlsx(h.fijarColumnas - 1)}',
      if (h.fijarFilas > 0) '$nombre!\$1:\$${h.fijarFilas}',
    ];
    if (partes.isNotEmpty) {
      titulos.add('<definedName name="_xlnm.Print_Titles" localSheetId="$i">${_xml(partes.join(','))}</definedName>');
    }
  }
  if (titulos.isNotEmpty) b.write('<definedNames>${titulos.join()}</definedNames>');
  // Que Excel recalcule las fórmulas al abrir.
  b.write('<calcPr calcId="0" fullCalcOnLoad="1"/></workbook>');
  return b.toString();
}

String _relsLibroXml(int hojas) {
  final b = StringBuffer(_cabeceraXml)
    ..write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
  for (var i = 1; i <= hojas; i++) {
    b.write('<Relationship Id="rId$i" Type="$_nsR/worksheet" Target="worksheets/sheet$i.xml"/>');
  }
  b
    ..write('<Relationship Id="rId${hojas + 1}" Type="$_nsR/styles" Target="styles.xml"/>')
    ..write('</Relationships>');
  return b.toString();
}

String _tiposXml(int hojas) {
  final b = StringBuffer(_cabeceraXml)
    ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
    ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
    ..write('<Default Extension="xml" ContentType="application/xml"/>')
    ..write('<Override PartName="/xl/workbook.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
    ..write('<Override PartName="/xl/styles.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
  for (var i = 1; i <= hojas; i++) {
    b.write('<Override PartName="/xl/worksheets/sheet$i.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
  }
  b.write('</Types>');
  return b.toString();
}

const _relsRaizXml = '$_cabeceraXml'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="$_nsR/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

// Mismos colores que CeldaEstado en la app: verde presente, rojo falta, amarillo pastel justificada,
// azul dual.
const _estilos = '$_cabeceraXml'
    '<styleSheet xmlns="$_ns">'
    '<fonts count="10">'
    '<font><sz val="11"/><name val="Calibri"/></font>' // 0 normal
    '<font><b/><sz val="14"/><name val="Calibri"/></font>' // 1 título
    '<font><i/><sz val="10"/><color rgb="FF616161"/><name val="Calibri"/></font>' // 2 nota
    '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>' // 3 encabezado
    '<font><b/><sz val="11"/><color rgb="FF2E7D32"/><name val="Calibri"/></font>' // 4 presente
    '<font><b/><sz val="11"/><color rgb="FFC62828"/><name val="Calibri"/></font>' // 5 falta
    '<font><b/><sz val="11"/><color rgb="FF000000"/><name val="Calibri"/></font>' // 6 justificada
    '<font><i/><sz val="11"/><color rgb="FF757575"/><name val="Calibri"/></font>' // 7 baja
    '<font><b/><sz val="11"/><color rgb="FF1A237E"/><name val="Calibri"/></font>' // 8 total
    '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>' // 9 dual
    '</fonts>'
    '<fills count="8">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FF3F51B5"/><bgColor indexed="64"/></patternFill></fill>' // 2
    '<fill><patternFill patternType="solid"><fgColor rgb="FFDFF3E0"/><bgColor indexed="64"/></patternFill></fill>' // 3
    '<fill><patternFill patternType="solid"><fgColor rgb="FFFBE0E0"/><bgColor indexed="64"/></patternFill></fill>' // 4
    '<fill><patternFill patternType="solid"><fgColor rgb="FFFFF4BF"/><bgColor indexed="64"/></patternFill></fill>' // 5
    '<fill><patternFill patternType="solid"><fgColor rgb="FFE8EAF6"/><bgColor indexed="64"/></patternFill></fill>' // 6
    '<fill><patternFill patternType="solid"><fgColor rgb="FF1565C0"/><bgColor indexed="64"/></patternFill></fill>' // 7
    '</fills>'
    '<borders count="2">'
    '<border><left/><right/><top/><bottom/><diagonal/></border>'
    '<border><left style="thin"><color rgb="FFBDBDBD"/></left><right style="thin"><color rgb="FFBDBDBD"/></right>'
    '<top style="thin"><color rgb="FFBDBDBD"/></top><bottom style="thin"><color rgb="FFBDBDBD"/></bottom>'
    '<diagonal/></border>'
    '</borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="14">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' // normal
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>' // titulo
    '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>' // nota
    '<xf numFmtId="0" fontId="3" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" '
    'applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>' // encabezado
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>' // texto
    '<xf numFmtId="0" fontId="4" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" '
    'applyAlignment="1"><alignment horizontal="center"/></xf>' // presente
    '<xf numFmtId="0" fontId="5" fillId="4" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" '
    'applyAlignment="1"><alignment horizontal="center"/></xf>' // falta
    '<xf numFmtId="0" fontId="6" fillId="5" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" '
    'applyAlignment="1"><alignment horizontal="center"/></xf>' // justificada
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1">'
    '<alignment horizontal="center"/></xf>' // vacia
    '<xf numFmtId="0" fontId="7" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>' // baja
    '<xf numFmtId="1" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" '
    'applyAlignment="1"><alignment horizontal="center"/></xf>' // numero
    '<xf numFmtId="9" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" '
    'applyAlignment="1"><alignment horizontal="center"/></xf>' // porcentaje
    '<xf numFmtId="0" fontId="8" fillId="6" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" '
    'applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>' // total
    '<xf numFmtId="0" fontId="9" fillId="7" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" '
    'applyAlignment="1"><alignment horizontal="center"/></xf>' // dual
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';

/// El libro completo, listo para guardar como .xlsx. La primera hoja es la que se abre.
Uint8List crearXlsx(List<HojaXlsx> hojas) {
  if (hojas.isEmpty) throw ArgumentError('Un libro necesita al menos una hoja.');
  return zipSinCompresion({
    '[Content_Types].xml': utf8.encode(_tiposXml(hojas.length)),
    '_rels/.rels': utf8.encode(_relsRaizXml),
    'xl/workbook.xml': utf8.encode(_libroXml(hojas)),
    'xl/_rels/workbook.xml.rels': utf8.encode(_relsLibroXml(hojas.length)),
    'xl/styles.xml': utf8.encode(_estilos),
    for (var i = 0; i < hojas.length; i++)
      'xl/worksheets/sheet${i + 1}.xml': utf8.encode(hojaXml(hojas[i], activa: i == 0)),
  });
}

// ── ZIP ──────────────────────────────────────────────────────────────────────────────────────────

final _tablaCrc = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

/// CRC-32 de ZIP (polinomio 0xEDB88320).
int crc32(List<int> datos) {
  var c = 0xFFFFFFFF;
  for (final b in datos) {
    c = _tablaCrc[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// ZIP con los archivos tal cual (sin comprimir), en el orden del mapa. La fecha de todos es la
/// mínima de ZIP (1980-01-01), así el mismo contenido da siempre los mismos bytes.
Uint8List zipSinCompresion(Map<String, List<int>> archivos) {
  const fechaDos = (0 << 9) | (1 << 5) | 1; // 1980-01-01
  const utf8Nombres = 0x0800; // bit 11: nombres en UTF-8
  final salida = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  var offset = 0;

  for (final MapEntry(key: nombre, value: datos) in archivos.entries) {
    final n = utf8.encode(nombre);
    final crc = crc32(datos);
    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little) // versión necesaria
      ..setUint16(6, utf8Nombres, Endian.little)
      ..setUint16(8, 0, Endian.little) // método: store
      ..setUint16(10, 0, Endian.little) // hora
      ..setUint16(12, fechaDos, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, datos.length, Endian.little)
      ..setUint32(22, datos.length, Endian.little)
      ..setUint16(26, n.length, Endian.little)
      ..setUint16(28, 0, Endian.little);
    salida
      ..add(local.buffer.asUint8List())
      ..add(n)
      ..add(datos);

    final entrada = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little) // hecho con
      ..setUint16(6, 20, Endian.little) // versión necesaria
      ..setUint16(8, utf8Nombres, Endian.little)
      ..setUint16(10, 0, Endian.little)
      ..setUint16(12, 0, Endian.little)
      ..setUint16(14, fechaDos, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, datos.length, Endian.little)
      ..setUint32(24, datos.length, Endian.little)
      ..setUint16(28, n.length, Endian.little)
      ..setUint16(30, 0, Endian.little) // extra
      ..setUint16(32, 0, Endian.little) // comentario
      ..setUint16(34, 0, Endian.little) // disco
      ..setUint16(36, 0, Endian.little) // atributos internos
      ..setUint32(38, 0, Endian.little) // atributos externos
      ..setUint32(42, offset, Endian.little);
    central
      ..add(entrada.buffer.asUint8List())
      ..add(n);
    offset += 30 + n.length + datos.length;
  }

  final tamCentral = central.length;
  final fin = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(4, 0, Endian.little)
    ..setUint16(6, 0, Endian.little)
    ..setUint16(8, archivos.length, Endian.little)
    ..setUint16(10, archivos.length, Endian.little)
    ..setUint32(12, tamCentral, Endian.little)
    ..setUint32(16, offset, Endian.little)
    ..setUint16(20, 0, Endian.little);
  salida
    ..add(central.takeBytes())
    ..add(fin.buffer.asUint8List());
  return salida.takeBytes();
}
