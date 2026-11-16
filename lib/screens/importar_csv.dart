import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/csv_alumnos.dart';
import '../models/grupo.dart';
import '../services/grupos.dart';
import 'inicio.dart';

/// Importar una lista desde CSV: elegir el archivo, revisar la vista previa y guardar.
/// Sin [grupoId] crea un grupo nuevo; con [grupoId] reemplaza la lista de ese grupo comparando
/// por N.L (ver `compararListas`).
class ImportarCsv extends StatefulWidget {
  const ImportarCsv({super.key}) : grupoId = null, nombreGrupo = null;
  const ImportarCsv.reemplazar({super.key, required String this.grupoId, required this.nombreGrupo});

  final String? grupoId;
  final String? nombreGrupo;

  @override
  State<ImportarCsv> createState() => _ImportarCsvState();
}

class _ImportarCsvState extends State<ImportarCsv> {
  final _nombre = TextEditingController();
  late final StreamSubscription<void> _sub;

  /// Grupo nuevo: IDs que ya existen, para avisar en vez de sobrescribir. `null` mientras carga.
  /// Sale de la caché de Firestore, así que también funciona sin internet.
  Set<String>? _idsExistentes;

  /// Reemplazo: la lista guardada hoy, para comparar. `null` mientras carga.
  List<Alumno>? _actual;
  Object? _errorGrupos;

  String? _archivo;
  ListaCsv? _lista;
  String? _errorArchivo;
  bool _arrastrando = false;

  bool get _reemplazo => widget.grupoId != null;

  @override
  void initState() {
    super.initState();
    void alFallar(Object e) => setState(() => _errorGrupos = e);
    _sub = _reemplazo
        ? grupo(widget.grupoId!).listen(
            (d) => setState(() => _actual = alumnosDe(d.data()?['alumnos'])),
            onError: alFallar,
          )
        : grupos().listen(
            (s) => setState(() => _idsExistentes = {for (final d in s.docs) d.id}),
            onError: alFallar,
          );
  }

  @override
  void dispose() {
    _sub.cancel();
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _elegir() async {
    try {
      final archivo = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['csv']);
      if (archivo == null) return; // canceló
      await _cargar(archivo.name, archivo.readAsBytes());
    } catch (e) {
      if (mounted) setState(() => _errorArchivo = 'No se pudo abrir el archivo: $e');
    }
  }

  Future<void> _soltar(DropDoneDetails detalle) async {
    setState(() => _arrastrando = false);
    if (detalle.files.isEmpty) return;
    if (detalle.files.length > 1) {
      setState(() => _errorArchivo = 'Suelta un solo archivo a la vez.');
      return;
    }
    final archivo = detalle.files.single;
    await _cargar(archivo.name, archivo.readAsBytes());
  }

  Future<void> _cargar(String nombre, Future<List<int>> bytes) async {
    if (!nombre.toLowerCase().endsWith('.csv')) {
      setState(() {
        _archivo = _lista = null;
        _errorArchivo = '"$nombre" no es un archivo .csv. En Excel usa Guardar como → CSV.';
      });
      return;
    }
    try {
      final lista = leerCsv(await bytes);
      if (!mounted) return;
      setState(() {
        _archivo = nombre;
        _lista = lista;
        _errorArchivo = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _archivo = _lista = null;
        _errorArchivo = 'No se pudo leer "$nombre": $e';
      });
    }
  }

  /// Por qué no se puede usar el nombre escrito; `null` si está bien o aún no escribe nada.
  String? get _errorNombre {
    if (_nombre.text.trim().isEmpty) return null;
    final id = idGrupo(_nombre.text);
    if (id.isEmpty) return 'Usa letras o números en el nombre.';
    if (_idsExistentes?.contains(id) ?? false) {
      return 'Ya existe un grupo con el ID "$id". Usa otro nombre.';
    }
    return null;
  }

  bool get _puedeSubir =>
      (_lista?.valida ?? false) &&
      _idsExistentes != null &&
      idGrupo(_nombre.text).isNotEmpty &&
      _errorNombre == null;

  /// Reemplazo: qué va a pasar con la lista guardada; `null` si falta el archivo o tiene errores.
  CambiosLista? get _cambios {
    final lista = _lista;
    final actual = _actual;
    if (lista == null || !lista.valida || actual == null) return null;
    return compararListas(actual, lista.alumnos);
  }

  void _subir() {
    final nombre = _nombre.text.trim();
    final alumnos = _lista!.alumnos;
    // Sin `await`: sin internet el Future no se completa (ver CLAUDE.md); solo avisa si falla.
    avisarSiFalla(
      context,
      crearGrupo(idGrupo(nombre), nombre, alumnos),
      'No se guardó el grupo $nombre',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Grupo $nombre guardado con ${alumnos.length} alumnos.')),
    );
    Navigator.pop(context);
  }

