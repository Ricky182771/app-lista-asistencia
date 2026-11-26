import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/actualizacion.dart';

/// El aviso de actualización de este APK; `null` = al día. Solo en Android: la web siempre carga la
/// versión desplegada. Si no se puede leer `config/app` (sin las reglas nuevas desplegadas, por
/// ejemplo), no avisa nada: nunca bloquea la app por un error.
Stream<AvisoActualizacion?> escucharActualizacion() async* {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  final info = await PackageInfo.fromPlatform();
  final miBuild = int.tryParse(info.buildNumber) ?? 0;
  yield* FirebaseFirestore.instance
      .doc('config/app')
      .snapshots()
      .map((d) => avisoActualizacion(miBuild, d.data()))
      .handleError((Object _) {});
}

/// Abre el enlace del APK en el navegador, que lo descarga; Android pregunta si se instala.
Future<bool> abrirDescarga(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

/// `config/app` en vivo, para el formulario del admin (Herramientas avanzadas → Versión de la app).
Stream<DocumentSnapshot<Map<String, dynamic>>> configApp() =>
    FirebaseFirestore.instance.doc('config/app').snapshots(includeMetadataChanges: true);

/// Guarda `config/app` con `merge`: no pisa otros campos que alguien haya puesto en la consola. Un
/// valor `null` borra el campo (así se quita `buildMinimo`). Sin `await` a propósito, como el resto
/// de las escrituras del admin (ver CLAUDE.md); solo el admin puede escribir (reglas).
Future<void> guardarConfigApp(Map<String, Object?> datos) => FirebaseFirestore.instance.doc('config/app').set(
      {for (final e in datos.entries) e.key: e.value ?? FieldValue.delete()},
      SetOptions(merge: true),
    );
