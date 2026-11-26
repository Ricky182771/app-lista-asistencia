import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/clase.dart';
import 'package:app_lista_asistencia/models/rol.dart';
import 'package:app_lista_asistencia/models/usuarios.dart';

void main() {
  group('coincideBusqueda', () {
    test('no distingue mayúsculas ni acentos', () {
      expect(coincideBusqueda('lopez', ['María López']), isTrue);
      expect(coincideBusqueda('MARÍA', ['maria lopez']), isTrue);
    });
    test('con varias palabras deben aparecer todas, en cualquier campo y orden', () {
      expect(coincideBusqueda('lopez maria', ['María López', 'maria@x.mx']), isTrue);
      expect(coincideBusqueda('maria x.mx', ['María López', 'maria@x.mx']), isTrue);
      expect(coincideBusqueda('maria beto', ['María López', 'maria@x.mx']), isFalse);
    });
    test('busca dentro del correo y del rol', () {
      expect(coincideBusqueda('gmail', ['Ana', 'ana@gmail.com', 'Profesor']), isTrue);
      expect(coincideBusqueda('encargado', ['Ana', 'ana@gmail.com', 'Encargado de orden']), isTrue);
    });
    test('una búsqueda vacía o de puros espacios coincide con todo', () {
      expect(coincideBusqueda('', ['Ana']), isTrue);
      expect(coincideBusqueda('   ', []), isTrue);
    });
    test('sin campos y con búsqueda no coincide', () {
      expect(coincideBusqueda('ana', []), isFalse);
    });
  });

  group('clasesPorProfe y textoClases', () {
    const a = Clase(id: '1', profesorUid: 'ana', grupoId: 'g1', materia: 'Mate', salon: 'A1');
    const b = Clase(id: '2', profesorUid: 'ana', grupoId: 'g2', materia: 'Mate', salon: 'A2');
    const c = Clase(id: '3', profesorUid: 'beto', grupoId: 'g1', materia: 'Hist', salon: 'A1');

    test('cuenta las clases de cada profe', () {
      expect(clasesPorProfe([a, b, c]), {'ana': 2, 'beto': 1});
      expect(clasesPorProfe([]), isEmpty);
    });
    test('textoClases', () {
      expect(textoClases(0), 'sin clases');
      expect(textoClases(1), '1 clase');
      expect(textoClases(4), '4 clases');
    });
  });

  group('errorCambioRol', () {
    String? error({
      String uid = 'ana',
      String miUid = 'admin1',
      Rol? actual = Rol.profesor,
      Rol nuevo = Rol.orden,
      int clases = 0,
    }) =>
        errorCambioRol(uid: uid, miUid: miUid, actual: actual, nuevo: nuevo, clases: clases);

    test('un profe sin clases puede pasar a otro rol', () {
      expect(error(), isNull);
      expect(error(nuevo: Rol.admin), isNull);
    });
    test('nadie cambia su propio rol', () {
      expect(error(uid: 'admin1', actual: Rol.admin, nuevo: Rol.profesor), contains('propio rol'));
    });
    test('mismo rol', () {
      expect(error(nuevo: Rol.profesor), 'Ya es Profesor.');
    });
    test('un profe con clases no cambia de rol hasta reasignarlas', () {
      final e = error(clases: 2);
      expect(e, contains('2 clases'));
      expect(e, contains('Reasígnalas'));
    });
    test('otros roles no dependen de las clases', () {
      expect(error(actual: Rol.orden, nuevo: Rol.profesor, clases: 3), isNull);
      expect(error(actual: Rol.admin, nuevo: Rol.orden, clases: 3), isNull);
    });
    test('un rol desconocido (null) se puede corregir', () {
      expect(error(actual: null, nuevo: Rol.profesor), isNull);
    });
  });

  test('cada rol tiene su descripción', () {
    for (final r in Rol.values) {
      expect(r.descripcion, isNotEmpty);
    }
  });
}
