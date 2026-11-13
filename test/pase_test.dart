import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/pase.dart';

void main() {
  test('siguienteEstado: 0 → 1 → 2 → 0 y lo desconocido vuelve a presente', () {
    expect(siguienteEstado(presente), falta);
    expect(siguienteEstado(falta), justificada);
    expect(siguienteEstado(justificada), presente);
    for (final v in [-1, 3, 99]) {
      expect(siguienteEstado(v), presente, reason: '$v');
    }
  });

  test('fechaLocal rellena con ceros', () {
    expect(fechaLocal(DateTime(2026, 3, 5, 23, 59)), '2026-03-05');
    expect(fechaLocal(DateTime(2026, 12, 9)), '2026-12-09');
  });

  group('esEditable', () {
    final hoy = DateTime(2026, 11, 13, 20, 30); // 8:30 p.m.: en UTC ya es el día 14

    test('de hoy hasta 28 días atrás', () {
      expect(esEditable('2026-11-13', hoy), isTrue);
      expect(esEditable('2026-11-12', hoy), isTrue);
      expect(esEditable('2026-10-16', hoy), isTrue); // hoy − 28
    });

    test('nunca futura ni de hace más de 28 días', () {
      expect(esEditable('2026-11-14', hoy), isFalse);
      expect(esEditable('2026-10-15', hoy), isFalse); // hoy − 29
      expect(esEditable('2025-11-13', hoy), isFalse);
    });

    test('cruza meses, años y años bisiestos', () {
      expect(esEditable('2026-12-04', DateTime(2027, 1, 1)), isTrue);
      expect(esEditable('2026-12-03', DateTime(2027, 1, 1)), isFalse);
      expect(esEditable('2028-02-01', DateTime(2028, 2, 29)), isTrue);
    });

    test('una fecha mal escrita no es editable', () {
      expect(esEditable('', hoy), isFalse);
      expect(esEditable('13/11/2026', hoy), isFalse);
    });
  });

  test('IDs determinísticos', () {
    expect(claseId('uidProfe', 'prueba-3a'), 'uidProfe_prueba-3a');
    expect(paseId('uidProfe_prueba-3a', '2026-11-13'), 'uidProfe_prueba-3a_2026-11-13');
  });

  const alumnos = [
    {'num': 1, 'nombre': 'Ana', 'activo': true},
    {'num': 2, 'nombre': 'Beto', 'activo': false},
    {'num': 10, 'nombre': 'Carla', 'activo': true},
    {'num': 3, 'nombre': 'Diego'}, // sin `activo`: cuenta como activo
  ];

  test('estadosIniciales: solo activos, todos presentes, llaves en texto', () {
    expect(estadosIniciales(alumnos), {'1': presente, '10': presente, '3': presente});
    expect(estadosIniciales(const []), isEmpty);
  });

  group('filasDelPase', () {
    test('activos ordenados por N.L numérico', () {
      expect(filasDelPase(alumnos, const {}), [
        (nl: '1', nombre: 'Ana', baja: false),
        (nl: '3', nombre: 'Diego', baja: false),
        (nl: '10', nombre: 'Carla', baja: false),
      ]);
    });

    test('incluye a dados de baja y a N.L desconocidos si ya tienen estado', () {
      final filas = filasDelPase(alumnos, const {'1': 0, '2': 1, '7': 2});
      expect(filas.map((f) => f.nl), ['1', '2', '3', '7', '10']);
      expect(filas[1], (nl: '2', nombre: 'Beto', baja: true));
      expect(filas[3], (nl: '7', nombre: '', baja: true));
    });
  });

  test('camposEditados: solo lo que cambió, con la ruta estados.<N.L>', () {
    const guardados = {'1': 0, '2': 1, '3': 0};
    expect(camposEditados(guardados, {'1': 0, '2': 2, '4': 1}), {'estados.2': 2, 'estados.4': 1});
    expect(camposEditados(guardados, {'1': 0}), isEmpty);
    expect(camposEditados(guardados, {}), isEmpty);
  });

  test('rangoDelMes: del día 1 al primer día del mes siguiente, también en diciembre', () {
    expect(rangoDelMes(2026, 11), (desde: '2026-11-01', hasta: '2026-12-01'));
    expect(rangoDelMes(2026, 12), (desde: '2026-12-01', hasta: '2027-01-01'));
  });

  test('columnasDelMes: días con pase, sin repetir y ordenados', () {
    expect(columnasDelMes(['2026-11-13', '2026-11-02', '2026-11-10', '2026-11-02']),
        ['2026-11-02', '2026-11-10', '2026-11-13']);
    expect(columnasDelMes(const []), isEmpty);
  });
}
