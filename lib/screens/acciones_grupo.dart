import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/grupo.dart';
import '../services/grupos.dart';
import 'celda_estado.dart';
import 'inicio.dart';

/// Activa o quita el modo dual de un alumno (admin en la pantalla del grupo, orden en el detalle).
/// Sin `await`: sin internet el Future no se completa (ver CLAUDE.md); solo avisa si falla.
class BotonDual extends StatelessWidget {
  const BotonDual({super.key, required this.grupoId, required this.num, required this.nombre, required this.esDual});
  final String grupoId;
  final int num;
  final String nombre;
  final bool esDual;

  @override
  Widget build(BuildContext context) => IconButton(
        isSelected: esDual,
        tooltip: esDual ? 'Quitar modo dual a $nombre' : 'Activar modo dual a $nombre',
        icon: const Icon(Icons.work_outline),
        selectedIcon: const Icon(Icons.work, color: azulDual),
        onPressed: () => avisarSiFalla(
          context,
          cambiarDual(grupoId, num, !esDual),
          esDual ? 'No se quitó el modo dual a $nombre' : 'No se activó el modo dual a $nombre',
        ),
      );
}

/// Acciones de admin sobre un grupo completo, desde la lista de grupos o desde la pantalla del grupo.
enum AccionGrupo { renombrar, eliminar }

/// Menú "⋮" con Renombrar y Eliminar. [alEliminar] se llama después de borrar el grupo (por ejemplo,
/// para cerrar la pantalla del grupo).
class MenuGrupo extends StatelessWidget {
  const MenuGrupo({
    super.key,
    required this.grupoId,
    required this.nombre,
    this.alEliminar,
    this.enabled = true,
  });
  final String grupoId;
  final String nombre;
  final VoidCallback? alEliminar;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AccionGrupo>(
      enabled: enabled,
      tooltip: 'Opciones del grupo',
      onSelected: (accion) async {
        switch (accion) {
          case AccionGrupo.renombrar:
            await renombrarGrupoConDialogo(context, grupoId, nombre);
          case AccionGrupo.eliminar:
            if (await eliminarGrupoConDialogo(context, grupoId, nombre)) alEliminar?.call();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: AccionGrupo.renombrar,
          child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Renombrar grupo')),
        ),
        PopupMenuItem(
          value: AccionGrupo.eliminar,
          child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar grupo')),
        ),
      ],
    );
  }
}

// Los avisos se toman antes de abrir el diálogo: en la lista del admin, la fila del grupo (y con ella
// este `context`) puede desaparecer mientras el diálogo sigue abierto.

/// Pide el nombre nuevo y lo guarda. Funciona sin internet (se sincroniza después).
Future<void> renombrarGrupoConDialogo(BuildContext context, String id, String nombre) async {
  final avisos = ScaffoldMessenger.of(context);
  final nuevo = await showDialog<String>(
    context: context,
    builder: (_) => _DialogoRenombrar(id: id, nombre: nombre),
  );
  if (nuevo == null) return;
  // Sin `await`: sin internet el Future no se completa (ver CLAUDE.md); solo avisa si falla.
  renombrarGrupo(id, nuevo).catchError((Object e) {
    avisos.showSnackBar(SnackBar(content: Text('No se renombró el grupo $nombre: $e')));
  });
  avisos.showSnackBar(SnackBar(content: Text('Grupo $nombre renombrado a $nuevo.')));
}

/// Confirma y borra el grupo con sus clases y pases. Devuelve `true` si se borró.
Future<bool> eliminarGrupoConDialogo(BuildContext context, String id, String nombre) async {
  final avisos = ScaffoldMessenger.of(context);
  final borrado = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DialogoEliminar(id: id, nombre: nombre),
  );
  if (borrado != true) return false;
  avisos.showSnackBar(SnackBar(content: Text('Grupo $nombre eliminado.')));
  return true;
}

class _DialogoRenombrar extends StatefulWidget {
  const _DialogoRenombrar({required this.id, required this.nombre});
  final String id;
  final String nombre;

  @override
  State<_DialogoRenombrar> createState() => _DialogoRenombrarState();
}

class _DialogoRenombrarState extends State<_DialogoRenombrar> {
  late final _nombre = TextEditingController(text: widget.nombre);
  late final StreamSubscription<void> _sub;

  /// ID → nombre de todos los grupos, para no repetir nombres. Sale de la caché si no hay internet.
  Map<String, String>? _grupos;
  Object? _errorGrupos;
  bool _intentado = false;

  @override
  void initState() {
    super.initState();
    _sub = grupos().listen(
      (s) => setState(() => _grupos = {
            for (final d in s.docs) d.id: '${d.data()['nombre'] ?? d.id}',
          }),
      onError: (Object e) => setState(() => _errorGrupos = e),
    );
  }

  @override
  void dispose() {
    _sub.cancel();
    _nombre.dispose();
    super.dispose();
  }

  String? get _error {
    final grupos = _grupos;
    if (grupos == null) return null;
    return errorRenombrar(widget.id, _nombre.text, grupos);
  }

  void _guardar() {
    setState(() => _intentado = true);
    if (_grupos == null || _error != null) return;
    final nuevo = limpiarNombre(_nombre.text);
    Navigator.pop(context, nuevo == widget.nombre ? null : nuevo);
  }

