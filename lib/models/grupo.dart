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

/// Un nombre como se guarda: sin espacios al inicio o al final ni espacios dobles.
String limpiarNombre(String nombre) => nombre.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Una entrada de `alumnos`, o `null` si no se reconoce. El N.L puede venir como `3.0`: pasa con un
/// número creado a mano en la consola y en la web compilada a WebAssembly, donde `int` y `double`
/// son tipos distintos. Sin `activo` se toma como activo.
Alumno? _alumnoDe(Object? a) {
  if (a is! Map) return null;
  final n = a['num'];
  final nombre = a['nombre'];
  if (n is! num || !n.isFinite || n != n.roundToDouble() || nombre is! String) return null;
  return Alumno(num: n.toInt(), nombre: nombre, activo: a['activo'] != false);
}

/// Convierte el campo `alumnos` de Firestore, ordenado por N.L. Lo que no se reconoce no sale en
/// la lista: antes de guardar cambios hay que revisar [sinReconocer].
List<Alumno> alumnosDe(Object? campo) {
  if (campo is! List) return [];
  return [
    for (final a in campo) ?_alumnoDe(a),
  ]..sort((a, b) => a.num.compareTo(b.num));
}

/// Cuántas entradas del campo `alumnos` no reconoce [alumnosDe]. Si no es 0, el grupo no se debe
/// editar: guardar reescribe la lista completa y esos alumnos se perderían junto con la liga a su
/// historial. Un campo que falta cuenta como lista vacía; uno que no es lista, como no reconocido.
int sinReconocer(Object? campo) {
  if (campo == null) return 0;
  if (campo is! List) return 1;
  return campo.where((a) => _alumnoDe(a) == null).length;
}

/// El aviso que se muestra en vez de dejar editar un grupo con entradas sin reconocer.
const avisoSinReconocer =
    'Hay alumnos con datos que la app no reconoce; revisa el grupo en la consola de Firebase. '
    'Mientras tanto no se puede editar, para no perderlos.';

/// Un N.L cuyo nombre cambia al reemplazar la lista.
class CambioNombre {
  const CambioNombre({required this.num, required this.antes, required this.despues});
  final int num;
  final String antes;
  final String despues;
}

/// Lo que pasa al reemplazar la lista de un grupo con otra, comparando por N.L.
class CambiosLista {
  const CambiosLista({
    required this.resultado,
    required this.nuevos,
    required this.bajas,
    required this.renombrados,
  });

  /// La lista como quedará guardada, ordenada por N.L. Nunca pierde un N.L de la lista anterior.
  final List<Alumno> resultado;

  /// N.L que solo están en la lista nueva: se agregan como activos.
  final List<Alumno> nuevos;

  /// N.L activos que ya no vienen en la lista nueva: quedan con `activo: false`, no se borran.
  final List<Alumno> bajas;

  /// N.L que están en las dos listas con distinto nombre.
  final List<CambioNombre> renombrados;

  bool get sinCambios => nuevos.isEmpty && bajas.isEmpty && renombrados.isEmpty;

  /// Por ejemplo: "3 nuevos, 1 dado de baja, 2 cambian de nombre".
  String get resumen {
    if (sinCambios) return 'Sin cambios: la lista es igual a la que ya está guardada.';
    String parte(int n, String uno, String varios) => n == 1 ? '1 $uno' : '$n $varios';
    return [
      if (nuevos.isNotEmpty) parte(nuevos.length, 'nuevo', 'nuevos'),
      if (bajas.isNotEmpty) parte(bajas.length, 'dado de baja', 'dados de baja'),
      if (renombrados.isNotEmpty)
        parte(renombrados.length, 'cambia de nombre', 'cambian de nombre'),
    ].join(', ');
  }
}

/// Compara la lista guardada con la del CSV nuevo. El N.L es lo que une al alumno con su historial:
/// - N.L en las dos listas: se actualiza el nombre; quien estaba dado de baja sigue de baja
///   (reactivar es una decisión del admin, se hace a mano);
/// - N.L solo en la nueva: se agrega como activo;
/// - N.L solo en la vieja: se marca `activo: false`, nunca se borra.
CambiosLista compararListas(List<Alumno> actual, List<Alumno> nueva) {
  final viejos = {for (final a in actual) a.num: a};
  final entrantes = {for (final a in nueva) a.num: a};
  final resultado = <Alumno>[];
  final nuevos = <Alumno>[];
  final bajas = <Alumno>[];
  final renombrados = <CambioNombre>[];

  for (final a in nueva) {
    final viejo = viejos[a.num];
    final alumno = Alumno(num: a.num, nombre: a.nombre, activo: viejo?.activo ?? true);
    if (viejo == null) {
      nuevos.add(alumno);
    } else if (viejo.nombre != a.nombre) {
      renombrados.add(CambioNombre(num: a.num, antes: viejo.nombre, despues: a.nombre));
    }
    resultado.add(alumno);
  }
  for (final viejo in actual) {
    if (entrantes.containsKey(viejo.num)) continue;
    if (viejo.activo) bajas.add(viejo);
    resultado.add(Alumno(num: viejo.num, nombre: viejo.nombre, activo: false));
  }
  int porNum(Alumno a, Alumno b) => a.num.compareTo(b.num);
  return CambiosLista(
    resultado: resultado..sort(porNum),
    nuevos: nuevos..sort(porNum),
    bajas: bajas..sort(porNum),
    renombrados: renombrados..sort((a, b) => a.num.compareTo(b.num)),
  );
}

/// El siguiente N.L libre: uno más que el mayor, contando a los dados de baja, para no reutilizar
/// el número de alguien que ya tiene historial.
int siguienteNum(List<Alumno> alumnos) =>
    alumnos.fold(0, (mayor, a) => a.num > mayor ? a.num : mayor) + 1;

/// Edición a mano: agrega un alumno activo con el siguiente N.L libre.
List<Alumno> agregarAlumno(List<Alumno> alumnos, String nombre) =>
    [...alumnos, Alumno(num: siguienteNum(alumnos), nombre: limpiarNombre(nombre))];

/// Edición a mano: corrige el nombre del alumno con ese N.L.
List<Alumno> corregirNombre(List<Alumno> alumnos, int num, String nombre) => [
      for (final a in alumnos)
        a.num == num ? Alumno(num: num, nombre: limpiarNombre(nombre), activo: a.activo) : a,
    ];

/// Edición a mano: da de baja (`false`) o reactiva (`true`) al alumno con ese N.L. No se borra.
List<Alumno> cambiarActivo(List<Alumno> alumnos, int num, bool activo) => [
      for (final a in alumnos)
        a.num == num ? Alumno(num: num, nombre: a.nombre, activo: activo) : a,
    ];
