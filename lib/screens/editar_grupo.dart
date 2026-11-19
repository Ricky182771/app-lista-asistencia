import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/grupo.dart';
import '../services/grupos.dart';
import 'acciones_grupo.dart';
import 'clases_grupo.dart';
import 'importar_csv.dart';
import 'inicio.dart';

/// Un grupo: sus clases y su lista de alumnos, con reemplazo por CSV y edición a mano. Desde el menú
/// de la barra se renombra o se elimina el grupo completo (ver `acciones_grupo.dart`).
/// No hay forma de borrar a un alumno: se da de baja y conserva su N.L y su historial.
class EditarGrupo extends StatefulWidget {
  const EditarGrupo({super.key, required this.grupoId, required this.nombre});
  final String grupoId;

  /// El nombre que se veía en la lista, para el título mientras carga.
  final String nombre;

  @override
  State<EditarGrupo> createState() => _EditarGrupoState();
}

class _EditarGrupoState extends State<EditarGrupo> {
  late final StreamSubscription<void> _sub;
  DocumentSnapshot<Map<String, dynamic>>? _grupo;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _sub = grupo(widget.grupoId).listen(
      (d) => setState(() => _grupo = d),
      onError: (Object e) => setState(() => _error = e),
    );
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  String get _nombre => '${_grupo?.data()?['nombre'] ?? widget.nombre}';
  List<Alumno> get _alumnos => alumnosDe(_grupo?.data()?['alumnos']);

  /// Con entradas sin reconocer no se edita: guardar reescribiría la lista sin ellas.
  bool get _editable => sinReconocer(_grupo?.data()?['alumnos']) == 0;

  /// Sin `await`: sin internet el Future no se completa (ver CLAUDE.md); solo avisa si falla.
  void _guardar(List<Alumno> alumnos, String siFalla) =>
      avisarSiFalla(context, guardarAlumnos(widget.grupoId, alumnos), siFalla);

  Future<void> _agregar() async {
    if (!_editable) return;
    final num = siguienteNum(_alumnos);
    final nombre = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoNombre(titulo: 'Agregar alumno', ayuda: 'Tendrá el N.L $num.'),
    );
    if (nombre == null || !mounted || !_editable) return;
    // Se vuelve a leer la lista: pudo cambiar mientras el diálogo estaba abierto.
    _guardar(agregarAlumno(_alumnos, nombre), 'No se agregó a $nombre');
  }

  Future<void> _corregir(Alumno a) async {
    final nombre = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoNombre(
        titulo: 'Corregir nombre',
        ayuda: 'N.L ${a.num}. Solo para corregir cómo está escrito: el número sigue siendo '
            'de la misma persona.',
        inicial: a.nombre,
      ),
    );
    if (nombre == null || nombre == a.nombre || !mounted || !_editable) return;
    _guardar(corregirNombre(_alumnos, a.num, nombre), 'No se corrigió el nombre del N.L ${a.num}');
  }

  void _cambiarActivo(Alumno a, bool activo) {
    if (!_editable) return;
    _guardar(
      cambiarActivo(_alumnos, a.num, activo),
      activo ? 'No se reactivó a ${a.nombre}' : 'No se dio de baja a ${a.nombre}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = _grupo;
    return Scaffold(
      appBar: AppBar(
        title: Text(_nombre),
        actions: [
          MenuGrupo(
            grupoId: widget.grupoId,
            nombre: _nombre,
            enabled: doc != null && doc.exists,
            // Borrado el grupo, esta pantalla ya no tiene nada que mostrar.
            alEliminar: () {
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text('Error al cargar: $_error'))
          : doc == null
              ? const Center(child: CircularProgressIndicator())
              : !doc.exists
                  ? const Center(child: Text('Este grupo ya no existe.'))
                  : _lista(context, doc),
    );
  }

  Widget _lista(BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc) {
    final alumnos = _alumnos;
    final activos = alumnos.where((a) => a.activo).length;
    final bajas = alumnos.length - activos;
    final gris = Theme.of(context).colorScheme.outline;
    final editable = _editable;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!editable)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              avisoSinReconocer,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ClasesDelGrupo(grupo: doc, nombreGrupo: _nombre),
        const SizedBox(height: 16),
        Text('Alumnos', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text([
          activos == 1 ? '1 alumno activo' : '$activos alumnos activos',
          if (bajas > 0) bajas == 1 ? '1 dado de baja' : '$bajas dados de baja',
        ].join(' · ')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: editable ? _agregar : null,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Agregar alumno'),
            ),
            OutlinedButton.icon(
              onPressed: !editable
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ImportarCsv.reemplazar(
                            grupoId: widget.grupoId,
                            nombreGrupo: _nombre,
                          ),
                        ),
                      ),
              icon: const Icon(Icons.upload_file),
              label: const Text('Reemplazar lista (CSV)'),
            ),
          ],
        ),
        if (doc.metadata.hasPendingWrites)
          const ListTile(
            leading: Icon(Icons.cloud_upload_outlined),
            title: Text('Hay cambios pendientes de sincronizar'),
          ),
        const SizedBox(height: 8),
        if (alumnos.isEmpty) const ListTile(title: Text('Este grupo no tiene alumnos.')),
        for (final a in alumnos)
          ListTile(
            leading: SizedBox(
              width: 32,
              child: Text('${a.num}', style: a.activo ? null : TextStyle(color: gris)),
            ),
            title: Text(a.nombre, style: a.activo ? null : TextStyle(color: gris)),
            subtitle: a.activo ? null : const Text('Dado de baja'),
            trailing: PopupMenuButton<void Function()>(
              enabled: editable,
              tooltip: 'Opciones',
              onSelected: (accion) => accion(),
              itemBuilder: (_) => [
                PopupMenuItem(value: () => _corregir(a), child: const Text('Corregir nombre')),
                PopupMenuItem(
                  value: () => _cambiarActivo(a, !a.activo),
                  child: Text(a.activo ? 'Dar de baja' : 'Reactivar'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Pide un nombre de alumno; devuelve el nombre limpio o `null` si se cancela.
class _DialogoNombre extends StatefulWidget {
  const _DialogoNombre({required this.titulo, required this.ayuda, this.inicial = ''});
  final String titulo;
  final String ayuda;
  final String inicial;

  @override
  State<_DialogoNombre> createState() => _DialogoNombreState();
}

class _DialogoNombreState extends State<_DialogoNombre> {
  late final _nombre = TextEditingController(text: widget.inicial);
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  void _aceptar() {
    final nombre = limpiarNombre(_nombre.text);
    if (nombre.isEmpty) {
      setState(() => _error = 'Escribe el nombre completo.');
      return;
    }
    Navigator.pop(context, nombre);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: TextField(
        controller: _nombre,
        autofocus: true,
        maxLength: 100,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: 'Nombre completo',
          helperText: widget.ayuda,
          helperMaxLines: 3,
          errorText: _error,
        ),
        onSubmitted: (_) => _aceptar(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _aceptar, child: const Text('Guardar')),
      ],
    );
  }
}
