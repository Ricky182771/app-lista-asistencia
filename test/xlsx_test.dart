import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/xlsx.dart';

import 'zip_util.dart';

void main() {
  test('crc32 con el vector de prueba estándar', () {
    expect(crc32(ascii.encode('123456789')), 0xCBF43926);
    expect(crc32(const []), 0);
  });

  test('columnaXlsx y celdaXlsx', () {
    expect([0, 1, 25, 26, 27, 51, 52, 701, 702].map(columnaXlsx), ['A', 'B', 'Z', 'AA', 'AB', 'AZ', 'BA', 'ZZ', 'AAA']);
    expect(celdaXlsx(0, 0), 'A1');
    expect(celdaXlsx(4, 2), 'C5');
  });

  test('nombreHoja quita lo que Excel no acepta y corta a 31', () {
    expect(nombreHoja('3A: Mate/Física?'), '3A- Mate-Física-');
    expect(nombreHoja('x' * 40).length, 31);
    expect(nombreHoja('  '), 'Hoja');
  });

  test('hojaXml escapa el texto y guarda fórmula con su resultado', () {
    final xml = hojaXml(
      HojaXlsx(
        nombre: 'H',
        filas: [
          [const CeldaXlsx.texto('A & B <c> "d"\u0001'), const CeldaXlsx.numero(3), null, const CeldaXlsx.vacia()],
          [CeldaXlsx.formula('COUNTIF(A1:B1,"P")', 2), CeldaXlsx.formula('IF(1=0,"",1)', '')],
        ],
        anchos: {1: 30, 0: 6},
        fijarFilas: 1,
        fijarColumnas: 2,
      ),
      activa: true,
    );
    expect(xml, contains('<t xml:space="preserve">A &amp; B &lt;c&gt; &quot;d&quot;</t>'));
    expect(xml, contains('<c r="B1" s="${EstiloXlsx.numero.index}"><v>3</v></c>'));
    expect(xml, isNot(contains('r="C1"')));
    expect(xml, contains('<c r="D1" s="${EstiloXlsx.vacia.index}"/>'));
    expect(xml, contains('<f>COUNTIF(A1:B1,&quot;P&quot;)</f><v>2</v>'));
    expect(xml, contains('t="str"><f>IF(1=0,&quot;&quot;,1)</f><v></v>'));
    expect(xml, contains('xSplit="2" ySplit="1" topLeftCell="C2" activePane="bottomRight" state="frozen"'));
    expect(xml, contains('tabSelected="1"'));
    // Columnas en orden aunque el mapa no lo esté.
    expect(xml.indexOf('<col min="1"'), lessThan(xml.indexOf('<col min="2"')));
  });

  test('crearXlsx arma un ZIP válido con todas las partes', () {
    final hojas = [
      HojaXlsx(nombre: 'Resumen', filas: [
        [const CeldaXlsx.texto('hola')],
      ]),
      HojaXlsx(nombre: "Nov '26", filas: const [], fijarFilas: 4, fijarColumnas: 2),
    ];
    final bytes = crearXlsx(hojas);
    expect(crearXlsx(hojas), bytes, reason: 'mismo contenido, mismos bytes');
    final zip = leerZip(bytes);
    expect(zip.keys, [
      '[Content_Types].xml',
      '_rels/.rels',
      'xl/workbook.xml',
      'xl/_rels/workbook.xml.rels',
      'xl/styles.xml',
      'xl/worksheets/sheet1.xml',
      'xl/worksheets/sheet2.xml',
    ]);
    expect(zip['[Content_Types].xml'], contains('/xl/worksheets/sheet2.xml'));
    expect(zip['xl/workbook.xml'], contains('<sheet name="Resumen" sheetId="1" r:id="rId1"/>'));
    expect(zip['xl/workbook.xml'], contains("'Nov ''26'!\$A:\$B,'Nov ''26'!\$1:\$4"));
    expect(zip['xl/_rels/workbook.xml.rels'], contains('Id="rId3"'));
    expect(zip['xl/styles.xml'], contains('<cellXfs count="${EstiloXlsx.values.length}">'));
    expect(RegExp('<xf ').allMatches(zip['xl/styles.xml']!.split('<cellXfs')[1]).length, EstiloXlsx.values.length);
  });

  test('crearXlsx sin hojas falla', () {
    expect(() => crearXlsx(const []), throwsArgumentError);
  });
}
