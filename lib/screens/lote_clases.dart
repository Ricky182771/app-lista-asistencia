import 'dart:async';

import 'package:flutter/material.dart';

import '../models/clase.dart';
import '../models/lote_clases.dart';
import '../models/lote_csv.dart';
import '../models/rol.dart';
import '../services/clases.dart';
import '../services/grupos.dart';
import '../services/pases.dart';
import '../services/sesion.dart';
import 'inicio.dart';
import 'lote_comun.dart';

/// Dar de alta las clases de varios profesores a la vez desde un CSV `profesor,grupo,materia,salón`.
/// El profesor puede venir por correo o por nombre (si no hay otro igual), y el grupo debe existir.
/// Las clases que ya existen se omiten; las demás se pueden corregir o quitar antes de guardar.
class LoteClases extends StatefulWidget {
  const LoteClases({super.key});

  @override
  State<LoteClases> createState() => _LoteClasesState();
}

class _LoteClasesState extends State<LoteClases> {
  final _subs = <StreamSubscription<void>>[];
  List<UsuarioLote>? _usuarios;
  Map<String, Rol?>? _invitaciones;
  Map<String, String>? _grupos;
  List<Clase>? _existentes;
  Object? _errorCarga;

  final _filas = <FilaClaseLote>[];
  String? _archivo;
  String? _errorArchivo;

