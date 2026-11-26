// Lógica pura del aviso de actualización del APK: sin Firebase, para poder probarla con `flutter test`.

/// Lo que se le muestra al profe cuando su APK es más viejo que el publicado en `config/app`.
class AvisoActualizacion {
  const AvisoActualizacion({required this.version, required this.url, required this.obligatoria});

  /// "1.1.0" o `''` si `config/app` no la trae.
  final String version;

  /// Enlace de descarga del APK (siempre https).
  final Uri url;

  /// `true` si este APK es más viejo que `buildMinimo`: la app no deja seguir sin actualizar.
  final bool obligatoria;
}

/// Compara el número de compilación de este APK ([miBuild], lo que va después del `+` en
/// `pubspec.yaml`) contra `config/app`: `{versionActual, buildActual, buildMinimo, urlApk}`.
/// `null` si está al día, si no hay `config/app` o si viene mal (sin `buildActual` o sin un enlace
/// https): ante la duda no se molesta al profe ni se le bloquea la app.
AvisoActualizacion? avisoActualizacion(int miBuild, Map<String, dynamic>? config) {
  final actual = config?['buildActual'];
  final url = Uri.tryParse('${config?['urlApk'] ?? ''}');
  if (actual is! num || url == null || url.scheme != 'https' || url.host.isEmpty) return null;
  if (miBuild >= actual) return null;
  final minimo = config?['buildMinimo'];
  return AvisoActualizacion(
    version: '${config?['versionActual'] ?? ''}'.trim(),
    url: url,
    obligatoria: minimo is num && miBuild < minimo,
  );
}

// ── Editar config/app desde la app (Herramientas avanzadas → Versión de la app) ─────────────────

/// El enlace fijo del último APK publicado con `scripts/publicar-apk.sh`.
const urlApkPorOmision =
    'https://github.com/Ricky182771/app-lista-asistencia/releases/latest/download/PaseLista.apk';

/// Lo escrito en el formulario de `config/app`, antes de validarlo.
typedef BorradorConfig = ({String version, String buildActual, String buildMinimo, String urlApk});

/// Los problemas de cada campo; `null` = bien.
typedef ErroresConfig = ({String? version, String? buildActual, String? buildMinimo, String? urlApk});

extension ErroresConfigX on ErroresConfig {
  bool get hayErrores => version != null || buildActual != null || buildMinimo != null || urlApk != null;
}

/// El formulario con lo que hay hoy en `config/app` (vacío si no existe).
BorradorConfig borradorDeConfig(Map<String, dynamic>? config) => (
      version: '${config?['versionActual'] ?? ''}'.trim(),
      buildActual: config?['buildActual'] is num ? '${(config!['buildActual'] as num).toInt()}' : '',
      buildMinimo: config?['buildMinimo'] is num ? '${(config!['buildMinimo'] as num).toInt()}' : '',
      urlApk: '${config?['urlApk'] ?? ''}'.trim(),
    );

int? _entero(String texto) {
  final n = int.tryParse(texto.trim());
  return n != null && n >= 1 ? n : null;
}

/// Revisa el formulario con las mismas exigencias de [avisoActualizacion]: sin un `buildActual`
/// numérico y un enlace https la app ignora `config/app` por completo.
ErroresConfig validarConfig(BorradorConfig b) {
  final version = b.version.trim();
  final actual = _entero(b.buildActual);
  final minimoTexto = b.buildMinimo.trim();
  final minimo = _entero(minimoTexto);
  final url = Uri.tryParse(b.urlApk.trim());
  return (
    version: version.isEmpty
        ? 'Escribe la versión, por ejemplo 1.2.0.'
        : RegExp(r'^\d+(\.\d+){1,3}$').hasMatch(version)
            ? null
            : 'Usa solo números y puntos, por ejemplo 1.2.0.',
    buildActual: b.buildActual.trim().isEmpty
        ? 'Escribe el número de compilación (lo que va después del + en pubspec.yaml).'
        : actual == null
            ? 'Debe ser un número entero mayor que 0.'
            : null,
    buildMinimo: minimoTexto.isEmpty
        ? null
        : minimo == null
            ? 'Debe ser un número entero mayor que 0, o déjalo vacío.'
            : actual != null && minimo > actual
                ? 'No puede ser mayor que la compilación actual ($actual): nadie podría actualizar.'
                : null,
    urlApk: url == null || url.scheme != 'https' || url.host.isEmpty || b.urlApk.trim().contains(' ')
        ? 'Escribe un enlace https completo al APK.'
        : null,
  );
}

/// Lo que se escribe en `config/app` (con `merge`). `buildMinimo` vacío = `null`: se borra el campo.
/// Solo tiene sentido si [validarConfig] no encontró errores.
Map<String, Object?> configParaGuardar(BorradorConfig b) => {
      'versionActual': b.version.trim(),
      'buildActual': int.parse(b.buildActual.trim()),
      'buildMinimo': b.buildMinimo.trim().isEmpty ? null : int.parse(b.buildMinimo.trim()),
      'urlApk': b.urlApk.trim(),
    };

/// Advertencias antes de guardar, separadas por una línea en blanco; `null` si no hace falta ninguna.
/// [antes] es lo que había (`null` si `config/app` no existía).
/// - Poner un `buildMinimo` nuevo bloquea a quien tenga menos, también a un admin con ese APK en Android.
/// - Bajar `buildActual` hace que los celulares que ya actualizaron dejen de ver el aviso y puede ser un
///   error de dedo.
String? advertenciaConfig(BorradorConfig b, BorradorConfig? antes) {
  final avisos = <String>[];
  final actual = _entero(b.buildActual);
  final actualAntes = antes == null ? null : _entero(antes.buildActual);
  if (actual != null && actualAntes != null && actual < actualAntes) {
    avisos.add('La compilación actual baja de $actualAntes a $actual. Es válido para volver a una '
        'versión anterior, pero si fue un error de dedo, corrígelo antes de guardar.');
  }
  final minimo = _entero(b.buildMinimo);
  if (minimo != null && (antes == null || _entero(antes.buildMinimo) != minimo)) {
    avisos.add('Quien tenga una compilación menor que $minimo no podrá usar la app hasta actualizarla, '
        'también tú si tu celular Android tiene un APK anterior (te queda la web). La web no se ve '
        'afectada. Asegúrate de que el APK de esa versión ya esté publicado y que el enlace funcione.');
  }
  return avisos.isEmpty ? null : avisos.join('\n\n');
}
