import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/exportar.dart';
import 'package:app_lista_asistencia/models/pase.dart';

import 'zip_util.dart';

// Datos inventados.
const _alumnos = [
  {'num': 1, 'nombre': 'Ana Pérez', 'activo': true},
  {'num': 2, 'nombre': 'Beto Ruiz', 'activo': true},
  {'num': 3, 'nombre': 'Caro Díaz', 'activo': false},
];

final List<ClaseDelGrupo> _clases = [
  (
    materia: 'Matemáticas',
    profesor: 'Ana López',
    salon: 'A1',
    pases: {
      '2026-11-03': {'1': falta, '2': justificada},
      '2026-11-04': {'1': presente, '2': presente},
    },
  ),
  (
    materia: 'Física',
    profesor: 'Beto Ruiz',
    salon: 'B2',
    pases: {
      '2026-10-30': {'1': presente, '2': falta, '3': presente},
      '2026-11-04': {'1': presente, '2': presente},
    },
  ),
  (
    materia: 'Historia',
    profesor: '',
    salon: 'C3',
    pases: {
      '2026-09-01': {'1': presente},
    },
  ),
];

RegistroGrupo _grupo(Set<String> meses) =>
    RegistroGrupo(titulo: 'Prueba 3A · Grupo completo', alumnos: _alumnos, delGrupo: _clases, meses: meses);

void main() {
  group('RegistroGrupo', () {
    final g = _grupo({'2026-10', '2026-11'});

    test('solo las clases con pases en los meses elegidos, por materia', () {
      expect([for (final c in g.clases) c.etiqueta], [
        'Física (Prof. Beto Ruiz)',
        'Matemáticas (Prof. Ana López)',
      ]);
    });

    test('meses y días con pase (distintos) de todo el grupo', () {
      expect(g.meses, ['2026-10', '2026-11']);
      expect(g.diasConPase, 3);
    });

    test('una clase sin profe lleva solo la materia', () {
      final h = _grupo({'2026-09'});
      expect(h.clases.single.etiqueta, 'Historia');
    });

    test('filas: los activos y quien tenga registro aunque esté de baja', () {
      expect([for (final f in g.filas) '${f.nl}${f.baja ? ' (baja)' : ''}'], ['1', '2', '3 (baja)']);
      // En septiembre solo hay un pase de Ana: la baja no aparece.
      expect([for (final f in _grupo({'2026-09'}).filas) f.nl], ['1', '2']);
    });

    test('conteo por clase y total', () {
      final fisica = g.clases[0], mate = g.clases[1];
      expect(g.conteoDe('1', fisica), (presentes: 2, faltas: 0, justificadas: 0));
      expect(g.conteoDe('1', mate), (presentes: 1, faltas: 1, justificadas: 0));
      expect(g.total('2'), (presentes: 2, faltas: 1, justificadas: 1));
      expect(g.total('3'), (presentes: 1, faltas: 0, justificadas: 0));
    });

    test('sin pases en los meses elegidos no hay clases', () {
      expect(_grupo({'2026-12'}).clases, isEmpty);
    });
  });

  group('csvGrupo', () {
    test('una tabla con las clases por columnas y los totales', () {
      final csv = csvGrupo(_grupo({'2026-10', '2026-11'}));
      expect(csv.startsWith('﻿'), isTrue);
      final lineas = csv.substring(1).split('\r\n');
      expect(lineas.last, '', reason: 'termina en CRLF');
      expect(lineas[0],
          'N.L,Nombre,Estatus,'
          'Física (Prof. Beto Ruiz) - Asistencias,Física (Prof. Beto Ruiz) - Faltas,Física (Prof. Beto Ruiz) - Justificadas,'
          'Matemáticas (Prof. Ana López) - Asistencias,Matemáticas (Prof. Ana López) - Faltas,Matemáticas (Prof. Ana López) - Justificadas,'
          'Total asistencias,Total faltas,Total justificadas,% asistencia');
      expect(lineas[1], '1,Ana Pérez,Activo,2,0,0,1,1,0,3,1,0,75.0');
      expect(lineas[2], '2,Beto Ruiz,Activo,1,1,0,1,0,1,2,1,1,50.0');
      expect(lineas[3], '3,Caro Díaz,Baja,1,0,0,0,0,0,1,0,0,100.0');
      expect(lineas, hasLength(5));
    });

    test('un nombre que parece fórmula lleva apóstrofo y uno con comas va entre comillas', () {
      final g = RegistroGrupo(
        titulo: 'x',
        alumnos: const [
          {'num': 1, 'nombre': '=Cero', 'activo': true},
          {'num': 2, 'nombre': 'Ruiz, Beto', 'activo': true},
        ],
        delGrupo: [
          (
            materia: 'Física',
            profesor: 'Ana',
            salon: 'A1',
            pases: {
              '2026-11-04': {'1': presente, '2': falta},
            },
          ),
        ],
        meses: {'2026-11'},
      );
      final lineas = csvGrupo(g).split('\r\n');
      expect(lineas[1], startsWith("1,'=Cero,Activo,"));
      expect(lineas[2], startsWith('2,"Ruiz, Beto",Activo,'));
    });
  });

  group('xlsxGrupo', () {
    final zip = leerZip(xlsxGrupo(_grupo({'2026-10', '2026-11'})));
    final hoja = zip['xl/worksheets/sheet1.xml']!;

    test('una sola hoja con el título y el nombre de cada clase combinado arriba', () {
      expect(zip['xl/workbook.xml'], contains('<sheet name="Grupo completo" sheetId="1"'));
      expect(zip.containsKey('xl/worksheets/sheet2.xml'), isFalse);
      expect(hoja, contains('<t xml:space="preserve">Prueba 3A · Grupo completo</t>'));
      expect(hoja, contains('<t xml:space="preserve">Física (Prof. Beto Ruiz)</t>'));
      expect(hoja, contains('<t xml:space="preserve">Matemáticas (Prof. Ana López)</t>'));
      expect(hoja, contains('<mergeCell ref="C4:E4"/>'));
      expect(hoja, contains('<mergeCell ref="F4:H4"/>'));
      expect(hoja, contains('<mergeCell ref="I4:L4"/>'));
    });

    test('los totales de cada alumno son fórmulas que suman sus clases', () {
      // Ana, fila 6: Física en C:E, Matemáticas en F:H, totales en I:L.
      expect(hoja, contains('<c r="C6" s="10"><v>2</v></c>'));
      expect(hoja, contains('<c r="I6" s="10"><f>C6+F6</f><v>3</v></c>'));
      expect(hoja, contains('<c r="J6" s="10"><f>D6+G6</f><v>1</v></c>'));
      expect(hoja, contains('<f>IF(SUM(I6:K6)=0,&quot;&quot;,I6/SUM(I6:K6))</f><v>0.75</v>'));
    });

    test('la baja con registro aparece marcada', () {
      expect(hoja, contains('Caro Díaz (baja)'));
    });

    test('sin pases en los meses elegidos falla', () {
      expect(() => xlsxGrupo(_grupo({'2026-12'})), throwsArgumentError);
    });
  });
}
