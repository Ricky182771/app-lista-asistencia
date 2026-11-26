import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/grupo.dart' show enLotes;
import '../models/rol.dart';
import 'almacen_local.dart' if (dart.library.js_interop) 'almacen_local_web.dart';

final _db = FirebaseFirestore.instance;

/// Android: no se pasa `serverClientId`. El plugin `com.google.gms.google-services` genera el
/// recurso `default_web_client_id` desde google-services.json y `google_sign_in_android` lo toma de ahí.
Future<void> iniciarGoogleSignIn() =>
    kIsWeb ? Future.value() : GoogleSignIn.instance.initialize();

/// Los dos dominios con los que Firebase Hosting sirve la versión web.
const dominiosHosting = {'paselista-9326a.web.app', 'paselista-9326a.firebaseapp.com'};

/// Web: [base] con `authDomain` = el dominio desde el que se abrió la app ([host]).
///
/// El inicio de sesión con Google pasa por `https://{authDomain}/__/auth/handler`. Si ese dominio no es
/// el de la página (la app en `web.app` y el handler en `firebaseapp.com`), Safari en iPhone y otros
/// navegadores que particionan el almacenamiento por sitio no le pasan su estado al handler y Google
/// responde "Unable to process request due to missing initial state". Con el mismo dominio no pasa.
/// Fuera de Hosting (localhost, emulador) se queda el de firebase_options.dart.
/// Cada dominio necesita su `https://{dominio}/__/auth/handler` en los URI de redireccionamiento del
/// cliente OAuth web (ver README).
FirebaseOptions opcionesWeb(FirebaseOptions base, String host) {
  if (!dominiosHosting.contains(host) || host == base.authDomain) return base;
  return FirebaseOptions(
    apiKey: base.apiKey,
    appId: base.appId,
    messagingSenderId: base.messagingSenderId,
    projectId: base.projectId,
    authDomain: host,
    databaseURL: base.databaseURL,
    storageBucket: base.storageBucket,
    measurementId: base.measurementId,
  );
}

const _claveCompartida = 'paselista.computadoraCompartida';

/// Web: sin nada guardado cuenta como compartida (lo más seguro en un laboratorio).
bool esCompartida(String? guardado) => guardado != 'no';

bool computadoraCompartida() => esCompartida(leerLocal(_claveCompartida));

void guardarComputadoraCompartida(bool compartida) =>
    guardarLocal(_claveCompartida, compartida ? 'si' : 'no');

/// Compartida: la sesión dura lo que la pestaña y la caché de Firestore vive solo en memoria.
({Persistence auth, bool cacheEnDisco}) configuracionWeb(bool compartida) => compartida
    ? (auth: Persistence.SESSION, cacheEnDisco: false)
    : (auth: Persistence.LOCAL, cacheEnDisco: true);

/// Web, en `main()` antes de cualquier uso de Firestore.
Future<void> configurarWeb() async {
  final config = configuracionWeb(computadoraCompartida());
  // Pasa a sesión de pestaña también a quien ya había entrado antes de este cambio.
  await FirebaseAuth.instance.setPersistence(config.auth);
  // Primero `settings`: la instancia de Firestore se crea en el primer uso, y `clearPersistence()` ya cuenta.
  _db.settings = Settings(persistenceEnabled: config.cacheEnDisco);
  if (config.cacheEnDisco) return;
  try {
    // Borra lo que dejó en IndexedDB alguien que entró sin la casilla. Si otra pestaña tiene la base
    // abierta, el borrado se queda esperando: mejor seguir que dejar la app cargando.
    await _db.clearPersistence().timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint('No se pudo borrar la caché de Firestore: $e');
  }
}

/// Solo pide `openid email profile` (lo que Google da por defecto).
/// Web: la persistencia de Auth ya la fijó `LoginScreen` con la casilla "Computadora compartida".
Future<void> entrarConGoogle() async {
  if (kIsWeb) {
    // Sin ningún `await` antes: Safari bloquea la ventana emergente si no se abre justo al tocar el botón.
    // Siempre pregunta la cuenta: en los laboratorios hay varias en el mismo Chrome.
    await FirebaseAuth.instance.signInWithPopup(
        GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'}));
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

/// Escucha `usuarios/{uid}` (sin internet sale de la caché). Si no existe al entrar, hace el alta por
/// invitación con [cargarUsuario]; si desaparece después (le quitaron el acceso), emite `null`.
Stream<Map<String, dynamic>?> escucharUsuario(User user) async* {
  var primero = true;
  await for (final doc in _db.doc('usuarios/${user.uid}').snapshots()) {
    if (doc.exists) {
      yield doc.data();
    } else {
      yield primero ? await cargarUsuario(user) : null;
    }
    primero = false;
  }
}

/// Sin `await` a propósito: sin internet el Future no se completa (ver CLAUDE.md).
/// Lo pendiente se ve con `metadata.hasPendingWrites` en [invitaciones].
Future<void> invitar(String correo, Rol rol) =>
    _db.doc('invitaciones/${normalizarCorreo(correo)}').set({
      'rol': rol.name,
      'creadoPor': FirebaseAuth.instance.currentUser!.uid,
    });

/// Invita a varias personas a la vez (Herramientas avanzadas), en lotes de 400 (límite de un
/// `WriteBatch`: 500). Una invitación que ya existía se reescribe con el rol nuevo. Devuelve un
/// Future por lote; sin `await` a propósito (ver [invitar]).
List<Future<void>> invitarVarios(List<({String correo, Rol rol})> personas) {
  final yo = FirebaseAuth.instance.currentUser!.uid;
  final lotes = <Future<void>>[];
  for (final lote in enLotes(personas, 400)) {
    final batch = _db.batch();
    for (final p in lote) {
      batch.set(_db.doc('invitaciones/${normalizarCorreo(p.correo)}'), {
        'rol': p.rol.name,
        'creadoPor': yo,
      });
    }
    lotes.add(batch.commit());
  }
  return lotes;
}

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

/// Cambia el rol del usuario y el de su invitación en el mismo `WriteBatch`: si solo cambiara el
/// usuario y alguien borrara su documento a mano, volvería a darse de alta con el rol viejo. La
/// invitación se escribe con `merge` porque el primer admin (creado a mano en la consola) puede no
/// tener. El usuario ve su pantalla nueva al instante: `escucharUsuario` emite el cambio.
/// Sin `await` a propósito (ver [invitar]). Quien llama revisa antes con `errorCambioRol`.
Future<void> cambiarRol(String uid, String correo, Rol rol) {
  final batch = _db.batch()..update(_db.doc('usuarios/$uid'), {'rol': rol.name});
  // Un usuario creado a mano en la consola puede no tener `email`.
  final c = normalizarCorreo(correo);
  if (c.isNotEmpty) {
    batch.set(_db.doc('invitaciones/$c'), {'rol': rol.name}, SetOptions(merge: true));
  }
  return batch.commit();
}

/// Para invitaciones que nadie ha usado. Sin `await` a propósito (ver [invitar]).
Future<void> cancelarInvitacion(String correo) =>
    _db.doc('invitaciones/${normalizarCorreo(correo)}').delete();

/// Sin `orderBy`: ocultaría los documentos sin `nombre` (el primer admin se crea a mano).
Stream<QuerySnapshot<Map<String, dynamic>>> usuarios() =>
    _db.collection('usuarios').snapshots(includeMetadataChanges: true);
