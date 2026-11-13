import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'models/rol.dart';
import 'screens/admin_home.dart';
import 'screens/inicio.dart';
import 'screens/login_screen.dart';
import 'screens/sin_acceso_screen.dart';
import 'services/sesion.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // En Android la caché offline ya viene activada; en web hay que pedirla.
  if (kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  }
  await iniciarGoogleSignIn();
  runApp(const PaseListaApp());
}

class PaseListaApp extends StatelessWidget {
  const PaseListaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaseLista',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const Raiz(),
    );
  }
}

const _cargando = Scaffold(body: Center(child: CircularProgressIndicator()));

class Raiz extends StatelessWidget {
  const Raiz({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return _cargando;
        final user = snap.data;
        if (user == null) return const LoginScreen();
        return _ConSesion(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

class _ConSesion extends StatefulWidget {
  const _ConSesion({super.key, required this.user});
  final User user;

  @override
  State<_ConSesion> createState() => _ConSesionState();
}

class _ConSesionState extends State<_ConSesion> {
  late Future<Map<String, dynamic>?> _usuario = cargarUsuario(widget.user);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _usuario,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _cargando;
        if (snap.hasError) return _errorCarga(snap.error!);
        final usuario = snap.data;
        return switch (decidirPantalla(conSesion: true, usuario: usuario)) {
          Pantalla.profesor => ProfesorHome(usuario: usuario!),
          Pantalla.orden => OrdenHome(usuario: usuario!),
          Pantalla.admin => AdminHome(usuario: usuario!),
          Pantalla.sinAcceso || Pantalla.login => SinAccesoScreen(correo: widget.user.email ?? ''),
        };
      },
    );
  }

  Widget _errorCarga(Object error) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No se pudo cargar tu cuenta.\n$error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => setState(() => _usuario = cargarUsuario(widget.user)),
                child: const Text('Reintentar'),
              ),
              const SizedBox(height: 8),
              const BotonCerrarSesion(),
            ],
          ),
        ),
      ),
    );
  }
}