  @override
  void initState() {
    super.initState();
    void alFallar(Object e) => setState(() => _errorCarga = e);
    _subs.add(usuarios().listen(
      (s) => setState(() => _usuarios = [
            for (final d in s.docs)
              (
                uid: d.id,
                nombre: '${d.data()['nombre'] ?? ''}',
                correo: '${d.data()['email'] ?? ''}',
                rol: parseRol(d.data()['rol']),
              ),
          ]),
      onError: alFallar,
    ));
    _subs.add(invitaciones().listen(
      (s) => setState(() => _invitaciones = {for (final d in s.docs) d.id: parseRol(d.data()['rol'])}),
      onError: alFallar,
    ));
    _subs.add(grupos().listen(
      (s) => setState(() => _grupos = {for (final d in s.docs) d.id: '${d.data()['nombre'] ?? d.id}'}),
      onError: alFallar,
    ));
    _subs.add(todasLasClases().listen(
      (s) => setState(() => _existentes = [for (final d in s.docs) ?claseDe(d.id, d.data())]),
      onError: alFallar,
    ));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _leer(String nombre, List<int> bytes) {
    try {
      final lectura = leerClasesLote(bytes);
      setState(() {
        _archivo = nombre;
        _errorArchivo = lectura.errorGeneral;
        _filas
          ..clear()
          ..addAll(lectura.filas);
      });
    } catch (e) {
      setState(() => _errorArchivo = 'No se pudo leer "$nombre": $e');
    }
  }

  /// Correo → "Nombre · correo" de los profesores, para elegir en el diálogo.
  Map<String, String> get _opcionesProfe => {
        for (final u in [...?_usuarios]..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase())))
          if (u.rol == Rol.profesor && u.correo.isNotEmpty) u.correo: '${u.nombre} · ${u.correo}',
      };

  /// Nombre → nombre de los grupos que existen.
  Map<String, String> get _opcionesGrupo => {
        for (final n in [...?_grupos?.values]..sort()) n: n,
      };

  /// El valor del desplegable que corresponde a lo que trae la celda (el correo exacto o el grupo con
  /// su nombre de hoy), para que abra con la opción elegida cuando la validación ya la reconoce.
  List<CampoLote> _campos(FilaClaseLote f) {
    final profes = _opcionesProfe;
    final correo = profes.keys.where((c) => normalizarCorreo(c) == normalizarCorreo(f.profesor)).firstOrNull;
    final grupos = _grupos ?? const <String, String>{};
    final grupoId = grupoPorNombre(f.grupo, grupos);
    return [
      CampoLote('Profesor', correo ?? f.profesor, opciones: profes),
      CampoLote('Grupo', grupoId == null ? f.grupo : grupos[grupoId]!, opciones: _opcionesGrupo),
      CampoLote('Materia', f.materia, maxLength: maxEtiqueta),
      CampoLote('Salón de siempre', f.salon, maxLength: maxEtiqueta),
    ];
  }

  Future<void> _editar(FilaClaseLote f) async {
    final valores = await dialogoCampos(context, titulo: 'Corregir clase', campos: _campos(f));
    if (valores == null) return;
    setState(() {
      f.profesor = valores[0];
      f.grupo = valores[1];
      f.materia = valores[2];
      f.salon = valores[3];
    });
  }

  Future<void> _agregar() async {
    final fila = FilaClaseLote(fila: 0, profesor: '', grupo: '', materia: '', salon: '');
    final valores = await dialogoCampos(
      context,
      titulo: 'Agregar clase',
      textoGuardar: 'Agregar',
      campos: _campos(fila),
    );
    if (valores == null) return;
    fila
      ..profesor = valores[0]
      ..grupo = valores[1]
      ..materia = valores[2]
      ..salon = valores[3];
    setState(() => _filas.add(fila));
  }

  Future<void> _guardar(List<Clase> clases) async {
    final profes = {for (final c in clases) c.profesorUid}.length;
    final ok = await confirmarLote(
      context,
      titulo: 'Dar de alta ${clases.length} ${clases.length == 1 ? 'clase' : 'clases'}',
      mensaje: 'De $profes ${profes == 1 ? 'profesor' : 'profesores'}. Cada profesor verá sus clases '
          'nuevas en cuanto abra la app. Una clase se corrige o se borra después desde la pantalla de su grupo.',
      boton: 'Dar de alta',
    );
    if (!ok || !mounted) return;
    // Sin `await`: sin internet el Future no se completa (ver CLAUDE.md); solo avisa si falla.
    avisarSiFallan(context, darDeAltaClases(clases), 'No se dieron de alta todas las clases');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${clases.length} clases dadas de alta.')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final usuarios = _usuarios;
    final invitaciones = _invitaciones;
    final grupos = _grupos;
    final existentes = _existentes;
    final validadas = usuarios != null && invitaciones != null && grupos != null && existentes != null
        ? validarClases(
            _filas,
            usuarios: usuarios,
            invitaciones: invitaciones,
            grupos: grupos,
            existentes: existentes,
          )
        : null;
    final conteo = contarLote([...?validadas?.map((v) => v.resultado)]);
    final clases = [
      for (final v in validadas ?? const <ClaseValidada>[])
        if (v.resultado.seGuarda) ?v.clase,
    ];
    final error = TextStyle(color: Theme.of(context).colorScheme.error);
    return Scaffold(
      appBar: AppBar(title: const Text('Dar de alta clases por lote')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CargaCsv(
            ayuda: 'Archivo CSV con cuatro columnas: profesor (su correo; sirve su nombre si no hay otro '
                'igual), grupo, materia y salón de siempre. Los grupos y los profesores deben existir '
                'antes. El encabezado es opcional.',
            alLeer: _leer,
          ),
          if (_errorCarga != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('No se pudo cargar usuarios, grupos o clases: $_errorCarga', style: error),
            ),
          if (_errorArchivo != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_errorArchivo!, style: error)),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(_archivo == null ? 'Clases' : 'Clases de $_archivo',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: validadas == null ? null : _agregar,
                icon: const Icon(Icons.add),
                label: const Text('Agregar'),
              ),
            ],
          ),
          if (_filas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Elige un archivo o agrega clases a mano.'),
            )
          else if (validadas == null)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else ...[
            ResumenLote(conteo: conteo),
            const SizedBox(height: 8),
            for (var i = 0; i < _filas.length; i++) ...[
              FilaLote(
                titulo: _filas[i].materia,
                detalle: 'Prof. ${_filas[i].profesor.isEmpty ? '—' : _filas[i].profesor}'
                    ' · Grupo ${_filas[i].grupo.isEmpty ? '—' : _filas[i].grupo}'
                    ' · Salón ${_filas[i].salon.isEmpty ? '—' : _filas[i].salon}',
                resultado: validadas[i].resultado,
                alEditar: () => _editar(_filas[i]),
                alQuitar: () => setState(() => _filas.removeAt(i)),
              ),
              const Divider(height: 1),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: clases.isNotEmpty && conteo.conError == 0 ? () => _guardar(clases) : null,
                icon: const Icon(Icons.playlist_add),
                label: Text('Dar de alta (${clases.length})'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
