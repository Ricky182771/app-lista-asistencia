import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/csv_alumnos.dart';

/// Los bytes tal cual del archivo, no el texto: así se prueba también la codificación.
List<int> fixture(String nombre) => File('test/fixtures/csv/$nombre').readAsBytesSync();

/// Los 8 alumnos inventados que traen los archivos de prueba (ver test/fixtures/csv/LEEME.md).
const esperados = [
  'Ana María Hernández López',
  'José Ángel Muñoz Pérez',
  'Luis Fernando García Ruiz',
  'María José Torres Vega',
  'Diego Ramírez Castillo',
  'Ximena Peña Núñez',
  'Jesús Güemes Ordóñez',
  'Sofía Íñiguez Ávila',
];

void esperaLos8(ListaCsv lista, {List<String> nombres = esperados}) {
  expect(lista.valida, isTrue, reason: 'errores: ${lista.filas.map((f) => f.errores)}');
  expect(lista.alumnos.map((a) => a.num), [1, 2, 3, 4, 5, 6, 7, 8]);
  expect(lista.alumnos.map((a) => a.nombre), nombres);
  expect(lista.alumnos.every((a) => a.activo), isTrue);
}

void main() {
  group('archivos de test/fixtures/csv', () {
    test('01: UTF-8 con BOM de Excel → 8 alumnos con acentos', () {
      esperaLos8(leerCsv(fixture('01_utf8_bom_excel.csv')));
    });

    test('02: Windows-1252 de Excel → 8 alumnos con acentos', () {
      esperaLos8(leerCsv(fixture('02_windows1252_excel.csv')));
    });

    test('03: separado por punto y coma → 8 alumnos', () {
      esperaLos8(leerCsv(fixture('03_punto_y_coma.csv')));
    });

    test('04: con encabezado → se descarta y quedan 8 alumnos', () {
      final lista = leerCsv(fixture('04_con_encabezado.csv'));
      esperaLos8(lista);
      expect(lista.filas.first.fila, 2, reason: 'la fila 1 era el encabezado');
    });

    test('05: N.L 3 repetido → error en las dos filas y no se puede subir', () {
      final lista = leerCsv(fixture('05_numero_repetido.csv'));
      expect(lista.valida, isFalse);
      expect(lista.filas, hasLength(8));
      expect(lista.conError, 2);
      final conError = lista.filas.where((f) => !f.valida).toList();
      expect(conError.map((f) => f.fila), [3, 5]);
      expect(conError.map((f) => f.num), [3, 3]);
      expect(conError.first.errores.single, contains('repetido'));
    });

    test('06: nombre con coma entre comillas → el alumno 3 conserva la coma', () {
      final lista = leerCsv(fixture('06_nombre_con_coma.csv'));
      esperaLos8(lista, nombres: [...esperados]..[2] = 'García Ruiz, Luis Fernando');
    });
  });

  group('decodificar', () {
    test('quita el BOM', () {
      expect(decodificar([0xEF, 0xBB, 0xBF, ...utf8.encode('1,Ñu')]), '1,Ñu');
    });
    test('UTF-8 sin BOM', () {
      expect(decodificar(utf8.encode('Íñiguez')), 'Íñiguez');
    });
    test('si no es UTF-8 válido usa latin1', () {
      expect(decodificar(latin1.encode('Núñez Güemes')), 'Núñez Güemes');
    });
  });

  group('detectarSeparador', () {
    test('coma, punto y coma y tabulador', () {
      expect(detectarSeparador('1,Ana\r\n2,Luis'), ',');
      expect(detectarSeparador('1;Ana\r\n2;Luis'), ';');
      expect(detectarSeparador('1\tAna\r\n2\tLuis'), '\t');
    });
    test('no cuenta los separadores entre comillas', () {
      expect(detectarSeparador('1;"García, Ruiz, Luis"'), ';');
    });
    test('en un empate gana el punto y coma; sin separadores, la coma', () {
      expect(detectarSeparador('1;García, Luis'), ';');
      expect(detectarSeparador('Ana'), ',');
      expect(detectarSeparador(''), ',');
    });
    test('usa la primera línea con texto', () {
      expect(detectarSeparador('\r\n\r\n1;Ana'), ';');
    });
  });

  group('leerCsv', () {
    ListaCsv leer(String texto) => leerCsv(utf8.encode(texto));

    test('limpia espacios y salta filas vacías', () {
      final lista = leer('  1 ,  Ana   María  \r\n\r\n,,\r\n 2,Luis\r\n');
      expect(lista.valida, isTrue);
      expect(lista.alumnos.map((a) => a.nombre), ['Ana María', 'Luis']);
      expect(lista.filas.map((f) => f.fila), [1, 4]);
    });

    test('separado por tabuladores', () {
      expect(leer('1\tAna\n2\tLuis\n').alumnos.map((a) => a.nombre), ['Ana', 'Luis']);
    });

    test('ordena los alumnos por N.L', () {
      expect(leer('3,Luis\n1,Ana\n2,Eva').alumnos.map((a) => a.num), [1, 2, 3]);
    });

    test('N.L que no es entero positivo', () {
      for (final num in ['0', '-1', '1.5', 'x', '']) {
        final lista = leer('1,Ana\n$num,Luis');
        expect(lista.valida, isFalse, reason: 'N.L "$num"');
        expect(lista.filas.last.errores, isNotEmpty, reason: 'N.L "$num"');
      }
    });

    test('nombre vacío o fila sin segunda columna', () {
      expect(leer('1,Ana\n2,').filas.last.errores, ['Falta el nombre']);
      expect(leer('1,Ana\n2').filas.last.errores, ['Falta el nombre']);
    });

    test('nombre con coma sin comillas: avisa en vez de cortar el nombre', () {
      final lista = leer('1,Ana\n2,García Ruiz, Luis');
      expect(lista.valida, isFalse);
      expect(lista.filas.last.errores.single, contains('comillas'));
    });

    test('las columnas vacías de más no son error', () {
      expect(leer('1,Ana,,\n2,Luis,,').valida, isTrue);
    });

    test('archivo vacío o solo con encabezado', () {
      for (final texto in ['', '\r\n\r\n', 'No.,Nombre completo\r\n']) {
        final lista = leer(texto);
        expect(lista.valida, isFalse);
        expect(lista.errorGeneral, isNotNull);
      }
    });

    test('solo se descarta el encabezado de la primera fila', () {
      final lista = leer('No.,Nombre\n1,Ana\nx,Luis');
      expect(lista.filas, hasLength(2));
      expect(lista.valida, isFalse);
    });
  });
}
