import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/grupo.dart';

void main() {
  group('idGrupo', () {
    test('minúsculas y espacios a guiones', () {
      expect(idGrupo('IA 3A'), 'ia-3a');
      expect(idGrupo('  Programación   5B  '), 'programacion-5b');
    });
    test('quita acentos, diéresis y eñes', () {
      expect(idGrupo('Mecánica Ñandú Güero'), 'mecanica-nandu-guero');
      expect(idGrupo('ÁÉÍÓÚ'), 'aeiou');
    });
    test('otros símbolos también son guion: una "/" cambiaría la ruta del documento', () {
      expect(idGrupo('3°A / Turno matutino'), '3-a-turno-matutino');
      expect(idGrupo('--IA__3A--'), 'ia-3a');
    });
    test('sin letras ni números queda vacío', () {
      expect(idGrupo(''), '');
      expect(idGrupo('   '), '');
      expect(idGrupo('°/-'), '');
    });
  });

  test('Alumno.toMap usa los campos de grupos.alumnos y nace activo', () {
    expect(
      const Alumno(num: 3, nombre: 'Luis Fernando García Ruiz').toMap(),
      {'num': 3, 'nombre': 'Luis Fernando García Ruiz', 'activo': true},
    );
  });

  test('limpiarNombre quita espacios de sobra', () {
    expect(limpiarNombre('  Ana   María \t López '), 'Ana María López');
    expect(limpiarNombre('   '), '');
  });

  group('alumnosDe', () {
    test('lee el campo de Firestore y ordena por N.L', () {
      final alumnos = alumnosDe([
        {'num': 2, 'nombre': 'Luis', 'activo': false},
        {'num': 1, 'nombre': 'Ana', 'activo': true},
        {'num': 3, 'nombre': 'Eva'}, // sin `activo` cuenta como activo
      ]);
      expect(alumnos.map((a) => a.toMap()), [
        {'num': 1, 'nombre': 'Ana', 'activo': true},
        {'num': 2, 'nombre': 'Luis', 'activo': false},
        {'num': 3, 'nombre': 'Eva', 'activo': true},
      ]);
    });
    test('ignora lo que no es un alumno', () {
      expect(alumnosDe(null), isEmpty);
      expect(alumnosDe('x'), isEmpty);
      expect(
        alumnosDe([
          null,
          3,
          {'num': '1', 'nombre': 'Ana'},
          {'num': 1},
        ]),
        isEmpty,
      );
    });
  });

  group('compararListas', () {
    const ana = Alumno(num: 1, nombre: 'Ana');
    const luis = Alumno(num: 2, nombre: 'Luis');
    const eva = Alumno(num: 3, nombre: 'Eva');
    List<Map<String, dynamic>> mapas(List<Alumno> l) => [for (final a in l) a.toMap()];

    test('listas iguales: sin cambios', () {
      final c = compararListas([ana, luis], [luis, ana]);
      expect(c.sinCambios, isTrue);
      expect(c.resumen, startsWith('Sin cambios'));
      expect(mapas(c.resultado), mapas([ana, luis]));
    });

    test('N.L solo en la nueva: se agrega como activo', () {
      final c = compararListas([ana], [ana, luis, eva]);
      expect(c.nuevos.map((a) => a.num), [2, 3]);
      expect(c.resumen, '2 nuevos');
      expect(mapas(c.resultado), mapas([ana, luis, eva]));
    });

    test('N.L solo en la vieja: queda de baja, no se borra', () {
      final c = compararListas([ana, luis, eva], [ana, eva]);
      expect(c.bajas.map((a) => a.num), [2]);
      expect(c.resumen, '1 dado de baja');
      expect(mapas(c.resultado), [
        ana.toMap(),
        {'num': 2, 'nombre': 'Luis', 'activo': false},
        eva.toMap(),
      ]);
    });

    test('N.L en las dos con otro nombre: se actualiza y se reporta el cambio', () {
      final c = compararListas([ana, luis], [ana, const Alumno(num: 2, nombre: 'Luis Fernando')]);
      expect(c.renombrados.single.num, 2);
      expect(c.renombrados.single.antes, 'Luis');
      expect(c.renombrados.single.despues, 'Luis Fernando');
      expect(c.resumen, '1 cambia de nombre');
      expect(c.resultado[1].nombre, 'Luis Fernando');
    });

    test('quien ya estaba de baja y no viene: sigue de baja y no cuenta como baja nueva', () {
      const luisBaja = Alumno(num: 2, nombre: 'Luis', activo: false);
      final c = compararListas([ana, luisBaja], [ana]);
      expect(c.sinCambios, isTrue);
      expect(mapas(c.resultado), mapas([ana, luisBaja]));
    });

    test('quien estaba de baja y vuelve a venir: sigue de baja, no se reactiva solo', () {
      const luisBaja = Alumno(num: 2, nombre: 'Luis', activo: false);
      final c = compararListas([ana, luisBaja], [ana, luis]);
      expect(c.sinCambios, isTrue);
      expect(mapas(c.resultado), mapas([ana, luisBaja]));
    });

    test('quien estaba de baja y viene con otro nombre: cambia el nombre y sigue de baja', () {
      const luisBaja = Alumno(num: 2, nombre: 'Luis', activo: false);
      final c = compararListas([ana, luisBaja], [ana, const Alumno(num: 2, nombre: 'Luis Fernando')]);
      expect(c.resumen, '1 cambia de nombre');
      expect(c.resultado[1].toMap(), {'num': 2, 'nombre': 'Luis Fernando', 'activo': false});
    });

    test('resumen con todo, como en la guía', () {
      final actual = [ana, luis, eva, const Alumno(num: 4, nombre: 'Sofía')];
      final nueva = [
        const Alumno(num: 1, nombre: 'Ana María'),
        const Alumno(num: 2, nombre: 'Luis Fernando'),
        eva,
        const Alumno(num: 5, nombre: 'Diego'),
        const Alumno(num: 6, nombre: 'Ximena'),
        const Alumno(num: 7, nombre: 'Jesús'),
      ];
      final c = compararListas(actual, nueva);
      expect(c.resumen, '3 nuevos, 1 dado de baja, 2 cambian de nombre');
      expect(c.resultado.map((a) => a.num), [1, 2, 3, 4, 5, 6, 7]);
      expect(c.resultado.where((a) => !a.activo).map((a) => a.num), [4]);
    });

    test('lista guardada vacía: todos son nuevos', () {
      expect(compararListas([], [ana, luis]).resumen, '2 nuevos');
    });
  });

  group('edición a mano', () {
    const lista = [
      Alumno(num: 1, nombre: 'Ana'),
      Alumno(num: 2, nombre: 'Luis', activo: false),
      Alumno(num: 5, nombre: 'Eva'),
    ];

    test('siguienteNum es uno más que el mayor, contando las bajas', () {
      expect(siguienteNum(lista), 6);
      expect(siguienteNum(const [Alumno(num: 3, nombre: 'Luis', activo: false)]), 4);
      expect(siguienteNum(const []), 1);
    });

    test('agregarAlumno usa el siguiente N.L, limpia el nombre y no toca a los demás', () {
      final nueva = agregarAlumno(lista, '  Diego   Ramírez ');
      expect(nueva, hasLength(4));
      expect(nueva.last.toMap(), {'num': 6, 'nombre': 'Diego Ramírez', 'activo': true});
      expect(nueva.take(3).map((a) => a.toMap()), lista.map((a) => a.toMap()));
    });

    test('corregirNombre cambia solo ese N.L y conserva si está activo', () {
      final nueva = corregirNombre(lista, 2, ' Luis  Fernando ');
      expect(nueva.map((a) => a.toMap()), [
        {'num': 1, 'nombre': 'Ana', 'activo': true},
        {'num': 2, 'nombre': 'Luis Fernando', 'activo': false},
        {'num': 5, 'nombre': 'Eva', 'activo': true},
      ]);
    });

    test('cambiarActivo da de baja y reactiva sin borrar a nadie', () {
      final baja = cambiarActivo(lista, 1, false);
      expect(baja.map((a) => a.activo), [false, false, true]);
      final alta = cambiarActivo(baja, 2, true);
      expect(alta.map((a) => a.activo), [false, true, true]);
      expect(alta.map((a) => a.num), [1, 2, 5]);
    });
  });
}
