import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/services/pases.dart';

void main() {
  test('mensajeErrorEnvio: permission-denied no afirma la causa', () {
    final e = FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    expect(
      mensajeErrorEnvio(e, '2026-11-13'),
      'El servidor no aceptó el pase del 2026-11-13. Si ya habías pasado lista ese día desde otro '
      'dispositivo, se conservó ese.',
    );
  });

  test('mensajeErrorEnvio: otros errores conservan el mensaje de siempre', () {
    final e = FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    expect(mensajeErrorEnvio(e, '2026-11-13'), startsWith('No se envió el pase del 2026-11-13: '));
    expect(mensajeErrorEnvio(Exception('raro'), '2026-11-13'), 'No se envió el pase del 2026-11-13: Exception: raro');
  });
}
