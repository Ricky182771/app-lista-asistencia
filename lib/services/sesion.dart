import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/rol.dart';

final _db = FirebaseFirestore.instance;

/// Android: no se pasa `serverClientId`. El plugin `com.google.gms.google-services` genera el
/// recurso `default_web_client_id` desde google-services.json y `google_sign_in_android` lo toma de ahí.
Future<void> iniciarGoogleSignIn() =>
    kIsWeb ? Future.value() : GoogleSignIn.instance.initialize();

/// Solo pide `openid email profile` (lo que Google da por defecto).
Future<void> entrarConGoogle() async {
  if (kIsWeb) {
    await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
    return;
  }
  final cuenta = await GoogleSignIn.instance.authenticate();
  final idToken = cuenta.authentication.idToken;
  await FirebaseAuth.instance
      .signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
}

Future<void> cerrarSesion() async {
  await FirebaseAuth.instance.signOut();
  if (!kIsWeb) await GoogleSignIn.instance.signOut();
}

/// Un "cancelado" más rápido que esto no lo hizo el usuario: es el síntoma de la SHA-1 faltante.
const umbralCancelacionSha1 = Duration(milliseconds: 1500);

/// Mensaje para el usuario, o `null` si solo canceló.
/// [duracion] = tiempo entre tocar "Entrar con Google" y recibir el error.
String? mensajeDeError(Object e, Duration duracion) {
  final texto = e.toString();
  // Credential Manager no siempre usa el mismo código para "falta la SHA-1"; ver README.
  final esSha1 = texto.contains('ApiException: 10') ||
      texto.contains('28444') ||
      texto.contains('Developer console is not set up correctly') ||
      (e is GoogleSignInException &&
          e.code == GoogleSignInExceptionCode.clientConfigurationError);
  if (esSha1) {
    return 'Google rechazó esta instalación de la app (ApiException: 10). '
        'Casi siempre es porque la huella SHA-1 de la computadora que compiló la app '
        'no está registrada en Firebase. Pídele a Ricardo que la agregue '
        '(instrucciones en el README).';
  }
  if (e is GoogleSignInException && e.code == GoogleSignInExceptionCode.canceled) {
    // En Android una SHA-1 faltante a veces llega como "cancelado" (README de google_sign_in_android),
    // pero casi al instante: el usuario no alcanza a ver el selector de cuentas.
    if (duracion >= umbralCancelacionSha1) return null;
    return 'Google cerró el inicio de sesión antes de que pudieras elegir tu cuenta. '
        'Probablemente falta registrar la SHA-1 de esta compilación (ver README).';
  }
  if (e is FirebaseAuthException &&
      (e.code == 'popup-closed-by-user' || e.code == 'cancelled-popup-request')) {
    return null;
  }
  if (e is FirebaseAuthException && e.code == 'network-request-failed') {
    return 'Sin conexión. Revisa tu internet e intenta de nuevo.';
  }
  return 'No se pudo iniciar sesión: $texto';
}

/// Devuelve `usuarios/{uid}`; si no existe y hay invitación, lo crea con el rol invitado.
/// `null` = sin invitación.
Future<Map<String, dynamic>?> cargarUsuario(User user) async {
  final ref = _db.doc('usuarios/${user.uid}');
  final doc = await ref.get();
  if (doc.exists) return doc.data();

  final correo = normalizarCorreo(user.email ?? '');
  if (correo.isEmpty) return null;
  final inv = await _db.doc('invitaciones/$correo').get();
  if (!inv.exists) return null;

  // Las reglas piden nombre de 1 a 100 caracteres.
  final nombre = user.displayName?.trim() ?? '';
  final usuario = <String, dynamic>{
    'nombre': String.fromCharCodes((nombre.isEmpty ? correo : nombre).runes.take(100)),
    'email': correo,
    'fotoUrl': user.photoURL,
    'rol': inv.data()!['rol'],
  };
  // Aquí sí se espera: el primer inicio siempre es con internet (lo pide Google)
  // y hay que saber si las reglas aceptaron el alta antes de mostrar el inicio.
  await ref.set(usuario);
  return usuario;
}

/// Sin `await` a propósito: sin internet el Future no se completa (ver CLAUDE.md).
/// Lo pendiente se ve con `metadata.hasPendingWrites` en [invitaciones].
Future<void> invitar(String correo, Rol rol) =>
    _db.doc('invitaciones/${normalizarCorreo(correo)}').set({
      'rol': rol.name,
      'creadoPor': FirebaseAuth.instance.currentUser!.uid,
    });

Stream<QuerySnapshot<Map<String, dynamic>>> invitaciones() =>
    _db.collection('invitaciones').snapshots(includeMetadataChanges: true); // ordenadas por correo (id)

/// Borra el usuario y su invitación juntos; si quedara la invitación, se daría de alta solo otra vez.
/// Sin `await` a propósito (ver [invitar]); lo pendiente se ve en [usuarios] e [invitaciones].
Future<void> quitarAcceso(String uid, String correo) {
  final batch = _db.batch()..delete(_db.doc('usuarios/$uid'));
  // Un usuario creado a mano en la consola puede no tener `email`.
  if (normalizarCorreo(correo).isNotEmpty) {
    batch.delete(_db.doc('invitaciones/${normalizarCorreo(correo)}'));
  }
  return batch.commit();
}

/// Para invitaciones que nadie ha usado. Sin `await` a propósito (ver [invitar]).
Future<void> cancelarInvitacion(String correo) =>
    _db.doc('invitaciones/${normalizarCorreo(correo)}').delete();

/// Sin `orderBy`: ocultaría los documentos sin `nombre` (el primer admin se crea a mano).
Stream<QuerySnapshot<Map<String, dynamic>>> usuarios() =>
    _db.collection('usuarios').snapshots(includeMetadataChanges: true);
