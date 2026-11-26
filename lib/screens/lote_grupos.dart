import 'dart:async';

import 'package:flutter/material.dart';

import '../models/grupo.dart';
import '../models/lote_grupos.dart';
import '../services/grupos.dart';
import 'inicio.dart';
import 'lote_comun.dart';

/// Importar varios grupos a la vez desde un solo CSV `grupo,N.L,nombre`. Cada grupo se revisa por
/// separado y se puede corregir (un alumno, el nombre del grupo) o quitar del lote. Un grupo que ya
/// existe se omite, o se actualiza su lista comparando por N.L (igual que "Reemplazar lista").
class LoteGrupos extends StatefulWidget {
  const LoteGrupos({super.key});

  @override
  State<LoteGrupos> createState() => _LoteGruposState();
}

class _LoteGruposState extends State<LoteGrupos> {
  late final StreamSubscription<void> _sub;

  /// ID → nombre de los grupos que ya existen, y ID → su lista (`null` si trae entradas sin reconocer).
  Map<String, String>? _existentes;
  final _alumnosExistentes = <String, List<Alumno>?>{};
  Object? _errorCarga;

  final _filas = <FilaAlumnoLote>[];
  final _actualizar = <String>{};
  String? _archivo;
  String? _errorArchivo;

  @override
  void initState() {
    super.initState();
    _sub = grupos().listen(
      (s) => setState(() {
        _existentes = {for (final d in s.docs) d.id: '${d.data()['nombre'] ?? d.id}'};
        _alumnosExistentes
          ..clear()
          ..addEntries([
            for (final d in s.docs)
              MapEntry(
                d.id,
                sinReconocer(d.data()['alumnos']) == 0 ? alumnosDe(d.data()['alumnos']) : null,
              ),
          ]);
      }),
      onError: (Object e) => setState(() => _errorCarga = e),
    );
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  void _leer(String nombre, List<int> bytes) {
    try {
      final lectura = leerAlumnosLote(bytes);
      setState(() {
        _archivo = nombre;
        _errorArchivo = lectura.errorGeneral;
        _actualizar.clear();
        _filas
          ..clear()
          ..addAll(lectura.filas);
      });
    } catch (e) {
      setState(() => _errorArchivo = 'No se pudo leer "$nombre": $e');
    }
  }

  Future<void> _editar(FilaAlumnoLote f) async {
    final valores = await dialogoCampos(
      context,
      titulo: 'Corregir alumno',
      campos: [
        CampoLote('Grupo', f.grupo, maxLength: maxNombreGrupo),
        CampoLote('N.L', f.numTexto, teclado: TextInputType.number),
        CampoLote('Nombre completo', f.nombre),
      ],
    );
    if (valores == null) return;
    setState(() {
      f.grupo = valores[0];
      f.numTexto = valores[1];
      f.nombre = valores[2];
    });
  }

  Future<void> _agregarAlumno(GrupoLote g) async {
    final usados = [for (final f in g.filas) ?f.num];
    final siguiente = usados.isEmpty ? 1 : usados.reduce((a, b) => a > b ? a : b) + 1;
    final valores = await dialogoCampos(
      context,
      titulo: 'Agregar alumno a ${g.nombre}',
      textoGuardar: 'Agregar',
      campos: [
        CampoLote('N.L', '$siguiente', teclado: TextInputType.number),
        const CampoLote('Nombre completo', ''),
      ],
    );
    if (valores == null) return;
    setState(() => _filas.add(FilaAlumnoLote(fila: 0, grupo: g.nombre, numTexto: valores[0], nombre: valores[1])));
  }

  Future<void> _renombrar(GrupoLote g) async {
    final valores = await dialogoCampos(
      context,
      titulo: 'Nombre del grupo',
      campos: [CampoLote('Nombre', g.nombre, maxLength: maxNombreGrupo)],
    );
    if (valores == null) return;
    setState(() {
      _actualizar.remove(g.id);
      for (final f in g.filas) {
        f.grupo = valores[0];
      }
    });
  }

  void _quitarGrupo(GrupoLote g) => setState(() {
        _actualizar.remove(g.id);
        _filas.removeWhere(g.filas.contains);
      });

  Future<void> _subir(List<GrupoPorGuardar> lote) async {
    final alumnos = lote.fold<int>(0, (suma, g) => suma + g.alumnos.where((a) => a.activo).length);
    final nuevos = lote.where((g) => g.nombre != null).length;
    final ok = await confirmarLote(
      context,
      titulo: 'Guardar ${lote.length} ${lote.length == 1 ? 'grupo' : 'grupos'}',
      mensaje: '$nuevos nuevos y ${lote.length - nuevos} actualizados, con $alumnos alumnos activos en total. '
          'Los grupos nuevos quedan sin profesores hasta que les des de alta sus clases.',
      boton: 'Guardar',
    );
    if (!ok || !mounted) return;
    // Sin `await`: sin internet el Future no se completa (ver CLAUDE.md); solo avisa si falla.
    avisarSiFallan(context, guardarGrupos(lote), 'No se guardaron todos los grupos');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${lote.length} ${lote.length == 1 ? 'grupo guardado' : 'grupos guardados'}.')),
    );
    Navigator.pop(context);
  }

