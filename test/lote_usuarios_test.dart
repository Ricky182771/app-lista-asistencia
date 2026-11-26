import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/lote_csv.dart';
import 'package:app_lista_asistencia/models/lote_usuarios.dart';
import 'package:app_lista_asistencia/models/rol.dart';

List<int> bytes(String texto) => utf8.encode(texto);

void main() {
  group('rolDeTexto', () {
    test('reconoce el nombre interno, la etiqueta y formas comunes', () {
      expect(rolDeTexto('profesor'), Rol.profesor);
      expect(rolDeTexto(' DOCENTE '), Rol.profesor);
      expect(rolDeTexto('Encargado de orden'), Rol.orden);
      expect(rolDeTexto('orden'), Rol.orden);
      expect(rolDeTexto('Administrativo'), Rol.admin);
      expect(rolDeTexto('administrativa'), Rol.admin);
      expect(rolDeTexto('admin'), Rol.admin);
    });
    test('lo demás es null', () {
      expect(rolDeTexto(''), isNull);
      expect(rolDeTexto('director'), isNull);
    });
  });

  group('leerInvitaciones', () {
    test('con encabezado y rol', () {
      final l = leerInvitaciones(bytes('Correo,Rol\nana@x.mx,profesor\nbeto@x.mx,Encargado de orden\n'));
      expect(l.errorGeneral, isNull);
      expect([for (final f in l.filas) f.correo], ['ana@x.mx', 'beto@x.mx']);
      expect([for (final f in l.filas) f.rol], [Rol.profesor, Rol.orden]);
      expect([for (final f in l.filas) f.fila], [2, 3]);
    });

    test('sin encabezado toma correo y rol por posición', () {
      final l = leerInvitaciones(bytes('ana@x.mx,orden\n'));
      expect(l.filas.single.correo, 'ana@x.mx');
      expect(l.filas.single.rol, Rol.orden);
    });

    test('solo correos: el rol queda sin elegir y sin texto', () {
      final l = leerInvitaciones(bytes('correo\nana@x.mx\nbeto@x.mx\n'));
      expect([for (final f in l.filas) f.rol], [null, null]);
      expect([for (final f in l.filas) f.rolTexto], ['', '']);
    });

    test('un rol que no se reconoce guarda su texto', () {
      final f = leerInvitaciones(bytes('correo,rol\nana@x.mx,director\n')).filas.single;
      expect(f.rol, isNull);
      expect(f.rolTexto, 'director');
    });

    test('con encabezado sin columna de correo es un error', () {
      expect(leerInvitaciones(bytes('nombre,rol\nAna,profesor\n')).errorGeneral, contains('"correo"'));
    });
  });

  group('rolEfectivo', () {
    test('usa el de la fila; sin texto de rol, el de por omisión; con texto raro, ninguno', () {
      expect(rolEfectivo(FilaInvitacion(fila: 1, correo: 'a@x.mx', rol: Rol.orden), Rol.profesor), Rol.orden);
      expect(rolEfectivo(FilaInvitacion(fila: 1, correo: 'a@x.mx'), Rol.admin), Rol.admin);
      expect(rolEfectivo(FilaInvitacion(fila: 1, correo: 'a@x.mx', rolTexto: 'jefe'), Rol.admin), isNull);
    });
  });

  group('correo', () {
    test('correoValido', () {
      expect(correoValido('ana@x.mx'), isTrue);
      expect(correoValido('ana.perez+1@sub.x.mx'), isTrue);
      for (final mal in ['', 'ana', 'ana@x', '@x.mx', 'ana @x.mx', 'a/b@x.mx']) {
        expect(correoValido(mal), isFalse, reason: mal);
      }
    });
    test('sugerirCorreo corrige erratas de dominios comunes', () {
      expect(sugerirCorreo('ana@gmial.com'), 'ana@gmail.com');
      expect(sugerirCorreo('ana@gmail.con'), 'ana@gmail.com');
      expect(sugerirCorreo('ana@hotmial.com'), 'ana@hotmail.com');
      expect(sugerirCorreo('ana@gmail.com'), isNull);
      expect(sugerirCorreo('ana@escuela.edu.mx'), isNull);
      expect(sugerirCorreo('sin-arroba'), isNull);
    });
  });

  group('validarInvitaciones', () {
    final usuarios = <String, Rol?>{'ya@x.mx': Rol.profesor};
    final invitaciones = <String, Rol?>{'inv@x.mx': Rol.orden, 'inv2@x.mx': Rol.profesor};

    List<ResultadoFila> validar(List<FilaInvitacion> filas) => validarInvitaciones(
          filas,
          rolPorOmision: Rol.profesor,
          usuarios: usuarios,
          invitaciones: invitaciones,
        );

    FilaInvitacion fila(int n, String correo, {Rol? rol, String rolTexto = ''}) =>
        FilaInvitacion(fila: n, correo: correo, rol: rol, rolTexto: rolTexto);

    test('una fila normal se guarda; sin rol usa el de por omisión', () {
      final r = validar([fila(1, 'ana@x.mx')]).single;
      expect(r.seGuarda, isTrue);
      expect(r.errores, isEmpty);
      expect(r.avisos, isEmpty);
    });

    test('correo vacío o inválido', () {
      final r = validar([fila(1, ''), fila(2, 'mal'), fila(3, ' ana@x.mx ')]);
      expect(r[0].errores, ['Falta el correo']);
      expect(r[1].errores, ['El correo no es válido']);
      expect(r[2].seGuarda, isTrue);
    });

    test('un rol que no se reconoce es error', () {
      final r = validar([fila(1, 'ana@x.mx', rolTexto: 'jefe')]).single;
      expect(r.errores.single, contains('No se reconoce el rol "jefe"'));
    });

    test('repetido en el archivo: igual rol se omite, otro rol es error (sin importar mayúsculas)', () {
      final r = validar([
        fila(1, 'ana@x.mx'),
        fila(2, 'ANA@x.mx '),
        fila(3, 'ana@x.mx', rol: Rol.admin),
      ]);
      expect(r[0].seGuarda, isTrue);
      expect(r[1].omitida, contains('la fila 1'));
      expect(r[2].errores.single, contains('otro rol'));
    });

    test('quien ya tiene acceso se omite y manda a Cambiar rol', () {
      final r = validar([fila(1, 'ya@x.mx', rol: Rol.admin)]).single;
      expect(r.omitida, contains('Cambiar rol'));
      expect(r.seGuarda, isFalse);
    });

    test('invitación existente: igual rol se omite; otro rol avisa que se cambiará', () {
      final r = validar([
        fila(1, 'inv@x.mx', rol: Rol.orden),
        fila(2, 'inv2@x.mx', rol: Rol.admin),
      ]);
      expect(r[0].omitida, contains('Ya estaba invitado'));
      expect(r[1].seGuarda, isTrue);
      expect(r[1].avisos.single, contains('se cambiará a Administrativo'));
    });

    test('avisa de una errata común en el dominio pero se guarda', () {
      final r = validar([fila(1, 'ana@gmial.com')]).single;
      expect(r.seGuarda, isTrue);
      expect(r.avisos.single, contains('ana@gmail.com'));
    });

    test('editar la fila corrige el error', () {
      final f = fila(1, 'mal');
      expect(validar([f]).single.seGuarda, isFalse);
      f.correo = 'ana@x.mx';
      expect(validar([f]).single.seGuarda, isTrue);
    });
  });
}
