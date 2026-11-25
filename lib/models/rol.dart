// Lógica pura de roles: sin Firebase, para poder probarla con `flutter test`.

enum Rol {
  profesor('Profesor', 'Profesores'),
  orden('Encargado de orden', 'Encargados de orden'),
  admin('Administrativo', 'Administrativos');

  const Rol(this.etiqueta, this.plural);
  final String etiqueta;

  /// Para los filtros de la lista de usuarios del admin.
  final String plural;
}

/// Convierte el campo `rol` de Firestore; cualquier otra cosa es `null`.
Rol? parseRol(Object? valor) {
  for (final r in Rol.values) {
    if (r.name == valor) return r;
  }
  return null;
}

/// Las invitaciones se guardan con el correo en minúsculas y sin espacios.
String normalizarCorreo(String correo) => correo.trim().toLowerCase();

/// Las invitaciones (IDs = correos) con las que nadie ha entrado todavía: ningún usuario tiene ese
/// correo. El de `usuarios.email` viene del token de Google y puede traer mayúsculas, por eso se
/// normaliza antes de comparar.
Set<String> invitacionesSinUsar(Iterable<String> invitaciones, Iterable<String> correosDeUsuarios) {
  final enUso = {for (final c in correosDeUsuarios) normalizarCorreo(c)};
  return {for (final i in invitaciones) if (!enUso.contains(normalizarCorreo(i))) i};
}

enum Pantalla { login, sinAcceso, profesor, orden, admin }

/// [usuario] es el documento `usuarios/{uid}` (ya creado desde la invitación si había una).
Pantalla decidirPantalla({required bool conSesion, Map<String, dynamic>? usuario}) {
  if (!conSesion) return Pantalla.login;
  return switch (parseRol(usuario?['rol'])) {
    Rol.profesor => Pantalla.profesor,
    Rol.orden => Pantalla.orden,
    Rol.admin => Pantalla.admin,
    null => Pantalla.sinAcceso,
  };
}
