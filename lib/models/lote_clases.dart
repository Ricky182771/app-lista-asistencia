// Dar de alta varias clases a la vez desde un CSV `profesor,grupo,materia,salón`: lectura y
// validación. Lógica pura, sin Firebase, para poder probarla con `flutter test`.

import 'clase.dart';
import 'grupo.dart' show idGrupo, limpiarNombre, sinAcentos;
import 'lote_csv.dart';
import 'rol.dart';

/// Una fila editable de la vista previa: una clase por dar de alta.
class FilaClaseLote {
  FilaClaseLote({
    required this.fila,
    required this.profesor,
    required this.grupo,
    required this.materia,
    required this.salon,
  });

  /// Fila del archivo; 0 si se agregó a mano.
  final int fila;

  /// El correo del profe (lo mejor: es con el que entra a la app) o, si no hay otro igual, su nombre.
  String profesor;

  /// El nombre del grupo, como se ve en la pestaña Grupos.
  String grupo;
  String materia;
  String salon;
}

class LecturaClasesLote {
  const LecturaClasesLote({required this.filas, this.errorGeneral});
  final List<FilaClaseLote> filas;
  final String? errorGeneral;
}

const _aliasClases = {
  'profesor': [
    'profesor',
    'profesora',
    'correo',
    'correo del profesor',
    'correo profesor',
    'email',
    'docente',
    'maestro',
    'maestra',
  ],
  'grupo': ['grupo'],
  'materia': ['materia', 'asignatura', 'clase'],
  'salon': ['salon', 'aula', 'salon de clase'],
};

/// Lee un CSV `profesor,grupo,materia,salón` (el encabezado es opcional).
LecturaClasesLote leerClasesLote(List<int> bytes) {
  final t = leerConColumnas(
    bytes,
    orden: const ['profesor', 'grupo', 'materia', 'salon'],
    alias: _aliasClases,
    obligatorias: const ['profesor', 'grupo', 'materia', 'salon'],
  );
  if (t.errorGeneral != null) return LecturaClasesLote(filas: const [], errorGeneral: t.errorGeneral);
  return LecturaClasesLote(filas: [
    for (final f in t.filas)
      FilaClaseLote(
        fila: f.fila,
        profesor: t.valor(f, 'profesor'),
        grupo: t.valor(f, 'grupo'),
        materia: t.valor(f, 'materia'),
        salon: t.valor(f, 'salon'),
      ),
  ]);
}

/// Un usuario con acceso, para encontrar al profe de cada fila.
typedef UsuarioLote = ({String uid, String nombre, String correo, Rol? rol});

/// El resultado de validar una fila; [clase] está lista para dar de alta solo si
/// `resultado.seGuarda`.
class ClaseValidada {
  const ClaseValidada({required this.resultado, this.clase});
  final ResultadoFila resultado;
  final Clase? clase;
}

String _llaveMateria(String materia) => sinAcentos(limpiarNombre(materia));

/// El ID del grupo que se llama [nombre] (por nombre actual o por ID) dentro de [grupos] (ID →
/// nombre); `null` si no hay ninguno. Un grupo renombrado conserva el ID de su nombre original.
String? grupoPorNombre(String nombre, Map<String, String> grupos) {
  final id = idGrupo(limpiarNombre(nombre));
  if (id.isEmpty) return null;
  if (grupos.containsKey(id)) return id;
  return grupos.entries.where((e) => idGrupo(e.value) == id).map((e) => e.key).firstOrNull;
}

