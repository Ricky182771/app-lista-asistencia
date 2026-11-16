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
}
