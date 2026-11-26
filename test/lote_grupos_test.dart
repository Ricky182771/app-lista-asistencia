import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/grupo.dart';
import 'package:app_lista_asistencia/models/lote_grupos.dart';

List<int> bytes(String texto) => utf8.encode(texto);

FilaAlumnoLote fila(String grupo, String nl, String nombre, {int n = 1}) =>
    FilaAlumnoLote(fila: n, grupo: grupo, numTexto: nl, nombre: nombre);

void main() {
  group('leerAlumnosLote', () {
    test('con encabezado', () {
      final l = leerAlumnosLote(bytes('Grupo,N.L,Nombre\nIA 3A,1,Ana López\nIA 3A,2,Beto Ruiz\nIA 3B,1,Caro Díaz\n'));
      expect(l.errorGeneral, isNull);
      expect(l.filas, hasLength(3));
      expect(l.filas.first.grupo, 'IA 3A');
      expect(l.filas.first.numTexto, '1');
      expect(l.filas.first.nombre, 'Ana López');
      expect(l.filas.first.fila, 2);
    });

    test('sin encabezado: grupo, N.L y nombre por posición', () {
      final l = leerAlumnosLote(bytes('IA 3A,1,Ana López\nIA 3A,2,"Ruiz, Beto"\n'));
      expect(l.filas, hasLength(2));
      expect(l.filas.last.nombre, 'Ruiz, Beto');
    });

    test('encabezado con otro orden y otros nombres', () {
      final l = leerAlumnosLote(bytes('Alumno;Número de lista;Grupo\nAna;4;IA 3A\n'));
      expect(l.filas.single.grupo, 'IA 3A');
      expect(l.filas.single.numTexto, '4');
      expect(l.filas.single.nombre, 'Ana');
    });

    test('con encabezado, falta una columna', () {
      expect(leerAlumnosLote(bytes('Grupo,Nombre\nIA 3A,Ana\n')).errorGeneral, contains('"nl"'));
    });
  });

  group('FilaAlumnoLote.num', () {
    test('entero positivo', () {
      expect(fila('g', '7', 'x').num, 7);
      expect(fila('g', ' 12 ', 'x').num, 12);
    });
    test('lo demás es null', () {
      for (final mal in ['', '0', '-3', '2.5', 'a', '1a']) {
        expect(fila('g', mal, 'x').num, isNull, reason: mal);
      }
    });
  });

  group('agruparPorGrupo', () {
    test('junta las formas de escribir el mismo grupo y avisa las variantes', () {
      final grupos = agruparPorGrupo([
        fila('IA 3A', '1', 'Ana López'),
        fila('ia 3a', '2', 'Beto Ruiz'),
        fila('IA-3A', '3', 'Caro Díaz'),
        fila('IA 3B', '1', 'Dani Paz'),
      ]);
      expect([for (final g in grupos) g.id], ['ia-3a', 'ia-3b']);
      expect(grupos.first.nombre, 'IA 3A');
      expect(grupos.first.filas, hasLength(3));
      expect(grupos.first.variantes, {'ia 3a', 'IA-3A'});
      expect(grupos.last.variantes, isEmpty);
    });

    test('ordena por nombre', () {
      final grupos = agruparPorGrupo([fila('IA 3B', '1', 'a b'), fila('IA 3A', '1', 'c d')]);
      expect([for (final g in grupos) g.nombre], ['IA 3A', 'IA 3B']);
    });
  });

  group('validarGrupos', () {
    List<ValidacionGrupo> validar(
      List<FilaAlumnoLote> filas, {
      Map<String, String> existentes = const {},
      Map<String, List<Alumno>?> alumnos = const {},
      Set<String> actualizar = const {},
    }) =>
        validarGrupos(filas, existentes: existentes, alumnosExistentes: alumnos, actualizar: actualizar);

    test('un grupo nuevo y sin problemas se guarda', () {
      final v = validar([fila('IA 3A', '2', 'Beto Ruiz'), fila('IA 3A', '1', 'Ana López')]).single;
      expect(v.nuevo, isTrue);
      expect(v.seGuarda, isTrue);
      expect(v.hayErrores, isFalse);
      final g = porGuardar(v)!;
      expect(g.id, 'ia-3a');
      expect(g.nombre, 'IA 3A');
      expect([for (final a in g.alumnos) a.num], [1, 2]);
    });

    test('N.L inválido, vacío o repetido; nombre vacío', () {
      final v = validar([
        fila('IA 3A', 'x', 'Ana López', n: 2),
        fila('IA 3A', '', 'Beto Ruiz', n: 3),
        fila('IA 3A', '4', 'Caro Díaz', n: 4),
        fila('IA 3A', '4', 'Dani Paz', n: 5),
        fila('IA 3A', '5', '', n: 6),
      ]).single;
      expect(v.filas[0].errores, ['El N.L debe ser un entero positivo']);
      expect(v.filas[1].errores, ['Falta el N.L']);
      expect(v.filas[2].errores.single, 'El N.L 4 está repetido en la fila 5');
      expect(v.filas[3].errores.single, 'El N.L 4 está repetido en la fila 4');
      expect(v.filas[4].errores, ['Falta el nombre']);
      expect(v.hayErrores, isTrue);
      expect(v.bloquea, isTrue);
      expect(porGuardar(v), isNull);
    });

    test('avisos: posible duplicado, una sola palabra, números', () {
      final v = validar([
        fila('IA 3A', '1', 'Ana López'),
        fila('IA 3A', '2', 'ana lopez'),
        fila('IA 3A', '3', 'Cher'),
        fila('IA 3A', '4', 'Dani Paz 2'),
      ]).single;
      expect(v.hayErrores, isFalse);
      expect(v.filas[0].avisos.single, contains('N.L 2'));
      expect(v.filas[1].avisos.single, contains('N.L 1'));
      expect(v.filas[2].avisos.single, contains('una palabra'));
      expect(v.filas[3].avisos.single, contains('números'));
      expect(v.filas.every((f) => f.seGuarda), isTrue);
    });

    test('nombre de grupo vacío, sin letras o demasiado largo', () {
      expect(validar([fila('', '1', 'Ana López')]).single.errores.single, 'Falta el nombre del grupo');
      expect(validar([fila('###', '1', 'Ana López')]).single.errores.single, contains('letras o números'));
      expect(validar([fila('G' * 41, '1', 'Ana López')]).single.errores.single, contains('40'));
    });

    test('variantes del nombre dan un aviso, no un error', () {
      final v = validar([fila('IA 3A', '1', 'Ana López'), fila('ia 3a', '2', 'Beto Ruiz')]).single;
      expect(v.errores, isEmpty);
      expect(v.avisos.single, contains('varias formas'));
    });

    test('un grupo que ya existe se omite por omisión y no bloquea aunque tenga errores', () {
      final v = validar(
        [fila('IA 3A', 'x', 'Ana López')],
        existentes: {'ia-3a': 'IA 3A'},
      ).single;
      expect(v.nuevo, isFalse);
      expect(v.existenteId, 'ia-3a');
      expect(v.seGuarda, isFalse);
      expect(v.hayErrores, isTrue);
      expect(v.bloquea, isFalse);
      expect(porGuardar(v), isNull);
    });

    test('un grupo renombrado se reconoce por su nombre actual y por su ID', () {
      // El grupo con ID ia-3b hoy se llama "IA 3A".
      final porNombre = validar(
        [fila('IA 3A', '1', 'Ana López')],
        existentes: {'ia-3b': 'IA 3A'},
      ).single;
      expect(porNombre.existenteId, 'ia-3b');
      // El grupo con ID ia-3a hoy se llama "Los Pumas": el archivo trae "IA 3A" (su ID original).
      final porId = validar(
        [fila('IA 3A', '1', 'Ana López')],
        existentes: {'ia-3a': 'Los Pumas'},
      ).single;
      expect(porId.existenteId, 'ia-3a');
      expect(porId.avisos.single, contains('Los Pumas'));
    });

    test('actualizar compara por N.L y conserva el historial', () {
      final existentes = {'ia-3a': 'IA 3A'};
      final actual = [
        const Alumno(num: 1, nombre: 'Ana López'),
        const Alumno(num: 2, nombre: 'Beto'),
        const Alumno(num: 9, nombre: 'Zoe Gil'),
      ];
      final v = validar(
        [
          fila('IA 3A', '1', 'Ana López'),
          fila('IA 3A', '2', 'Beto Ruiz'),
          fila('IA 3A', '3', 'Caro Díaz'),
        ],
        existentes: existentes,
        alumnos: {'ia-3a': actual},
        actualizar: {'ia-3a'},
      ).single;
      expect(v.actualizar, isTrue);
      expect(v.seGuarda, isTrue);
      expect(v.cambios!.nuevos.map((a) => a.num), [3]);
      expect(v.cambios!.renombrados.map((c) => c.num), [2]);
      expect(v.cambios!.bajas.map((a) => a.num), [9]);
      final g = porGuardar(v)!;
      expect(g.id, 'ia-3a');
      expect(g.nombre, isNull, reason: 'null = solo actualizar la lista, no crear el grupo');
      expect(g.alumnos.map((a) => a.num), [1, 2, 3, 9]);
      expect(g.alumnos.last.activo, isFalse);
    });

    test('actualizar sin cambios no escribe nada', () {
      final v = validar(
        [fila('IA 3A', '1', 'Ana López')],
        existentes: {'ia-3a': 'IA 3A'},
        alumnos: {'ia-3a': [const Alumno(num: 1, nombre: 'Ana López')]},
        actualizar: {'ia-3a'},
      ).single;
      expect(v.cambios!.sinCambios, isTrue);
      expect(porGuardar(v), isNull);
    });

    test('no se actualiza un grupo con alumnos que la app no reconoce', () {
      final v = validar(
        [fila('IA 3A', '1', 'Ana López')],
        existentes: {'ia-3a': 'IA 3A'},
        alumnos: {'ia-3a': null},
        actualizar: {'ia-3a'},
      ).single;
      expect(v.errores.single, contains('no reconoce'));
      expect(v.bloquea, isTrue);
    });

    test('varios grupos en el mismo archivo se validan por separado', () {
      final v = validar([
        fila('IA 3A', '1', 'Ana López'),
        fila('IA 3B', '1', 'Beto Ruiz'),
        fila('IA 3B', '1', 'Caro Díaz'),
      ]);
      expect(v, hasLength(2));
      expect(v[0].hayErrores, isFalse);
      expect(v[1].hayErrores, isTrue, reason: 'el N.L 1 está repetido solo en IA 3B');
    });
  });
}
