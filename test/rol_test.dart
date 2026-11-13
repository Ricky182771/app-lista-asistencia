import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/rol.dart';

void main() {
  group('parseRol', () {
    test('reconoce los tres roles', () {
      expect(parseRol('profesor'), Rol.profesor);
      expect(parseRol('orden'), Rol.orden);
      expect(parseRol('admin'), Rol.admin);
    });
    test('cualquier otra cosa es null', () {
      for (final v in [null, '', 'Admin', ' admin', 'alumno', 3, true]) {
        expect(parseRol(v), isNull, reason: '$v');
      }
    });
  });

  test('normalizarCorreo quita espacios y pasa a minúsculas', () {
    expect(normalizarCorreo('  Ana.Perez@Gmail.COM \n'), 'ana.perez@gmail.com');
    expect(normalizarCorreo('ya@normal.mx'), 'ya@normal.mx');
  });

  group('decidirPantalla', () {
    test('sin sesión va al login aunque haya datos', () {
      expect(decidirPantalla(conSesion: false), Pantalla.login);
      expect(decidirPantalla(conSesion: false, usuario: {'rol': 'admin'}), Pantalla.login);
    });
    test('con sesión va a la pantalla de su rol', () {
      expect(decidirPantalla(conSesion: true, usuario: {'rol': 'profesor'}), Pantalla.profesor);
      expect(decidirPantalla(conSesion: true, usuario: {'rol': 'orden'}), Pantalla.orden);
      expect(decidirPantalla(conSesion: true, usuario: {'rol': 'admin'}), Pantalla.admin);
    });
    test('sin usuario (sin invitación) o con rol desconocido: sin acceso', () {
      expect(decidirPantalla(conSesion: true), Pantalla.sinAcceso);
      expect(decidirPantalla(conSesion: true, usuario: {}), Pantalla.sinAcceso);
      expect(decidirPantalla(conSesion: true, usuario: {'rol': 'director'}), Pantalla.sinAcceso);
    });
  });
}
