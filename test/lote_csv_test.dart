import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/lote_csv.dart';

List<int> bytes(String texto) => utf8.encode(texto);

void main() {
  group('leerTabla', () {
    test('lee las filas con su número y limpia espacios', () {
      final t = leerTabla(bytes('a, b \nc,d\n'));
      expect(t.errorGeneral, isNull);
      expect([for (final f in t.filas) f.celdas], [
        ['a', 'b'],
        ['c', 'd'],
      ]);
      expect([for (final f in t.filas) f.fila], [1, 2]);
    });

    test('salta las filas vacías (Excel deja filas de puras comas)', () {
      final t = leerTabla(bytes('a,b\n,\n\nc,d\n,,\n'));
      expect([for (final f in t.filas) f.celdas.first], ['a', 'c']);
    });

    test('detecta punto y coma y respeta las comillas', () {
      final t = leerTabla(bytes('x;y\n"a;b";c\n'));
      expect(t.filas.last.celdas, ['a;b', 'c']);
    });

    test('un nombre con coma entre comillas es una sola celda', () {
      final t = leerTabla(bytes('1,"García Ruiz, Luis"\n'));
      expect(t.filas.single.celdas, ['1', 'García Ruiz, Luis']);
    });

    test('si no es UTF-8 usa latin1 (Excel en Windows)', () {
      final t = leerTabla(latin1.encode('Peña,Ñandú\n'));
      expect(t.filas.single.celdas, ['Peña', 'Ñandú']);
    });

    test('quita el BOM de UTF-8', () {
      final t = leerTabla([0xEF, 0xBB, 0xBF, ...utf8.encode('a,b\n')]);
      expect(t.filas.single.celdas, ['a', 'b']);
    });

    test('UTF-16 se rechaza con un mensaje claro', () {
      final t = leerTabla([0xFF, 0xFE, 0x61, 0x00]);
      expect(t.errorGeneral, contains('UTF-16'));
    });

    test('un archivo vacío es un error', () {
      expect(leerTabla(bytes('')).errorGeneral, isNotNull);
      expect(leerTabla(bytes(' , \n\n')).errorGeneral, isNotNull);
    });

    test('celda devuelve vacío si la fila no llega hasta ahí', () {
      final f = leerTabla(bytes('a,b\n')).filas.single;
      expect(f.celda(1), 'b');
      expect(f.celda(5), '');
      expect(f.celda(-1), '');
    });
  });

  test('llaveEncabezado reconoce encabezados escritos de varias formas', () {
    expect(llaveEncabezado('N.L'), 'nl');
    expect(llaveEncabezado(' Número de lista '), 'numerodelista');
    expect(llaveEncabezado('Correo electrónico'), 'correoelectronico');
  });

  group('leerConColumnas', () {
    const alias = {
      'correo': ['correo', 'email'],
      'rol': ['rol'],
    };
    const orden = ['correo', 'rol'];

    test('con encabezado ubica las columnas en cualquier orden', () {
      final t = leerConColumnas(bytes('Rol,Correo\nprofesor,ana@x.mx\n'), orden: orden, alias: alias);
      expect(t.errorGeneral, isNull);
      expect(t.filas, hasLength(1));
      expect(t.valor(t.filas.single, 'correo'), 'ana@x.mx');
      expect(t.valor(t.filas.single, 'rol'), 'profesor');
    });

    test('sin encabezado toma las columnas por posición', () {
      final t = leerConColumnas(bytes('ana@x.mx,orden\nbeto@x.mx,admin\n'), orden: orden, alias: alias);
      expect(t.filas, hasLength(2));
      expect(t.valor(t.filas.first, 'correo'), 'ana@x.mx');
      expect(t.valor(t.filas.first, 'rol'), 'orden');
    });

    test('una columna que no viene da vacío', () {
      final t = leerConColumnas(bytes('correo\nana@x.mx\n'), orden: orden, alias: alias);
      expect(t.valor(t.filas.single, 'rol'), '');
    });

    test('con encabezado, si falta una columna obligatoria avisa cuál', () {
      final t = leerConColumnas(
        bytes('nombre,rol\nAna,profesor\n'),
        orden: orden,
        alias: alias,
        obligatorias: const ['correo'],
      );
      expect(t.errorGeneral, contains('"correo"'));
      expect(t.filas, isEmpty);
    });

    test('un archivo con solo encabezado es un error', () {
      final t = leerConColumnas(bytes('correo,rol\n'), orden: orden, alias: alias);
      expect(t.errorGeneral, contains('encabezado'));
    });

    test('propaga el error del archivo', () {
      expect(leerConColumnas(bytes(''), orden: orden, alias: alias).errorGeneral, isNotNull);
    });
  });

  group('contarLote y resumenLote', () {
    const ok = ResultadoFila();
    const conAviso = ResultadoFila(avisos: ['ojo']);
    const omitida = ResultadoFila(omitida: 'ya existe');
    const error = ResultadoFila(errores: ['mal']);

    test('cuenta cada tipo; una con error y omitida cuenta como error', () {
      final c = contarLote([ok, conAviso, omitida, error, const ResultadoFila(errores: ['x'], omitida: 'y')]);
      expect(c, (seGuardan: 2, omitidas: 1, conError: 2, conAviso: 1));
    });

    test('seGuarda solo sin errores y sin omitir', () {
      expect(ok.seGuarda, isTrue);
      expect(conAviso.seGuarda, isTrue);
      expect(omitida.seGuarda, isFalse);
      expect(error.seGuarda, isFalse);
    });

    test('resumenLote', () {
      expect(resumenLote((seGuardan: 1, omitidas: 0, conError: 0, conAviso: 0)), '1 se guardará');
      expect(
        resumenLote((seGuardan: 3, omitidas: 1, conError: 2, conAviso: 0)),
        '3 se guardarán · 1 omitida · 2 con error',
      );
    });
  });

  test('dondeFila', () {
    expect(dondeFila(5), 'la fila 5');
    expect(dondeFila(0), 'una fila agregada a mano');
  });
}
