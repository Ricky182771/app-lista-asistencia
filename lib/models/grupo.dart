// Lógica pura de grupos: sin Firebase, para poder probarla con `flutter test`.

/// Un alumno dentro de `grupos/{grupoId}.alumnos`.
class Alumno {
  const Alumno({required this.num, required this.nombre, this.activo = true});
  final int num;
  final String nombre;
  final bool activo;

  Map<String, dynamic> toMap() => {'num': num, 'nombre': nombre, 'activo': activo};
}

const _sinAcento = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// ID del documento a partir del nombre del grupo: minúsculas, sin acentos y con guiones en vez de
/// espacios ("IA 3A" → "ia-3a"). Cualquier otro símbolo también se vuelve guion, porque una `/` en
/// el ID cambiaría la ruta del documento. Devuelve '' si el nombre no deja nada utilizable.
String idGrupo(String nombre) {
  final sinAcentos = nombre.trim().toLowerCase().split('').map((c) => _sinAcento[c] ?? c).join();
  return sinAcentos.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
}