  void _reemplazar(CambiosLista cambios) {
    final nombre = widget.nombreGrupo ?? widget.grupoId!;
    avisarSiFalla(
      context,
      guardarAlumnos(widget.grupoId!, cambios.resultado),
      'No se reemplazó la lista de $nombre',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Lista de $nombre reemplazada: ${cambios.resumen}.')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final lista = _lista;
    final cambios = _cambios;
    final id = idGrupo(_nombre.text);
    final error = TextStyle(color: Theme.of(context).colorScheme.error);
    return Scaffold(
      appBar: AppBar(
        title: Text(_reemplazo ? 'Reemplazar lista de ${widget.nombreGrupo}' : 'Importar lista'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Archivo CSV con dos columnas: número de lista y nombre completo.'),
          if (_reemplazo)
            const Text('Se compara por número de lista: los que ya no vengan en el archivo '
                'quedan dados de baja, no se borran.'),
          const SizedBox(height: 12),
          DropTarget(
            onDragEntered: (_) => setState(() => _arrastrando = true),
            onDragExited: (_) => setState(() => _arrastrando = false),
            onDragDone: _soltar,
            child: _ZonaArchivo(resaltada: _arrastrando, archivo: _archivo, alTocar: _elegir),
          ),
          if (_errorArchivo != null) ...[
            const SizedBox(height: 8),
            Text(_errorArchivo!, style: error),
          ],
          if (_errorGrupos != null) ...[
            const SizedBox(height: 8),
            Text(
              _reemplazo
                  ? 'No se pudo cargar la lista guardada: $_errorGrupos'
                  : 'No se pudo revisar si el grupo ya existe: $_errorGrupos',
              style: error,
            ),
          ],
          if (lista != null) ...[
            const SizedBox(height: 16),
            // Con errores (o mientras carga la lista guardada) se muestra el archivo tal cual.
            if (cambios == null) _VistaPrevia(lista: lista) else _VistaCambios(cambios: cambios),
            const SizedBox(height: 16),
            if (_reemplazo)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: cambios == null || cambios.sinCambios
                      ? null
                      : () => _reemplazar(cambios),
                  icon: const Icon(Icons.published_with_changes),
                  label: const Text('Reemplazar lista'),
                ),
              )
            else ...[
              TextField(
                controller: _nombre,
                maxLength: 40,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Nombre del grupo',
                  hintText: 'Por ejemplo: IA 3A',
                  helperText: id.isEmpty ? null : 'Se guardará con el ID "$id"',
                  errorText: _errorNombre,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _puedeSubir ? _subir : null,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Subir'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Zona para soltar el archivo (web) o tocarla y elegirlo (web y Android).
class _ZonaArchivo extends StatelessWidget {
  const _ZonaArchivo({required this.resaltada, required this.archivo, required this.alTocar});
  final bool resaltada;
  final String? archivo;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Material(
      color: resaltada ? colores.primaryContainer : colores.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: resaltada ? colores.primary : colores.outline, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: alTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: Column(
            children: [
              Icon(Icons.upload_file, size: 40, color: colores.primary),
              const SizedBox(height: 8),
              Text(
                'Elige o suelta el archivo aquí',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (archivo != null) ...[
                const SizedBox(height: 4),
                Text('Archivo: $archivo', textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Lo que se va a guardar: total de alumnos y la tabla, con las filas con error en rojo.
class _VistaPrevia extends StatelessWidget {
  const _VistaPrevia({required this.lista});
  final ListaCsv lista;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final textos = Theme.of(context).textTheme;
    final errores = lista.conError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Vista previa', style: textos.titleMedium),
        const SizedBox(height: 4),
        if (lista.errorGeneral != null)
          Text(lista.errorGeneral!, style: TextStyle(color: colores.error))
        else if (errores == 0)
          Text('Total: ${lista.filas.length} alumnos.')
        else
          Text(
            '${lista.filas.length} filas, $errores con error. '
            'Corrige el archivo y vuelve a elegirlo para poder subirlo.',
            style: TextStyle(color: colores.error),
          ),
        const SizedBox(height: 8),
        for (final f in lista.filas)
          Container(
            color: f.valida ? null : colores.errorContainer,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 48, child: Text(f.numTexto.isEmpty ? '—' : f.numTexto)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.nombre.isEmpty ? '(sin nombre)' : f.nombre),
                      for (final e in f.errores)
                        Text(
                          'Fila ${f.fila}: $e',
                          style: textos.bodySmall?.copyWith(color: colores.onErrorContainer),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Reemplazo: cómo quedará la lista y qué cambia en cada N.L, con los cambios de nombre resaltados.
class _VistaCambios extends StatelessWidget {
  const _VistaCambios({required this.cambios});
  final CambiosLista cambios;

  // Mismo amarillo pastel que la falta justificada: llama la atención sin parecer error.
  static const _resaltado = Color(0xFFFFF3C4);

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final textos = Theme.of(context).textTheme;
    final nuevos = {for (final a in cambios.nuevos) a.num};
    final bajas = {for (final a in cambios.bajas) a.num};
    final renombrados = {for (final c in cambios.renombrados) c.num: c};
    final activos = cambios.resultado.where((a) => a.activo).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Vista previa', style: textos.titleMedium),
        const SizedBox(height: 4),
        Text(cambios.resumen, style: textos.titleSmall),
        Text('La lista quedará con $activos alumnos activos.'),
        if (cambios.renombrados.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Revisa los cambios de nombre: el número de lista une al alumno con su historial '
              'de asistencia. Si un número pasa a ser de otra persona, el historial se mezcla.',
              style: TextStyle(color: colores.error),
            ),
          ),
        const SizedBox(height: 8),
        for (final a in cambios.resultado)
          Container(
            color: renombrados.containsKey(a.num) ? _resaltado : null,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 48, child: Text('${a.num}')),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.nombre,
                        style: a.activo ? null : TextStyle(color: colores.outline),
                      ),
                      if (renombrados[a.num] case final c?)
                        Text('Antes: ${c.antes}', style: textos.bodySmall),
                    ],
                  ),
                ),
                Text(
                  [
                    if (nuevos.contains(a.num)) 'Nuevo',
                    if (bajas.contains(a.num)) 'Se da de baja',
                    if (renombrados.containsKey(a.num)) 'Cambia de nombre',
                    if (!a.activo && !bajas.contains(a.num)) 'Sigue de baja',
                  ].join(' · '),
                  style: textos.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
