import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/clase.dart' show claseDe, nombresDesactualizados;
import '../models/rol.dart';
import '../services/clases.dart' show ponerNombresDeProfes;
import '../services/grupos.dart';
import '../services/pases.dart' show todasLasClases;
import '../services/sesion.dart';
import 'acciones_grupo.dart';
import 'aviso_actualizacion.dart';
import 'datos_prueba.dart';
import 'editar_grupo.dart';
import 'importar_csv.dart';
import 'inicio.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key, required this.usuario});
  final Map<String, dynamic> usuario;

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

/// Inicio del admin en dos pestañas: Grupos (y sus clases) y Usuarios (con las invitaciones que
/// aún nadie usa). La cuenta y cerrar sesión van en el menú del avatar, arriba a la derecha.
class _AdminHomeState extends State<AdminHome> {
  final _miUid = FirebaseAuth.instance.currentUser?.uid;
  // Suscripciones en el estado: cada pestaña construye su lista al abrirse y un StreamBuilder
  // creado tarde se perdería el primer snapshot.
  QuerySnapshot<Map<String, dynamic>>? _usuarios, _invitaciones, _grupos;
  Object? _errorUsuarios, _errorInvitaciones, _errorGrupos;
  QuerySnapshot<Map<String, dynamic>>? _clases;
  late final List<StreamSubscription<void>> _subs;

  /// Filtro de la pestaña Usuarios; `null` = todos los roles.
  Rol? _filtro;

  @override
  void initState() {
    super.initState();
    _subs = [
      usuarios().listen(
        (s) {
          setState(() => _usuarios = s);
          _ponerAlDiaNombres();
        },
        onError: (Object e) => setState(() => _errorUsuarios = e),
      ),
      // Solo para poner al día `clases.profesorNombre`; si falla, la app sigue igual.
      // También da el número de clases de cada grupo; si falla, la pestaña Grupos no lo muestra.
      todasLasClases().listen((s) {
        setState(() => _clases = s);
        _ponerAlDiaNombres();
      }, onError: (Object _) {}),
      invitaciones().listen(
        (s) => setState(() => _invitaciones = s),
        onError: (Object e) => setState(() => _errorInvitaciones = e),
      ),
      grupos().listen(
        (s) => setState(() => _grupos = s),
        onError: (Object e) => setState(() => _errorGrupos = e),
      ),
    ];
  }