  Widget _grupo(ValidacionGrupo v) {
    final g = v.grupo;
    final colores = Theme.of(context).colorScheme;
    final String estado;
    if (v.nuevo) {
      estado = 'Nuevo · ${g.filas.length} alumnos';
    } else if (!v.actualizar) {
      estado = 'Ya existe como "${v.existenteNombre}" · se omite';
    } else if (v.cambios != null) {
      estado = 'Ya existe · ${v.cambios!.resumen}';
    } else {
      estado = 'Ya existe · se actualizará su lista';
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        key: ValueKey(g.id.isEmpty ? 'sin-id-${g.nombre}' : g.id),
        initiallyExpanded: v.bloquea,
        title: Text(g.nombre.isEmpty ? '(sin nombre)' : g.nombre),
        subtitle: Text(
          v.hayErrores && v.seGuarda ? '$estado · con errores' : estado,
          style: v.bloquea ? TextStyle(color: colores.error) : null,
        ),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          for (final e in v.errores)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(e, style: TextStyle(color: colores.error)),
              ),
            ),
          for (final a in v.avisos)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Align(alignment: Alignment.centerLeft, child: Text(a)),
            ),
          if (!v.nuevo)
            SwitchListTile(
              title: const Text('Actualizar su lista'),
              subtitle: const Text('Se compara por N.L: los que ya no vengan quedan dados de baja, no se borran.'),
              value: v.actualizar,
              onChanged: (si) => setState(() => si ? _actualizar.add(g.id) : _actualizar.remove(g.id)),
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _renombrar(g),
                icon: const Icon(Icons.drive_file_rename_outline),
                label: const Text('Nombre del grupo'),
              ),
              TextButton.icon(
                onPressed: () => _agregarAlumno(g),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Agregar alumno'),
              ),
              TextButton.icon(
                onPressed: () => _quitarGrupo(g),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Quitar del lote'),
              ),
            ],
          ),
          for (var i = 0; i < g.filas.length; i++) ...[
            const Divider(height: 1),
            FilaLote(
              titulo: '${g.filas[i].numTexto.isEmpty ? '—' : g.filas[i].numTexto}  ${g.filas[i].nombre}',
              resultado: v.filas[i],
              alEditar: () => _editar(g.filas[i]),
              alQuitar: () => setState(() => _filas.remove(g.filas[i])),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existentes = _existentes;
    final validaciones = existentes == null
        ? const <ValidacionGrupo>[]
        : validarGrupos(
            _filas,
            existentes: existentes,
            alumnosExistentes: _alumnosExistentes,
            actualizar: _actualizar,
          );
    final lote = [for (final v in validaciones) ?porGuardar(v)];
    final bloqueados = validaciones.where((v) => v.bloquea).length;
    final omitidos = validaciones.where((v) => !v.seGuarda).length;
    final sinCambios = validaciones.where((v) => v.actualizar && !v.hayErrores && porGuardar(v) == null).length;
    final error = TextStyle(color: Theme.of(context).colorScheme.error);
    return Scaffold(
      appBar: AppBar(title: const Text('Importar grupos por lote')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CargaCsv(
            ayuda: 'Un solo archivo CSV con tres columnas: grupo, número de lista y nombre completo. '
                'Cada fila es un alumno; los grupos se arman con la primera columna. '
                'El encabezado es opcional.',
            alLeer: _leer,
          ),
          if (_errorCarga != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('No se pudo revisar qué grupos ya existen: $_errorCarga', style: error),
            ),
          if (_errorArchivo != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_errorArchivo!, style: error)),
          const SizedBox(height: 16),
          if (_filas.isEmpty)
            const Text('Elige un archivo para ver la vista previa.')
          else if (existentes == null)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else ...[
            Text(_archivo == null ? 'Grupos' : 'Grupos de $_archivo', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${validaciones.length} ${validaciones.length == 1 ? 'grupo' : 'grupos'}: '
              '${lote.length} por guardar'
              '${omitidos > 0 ? ' · $omitidos omitidos' : ''}'
              '${sinCambios > 0 ? ' · $sinCambios sin cambios' : ''}'
              '${bloqueados > 0 ? ' · $bloqueados con errores' : ''}',
              style: bloqueados > 0 ? error : Theme.of(context).textTheme.titleSmall,
            ),
            if (bloqueados > 0)
              Text('Abre los grupos con errores y corrígelos (lápiz) o quítalos del lote para poder guardar.',
                  style: error),
            const SizedBox(height: 8),
            for (final v in validaciones) _grupo(v),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: bloqueados == 0 && lote.isNotEmpty ? () => _subir(lote) : null,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text('Guardar (${lote.length})'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
