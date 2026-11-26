import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/clase.dart';
import '../models/exportar.dart';
import '../models/grupo.dart';
import '../models/xlsx.dart' show mimeXlsx;
import '../services/clases.dart';
import '../services/pases.dart' show pasesDelGrupo;
import 'inicio.dart';
import 'lote_comun.dart' show confirmarLote;
import 'pase_mensual.dart';

/// Las clases de un grupo, con su profe y materia, y el alta, la edición y el borrado de clases.
/// Va dentro de la pantalla del grupo, así que el grupo de la clase es el que está abierto.
/// Cada clase abre también su vista mensual en solo consulta.
class ClasesDelGrupo extends StatefulWidget {
  const ClasesDelGrupo({super.key, required this.grupo, required this.nombreGrupo});

  /// El grupo abierto; la vista mensual toma de aquí la lista de alumnos.
  final DocumentSnapshot<Map<String, dynamic>> grupo;
  final String nombreGrupo;

  String get grupoId => grupo.id;

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
        [for (final d in [...?_clases?.docs]) ?claseDe(d.id, d.data())],
        _nombres,
      );

  /// Alta si [editar] es `null`; si no, corrige la materia y el salón de esa clase.
  Future<void> _abrirDialogo([Clase? editar]) async {
    final clase = await showDialog<Clase>(
      context: context,
      builder: (_) => _DialogoClase(
        grupoId: widget.grupoId,
        nombreGrupo: widget.nombreGrupo,
        profesores: [...?_profesores?.docs],
        clases: _lista,
        editar: editar,
      ),
    );
    if (clase == null || !mounted) return;
    // Se vuelve a revisar: la lista pudo cambiar con el diálogo abierto.
    if (materiaRepetida(_lista, clase)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ese profesor ya da ${clase.materia} a este grupo.')),
      );
      return;
    }
    if (editar != null && editar.profesorUid != clase.profesorUid) {
      await _reasignar(editar, clase);
      return;
    }
    // Sin `await`: sin internet el Future no se completa (ver CLAUDE.md); solo avisa si falla.
    if (editar == null) {
      avisarSiFalla(context, darDeAltaClase(clase), 'No se dio de alta la clase de ${clase.materia}');
    } else {
      avisarSiFalla(context, editarClase(clase), 'No se guardaron los cambios de la clase de ${clase.materia}');
    }
  }

  bool _exportando = false;

  /// Lee los pases de todas las clases del grupo, pregunta meses y formato, arma una sola tabla con los
  /// totales de cada alumno por clase y la guarda: en web se descarga y en Android se abre "Guardar como".
  /// Las clases que ya se borraron no entran (sus pases se conservan, pero ya no tienen materia).
  Future<void> _exportar() async {
    final avisos = ScaffoldMessenger.of(context);
    void avisar(String m) => avisos.showSnackBar(SnackBar(content: Text(m)));
    setState(() => _exportando = true);
    try {
      final snap = await pasesDelGrupo(widget.grupoId);
      final nombres = _nombres;
      final porClase = <String, Map<String, Map<String, dynamic>>>{};
      for (final d in snap.docs) {
        (porClase['${d.data()['claseId']}'] ??= {})['${d.data()['fecha']}'] =
            Map<String, dynamic>.from(d.data()['estados'] as Map? ?? const {});
      }
      final delGrupo = <ClaseDelGrupo>[
        for (final c in _lista)
          (
            materia: c.materia,
            profesor: nombres[c.profesorUid] ?? c.profesorNombre,
            salon: c.salon,
            pases: porClase[c.id] ?? const {},
          ),
      ];
      final dias = diasPorMes([for (final c in delGrupo) ...c.pases.keys]);
      if (!mounted) return;
      if (dias.isEmpty) {
        avisar('Este grupo todavía no tiene pases para exportar.');
        return;
      }
      final eleccion = await showDialog<({Set<String> meses, bool xlsx})>(
        context: context,
        builder: (_) => DialogoExportar(diasPorMes: dias, delGrupo: true),
      );
      if (eleccion == null) return;

      final registro = RegistroGrupo(
        titulo: '${widget.nombreGrupo} · Grupo completo',
        alumnos: (widget.grupo.data()?['alumnos'] as List?) ?? const [],
        delGrupo: delGrupo,
        meses: eleccion.meses,
      );
      if (registro.clases.isEmpty) {
        avisar('No hay pases en los meses elegidos.');
        return;
      }
      final nombre = nombreArchivo(registro.titulo, registro.meses, eleccion.xlsx ? 'xlsx' : 'csv');
      final uri = await FilePicker.saveFile(
        fileName: nombre,
        bytes: eleccion.xlsx ? xlsxGrupo(registro) : csvGrupoBytes(registro),
        mimeType: eleccion.xlsx ? mimeXlsx : 'text/csv',
        dialogTitle: 'Guardar asistencia del grupo',
      );
      // En web la descarga siempre devuelve null; en Android null = canceló.
      if (kIsWeb) {
        avisar('Se descargó $nombre');
      } else if (uri != null) {
        avisar('Se guardó $nombre');
      }
    } catch (e) {
      avisar('No se pudo exportar: $e');
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  /// Pasa la clase a otro profe. Es lo único de las clases que **espera con `await` y pide internet**
  /// (lee del servidor los pases de la clase y los pasa al profe nuevo); por eso se avisa con un
  /// diálogo de progreso en vez de dejar la escritura pendiente.
  Future<void> _reasignar(Clase anterior, Clase nueva) async {
    final nombres = _nombres;
    final deQuien = nombres[anterior.profesorUid] ?? anterior.profesorNombre;
    final ok = await confirmarLote(
      context,
      titulo: 'Pasar la clase a otro profesor',
      mensaje: '${nueva.materia} de ${widget.nombreGrupo} deja de ser de '
          '${deQuien.isEmpty ? 'su profesor actual' : deQuien} y pasa a '
          '${nueva.profesorNombre.isEmpty ? 'el profesor elegido' : nueva.profesorNombre}. '
          'Los pases ya hechos pasan con la clase: el profesor nuevo ve todo el historial y puede '
          'corregirlo. Se necesita internet.',
      boton: 'Pasar clase',
    );
    if (!ok || !mounted) return;
    final progreso = ValueNotifier<String>('Preparando…');
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: progreso,
                  builder: (_, texto, _) => Text(texto),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    String? error;
    try {
      await reasignarClase(
        clase: nueva,
        profesorUid: nueva.profesorUid,
        profesorNombre: nueva.profesorNombre,
        progreso: (hechos, total) => progreso.value = 'Moviendo la clase y sus pases ($hechos de $total)…',
      );
    } on FirebaseException catch (e) {
      error = e.code == 'unavailable'
          ? 'No hay conexión con el servidor. Conéctate a internet y vuelve a intentarlo.'
          : (e.message ?? e.code);
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    Navigator.pop(context); // cierra el progreso
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error == null
          ? 'La clase de ${nueva.materia} pasó a ${nueva.profesorNombre.isEmpty ? 'el profesor elegido' : nueva.profesorNombre}.'
          : 'No se terminó de pasar la clase: $error Puedes volver a intentarlo: continúa donde se quedó.'),
    ));
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
    avisarSiFalla(
      context,
      borrarClase(clase, quitarProfe: quitarProfeDelGrupo(_lista, clase)),
      'No se borró la clase de ${clase.materia}',
    );
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: cargando || _error != null ? null : () => _abrirDialogo(),
              icon: const Icon(Icons.add),
              label: const Text('Dar de alta clase'),
            ),
            OutlinedButton.icon(
              onPressed: cargando || _error != null || _exportando || _lista.isEmpty ? null : _exportar,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Exportar asistencia del grupo'),
            ),
          ],
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Vista mensual',
                      icon: const Icon(Icons.calendar_view_month),
                      onPressed: () => abrirConsultaMensual(
                        context,
                        claseId: c.id,
                        grupo: widget.grupo,
                        titulo: '${widget.nombreGrupo} · ${c.materia}',
                        subtitulo: profeYSalon(nombres[c.profesorUid] ?? c.profesorNombre, c.salon),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Editar clase',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _abrirDialogo(c),
                    ),
                    IconButton(
                      tooltip: 'Borrar clase',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmarBorrar(c, nombres[c.profesorUid] ?? 'El profesor'),
                    ),
                  ],
                ),
              ),
        ],
      ],
    );
  }
}