  /// El encargado de orden ve el nombre del profe en `clases.profesorNombre` (no puede leer
  /// `usuarios`). Aquí se llena en las clases viejas y se corrige si el profe cambió de nombre. Espera
  /// a que los usuarios lleguen del servidor para no escribir un nombre viejo de la caché. Sin `await`:
  /// la escritura local se ve al instante en `_clases`, así que no se repite.
  void _ponerAlDiaNombres() {
    final usuarios = _usuarios, clases = _clases;
    if (usuarios == null || clases == null || usuarios.metadata.isFromCache) return;
    final cambios = nombresDesactualizados(
      [for (final d in clases.docs) ?claseDe(d.id, d.data())],
      {for (final d in usuarios.docs) d.id: '${d.data()['nombre'] ?? ''}'},
    );
    if (cambios.isEmpty) return;
    for (final lote in ponerNombresDeProfes(cambios)) {
      avisarSiFalla(context, lote, 'No se actualizó el nombre del profesor en sus clases');
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usuarios = [...?_usuarios?.docs]
      ..sort((a, b) => '${a.data()['nombre']}'.compareTo('${b.data()['nombre']}'));
    // Sin la lista de usuarios no se sabe cuáles invitaciones ya se usaron: no se muestra ninguna.
    final sinUsar = _usuarios == null
        ? <String>{}
        : invitacionesSinUsar(
            [for (final d in [...?_invitaciones?.docs]) d.id],
            [for (final d in usuarios) '${d.data()['email'] ?? ''}'],
          );
    final pendientes = [
      for (final d in [...?_invitaciones?.docs])
        if (sinUsar.contains(d.id)) d,
    ]..sort((a, b) => a.id.compareTo(b.id));
    final grupos = [...?_grupos?.docs]
      ..sort((a, b) => '${a.data()['nombre'] ?? a.id}'.compareTo('${b.data()['nombre'] ?? b.id}'));
    final clasesPorGrupo = <String, int>{};
    for (final c in [...?_clases?.docs]) {
      final g = '${c.data()['grupoId']}';
      clasesPorGrupo[g] = (clasesPorGrupo[g] ?? 0) + 1;
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PaseLista'),
          actions: [_MenuCuenta(usuario: widget.usuario), const SizedBox(width: 8)],
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Grupos'),
              Tab(
                child: Badge(
                  isLabelVisible: pendientes.isNotEmpty,
                  label: Text('${pendientes.length}'),
                  offset: const Offset(14, -6),
                  child: const Text('Usuarios'),
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: AvisoActualizacionTarjeta(),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _pestana('grupos', [
                    const BotonDatosPrueba(), // solo en depuración
                    _boton(
                      icono: Icons.upload_file,
                      texto: 'Importar lista (CSV)',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => const ImportarCsv()),
                      ),
                    ),
                    const _Ayuda('Toca un grupo para ver sus alumnos y darle de alta sus clases.'),
                    ..._seccion(_grupos, _errorGrupos, 'Aún no hay grupos.', [
                      for (final d in grupos) _filaGrupo(d, clasesPorGrupo[d.id]),
                    ]),
                  ]),
                  _pestana('usuarios', _pestanaUsuarios(usuarios, pendientes)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Invitar, filtro por rol, las invitaciones que esperan su primer inicio de sesión (se pueden
  /// cancelar) y los usuarios con acceso. Al entrar por primera vez, la persona deja de estar en
  /// "Esperando…" y aparece en "Con acceso".
  List<Widget> _pestanaUsuarios(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> usuarios,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> pendientes,
  ) {
    bool pasa(Object? rol) => _filtro == null || parseRol(rol) == _filtro;
    int cuantos(Rol? r) => [...usuarios, ...pendientes]
        .where((d) => r == null || parseRol(d.data()['rol']) == r)
        .length;
    final titulo = Theme.of(context).textTheme.titleSmall;
    final usuariosFiltrados = [for (final d in usuarios) if (pasa(d.data()['rol'])) d];
    final pendientesFiltrados = [for (final d in pendientes) if (pasa(d.data()['rol'])) d];
    final nombreFiltro = _filtro?.plural.toLowerCase();

    return [
      _boton(icono: Icons.person_add, texto: 'Invitar usuario', onPressed: _invitar),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final r in <Rol?>[null, ...Rol.values])
            ChoiceChip(
              label: Text('${r?.plural ?? 'Todos'} (${cuantos(r)})'),
              selected: _filtro == r,
              onSelected: (_) => setState(() => _filtro = r),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (_errorInvitaciones != null) Text('Error al cargar las invitaciones: $_errorInvitaciones'),
      if (pendientesFiltrados.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Esperando su primer inicio de sesión (${pendientesFiltrados.length})', style: titulo),
        ),
        const _Ayuda('Ya pueden entrar con su cuenta de Google. Si te equivocaste de correo, cancela '
            'la invitación.'),
        for (final d in pendientesFiltrados) _filaInvitacion(d),
        const SizedBox(height: 8),
      ],
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('Con acceso${_usuarios == null ? '' : ' (${usuariosFiltrados.length})'}', style: titulo),
      ),
      ..._seccion(
        _usuarios,
        _errorUsuarios,
        nombreFiltro == null ? 'Aún no hay usuarios.' : 'No hay $nombreFiltro con acceso.',
        [for (final d in usuariosFiltrados) _filaUsuario(d)],
      ),
    ];
  }

  void _invitar() => showDialog<void>(context: context, builder: (_) => const _DialogoInvitar());

  /// Una pestaña: su propia lista, que recuerda hasta dónde bajaste al cambiar de pestaña.
  Widget _pestana(String clave, List<Widget> children) => ListView(
        key: PageStorageKey(clave),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: children,
      );

  Widget _boton({required IconData icono, required String texto, required VoidCallback onPressed}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(onPressed: onPressed, icon: Icon(icono), label: Text(texto)),
        ),
      );

  Widget _filaInvitacion(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    return ListTile(
      leading: Icon(d.metadata.hasPendingWrites ? Icons.cloud_upload_outlined : Icons.mail_outline),
      title: Text(d.id),
      subtitle: Text([
        parseRol(d.data()['rol'])?.etiqueta ?? '${d.data()['rol']}',
        'aún no entra',
        if (d.metadata.hasPendingWrites) 'pendiente de sincronizar',
      ].join(' · ')),
      trailing: IconButton(
        tooltip: 'Cancelar invitación',
        icon: const Icon(Icons.close),
        onPressed: () => _avisarSiFalla(
          cancelarInvitacion(d.id),
          'No se canceló la invitación de ${d.id}',
        ),
      ),
    );
  }

  /// [clases]: cuántas clases tiene dadas de alta; `null` si aún no se cargan.
  Widget _filaGrupo(QueryDocumentSnapshot<Map<String, dynamic>> d, int? clases) {
    final alumnos = d.data()['alumnos'];
    final activos = alumnos is List
        ? alumnos.where((a) => a is Map && a['activo'] != false).length
        : 0;
    final nombre = '${d.data()['nombre'] ?? d.id}';
    return ListTile(
      leading: Icon(
        d.metadata.hasPendingWrites ? Icons.cloud_upload_outlined : Icons.groups_outlined,
      ),
      title: Text(nombre),
      subtitle: Text([
        activos == 1 ? '1 alumno' : '$activos alumnos',
        if (_clases != null) clases == 1 ? '1 clase' : '${clases ?? 0} clases',
        if (d.metadata.hasPendingWrites) 'pendiente de sincronizar',
      ].join(' · ')),
      trailing: MenuGrupo(grupoId: d.id, nombre: nombre),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => EditarGrupo(grupoId: d.id, nombre: nombre)),
      ),
    );
  }

