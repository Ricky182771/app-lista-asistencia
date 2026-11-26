import 'package:flutter/material.dart';

import '../models/actualizacion.dart';
import '../services/actualizacion.dart';
import 'sin_acceso_screen.dart' show BotonCerrarSesion;

Future<void> _descargar(BuildContext context, Uri url) async {
  final avisos = ScaffoldMessenger.maybeOf(context);
  final ok = await abrirDescarga(url).catchError((Object _) => false);
  if (!ok) avisos?.showSnackBar(SnackBar(content: Text('No se pudo abrir $url')));
}

String _nombre(AvisoActualizacion a) => a.version.isEmpty ? 'PaseLista' : 'PaseLista ${a.version}';

/// Tarjeta "Hay una versión nueva" al principio de cada inicio (ver `Inicio`). No se ve en la web
/// ni si el APK está al día.
class AvisoActualizacionTarjeta extends StatefulWidget {
  const AvisoActualizacionTarjeta({super.key});

  @override
  State<AvisoActualizacionTarjeta> createState() => _AvisoActualizacionTarjetaState();
}

class _AvisoActualizacionTarjetaState extends State<AvisoActualizacionTarjeta> {
  final _aviso = escucharActualizacion();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AvisoActualizacion?>(
      stream: _aviso,
      builder: (context, snap) {
        final aviso = snap.data;
        if (aviso == null) return const SizedBox.shrink();
        final colores = Theme.of(context).colorScheme;
        return Card(
          color: colores.primaryContainer,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(Icons.system_update, color: colores.onPrimaryContainer),
            title: Text('Ya está disponible ${_nombre(aviso)}'),
            subtitle: const Text('Descárgala e instálala encima de esta; no se pierde nada.'),
            textColor: colores.onPrimaryContainer,
            trailing: FilledButton(
              onPressed: () => _descargar(context, aviso.url),
              child: const Text('Descargar'),
            ),
          ),
        );
      },
    );
  }
}

/// Si este APK es más viejo que `config/app.buildMinimo`, muestra la pantalla de actualizar en vez
/// de [child]. Va alrededor del inicio de cada rol (ver `main.dart`).
class PuertaActualizacion extends StatefulWidget {
  const PuertaActualizacion({super.key, required this.child});
  final Widget child;

  @override
  State<PuertaActualizacion> createState() => _PuertaActualizacionState();
}

class _PuertaActualizacionState extends State<PuertaActualizacion> {
  final _aviso = escucharActualizacion();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AvisoActualizacion?>(
      stream: _aviso,
      builder: (context, snap) {
        final aviso = snap.data;
        if (aviso == null || !aviso.obligatoria) return widget.child;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.system_update, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'Actualiza la app',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Esta versión ya no se puede usar. Descarga ${_nombre(aviso)} e instálala encima de '
                      'esta; no se pierde nada. Mientras, puedes pasar lista desde la versión web.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _descargar(context, aviso.url),
                      icon: const Icon(Icons.download),
                      label: const Text('Descargar'),
                    ),
                    const SizedBox(height: 8),
                    const BotonCerrarSesion(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
