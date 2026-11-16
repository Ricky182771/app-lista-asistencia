import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/clase.dart';
import 'package:app_lista_asistencia/models/pase.dart' show claseId;

void main() {
  const clase = Clase(profesorUid: 'uidAna', grupoId: 'ia-3a', materia: 'Matemáticas', salon: 'A1');

  group('idClase', () {
    test('es {profesorUid}_{grupoId}', () {
      expect(idClase('uidAna', 'ia-3a'), 'uidAna_ia-3a');
      expect(clase.id, 'uidAna_ia-3a');
    });
    test('coincide con claseId de pase.dart: los pases y las reglas dependen de ese ID', () {
      expect(idClase('uidAna', 'ia-3a'), claseId('uidAna', 'ia-3a'));
    });
  });

  test('toMap guarda los cuatro campos de clases/{id} y nada más', () {
    expect(clase.toMap(), {
      'profesorUid': 'uidAna',
      'grupoId': 'ia-3a',
      'materia': 'Matemáticas',
      'salon': 'A1',
    });
  });

  group('claseDe', () {
    test('lee un documento de clases', () {
      final c = claseDe(clase.toMap())!;
      expect(c.id, clase.id);
      expect(c.materia, 'Matemáticas');
      expect(c.salon, 'A1');
    });
    test('sin materia o salón quedan vacíos', () {
      final c = claseDe({'profesorUid': 'uidAna', 'grupoId': 'ia-3a'})!;
      expect(c.materia, '');
      expect(c.salon, '');
    });
    test('sin profesor o sin grupo no es una clase', () {
      expect(claseDe(null), isNull);
      expect(claseDe({}), isNull);
      expect(claseDe({'profesorUid': 'uidAna'}), isNull);
      expect(claseDe({'grupoId': 'ia-3a'}), isNull);
      expect(claseDe({'profesorUid': '', 'grupoId': 'ia-3a'}), isNull);
      expect(claseDe({'profesorUid': 7, 'grupoId': 'ia-3a'}), isNull);
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

  test('ordenarClases: por nombre del profesor y materia; sin nombre va al final', () {
    Clase de(String uid, String materia) =>
        Clase(profesorUid: uid, grupoId: 'ia-3a', materia: materia, salon: 'A1');
    final ordenadas = ordenarClases(
      [de('u3', 'Historia'), de('uX', 'Física'), de('u1', 'Química'), de('u2', 'Álgebra')],
      {'u1': 'Zoe', 'u2': 'ana', 'u3': 'Luis'},
    );
    expect(ordenadas.map((c) => c.profesorUid), ['u2', 'u3', 'u1', 'uX']);
  });
}
