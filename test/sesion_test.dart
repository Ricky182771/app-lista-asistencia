import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:app_lista_asistencia/services/sesion.dart';

void main() {
  group('opcionesWeb', () {
    const base = FirebaseOptions(
      apiKey: 'clave',
      appId: 'app',
      messagingSenderId: '1',
      projectId: 'paselista-9326a',
      authDomain: 'paselista-9326a.firebaseapp.com',
      storageBucket: 'cubeta',
    );

    test('en web.app el inicio de sesión usa web.app y lo demás no cambia', () {
      final o = opcionesWeb(base, 'paselista-9326a.web.app');
      expect(o.authDomain, 'paselista-9326a.web.app');
      expect(
        [o.apiKey, o.appId, o.messagingSenderId, o.projectId, o.storageBucket],
        [base.apiKey, base.appId, base.messagingSenderId, base.projectId, base.storageBucket],
      );
    });

    test('en firebaseapp.com se queda igual', () {
      expect(opcionesWeb(base, 'paselista-9326a.firebaseapp.com'), same(base));
    });

    test('fuera de Hosting (localhost, otro dominio) se queda igual', () {
      expect(opcionesWeb(base, 'localhost'), same(base));
      expect(opcionesWeb(base, 'otro.web.app'), same(base));
    });
  });

  group('computadora compartida (web)', () {
    test('sin nada guardado o con cualquier valor que no sea "no" cuenta como compartida', () {
      expect(esCompartida(null), isTrue);
      expect(esCompartida('si'), isTrue);
      expect(esCompartida(''), isTrue);
      expect(esCompartida('no'), isFalse);
    });

    test('compartida: sesión de pestaña y caché solo en memoria', () {
      final config = configuracionWeb(true);
      expect(config.auth, Persistence.SESSION);
      expect(config.cacheEnDisco, isFalse);
    });

    test('no compartida: sesión recordada y caché en disco, como antes', () {
      final config = configuracionWeb(false);
      expect(config.auth, Persistence.LOCAL);
      expect(config.cacheEnDisco, isTrue);
    });
  });

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
