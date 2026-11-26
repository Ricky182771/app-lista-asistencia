import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/clase.dart';
import 'package:app_lista_asistencia/models/resumen_dia.dart';

void main() {
  const mate = Clase(id: 'c1', profesorUid: 'ana', grupoId: 'ia-3a', materia: 'Matemáticas', salon: 'A1', profesorNombre: 'Ana López');
  const fisica = Clase(id: 'c2', profesorUid: 'ana', grupoId: 'ia-3b', materia: 'Física', salon: 'B2', profesorNombre: 'Ana López');
  const historia = Clase(id: 'c3', profesorUid: 'beto', grupoId: 'ia-3a', materia: 'Historia', salon: 'A1', profesorNombre: 'Beto Ruiz');

  Map<String, dynamic> pase(String claseId, Map<String, int> estados) =>
      {'claseId': claseId, 'estados': estados, 'salon': 'A7'};

  group('resumenDelDia', () {
    test('une cada clase con su pase y cuenta faltas y justificadas', () {
      final r = resumenDelDia(
        [mate, fisica, historia],
        [pase('c1', {'1': 0, '2': 1, '3': 1, '4': 2})],
      );
      expect(r.total, 3);
      expect(r.conPase, 1);
      expect(r.sinPase, 2);
      expect(r.faltas, 2);
      expect(r.justificadas, 1);
      expect(r.clases.first.conPase, isTrue);
      expect(r.clases[1].conPase, isFalse);
      expect(r.clases[1].faltas, 0);
    });

    test('un pase de una clase que ya no existe no cuenta', () {
      final r = resumenDelDia([mate], [pase('borrada', {'1': 1}), pase('c1', {'1': 0})]);
      expect(r.conPase, 1);
      expect(r.faltas, 0);
    });

    test('los estados pueden llegar como double (web)', () {
      final r = resumenDelDia([mate], [
        {'claseId': 'c1', 'estados': {'1': 1.0, '2': 2.0}},
      ]);
      expect(r.clases.single.faltas, 1);
      expect(r.clases.single.justificadas, 1);
    });

    test('un pase sin estados cuenta como pase con cero faltas', () {
      final r = resumenDelDia([mate], [
        {'claseId': 'c1'},
      ]);
      expect(r.conPase, 1);
      expect(r.faltas, 0);
    });

    test('sin clases todo es cero', () {
      final r = resumenDelDia([], []);
      expect(r.total, 0);
      expect(r.huboPases, isFalse);
      expect(r.profesSinPase, isEmpty);
    });
  });

  group('resaltar y profesSinPase', () {
    test('si nadie pasó lista en la escuela no se resalta nada ni se acusa a ningún profe', () {
      final r = resumenDelDia([mate, fisica, historia], []);
      expect(r.huboPases, isFalse);
      expect(r.clases.any(r.resaltar), isFalse);
      expect(r.profesSinPase, isEmpty);
    });

    test('con pases ese día se resaltan las clases sin pase', () {
      final r = resumenDelDia([mate, fisica, historia], [pase('c1', {'1': 0})]);
      expect([for (final c in r.clases) r.resaltar(c)], [false, true, true]);
    });

    test('profe sin pase = tiene clases y ninguna con pase', () {
      // Ana pasó lista en una de sus dos clases; Beto en ninguna.
      final r = resumenDelDia([mate, fisica, historia], [pase('c1', {'1': 0})]);
      expect(r.profesSinPase, {'beto'});
    });
  });

  group('listarDelDia', () {
    final r = resumenDelDia([historia, fisica, mate], [pase('c3', {'1': 0})]);
    const grupos = {'ia-3a': 'IA 3A', 'ia-3b': 'IA 3B'};

    List<String> ids(List<ClaseDelDia> l) => [for (final c in l) c.clase.id];

    test('primero las que no tienen pase, luego por grupo, profe y materia', () {
      expect(ids(listarDelDia(r, nombresGrupo: grupos)), ['c1', 'c2', 'c3']);
    });

    test('filtra por con pase o sin pase', () {
      expect(ids(listarDelDia(r, filtro: FiltroDia.sinPase, nombresGrupo: grupos)), ['c1', 'c2']);
      expect(ids(listarDelDia(r, filtro: FiltroDia.conPase, nombresGrupo: grupos)), ['c3']);
    });

    test('filtra por grupo', () {
      expect(ids(listarDelDia(r, grupoId: 'ia-3b', nombresGrupo: grupos)), ['c2']);
    });

    test('ordena el nombre del profe sin distinguir acentos ni mayúsculas', () {
      const a = Clase(id: 'a', profesorUid: 'u1', grupoId: 'g', materia: 'X', salon: '1');
      const b = Clase(id: 'b', profesorUid: 'u2', grupoId: 'g', materia: 'X', salon: '1');
      final res = resumenDelDia([a, b], []);
      expect(ids(listarDelDia(res, nombresProfe: {'u1': 'Óscar', 'u2': 'Ana'})), ['b', 'a']);
    });
  });
}
