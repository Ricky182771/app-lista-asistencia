// Lógica pura de roles: sin Firebase, para poder probarla con `flutter test`.

enum Rol {
  profesor('Profesor'),
  orden('Encargado de orden'),
  admin('Administrativo');

  const Rol(this.etiqueta);
  final String etiqueta;
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
