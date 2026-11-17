import 'package:web/web.dart';

// El navegador puede bloquear el almacenamiento (sitio con datos bloqueados): se trata como vacío.
String? leerLocal(String clave) {
  try {
    return window.localStorage.getItem(clave);
  } catch (_) {
    return null;
  }
}

void guardarLocal(String clave, String valor) {
  try {
    window.localStorage.setItem(clave, valor);
  } catch (_) {}
}
