import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:app_lista_asistencia/models/orden.dart';
import 'package:app_lista_asistencia/models/pase.dart';

Map<String, dynamic> pase(String claseId, int hora, int minuto, Map<String, int> estados, {int? enviado}) => {
  'claseId': claseId,
  'marcadoEn': Timestamp.fromDate(DateTime(2026, 11, 11, hora, minuto)),
  'enviadoEn': Timestamp.fromDate(DateTime(2026, 11, 11, enviado ?? hora, minuto)),
  'estados': estados,
};

void main() {
  setUpAll(() => initializeDateFormatting('es_MX'));

  group('paseDeLaManana', () {
    test('sin pases es null', () {
      expect(paseDeLaManana([]), isNull);
    });

    test('gana el marcadoEn más temprano aunque se haya enviado después', () {
      // El de las 7:00 se marcó sin internet y llegó a las 12:00, después del de las 9:00.
      final temprano = pase('a', 7, 0, {}, enviado: 12);
      final tarde = pase('b', 9, 0, {});
      expect(paseDeLaManana([tarde, temprano]), same(temprano));
      expect(paseDeLaManana([temprano, tarde]), same(temprano));
    });

    test('un pase sin marcadoEn no le gana a uno con hora', () {
      final sinHora = {'claseId': 'x'};
      final conHora = pase('a', 10, 0, {});
      expect(paseDeLaManana([sinHora, conHora]), same(conHora));
      expect(paseDeLaManana([sinHora]), same(sinHora));
    });
  });

  const alumnos = [
    {'num': 1, 'nombre': 'Ana Ruiz', 'activo': true},
    {'num': 2, 'nombre': 'Beto Soto', 'activo': false},
    {'num': 10, 'nombre': 'Carla Díaz', 'activo': true},
    {'num': 3, 'nombre': 'Diego Paz'},
  ];

  group('alumnosConEstado', () {
    final estados = {'10': falta, '1': falta, '3': justificada, '2': falta};

    test('faltas ordenadas por N.L, incluido el dado de baja con registro', () {
      expect(alumnosConEstado(alumnos, estados, falta), ['Ana Ruiz', 'Beto Soto', 'Carla Díaz']);
    });

    test('justificadas aparte', () {
      expect(alumnosConEstado(alumnos, estados, justificada), ['Diego Paz']);
    });

    test('un N.L que ya no está en el grupo sale con su número', () {
      expect(alumnosConEstado(alumnos, {'7': falta}, falta), ['N.L 7']);
    });

    test('nadie faltó', () {
      expect(alumnosConEstado(alumnos, {'1': presente, '10': presente}, falta), isEmpty);
    });
  });

  group('mensajeParaPadres', () {
    final hoy = DateTime(2026, 11, 11, 20, 30); // 8:30 p.m.: en UTC ya es el día 12

    test('hoy, con la lista de nombres y sin materia', () {
      expect(
        mensajeParaPadres('3A', '2026-11-11', hoy, ['Ana Ruiz', 'Carla Díaz']),
        'Buenos días, estimados padres de familia del grupo 3A.\n'
        '\n'
        'Les informamos que hoy, miércoles 11 de noviembre de 2026, los siguientes alumnos no se '
        'presentaron a clase:\n'
        '\n'
        '• Ana Ruiz\n'
        '• Carla Díaz\n'
        '\n'
        'Les pedimos su apoyo para dar seguimiento. Para cualquier aclaración, pueden comunicarse con '
        'el área de orden.\n'
        '\n'
        'Atentamente,\n'
        'Encargados de orden',
      );
    });

    test('otro día dice "el"', () {
      expect(
        mensajeParaPadres('3A', '2026-11-09', hoy, ['Ana Ruiz']),
        contains('Les informamos que el lunes 9 de noviembre de 2026, los siguientes'),
      );
    });

    test('nadie faltó: mensaje corto', () {
      expect(
        mensajeParaPadres('3A', '2026-11-11', hoy, []),
        'Buenos días, estimados padres de familia del grupo 3A.\n'
        '\n'
        'Les informamos que hoy, miércoles 11 de noviembre de 2026, no hubo faltas sin justificar '
        'en el grupo.\n'
        '\n'
        'Atentamente,\n'
        'Encargados de orden',
      );
    });
  });

  group('resumenDelGrupo', () {
    test('grupo sin pases ese día', () {
      final r = resumenDelGrupo({'a', 'b'}, []);
      expect((r.conPase, r.clases, r.manana, r.faltas), (0, 2, null, 0));
    });

    test('dos pases: cuenta clases y solo las faltas sin justificar del de la mañana', () {
      final manana = pase('a', 7, 0, {'1': falta, '2': justificada, '3': falta, '4': presente}, enviado: 12);
      final otro = pase('b', 9, 0, {'1': falta, '2': falta, '3': falta, '4': falta});
      final r = resumenDelGrupo({'a', 'b', 'c'}, [otro, manana]);
      expect((r.conPase, r.clases, r.faltas), (2, 3, 2));
      expect(r.manana, same(manana));
    });

    test('un pase de una clase que ya no existe no cuenta como clase con pase', () {
      final r = resumenDelGrupo({'a'}, [pase('borrada', 7, 0, {})]);
      expect((r.conPase, r.clases), (0, 1));
    });
  });
}
