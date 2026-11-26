// Invitar usuarios por lote desde un CSV `correo,rol`: lectura y validación. Lógica pura, sin
// Firebase, para poder probarla con `flutter test`.

import 'grupo.dart' show limpiarNombre, sinAcentos;
import 'lote_csv.dart';
import 'rol.dart';

/// Una fila editable de la vista previa.
class FilaInvitacion {
  FilaInvitacion({required this.fila, required this.correo, this.rol, this.rolTexto = ''});

  /// Fila del archivo; 0 si se agregó a mano.
  final int fila;
  String correo;

  /// El rol elegido o reconocido en el archivo; `null` = sin rol (ver [rolEfectivo]).
  Rol? rol;

  /// La celda de rol tal como venía en el archivo, para el mensaje cuando no se reconoce.
  final String rolTexto;
}

/// El rol de una celda: acepta el nombre interno ("admin"), la etiqueta ("Encargado de orden") y
/// algunas formas comunes ("docente", "administrativa"). `null` si no se reconoce o viene vacía.
Rol? rolDeTexto(String texto) {
  final t = sinAcentos(limpiarNombre(texto));
  if (t.isEmpty) return null;
  for (final r in Rol.values) {
    if (t == r.name || t == sinAcentos(r.etiqueta)) return r;
  }
  return switch (t) {
    'profesora' || 'profe' || 'docente' || 'maestro' || 'maestra' => Rol.profesor,
    'encargado' || 'encargada' || 'encargada de orden' => Rol.orden,
    'administrativa' || 'administrador' || 'administradora' => Rol.admin,
    _ => null,
  };
}

/// El rol con el que se invita a esta fila: el suyo o, si el archivo no traía rol (celda vacía),
/// [porOmision]. Una celda con un rol que no se reconoce no recibe el de por omisión: es un error
/// que el admin debe ver.
Rol? rolEfectivo(FilaInvitacion f, Rol porOmision) =>
    f.rol ?? (f.rolTexto.trim().isEmpty ? porOmision : null);

class LecturaInvitaciones {
  const LecturaInvitaciones({required this.filas, this.errorGeneral});
  final List<FilaInvitacion> filas;
  final String? errorGeneral;
}

const _aliasInvitaciones = {
  'correo': ['correo', 'email', 'correo electronico', 'correo de google', 'mail', 'e-mail'],
  'rol': ['rol', 'puesto', 'tipo', 'perfil'],
};

/// Lee un CSV `correo,rol` (el encabezado es opcional; con encabezado el rol puede faltar).
LecturaInvitaciones leerInvitaciones(List<int> bytes) {
  final t = leerConColumnas(
    bytes,
    orden: const ['correo', 'rol'],
    alias: _aliasInvitaciones,
    obligatorias: const ['correo'],
  );
  if (t.errorGeneral != null) return LecturaInvitaciones(filas: const [], errorGeneral: t.errorGeneral);
  return LecturaInvitaciones(filas: [
    for (final f in t.filas)
      FilaInvitacion(
        fila: f.fila,
        correo: t.valor(f, 'correo'),
        rol: rolDeTexto(t.valor(f, 'rol')),
        rolTexto: t.valor(f, 'rol'),
      ),
  ]);
}

/// El mismo criterio que el diálogo "Invitar usuario": algo@dominio.ext sin espacios ni `/`.
bool correoValido(String correo) => RegExp(r'^[^@\s/]+@[^@\s/]+\.[^@\s/]+$').hasMatch(correo);

const _erratas = {
  'gmial.com': 'gmail.com',
  'gmai.com': 'gmail.com',
  'gamil.com': 'gmail.com',
  'gmali.com': 'gmail.com',
  'gmaill.com': 'gmail.com',
  'gmail.con': 'gmail.com',
  'gmail.co': 'gmail.com',
  'gmail.cm': 'gmail.com',
  'gmail.om': 'gmail.com',
  'hotmial.com': 'hotmail.com',
  'hotmai.com': 'hotmail.com',
  'hotmal.com': 'hotmail.com',
  'hotmail.con': 'hotmail.com',
  'outlok.com': 'outlook.com',
  'outloo.com': 'outlook.com',
  'outlook.con': 'outlook.com',
  'yaho.com': 'yahoo.com',
  'yahooo.com': 'yahoo.com',
  'yahoo.con': 'yahoo.com',
};

/// El correo corregido si el dominio es una errata común ("ana@gmial.com" → "ana@gmail.com"); `null`
/// si no parece haber errata. [correo] ya normalizado.
String? sugerirCorreo(String correo) {
  final i = correo.lastIndexOf('@');
  if (i < 0) return null;
  final bien = _erratas[correo.substring(i + 1)];
  return bien == null ? null : '${correo.substring(0, i + 1)}$bien';
}

/// Valida las filas, una por una y en orden.
/// - [rolPorOmision]: el de las filas sin rol en el archivo.
/// - [usuarios]: correo normalizado → rol actual de quien ya tiene acceso (se omite: para cambiar un
///   rol está "Cambiar rol" en la pestaña Usuarios);
/// - [invitaciones]: correo normalizado → rol de las invitaciones que ya existen.
List<ResultadoFila> validarInvitaciones(
  List<FilaInvitacion> filas, {
  required Rol rolPorOmision,
  required Map<String, Rol?> usuarios,
  required Map<String, Rol?> invitaciones,
}) {
  String nombreRol(Rol? r) => r?.etiqueta ?? 'sin rol';
  final primeras = <String, int>{};
  final resultados = <ResultadoFila>[];
  for (var i = 0; i < filas.length; i++) {
    final f = filas[i];
    final correo = normalizarCorreo(f.correo);
    final rol = rolEfectivo(f, rolPorOmision);
    final errores = <String>[];
    final avisos = <String>[];
    String? omitida;

    if (correo.isEmpty) {
      errores.add('Falta el correo');
    } else if (!correoValido(correo)) {
      errores.add('El correo no es válido');
    } else {
      final sugerido = sugerirCorreo(correo);
      if (sugerido != null) avisos.add('¿Quisiste decir $sugerido?');
      final previa = primeras[correo];
      if (previa == null) {
        primeras[correo] = i;
      } else if (rol != null && rol == rolEfectivo(filas[previa], rolPorOmision)) {
        omitida = 'Repetido: ya está en ${dondeFila(filas[previa].fila)}';
      } else {
        errores.add('Aparece en ${dondeFila(filas[previa].fila)} con otro rol');
      }
    }
    if (rol == null) {
      errores.add(f.rolTexto.trim().isEmpty ? 'Elige el rol' : 'No se reconoce el rol "${f.rolTexto}"');
    }

    if (errores.isEmpty && omitida == null) {
      if (usuarios.containsKey(correo)) {
        omitida = 'Ya tiene acceso como ${nombreRol(usuarios[correo])}. Para cambiarle el rol usa '
            '"Cambiar rol" en la pestaña Usuarios.';
      } else if (invitaciones.containsKey(correo)) {
        if (invitaciones[correo] == rol) {
          omitida = 'Ya estaba invitado como ${nombreRol(rol)}';
        } else {
          avisos.add('Ya tenía invitación como ${nombreRol(invitaciones[correo])}: se cambiará a '
              '${nombreRol(rol)}.');
        }
      }
    }
    resultados.add(ResultadoFila(errores: errores, avisos: avisos, omitida: omitida));
  }
  return resultados;
}