/// Valida las filas, una por una y en orden.
/// - [usuarios]: todos los que tienen acceso (de ahí sale el profe de cada fila);
/// - [invitaciones]: correo normalizado → rol de las invitaciones, para decir "todavía no entra";
/// - [grupos]: ID → nombre de los grupos que ya existen (el grupo debe existir);
/// - [existentes]: las clases que ya están dadas de alta (no se repiten).
List<ClaseValidada> validarClases(
  List<FilaClaseLote> filas, {
  required List<UsuarioLote> usuarios,
  required Map<String, Rol?> invitaciones,
  required Map<String, String> grupos,
  required List<Clase> existentes,
}) {
  final yaEstan = {
    for (final c in existentes) '${c.profesorUid}\n${c.grupoId}\n${_llaveMateria(c.materia)}',
  };
  // Llave de la clase → (índice de la primera fila con esa llave).
  final primeras = <String, int>{};
  final resultados = <ClaseValidada>[];

  for (var i = 0; i < filas.length; i++) {
    final f = filas[i];
    final errores = <String>[];
    String? omitida;

    // Profesor.
    UsuarioLote? profe;
    final celda = limpiarNombre(f.profesor);
    if (celda.isEmpty) {
      errores.add('Falta el profesor');
    } else if (celda.contains('@')) {
      final correo = normalizarCorreo(celda);
      profe = usuarios.where((u) => normalizarCorreo(u.correo) == correo).firstOrNull;
      if (profe == null) {
        errores.add(invitaciones.containsKey(correo)
            ? '$celda ya está invitado pero todavía no entra a la app: cuando entre por primera '
                'vez podrás darle sus clases.'
            : '$celda no tiene acceso a PaseLista: invítalo primero.');
      }
    } else {
      final iguales = usuarios.where((u) => sinAcentos(limpiarNombre(u.nombre)) == sinAcentos(celda)).toList();
      if (iguales.length == 1) {
        profe = iguales.single;
      } else if (iguales.isEmpty) {
        errores.add('No hay un usuario llamado "$celda": usa su correo.');
      } else {
        errores.add('Hay ${iguales.length} usuarios llamados "$celda": usa su correo.');
      }
    }
    if (profe != null && profe.rol != Rol.profesor) {
      errores.add('${profe.nombre.isEmpty ? profe.correo : profe.nombre} es '
          '${profe.rol?.etiqueta ?? 'un usuario sin rol'}, no Profesor.');
      profe = null;
    }

    // Grupo.
    String? grupoId;
    final nombreGrupo = limpiarNombre(f.grupo);
    if (nombreGrupo.isEmpty) {
      errores.add('Falta el grupo');
    } else if (idGrupo(nombreGrupo).isEmpty) {
      errores.add('Usa letras o números en el nombre del grupo');
    } else {
      grupoId = grupoPorNombre(nombreGrupo, grupos);
      if (grupoId == null) {
        errores.add('El grupo "$nombreGrupo" no existe: impórtalo primero en "Importar grupos por lote".');
      }
    }

    // Materia y salón.
    final errorMateria = errorEtiqueta(f.materia, 'la materia');
    if (errorMateria != null) errores.add(errorMateria);
    final errorSalon = errorEtiqueta(f.salon, 'el salón');
    if (errorSalon != null) errores.add(errorSalon);

    // Repetidas: ya existe, o ya viene antes en el archivo.
    if (errores.isEmpty && profe != null && grupoId != null) {
      final llave = '${profe.uid}\n$grupoId\n${_llaveMateria(f.materia)}';
      final previa = primeras[llave];
      if (yaEstan.contains(llave)) {
        omitida = 'Ya existe: ${profe.nombre} ya da esa materia a este grupo';
      } else if (previa != null) {
        final otra = filas[previa];
        omitida = sinAcentos(limpiarNombre(otra.salon)) == sinAcentos(limpiarNombre(f.salon))
            ? 'Repetida: ya está en ${dondeFila(otra.fila)}'
            : null;
        if (omitida == null) {
          errores.add('Ya está en ${dondeFila(otra.fila)} con otro salón (${limpiarNombre(otra.salon)}): '
              'deja solo una.');
        }
      } else {
        primeras[llave] = i;
      }
    }

    Clase? clase;
    if (errores.isEmpty && omitida == null && profe != null && grupoId != null) {
      clase = Clase(
        id: '',
        profesorUid: profe.uid,
        grupoId: grupoId,
        materia: limpiarNombre(f.materia),
        salon: limpiarNombre(f.salon),
        profesorNombre: profe.nombre.trim(),
      );
    }
    resultados.add(ClaseValidada(
      resultado: ResultadoFila(errores: errores, omitida: omitida),
      clase: clase,
    ));
  }
  return resultados;
}