  @override
  Widget build(BuildContext context) {
    // El error de nombre repetido se ve al escribir; el de vacío, hasta que intenta guardar.
    final error = _errorGrupos != null
        ? 'No se pudo revisar si el nombre ya existe: $_errorGrupos'
        : _intentado || _nombre.text.trim().isNotEmpty
            ? _error
            : null;
    return AlertDialog(
      title: const Text('Renombrar grupo'),
      content: TextField(
        controller: _nombre,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: 'Nombre del grupo',
          helperText: 'Las clases, los pases y el historial siguen ligados al grupo. '
              'El ID interno "${widget.id}" no cambia.',
          helperMaxLines: 3,
          errorText: error,
          errorMaxLines: 3,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _guardar(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _grupos == null || _errorGrupos != null ? null : _guardar,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

enum _Fase { revisando, errorRevisar, confirmar, borrando, errorBorrar }

class _DialogoEliminar extends StatefulWidget {
  const _DialogoEliminar({required this.id, required this.nombre});
  final String id;
  final String nombre;

  @override
  State<_DialogoEliminar> createState() => _DialogoEliminarState();
}

class _DialogoEliminarState extends State<_DialogoEliminar> {
  final _confirmacion = TextEditingController();
  var _fase = _Fase.revisando;
  ContenidoGrupo? _contenido;
  Object? _error;
  double? _avance;

  @override
  void initState() {
    super.initState();
    _revisar();
  }

  @override
  void dispose() {
    _confirmacion.dispose();
    super.dispose();
  }

  Future<void> _revisar() async {
    setState(() => _fase = _Fase.revisando);
    try {
      final contenido = await contenidoDelGrupo(widget.id);
      if (!mounted) return;
      setState(() {
        _contenido = contenido;
        _fase = _Fase.confirmar;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _fase = _Fase.errorRevisar;
      });
    }
  }

  Future<void> _borrar() async {
    final contenido = _contenido;
    if (contenido == null || !confirmaNombre(_confirmacion.text, widget.nombre)) return;
    setState(() {
      _fase = _Fase.borrando;
      _avance = null;
    });
    try {
      await borrarGrupo(
        widget.id,
        contenido,
        progreso: (hechos, total) {
          if (mounted) setState(() => _avance = hechos / total);
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _fase = _Fase.errorBorrar;
      });
    }
  }

  static String _textoError(Object? e) {
    if (e is FirebaseException) {
      switch (e.code) {
        case 'unavailable':
          return 'No hay conexión con el servidor. Para eliminar un grupo necesitas internet: así se '
              'revisan todos sus pases y no queda ninguno suelto.';
        case 'permission-denied':
          return 'El servidor no lo permitió. Revisa que tu cuenta siga siendo de administrativo.';
      }
    }
    return '$e';
  }

  static String _cuantos(int n, String uno, String varios) => n == 1 ? '1 $uno' : '$n $varios';

  @override
  Widget build(BuildContext context) {
    final clases = _contenido?.clases.length ?? 0;
    final pases = _contenido?.pases.length ?? 0;
    final colores = Theme.of(context).colorScheme;
    final (Widget cuerpo, List<Widget> acciones) = switch (_fase) {
      _Fase.revisando => (
          const Row(children: [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
            SizedBox(width: 16),
            Expanded(child: Text('Revisando qué se va a borrar…')),
          ]),
          [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar'))],
        ),
      _Fase.errorRevisar => (
          Text(_textoError(_error)),
          [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cerrar')),
            FilledButton(onPressed: _revisar, child: const Text('Reintentar')),
          ],
        ),
      _Fase.confirmar => (
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Se borrará para siempre el grupo ${widget.nombre} con su lista de alumnos, '
                  '${_cuantos(clases, 'clase', 'clases')} y '
                  '${_cuantos(pases, 'pase de lista', 'pases de lista')} '
                  '(todo su historial de asistencia).'),
              const SizedBox(height: 8),
              Text(
                'No se puede deshacer.',
                style: TextStyle(color: colores.error, fontWeight: FontWeight.bold),
              ),
              if (pases > 0) ...[
                const SizedBox(height: 8),
                const Text('Si necesitas el historial, expórtalo antes desde la vista mensual de '
                    'cada clase.'),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _confirmacion,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Escribe ${widget.nombre} para confirmar',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _borrar(),
              ),
            ],
          ),
          [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colores.error,
                foregroundColor: colores.onError,
              ),
              onPressed: confirmaNombre(_confirmacion.text, widget.nombre) ? _borrar : null,
              child: const Text('Eliminar grupo'),
            ),
          ],
        ),
      _Fase.borrando => (
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: _avance),
              const SizedBox(height: 16),
              const Text('Borrando… No cierres esta ventana. Si se va el internet, sigue sola '
                  'cuando regrese.'),
            ],
          ),
          const <Widget>[],
        ),
      _Fase.errorBorrar => (
          Text('No se terminó de borrar: ${_textoError(_error)}\n\n'
              'Lo que alcanzó a borrarse ya no está. Si el grupo sigue en la lista, vuelve a '
              'eliminarlo para terminar.'),
          [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cerrar'))],
        ),
    };
    return PopScope(
      canPop: _fase != _Fase.borrando,
      child: AlertDialog(
        title: Text('Eliminar grupo ${widget.nombre}'),
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: cuerpo),
        actions: acciones,
      ),
    );
  }
}
