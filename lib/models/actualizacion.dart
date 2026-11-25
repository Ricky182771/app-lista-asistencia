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