/// Pide profesor, materia y salón; devuelve la [Clase] o `null` si se cancela. Con [editar] la clase
/// conserva su ID; si cambia el profesor, quien llama la reasigna (`reasignarClase`).
class _DialogoClase extends StatefulWidget {
  const _DialogoClase({
    required this.grupoId,
    required this.nombreGrupo,
    required this.profesores,
    required this.clases,
    this.editar,
  });
  final String grupoId;
  final String nombreGrupo;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> profesores;

  /// Las clases del grupo, para no repetir el mismo profe con la misma materia.
  final List<Clase> clases;
  final Clase? editar;

  @override
  State<_DialogoClase> createState() => _DialogoClaseState();
}

class _DialogoClaseState extends State<_DialogoClase> {
  late final _materia = TextEditingController(text: widget.editar?.materia);
  late final _salon = TextEditingController(text: widget.editar?.salon);
  late String? _profesorUid = widget.editar?.profesorUid;
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
    final profe = widget.profesores.where((d) => d.id == _profesorUid).firstOrNull?.data();
    final clase = Clase(
      id: widget.editar?.id ?? '',
      profesorUid: _profesorUid!,
      grupoId: widget.grupoId,
      materia: limpiarNombre(_materia.text),
      salon: limpiarNombre(_salon.text),
      // Un profe nuevo nunca hereda el nombre del anterior; solo si no cambia y perdió el acceso.
      profesorNombre: '${profe?['nombre'] ?? (_profesorUid == widget.editar?.profesorUid ? widget.editar?.profesorNombre : null) ?? ''}'.trim(),
    );
    if (materiaRepetida(widget.clases, clase)) {
      setState(() => _errorMateria = 'Este profesor ya da esa materia a este grupo.');
      return;
    }
    Navigator.pop(context, clase);
  }

  @override
  Widget build(BuildContext context) {
    final profesores = [...widget.profesores]
      ..sort((a, b) => '${a.data()['nombre']}'.toLowerCase().compareTo('${b.data()['nombre']}'.toLowerCase()));
    final editado = profesores.where((d) => d.id == widget.editar?.profesorUid).firstOrNull?.data();
    return AlertDialog(
      title: Text('${widget.editar == null ? 'Dar de alta' : 'Editar'} clase de ${widget.nombreGrupo}'),
      content: SizedBox(
        width: 400,
        child: profesores.isEmpty && widget.editar == null
            ? const Text('No hay usuarios con rol de profesor. Invítalos primero con '
                '"Invitar usuario" y pídeles que entren a la app una vez.')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Al editar se puede pasar la clase a otro profe (reasignar); el profe actual
                    // sigue en la lista aunque ya no tenga acceso, para poder dejarlo.
                    DropdownButtonFormField<String>(
                      initialValue: _profesorUid,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Profesor',
                        errorText: _errorProfesor,
                        helperText: widget.editar != null && _profesorUid != widget.editar!.profesorUid
                            ? 'La clase y sus pases pasarán a este profesor. Se necesita internet.'
                            : null,
                        helperMaxLines: 3,
                      ),
                      items: [
                        if (widget.editar != null && editado == null)
                          DropdownMenuItem(
                            value: widget.editar!.profesorUid,
                            child: Text(
                              widget.editar!.profesorNombre.isEmpty
                                  ? 'Profesor que ya no tiene acceso'
                                  : '${widget.editar!.profesorNombre} (ya no tiene acceso)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        for (final d in profesores)
                          DropdownMenuItem(
                            value: d.id,
                            child: Text(
                              '${d.data()['nombre'] ?? d.data()['email'] ?? d.id}',
                              overflow: TextOverflow.ellipsis,
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
        if (profesores.isNotEmpty || widget.editar != null)
          FilledButton(onPressed: _aceptar, child: Text(widget.editar == null ? 'Dar de alta' : 'Guardar')),
      ],
    );
  }
}
