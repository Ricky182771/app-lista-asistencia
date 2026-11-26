import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/clase.dart';

void main() {
  const clase = Clase(id: 'c1', profesorUid: 'uidAna', grupoId: 'ia-3a', materia: 'Matemáticas', salon: 'A1');

  test('toMap guarda los cinco campos de clases/{id} y nada más', () {
    expect(clase.toMap(), {
      'profesorUid': 'uidAna',
      'grupoId': 'ia-3a',
      'materia': 'Matemáticas',
      'salon': 'A1',
      'profesorNombre': '',
    });
  });

  group('claseDe', () {
    test('lee un documento de clases', () {
      final c = claseDe('c1', clase.toMap())!;
      expect(c.id, 'c1');
      expect(c.profesorUid, 'uidAna');
      expect(c.materia, 'Matemáticas');
      expect(c.salon, 'A1');
    });
    test('lee el nombre del profe', () {
      final c = claseDe('c1', {...clase.toMap(), 'profesorNombre': 'Ana López'})!;
      expect(c.profesorNombre, 'Ana López');
    });
    test('sin materia, salón o nombre del profe (clases viejas) quedan vacíos', () {
      final c = claseDe('c1', {'profesorUid': 'uidAna', 'grupoId': 'ia-3a'})!;
      expect(c.materia, '');
      expect(c.salon, '');
      expect(c.profesorNombre, '');
    });
    test('sin profesor o sin grupo no es una clase', () {
      expect(claseDe('c1', null), isNull);
      expect(claseDe('c1', {}), isNull);
      expect(claseDe('c1', {'profesorUid': 'uidAna'}), isNull);
      expect(claseDe('c1', {'grupoId': 'ia-3a'}), isNull);
      expect(claseDe('c1', {'profesorUid': '', 'grupoId': 'ia-3a'}), isNull);
      expect(claseDe('c1', {'profesorUid': 7, 'grupoId': 'ia-3a'}), isNull);
    });
  });

  group('errorEtiqueta', () {
    test('acepta un texto normal', () {
      expect(errorEtiqueta('Matemáticas', 'la materia'), isNull);
      expect(errorEtiqueta('  A1 ', 'el salón'), isNull);
      expect(errorEtiqueta('x' * maxEtiqueta, 'la materia'), isNull);
    });
    test('vacío o puros espacios', () {
      expect(errorEtiqueta('', 'la materia'), 'Escribe la materia.');
      expect(errorEtiqueta('   ', 'el salón'), 'Escribe el salón.');
    });
    test('demasiado largo', () {
      expect(errorEtiqueta('x' * (maxEtiqueta + 1), 'la materia'), contains('$maxEtiqueta'));
    });
  });

  Clase de(String id, String uid, String materia) =>
      Clase(id: id, profesorUid: uid, grupoId: 'ia-3a', materia: materia, salon: 'A1');

  test('ordenarClases: por nombre del profesor y materia; sin nombre va al final', () {
    final ordenadas = ordenarClases(
      [de('c1', 'u3', 'Historia'), de('c2', 'uX', 'Física'), de('c3', 'u1', 'Química'), de('c4', 'u2', 'Álgebra')],
      {'u1': 'Zoe', 'u2': 'ana', 'u3': 'Luis'},
    );
    expect(ordenadas.map((c) => c.profesorUid), ['u2', 'u3', 'u1', 'uX']);
  });

  group('materiaRepetida', () {
    final clases = [de('c1', 'uidAna', 'Matemáticas'), de('c2', 'uidLuis', 'Física')];
    test('mismo profe y misma materia, sin importar espacios, mayúsculas ni acentos', () {
      expect(materiaRepetida(clases, de('', 'uidAna', 'Matemáticas')), isTrue);
      expect(materiaRepetida(clases, de('', 'uidAna', '  MATEMATICAS ')), isTrue);
    });
    test('otra materia del mismo profe, o la misma materia de otro profe, sí se puede', () {
      expect(materiaRepetida(clases, de('', 'uidAna', 'Física')), isFalse);
      expect(materiaRepetida(clases, de('', 'uidLuis', 'Matemáticas')), isFalse);
    });
    test('al editar, la clase no choca consigo misma pero sí con otra', () {
      expect(materiaRepetida(clases, de('c1', 'uidAna', 'matemáticas')), isFalse);
      final conQuimica = [...clases, de('c3', 'uidAna', 'Química')];
      expect(materiaRepetida(conQuimica, de('c3', 'uidAna', 'Matemáticas')), isTrue);
    });
  });

  group('quitarProfeDelGrupo', () {
    final mate = de('c1', 'uidAna', 'Matemáticas');
    test('sin otra clase con el grupo se quita al profe', () {
      expect(quitarProfeDelGrupo([mate, de('c2', 'uidLuis', 'Física')], mate), isTrue);
    });
    test('con otra clase en el grupo se queda', () {
      expect(quitarProfeDelGrupo([mate, de('c2', 'uidAna', 'Física')], mate), isFalse);
    });
    test('si la clase ya no está en la lista, cuenta lo que queda', () {
      expect(quitarProfeDelGrupo(const [], mate), isTrue);
    });
  });

  group('nombresDesactualizados', () {
    Clase con(String id, String uid, String nombre) =>
        Clase(id: id, profesorUid: uid, grupoId: 'ia-3a', materia: 'M', salon: 'A1', profesorNombre: nombre);
    const nombres = {'uidAna': 'Ana López', 'uidLuis': 'Luis Pérez'};

    test('llena las clases viejas sin nombre', () {
      expect(nombresDesactualizados([con('c1', 'uidAna', '')], nombres), {'c1': 'Ana López'});
    });
    test('corrige un nombre que cambió', () {
      expect(nombresDesactualizados([con('c1', 'uidAna', 'Ana')], nombres), {'c1': 'Ana López'});
    });
    test('no toca las que ya están al día', () {
      expect(nombresDesactualizados([con('c1', 'uidAna', 'Ana López'), con('c2', 'uidLuis', 'Luis Pérez')], nombres),
          isEmpty);
    });
    test('compara sin espacios de sobra', () {
      expect(nombresDesactualizados([con('c1', 'uidAna', 'Ana López')], {'uidAna': '  Ana López '}), isEmpty);
    });
    test('deja igual la clase de un profe que ya no está o no tiene nombre', () {
      expect(nombresDesactualizados([con('c1', 'uidBeto', 'Beto')], nombres), isEmpty);
      expect(nombresDesactualizados([con('c1', 'uidAna', 'Ana')], {'uidAna': ' '}), isEmpty);
    });
    test('ignora una clase sin ID (aún no se da de alta)', () {
      expect(nombresDesactualizados([con('', 'uidAna', '')], nombres), isEmpty);
    });
  });

  group('profeYSalon', () {
    test('con los dos', () => expect(profeYSalon('Ana López', 'A7'), 'Prof. Ana López · Salón A7'));
    test('sin nombre del profe', () => expect(profeYSalon('', 'A7'), 'Salón A7'));
    test('sin salón', () => expect(profeYSalon(' Ana López ', ''), 'Prof. Ana López'));
    test('sin nada', () => expect(profeYSalon(' ', ''), ''));
  });
}
