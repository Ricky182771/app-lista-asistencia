// Lógica pura de la pestaña Usuarios del admin: búsqueda, cambio de rol y conteo de clases por
// profe. Sin Firebase, para poder probarla con `flutter test`.

import 'clase.dart';
import 'grupo.dart' show sinAcentos;
import 'rol.dart';

/// ¿[busqueda] aparece en [campos] (nombre, correo, rol…)? No distingue mayúsculas ni acentos; con
/// varias palabras deben aparecer todas, en cualquier campo y en cualquier orden. Una búsqueda vacía
/// coincide con todo.
bool coincideBusqueda(String busqueda, Iterable<String> campos) {
  final palabras = [
    for (final p in sinAcentos(busqueda).split(RegExp(r'\s+')))
      if (p.isNotEmpty) p,
  ];
  if (palabras.isEmpty) return true;
  final texto = sinAcentos(campos.join(' '));
  return palabras.every((p) => texto.contains(p));
}

/// profesorUid → cuántas clases tiene dadas de alta.
Map<String, int> clasesPorProfe(Iterable<Clase> clases) {
  final cuenta = <String, int>{};
  for (final c in clases) {
    cuenta[c.profesorUid] = (cuenta[c.profesorUid] ?? 0) + 1;
  }
  return cuenta;
}

/// "sin clases", "1 clase" o "3 clases".
String textoClases(int n) => switch (n) {
      0 => 'sin clases',
      1 => '1 clase',
      _ => '$n clases',
    };

/// Por qué no se puede cambiar el rol de [uid] a [nuevo]; `null` si se puede.
/// - [miUid]: el admin que lo intenta; no se cambia su propio rol (se quedaría sin acceso de
///   administrativo y otro admin tendría que devolvérselo);
/// - [clases]: cuántas clases tiene dadas de alta ese usuario. Un profe con clases no pasa a otro rol:
///   sus clases se quedarían con alguien que ya no pasa lista (reasígnalas o bórralas primero).
String? errorCambioRol({
  required String uid,
  required String miUid,
  required Rol? actual,
  required Rol nuevo,
  required int clases,
}) {
  if (uid == miUid) {
    return 'No puedes cambiar tu propio rol: te quedarías sin acceso de administrativo. '
        'Pídeselo a otro administrativo.';
  }
  if (actual == nuevo) return 'Ya es ${nuevo.etiqueta}.';
  if (actual == Rol.profesor && clases > 0) {
    return 'Tiene ${textoClases(clases)} dadas de alta. Reasígnalas a otro profesor o bórralas '
        'antes de cambiarle el rol.';
  }
  return null;
}
