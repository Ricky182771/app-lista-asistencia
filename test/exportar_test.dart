import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/exportar.dart';
import 'package:app_lista_asistencia/models/pase.dart';

import 'zip_util.dart';

// Datos inventados.
const _alumnos = [
  {'num': 1, 'nombre': 'Ana Pérez', 'activo': true},
  {'num': 2, 'nombre': 'Beto, el Grande', 'activo': true},
  {'num': 3, 'nombre': '=Cero', 'activo': false},
];

final _pases = <String, Map<String, dynamic>>{
  '2026-11-04': {'1': presente, '2': presente},
  '2026-10-30': {'1': presente, '2': falta},
  '2026-11-03': {'1': falta, '2': justificada, '3': presente},
  'mal': {'1': presente},
};

Registro _registro(Set<String> meses) =>
    Registro(titulo: 'Prueba 3A · Matemáticas', pases: _pases, alumnos: _alumnos, meses: meses);

void main() {
  test('diasPorMes: en orden, sin repetir e ignorando fechas mal formadas', () {
    expect(diasPorMes(['2026-11-04', '2026-10-30', '2026-11-03', '2026-11-03', 'mal', '']), {
      '2026-10': 1,
      '2026-11': 2,
    });
    expect(diasPorMes(const []), isEmpty);
  });

  test('nombreMes', () {
    expect(nombreMes('2026-01'), 'enero de 2026');
    expect(nombreMes('2026-12'), 'diciembre de 2026');
  });

  test('nombreArchivo', () {
    expect(nombreArchivo('Prueba 3A · Matemáticas', ['2026-11'], 'xlsx'),
        'PaseLista - Prueba 3A - Matemáticas - 2026-11.xlsx');
    expect(nombreArchivo('3A/B · Física: I', ['2026-09', '2026-10', '2026-11'], 'csv'),
        'PaseLista - 3A_B - Física_ I - 2026-09 a 2026-11.csv');
  });

  test('porcentajeAsistencia: la justificada cuenta como falta; sin registros, null', () {
    expect(porcentajeAsistencia((presentes: 3, faltas: 0, justificadas: 1)), 0.75);
    expect(porcentajeAsistencia((presentes: 0, faltas: 0, justificadas: 0)), isNull);
  });

  group('Registro', () {
    test('solo los meses elegidos y en orden', () {
      expect(_registro({'2026-10', '2026-11'}).fechas, ['2026-10-30', '2026-11-03', '2026-11-04']);
      expect(_registro({'2026-11'}).fechas, ['2026-11-03', '2026-11-04']);
      expect(_registro({'2026-11'}).meses, ['2026-11']);
      expect(_registro({'2026-12'}).fechas, isEmpty);
    });

    test('filas como en la vista mensual: la baja sale solo donde tiene registro', () {
      final r = _registro({'2026-10', '2026-11'});
      expect(r.filas(r.fechasDe('2026-10')).map((f) => f.nl), ['1', '2']);
      final nov = r.filas(r.fechasDe('2026-11'));
      expect(nov.map((f) => f.nl), ['1', '2', '3']);
      expect(nov.last.baja, isTrue);
    });

    test('conteo y estados desconocidos', () {
      final r = Registro(
        titulo: 't',
        pases: {
          '2026-11-03': {'1': falta},
          '2026-11-04': {'1': 7},
        },
        alumnos: const [],
        meses: {'2026-11'},
      );
      expect(r.estado('2026-11-04', '1'), isNull);
      expect(r.conteo('1', r.fechas), (presentes: 0, faltas: 1, justificadas: 0));
    });
  });

  test('csvRegistro: BOM, comillas, sin fórmulas y totales', () {
    expect(
      csvRegistro(_registro({'2026-10', '2026-11'})),
      '﻿N.L,Nombre,Estatus,2026-10-30,2026-11-03,2026-11-04,Asistencias,Faltas,Faltas justificadas,'
      '% asistencia\r\n'
      '1,Ana Pérez,Activo,P,F,P,2,1,0,66.7\r\n'
      '2,"Beto, el Grande",Activo,F,J,P,1,1,1,33.3\r\n'
      "3,'=Cero,Baja,,P,,1,0,0,100.0\r\n",
    );
    expect(utf8.decode(csvRegistroBytes(_registro({'2026-11'}))), startsWith('﻿N.L,'));
  });

  group('xlsxRegistro', () {
    test('un mes: una hoja con colores, fórmulas y faltas del día', () {
      final zip = leerZip(xlsxRegistro(_registro({'2026-11'})));
      expect(zip['xl/workbook.xml'], contains('<sheet name="noviembre de 2026" sheetId="1"'));
      expect(zip.containsKey('xl/worksheets/sheet2.xml'), isFalse);
      final hoja = zip['xl/worksheets/sheet1.xml']!;
      expect(hoja, contains('<t xml:space="preserve">Prueba 3A · Matemáticas</t>'));
      expect(hoja, contains('<t xml:space="preserve">mar 03</t>'));
      // Ana, fila 5: F el 03 y P el 04; los totales cuentan C5:D5.
      expect(hoja, contains('<c r="C5" s="6" t="inlineStr"><is><t xml:space="preserve">F</t>'));
      expect(hoja, contains('<c r="D5" s="5" t="inlineStr"><is><t xml:space="preserve">P</t>'));
      expect(hoja, contains('<c r="E5" s="10"><f>COUNTIF(C5:D5,&quot;P&quot;)</f><v>1</v></c>'));
      expect(hoja, contains('<f>IF(SUM(E5:G5)=0,&quot;&quot;,E5/SUM(E5:G5))</f><v>0.5</v>'));
      // La baja, en gris; la fila 8 cuenta faltas por día.
      expect(hoja, contains('=Cero (baja)'));
      expect(hoja, contains('<f>COUNTIF(C5:C7,&quot;F&quot;)</f><v>1</v>'));
      expect(hoja, contains('ySplit="4" topLeftCell="C5"'));
    });

    test('varios meses: resumen primero y una hoja por mes', () {
      final zip = leerZip(xlsxRegistro(_registro({'2026-10', '2026-11'})));
      final libro = zip['xl/workbook.xml']!;
      expect(libro, contains('<sheet name="Resumen" sheetId="1"'));
      expect(libro, contains('<sheet name="octubre de 2026" sheetId="2"'));
      expect(libro, contains('<sheet name="noviembre de 2026" sheetId="3"'));
      final resumen = zip['xl/worksheets/sheet1.xml']!;
      expect(resumen, contains('% oct 2026'));
      // Ana: 2 de 3 en el periodo.
      expect(resumen, contains('<c r="C5" s="10"><v>2</v></c>'));
      expect(resumen, contains('<c r="F5" s="11"><v>0.6666666666666666</v></c>'));
    });

    test('sin pases en los meses elegidos falla', () {
      expect(() => xlsxRegistro(_registro({'2026-12'})), throwsArgumentError);
    });
  });
}
