import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/clase.dart';
import '../models/grupo.dart';
import '../services/clases.dart';
import 'inicio.dart';

/// Las clases de un grupo, con su profe y materia, y el alta y el borrado de clases.
/// Va dentro de la pantalla del grupo, así que el grupo de la clase es el que está abierto.
class ClasesDelGrupo extends StatefulWidget {
  const ClasesDelGrupo({super.key, required this.grupoId, required this.nombreGrupo});
  final String grupoId;
  final String nombreGrupo;

  @override
  State<ClasesDelGrupo> createState() => _ClasesDelGrupoState();
}

class _ClasesDelGrupoState extends State<ClasesDelGrupo> {
  QuerySnapshot<Map<String, dynamic>>? _clases, _profesores;
  Object? _error;
  late final List<StreamSubscription<void>> _subs;

  @override
  void initState() {
    super.initState();
    void alFallar(Object e) => setState(() => _error = e);
    _subs = [
      clasesDelGrupo(widget.grupoId).listen((s) => setState(() => _clases = s), onError: alFallar),
      profesores().listen((s) => setState(() => _profesores = s), onError: alFallar),
    ];
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  /// uid → nombre de los usuarios con rol de profesor.
  Map<String, String> get _nombres => {
        for (final d in [...?_profesores?.docs]) d.id: '${d.data()['nombre'] ?? d.data()['email'] ?? d.id}',
      };

  List<Clase> get _lista => ordenarClases(
        [for (final d in [...?_clases?.docs]) ?claseDe(d.data())],
        _nombres,
      );

  Future<void> _darDeAlta() async {
    final clase = await showDialog<Clase>(
      context: context,
      builder: (_) => _DialogoClase(
        grupoId: widget.grupoId,
        nombreGrupo: widget.nombreGrupo,
        profesores: [...?_profesores?.docs],
        conClase: {for (final c in _lista) c.profesorUid},
      ),
    );
    if (clase == null || !mounted) return;
    // Se vuelve a revisar: la lista pudo cambiar con el diálogo abierto, y `set()` reemplazaría.
    if (_lista.any((c) => c.id == clase.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ese profesor ya tiene una clase con este grupo.')),
      );
      return;
    }
    // Sin `await`: sin internet el Future no se completa (ver CLAUDE.md); solo avisa si falla.
    avisarSiFalla(context, darDeAltaClase(clase), 'No se dio de alta la clase de ${clase.materia}');
  }

  Future<void> _confirmarBorrar(Clase clase, String profesor) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar clase'),
        content: Text('$profesor ya no verá la clase de ${clase.materia} con '
            '${widget.nombreGrupo} ni podrá pasarle lista. Los pases ya hechos se conservan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar clase'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    avisarSiFalla(context, borrarClase(clase), 'No se borró la clase de ${clase.materia}');
  }

  @override
  Widget build(BuildContext context) {
    final cargando = _clases == null || _profesores == null;
    final nombres = _nombres;
    final lista = _lista;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Clases', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: cargando || _error != null ? null : _darDeAlta,
          icon: const Icon(Icons.add),
          label: const Text('Dar de alta clase'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Error al cargar las clases: $_error'),
          )
        else if (cargando)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else ...[
          // Un borrado pendiente ya no tiene documento que marcar: se avisa en la consulta.
          if (_clases!.metadata.hasPendingWrites)
            const ListTile(
              leading: Icon(Icons.cloud_upload_outlined),
              title: Text('Hay cambios pendientes de sincronizar'),
            ),
          if (lista.isEmpty)
            const ListTile(title: Text('Este grupo aún no tiene clases.'))
          else
            for (final c in lista)
              ListTile(
                leading: const Icon(Icons.class_outlined),
                title: Text(nombres[c.profesorUid] ?? 'Profesor que ya no tiene acceso'),
                subtitle: Text('${c.materia} · Salón ${c.salon}'),
                trailing: IconButton(
                  tooltip: 'Borrar clase',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmarBorrar(c, nombres[c.profesorUid] ?? 'El profesor'),
                ),
              ),
        ],
      ],
    );
  }
}

/// Pide profesor, materia y salón; devuelve la [Clase] o `null` si se cancela.
class _DialogoClase extends StatefulWidget {
  const _DialogoClase({
    required this.grupoId,
    required this.nombreGrupo,
    required this.profesores,
    required this.conClase,
  });
  final String grupoId;
  final String nombreGrupo;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> profesores;

  /// Profes que ya tienen clase con este grupo: no se pueden elegir (una clase = profe + grupo).
  final Set<String> conClase;

  @override
  State<_DialogoClase> createState() => _DialogoClaseState();
}

class _DialogoClaseState extends State<_DialogoClase> {
  final _materia = TextEditingController();
  final _salon = TextEditingController();
  String? _profesorUid;
  String? _errorProfesor, _errorMateria, _errorSalon;

  @override
  void dispose() {
    _materia.dispose();
    _salon.dispose();
    super.dispose();
  }

  void _aceptar() {
    setState(() {
      _errorProfesor = _profesorUid == null ? 'Elige al profesor.' : null;
      _errorMateria = errorEtiqueta(_materia.text, 'la materia');
      _errorSalon = errorEtiqueta(_salon.text, 'el salón');
    });
    if (_errorProfesor != null || _errorMateria != null || _errorSalon != null) return;
    Navigator.pop(
      context,
      Clase(
        profesorUid: _profesorUid!,
        grupoId: widget.grupoId,
        materia: limpiarNombre(_materia.text),
        salon: limpiarNombre(_salon.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profesores = [...widget.profesores]
      ..sort((a, b) => '${a.data()['nombre']}'.toLowerCase().compareTo('${b.data()['nombre']}'.toLowerCase()));
    return AlertDialog(
      title: Text('Dar de alta clase de ${widget.nombreGrupo}'),
      content: SizedBox(
        width: 400,
        child: profesores.isEmpty
            ? const Text('No hay usuarios con rol de profesor. Invítalos primero con '
                '"Invitar usuario" y pídeles que entren a la app una vez.')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _profesorUid,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: 'Profesor', errorText: _errorProfesor),
                      items: [
                        for (final d in profesores)
                          DropdownMenuItem(
                            value: d.id,
                            enabled: !widget.conClase.contains(d.id),
                            child: Text(
                              [
                                '${d.data()['nombre'] ?? d.data()['email'] ?? d.id}',
                                if (widget.conClase.contains(d.id)) '(ya tiene clase con este grupo)',
                              ].join(' '),
                              overflow: TextOverflow.ellipsis,
                              style: widget.conClase.contains(d.id)
                                  ? TextStyle(color: Theme.of(context).disabledColor)
                                  : null,
                            ),
                          ),
                      ],
                      onChanged: (uid) => setState(() => _profesorUid = uid),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _materia,
                      maxLength: maxEtiqueta,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Materia',
                        hintText: 'Por ejemplo: Matemáticas',
                        errorText: _errorMateria,
                      ),
                    ),
                    TextField(
                      controller: _salon,
                      maxLength: maxEtiqueta,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Salón',
                        hintText: 'Por ejemplo: A1',
                        helperText: 'El de siempre; el profe lo puede corregir al pasar lista.',
                        errorText: _errorSalon,
                      ),
                      onSubmitted: (_) => _aceptar(),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        if (profesores.isNotEmpty)
          FilledButton(onPressed: _aceptar, child: const Text('Dar de alta')),
      ],
    );
  }
}