  /// Carga, error, vacío o las filas; con aviso si hay cambios sin sincronizar.
  List<Widget> _seccion(
    QuerySnapshot<Map<String, dynamic>>? snap,
    Object? error,
    String vacia,
    List<Widget> filas,
  ) {
    if (error != null) return [Text('Error al cargar: $error')];
    if (snap == null) {
      return const [
        Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      ];
    }
    return [
      // Un borrado pendiente ya no tiene documento que marcar: se avisa en la consulta.
      if (snap.metadata.hasPendingWrites)
        const ListTile(
          leading: Icon(Icons.cloud_upload_outlined),
          title: Text('Hay cambios pendientes de sincronizar'),
        ),
      if (filas.isEmpty) ListTile(title: Text(vacia)) else ...filas,
    ];
  }

  Widget _filaUsuario(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final datos = d.data();
    final nombre = '${datos['nombre'] ?? ''}';
    final correo = '${datos['email'] ?? ''}';
    final soyYo = d.id == _miUid;
    return ListTile(
      leading: Avatar(fotoUrl: datos['fotoUrl'] as String?, nombre: nombre),
      title: Text(nombre),
      subtitle: Text([
        correo,
        parseRol(datos['rol'])?.etiqueta ?? '${datos['rol']}',
        if (d.metadata.hasPendingWrites) 'pendiente de sincronizar',
      ].join(' · ')),
      trailing: TextButton(
        // Un admin no puede quitarse el acceso a sí mismo.
        onPressed: soyYo ? null : () => _confirmarQuitar(d.id, nombre, correo),
        child: const Text('Quitar acceso'),
      ),
    );
  }

  Future<void> _confirmarQuitar(String uid, String nombre, String correo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar acceso'),
        content: Text('$nombre ($correo) ya no podrá entrar a PaseLista '
            'hasta que lo vuelvas a invitar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitar acceso'),
          ),
        ],
      ),
    );
    if (ok == true) _avisarSiFalla(quitarAcceso(uid, correo), 'No se quitó el acceso a $correo');
  }

  /// Sin `await`: sin internet el Future no se completa (ver CLAUDE.md); solo avisa si falla.
  void _avisarSiFalla(Future<void> escritura, String mensaje) {
    final avisos = ScaffoldMessenger.of(context);
    escritura.catchError((Object e) {
      avisos.showSnackBar(SnackBar(content: Text('$mensaje: $e')));
    });
  }
}

/// Texto de ayuda chico al principio de cada pestaña.
class _Ayuda extends StatelessWidget {
  const _Ayuda(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          texto,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
}

/// Avatar en la barra de arriba: abre un menú con nombre, correo, rol y cerrar sesión.
class _MenuCuenta extends StatelessWidget {
  const _MenuCuenta({required this.usuario});
  final Map<String, dynamic> usuario;

  @override
  Widget build(BuildContext context) {
    final nombre = '${usuario['nombre'] ?? ''}';
    return PopupMenuButton<void>(
      tooltip: 'Tu cuenta',
      itemBuilder: (_) => [
        PopupMenuItem<void>(
          enabled: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(nombre),
            subtitle: Text([
              '${usuario['email'] ?? ''}',
              parseRol(usuario['rol'])?.etiqueta ?? '',
            ].where((t) => t.isNotEmpty).join('\n')),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<void>(
          onTap: cerrarSesion,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Cerrar sesión'),
          ),
        ),
      ],
      child: Avatar(fotoUrl: usuario['fotoUrl'] as String?, nombre: nombre),
    );
  }
}

class _DialogoInvitar extends StatefulWidget {
  const _DialogoInvitar();

  @override
  State<_DialogoInvitar> createState() => _DialogoInvitarState();
}

class _DialogoInvitarState extends State<_DialogoInvitar> {
  final _correo = TextEditingController();
  Rol _rol = Rol.profesor;
  String? _error;

  @override
  void dispose() {
    _correo.dispose();
    super.dispose();
  }

  void _guardar() {
    final correo = normalizarCorreo(_correo.text);
    if (!RegExp(r'^[^@\s/]+@[^@\s/]+\.[^@\s/]+$').hasMatch(correo)) {
      setState(() => _error = 'Escribe un correo válido.');
      return;
    }
    final avisos = ScaffoldMessenger.of(context);
    invitar(correo, _rol).catchError((Object e) {
      avisos.showSnackBar(SnackBar(content: Text('No se guardó la invitación de $correo: $e')));
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invitar usuario'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _correo,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'Correo de Google', errorText: _error),
            onSubmitted: (_) => _guardar(),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<Rol>(
            initialValue: _rol,
            decoration: const InputDecoration(labelText: 'Rol'),
            items: [
              for (final r in Rol.values) DropdownMenuItem(value: r, child: Text(r.etiqueta)),
            ],
            onChanged: (r) => setState(() => _rol = r!),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Invitar')),
      ],
    );
  }
}
