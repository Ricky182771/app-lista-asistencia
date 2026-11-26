import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/actualizacion.dart';
import '../services/actualizacion.dart';
import 'inicio.dart';
import 'lote_comun.dart' show confirmarLote;

/// Editar `config/app`: la última versión del APK, el enlace de descarga y, si hace falta, la
/// compilación mínima con la que todavía se puede usar la app. Antes había que hacerlo a mano en la
/// consola de Firebase después de `scripts/publicar-apk.sh`.
class VersionApp extends StatefulWidget {
  const VersionApp({super.key});

  @override
  State<VersionApp> createState() => _VersionAppState();
}

class _VersionAppState extends State<VersionApp> {
  final _version = TextEditingController();
  final _build = TextEditingController();
  final _minimo = TextEditingController();
  final _url = TextEditingController();
  late final StreamSubscription<void> _sub;

  /// Lo que había en `config/app` al abrir; `null` si no existía. Para saber si el mínimo cambió.
  BorradorConfig? _guardado;
  bool _cargado = false;
  Object? _errorCarga;
  bool _intentado = false;
  String? _estaApp;

  @override
  void initState() {
    super.initState();
    _sub = configApp().listen(
      (s) {
        // Solo la primera vez: después no se pisa lo que el admin está escribiendo.
        if (_cargado) return;
        final b = borradorDeConfig(s.data());
        setState(() {
          _cargado = true;
          _guardado = s.exists ? b : null;
          _version.text = b.version;
          _build.text = b.buildActual;
          _minimo.text = b.buildMinimo;
          _url.text = b.urlApk.isEmpty ? urlApkPorOmision : b.urlApk;
        });
      },
      onError: (Object e) => setState(() => _errorCarga = e),
    );
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _estaApp = 'Esta app: versión ${i.version}, compilación ${i.buildNumber}');
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _sub.cancel();
    for (final c in [_version, _build, _minimo, _url]) {
      c.dispose();
    }
    super.dispose();
  }

  BorradorConfig get _borrador =>
      (version: _version.text, buildActual: _build.text, buildMinimo: _minimo.text, urlApk: _url.text);

  Future<void> _guardar() async {
    setState(() => _intentado = true);
    final b = _borrador;
    if (validarConfig(b).hayErrores) return;
    final advertencia = advertenciaConfig(b, _guardado);
    if (advertencia != null) {
      final ok = await confirmarLote(
        context,
        titulo: 'Actualización obligatoria',
        mensaje: advertencia,
        boton: 'Guardar',
      );
      if (!ok || !mounted) return;
    }
    // Sin `await`: sin internet el Future no se completa (ver CLAUDE.md); solo avisa si falla.
    avisarSiFalla(context, guardarConfigApp(configParaGuardar(b)), 'No se guardó la versión');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Versión ${b.version.trim()} guardada.')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final errores = _intentado ? validarConfig(_borrador) : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Versión de la app')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Aquí se dice cuál es la última versión del APK. Los celulares con una compilación menor ven '
            'el aviso "Ya está disponible…" al abrir la app; si pones una compilación mínima, los que '
            'estén por debajo no pueden usarla hasta actualizar. La web siempre carga la versión '
            'desplegada y no se ve afectada. Publica primero el APK con scripts/publicar-apk.sh.',
          ),
          if (_estaApp != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_estaApp!)),
          const SizedBox(height: 16),
          if (_errorCarga != null)
            Text('No se pudo leer la versión guardada: $_errorCarga',
                style: TextStyle(color: Theme.of(context).colorScheme.error))
          else if (!_cargado)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else ...[
            TextField(
              controller: _version,
              decoration: InputDecoration(
                labelText: 'Versión',
                hintText: '1.2.0',
                helperText: 'El número de pubspec.yaml antes del +.',
                errorText: errores?.version,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _build,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Compilación actual',
                hintText: '3',
                helperText: 'El número de pubspec.yaml después del +.',
                errorText: errores?.buildActual,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _minimo,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Compilación mínima (opcional)',
                helperText: 'Vacío = la actualización es solo un aviso. Con un número, quien tenga menos queda '
                    'bloqueado hasta actualizar.',
                helperMaxLines: 3,
                errorText: errores?.buildMinimo,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Enlace de descarga del APK',
                helperText: 'https; el de GitHub Releases siempre apunta a la última versión publicada.',
                helperMaxLines: 2,
                errorText: errores?.urlApk,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _url.text = urlApkPorOmision),
                child: const Text('Usar el enlace de GitHub Releases'),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _guardar,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
