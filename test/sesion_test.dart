import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:app_lista_asistencia/services/sesion.dart';

void main() {
  group('mensajeDeError', () {
    const cancelado = GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
    const rapido = Duration(milliseconds: 300);
    const lento = Duration(seconds: 8);

    test('cancelado casi al instante = síntoma de la SHA-1: muestra aviso', () {
      expect(mensajeDeError(cancelado, rapido), contains('SHA-1'));
      expect(
        mensajeDeError(cancelado, umbralCancelacionSha1 - const Duration(milliseconds: 1)),
        contains('SHA-1'),
      );
    });

    test('cancelado después del umbral = el usuario canceló: nada', () {
      expect(mensajeDeError(cancelado, umbralCancelacionSha1), isNull);
      expect(mensajeDeError(cancelado, lento), isNull);
    });

    test('error de configuración es SHA-1 sin importar el tiempo', () {
      const e = GoogleSignInException(code: GoogleSignInExceptionCode.clientConfigurationError);
      expect(mensajeDeError(e, rapido), contains('SHA-1'));
      expect(mensajeDeError(e, lento), contains('SHA-1'));
      expect(mensajeDeError(Exception('ApiException: 10'), lento), contains('SHA-1'));
    });

    test('web: cerrar el popup no muestra nada', () {
      for (final code in ['popup-closed-by-user', 'cancelled-popup-request']) {
        expect(mensajeDeError(FirebaseAuthException(code: code), rapido), isNull, reason: code);
      }
    });

    test('sin red y errores desconocidos', () {
      expect(
        mensajeDeError(FirebaseAuthException(code: 'network-request-failed'), lento),
        contains('Sin conexión'),
      );
      expect(mensajeDeError(Exception('raro'), lento), startsWith('No se pudo iniciar sesión'));
    });
  });
}
