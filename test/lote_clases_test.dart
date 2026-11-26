import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/clase.dart';
import 'package:app_lista_asistencia/models/lote_clases.dart';
import 'package:app_lista_asistencia/models/rol.dart';

List<int> bytes(String texto) => utf8.encode(texto);

FilaClaseLote fila(int n, String profesor, String grupo, String materia, String salon) =>
    FilaClaseLote(fila: n, profesor: profesor, grupo: grupo, materia: materia, salon: salon);

void main() {
  group('leerClasesLote', () {
    test('con encabezado', () {
      final l = leerClasesLote(bytes('Correo,Grupo,Materia,Salón\nana@x.mx,IA 3A,Física,A1\n'));
      expect(l.errorGeneral, isNull);
      final f = l.filas.single;
      expect([f.profesor, f.grupo, f.materia, f.salon], ['ana@x.mx', 'IA 3A', 'Física', 'A1']);
      expect(f.fila, 2);
    });

    test('sin encabezado: profesor, grupo, materia y salón por posición', () {
      final l = leerClasesLote(bytes('ana@x.mx,IA 3A,Física,A1\nbeto@x.mx,IA 3B,Historia,B2\n'));
      expect(l.filas, hasLength(2));
      expect(l.filas.last.materia, 'Historia');
    });

    test('encabezado en otro orden', () {
      final l = leerClasesLote(bytes('Aula;Asignatura;Grupo;Docente\nA1;Física;IA 3A;ana@x.mx\n'));
      final f = l.filas.single;
      expect([f.profesor, f.grupo, f.materia, f.salon], ['ana@x.mx', 'IA 3A', 'Física', 'A1']);
    });

    test('con encabezado, falta una columna', () {
      expect(leerClasesLote(bytes('Correo,Grupo,Materia\nana@x.mx,IA 3A,Física\n')).errorGeneral, contains('"salon"'));
    });
  });

  group('grupoPorNombre', () {
    final grupos = {'ia-3a': 'IA 3A', 'ia-3b': 'Los Pumas'};
    test('por nombre sin importar mayúsculas, acentos o símbolos', () {
      expect(grupoPorNombre('ia 3a', grupos), 'ia-3a');
      expect(grupoPorNombre(' IA-3A ', grupos), 'ia-3a');
    });
    test('por nombre actual de un grupo renombrado', () {
      expect(grupoPorNombre('Los Pumas', grupos), 'ia-3b');
    });
    test('por el ID original de un grupo renombrado', () {
      expect(grupoPorNombre('IA 3B', grupos), 'ia-3b');
    });
    test('un grupo que no existe o un nombre sin letras', () {
      expect(grupoPorNombre('IA 9Z', grupos), isNull);
      expect(grupoPorNombre('###', grupos), isNull);
    });
  });

  group('validarClases', () {
    const usuarios = <UsuarioLote>[
      (uid: 'u1', nombre: 'Ana López', correo: 'Ana@x.mx', rol: Rol.profesor),
      (uid: 'u2', nombre: 'Beto Ruiz', correo: 'beto@x.mx', rol: Rol.orden),
      (uid: 'u3', nombre: 'Ana López', correo: 'ana2@x.mx', rol: Rol.profesor),
      (uid: 'u4', nombre: 'Caro Díaz', correo: 'caro@x.mx', rol: Rol.profesor),
    ];
    const grupos = {'ia-3a': 'IA 3A', 'ia-3b': 'IA 3B'};
    const existentes = [
      Clase(id: 'c1', profesorUid: 'u1', grupoId: 'ia-3a', materia: 'Matemáticas', salon: 'A1'),
    ];

    List<ClaseValidada> validar(List<FilaClaseLote> filas) => validarClases(
          filas,
          usuarios: usuarios,
          invitaciones: const {'pend@x.mx': Rol.profesor},
          grupos: grupos,
          existentes: existentes,
        );

    test('una fila buena arma la clase con el uid y el nombre del profe', () {
      final r = validar([fila(1, 'ana@x.mx', 'ia 3a', ' Física ', 'a1')]).single;
      expect(r.resultado.seGuarda, isTrue);
      final c = r.clase!;
      expect(c.id, '');
      expect(c.profesorUid, 'u1');
      expect(c.grupoId, 'ia-3a');
      expect(c.materia, 'Física');
      expect(c.salon, 'a1');
      expect(c.profesorNombre, 'Ana López');
    });

    test('el profe se encuentra por correo (sin importar mayúsculas) o por nombre único', () {
      final r = validar([
        fila(1, 'ANA@x.mx', 'IA 3A', 'Física', 'A1'),
        fila(2, 'caro díaz', 'IA 3A', 'Historia', 'A1'),
      ]);
      expect(r[0].clase!.profesorUid, 'u1');
      expect(r[1].clase!.profesorUid, 'u4');
    });

    test('un nombre repetido pide el correo', () {
      final r = validar([fila(1, 'Ana López', 'IA 3A', 'Física', 'A1')]).single;
      expect(r.resultado.errores.single, contains('2 usuarios'));
      expect(r.clase, isNull);
    });

    test('profe desconocido, invitado que aún no entra, o que no es profesor', () {
      final r = validar([
        fila(1, 'nadie@x.mx', 'IA 3A', 'Física', 'A1'),
        fila(2, 'pend@x.mx', 'IA 3A', 'Física', 'A1'),
        fila(3, 'beto@x.mx', 'IA 3A', 'Física', 'A1'),
        fila(4, 'Fulano', 'IA 3A', 'Física', 'A1'),
        fila(5, '', 'IA 3A', 'Física', 'A1'),
      ]);
      expect(r[0].resultado.errores.single, contains('invítalo primero'));
      expect(r[1].resultado.errores.single, contains('todavía no entra'));
      expect(r[2].resultado.errores.single, contains('no Profesor'));
      expect(r[3].resultado.errores.single, contains('No hay un usuario'));
      expect(r[4].resultado.errores.single, 'Falta el profesor');
    });

    test('grupo que no existe o vacío', () {
      final r = validar([
        fila(1, 'ana@x.mx', 'IA 9Z', 'Física', 'A1'),
        fila(2, 'ana@x.mx', '', 'Física', 'A1'),
      ]);
      expect(r[0].resultado.errores.single, contains('no existe'));
      expect(r[1].resultado.errores.single, 'Falta el grupo');
    });

    test('materia o salón vacíos o demasiado largos', () {
      final r = validar([
        fila(1, 'ana@x.mx', 'IA 3A', '', 'A1'),
        fila(2, 'ana@x.mx', 'IA 3A', 'Física', ''),
        fila(3, 'ana@x.mx', 'IA 3A', 'x' * 41, 'A1'),
      ]);
      expect(r[0].resultado.errores.single, 'Escribe la materia.');
      expect(r[1].resultado.errores.single, 'Escribe el salón.');
      expect(r[2].resultado.errores.single, contains('40'));
    });

    test('una clase que ya existe se omite (sin distinguir acentos ni mayúsculas)', () {
      final r = validar([fila(1, 'ana@x.mx', 'IA 3A', 'matematicas', 'A9')]).single;
      expect(r.resultado.omitida, contains('Ya existe'));
      expect(r.resultado.seGuarda, isFalse);
      expect(r.clase, isNull);
    });

    test('la misma materia con otro profe o en otro grupo no es repetida', () {
      final r = validar([
        fila(1, 'caro@x.mx', 'IA 3A', 'Matemáticas', 'A1'),
        fila(2, 'ana@x.mx', 'IA 3B', 'Matemáticas', 'A1'),
      ]);
      expect(r.every((c) => c.resultado.seGuarda), isTrue);
    });

    test('repetida en el archivo: mismo salón se omite, otro salón es error', () {
      final r = validar([
        fila(1, 'ana@x.mx', 'IA 3A', 'Física', 'A1'),
        fila(2, 'ana@x.mx', 'IA 3A', 'física', 'a1'),
        fila(3, 'ana@x.mx', 'IA 3A', 'Física', 'C3'),
      ]);
      expect(r[0].resultado.seGuarda, isTrue);
      expect(r[1].resultado.omitida, contains('la fila 1'));
      expect(r[2].resultado.errores.single, contains('otro salón'));
    });

    test('editar la fila corrige el error', () {
      final f = fila(1, 'nadie@x.mx', 'IA 3A', 'Física', 'A1');
      expect(validar([f]).single.resultado.seGuarda, isFalse);
      f.profesor = 'ana@x.mx';
      expect(validar([f]).single.resultado.seGuarda, isTrue);
    });
  });
}
