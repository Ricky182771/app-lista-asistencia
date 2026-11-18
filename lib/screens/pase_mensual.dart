import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/exportar.dart';
import '../models/pase.dart';
import '../models/xlsx.dart';
import '../services/almacen_local.dart' if (dart.library.js_interop) '../services/almacen_local_web.dart';
import '../services/pases.dart';
import 'celda_estado.dart';
import 'inicio.dart';

const _alto = 48.0;

/// Ancho de la columna Nombre que eligió el usuario arrastrando su borde. En web se guarda en
/// `localStorage` (por navegador, no por cuenta: es solo una preferencia visual, sin datos personales);
/// en Android dura mientras la app esté abierta. `null` = automático.
const _claveAnchoNombre = 'paselista.anchoNombre';
double? _anchoNombreElegido = double.tryParse(leerLocal(_claveAnchoNombre) ?? '');

void _guardarAnchoNombre(double? ancho) {
  _anchoNombreElegido = ancho;
  guardarLocal(_claveAnchoNombre, ancho == null ? '' : ancho.round().toString());
}
const _anchoDia = 96.0;

/// Admin y orden: la vista mensual en solo consulta (con exportar). [mes] por omisión, el actual.
void abrirConsultaMensual(
  BuildContext context, {
  required String claseId,
  required DocumentSnapshot<Map<String, dynamic>> grupo,
  required String titulo,
  DateTime? mes,
}) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => PaseMensual(
        claseId: claseId,
        grupo: grupo,
        titulo: titulo,
        mes: mes ?? DateTime.now(),
        soloLectura: true,
      ),
    ),
  );
}

/// Vista mensual de una clase: una columna por cada día con pase. N.L y Nombre quedan fijos y las
/// fechas se desplazan en horizontal. También exporta el registro a .xlsx o .csv.
class PaseMensual extends StatefulWidget {
  const PaseMensual({
    super.key,
    required this.claseId,
    required this.grupo,
    required this.titulo,
    required this.mes,
    this.soloLectura = false,
  });
  final String claseId;
  final DocumentSnapshot<Map<String, dynamic>> grupo;
  final String titulo;
  final DateTime mes;

  /// Para admin y orden: no se edita nada y las consultas no filtran por profesor (las reglas les
  /// dejan leer todos los pases). El profe siempre filtra por su uid, como piden las reglas.
  final bool soloLectura;

  @override
  State<PaseMensual> createState() => _PaseMensualState();
}

class _PaseMensualState extends State<PaseMensual> {
  late final String? _profesor = widget.soloLectura ? null : FirebaseAuth.instance.currentUser!.uid;
  late DateTime _mes = DateTime(widget.mes.year, widget.mes.month);
  QuerySnapshot<Map<String, dynamic>>? _snap;
  Object? _error;
  StreamSubscription<void>? _sub;
  bool _exportando = false;
  bool _sobreBorde = false;

  @override
  void initState() {
    super.initState();
    _escuchar();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _escuchar() {
    _sub?.cancel();
    _snap = null;
    _error = null;
    _sub = pasesDelMes(_profesor, widget.claseId, rangoDelMes(_mes.year, _mes.month)).listen(
      (s) => setState(() => _snap = s),
      onError: (Object e) => setState(() => _error = e),
    );
  }

  void _mover(int meses) => setState(() {
        _mes = DateTime(_mes.year, _mes.month + meses);
        _escuchar();
      });

  /// Un `update()` de ese solo campo, sin `await` (ver CLAUDE.md).
  void _tocar(String paseId, String fecha, String nl, int? actual) {
    final nuevo = actual == null ? presente : siguienteEstado(actual);
    avisarSiFalla(context, guardarCambios(paseId, {'estados.$nl': nuevo}),
        'No se guardó el cambio del $fecha');
  }

  /// Lee todos los pases de la clase, pregunta meses y formato, arma el archivo y lo guarda: en web
  /// se descarga y en Android se abre el selector de "Guardar como".
  Future<void> _exportar() async {
    final avisos = ScaffoldMessenger.of(context);
    void avisar(String m) => avisos.showSnackBar(SnackBar(content: Text(m)));
    setState(() => _exportando = true);
    try {
      final snap = await pasesDeLaClase(_profesor, widget.claseId);
      final pases = {
        for (final d in snap.docs)
          '${d.data()['fecha']}': Map<String, dynamic>.from(d.data()['estados'] as Map? ?? const {}),
      };
      final dias = diasPorMes(pases.keys);
      if (!mounted) return;
      if (dias.isEmpty) {
        avisar('Esta clase todavía no tiene pases para exportar.');
        return;
      }

      final eleccion = await showDialog<({Set<String> meses, bool xlsx})>(
        context: context,
        builder: (_) => _DialogoExportar(diasPorMes: dias),
      );
      if (eleccion == null) return;

      final registro = Registro(
        titulo: widget.titulo,
        pases: pases,
        alumnos: (widget.grupo.data()?['alumnos'] as List?) ?? const [],
        meses: eleccion.meses,
      );
      final nombre = nombreArchivo(widget.titulo, registro.meses, eleccion.xlsx ? 'xlsx' : 'csv');
      final uri = await FilePicker.saveFile(
        fileName: nombre,
        bytes: eleccion.xlsx ? xlsxRegistro(registro) : csvRegistroBytes(registro),
        mimeType: eleccion.xlsx ? mimeXlsx : 'text/csv',
        dialogTitle: 'Guardar registro de asistencia',
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

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final esMesActual = _mes.year == hoy.year && _mes.month == hoy.month;
    final snap = _snap;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo),
        actions: [
          IconButton(
            tooltip: 'Exportar registro (Excel o CSV)',
            onPressed: _exportando ? null : _exportar,
            icon: _exportando
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Mes anterior',
                onPressed: () => _mover(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  MaterialLocalizations.of(context).formatMonthYear(_mes),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Mes siguiente',
                // No hay pases en el futuro.
                onPressed: esMesActual ? null : () => _mover(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const LeyendaEstados(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.soloLectura ? Icons.visibility_outlined : Icons.lock_outline, size: 18),
                    const SizedBox(width: 6),
                    Text(widget.soloLectura ? 'Solo consulta' : 'Más de $diasEditables días: solo lectura'),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _error != null
                ? Center(child: Text('Error al cargar el mes: $_error'))
                : snap == null
                    ? const Center(child: CircularProgressIndicator())
                    : _tabla(snap, hoy),
          ),
        ],
      ),
    );
  }

  Widget _tabla(QuerySnapshot<Map<String, dynamic>> snap, DateTime hoy) {
    final pases = {for (final d in snap.docs) '${d.data()['fecha']}': d};
    final columnas = columnasDelMes(pases.keys);
    if (columnas.isEmpty) return const Center(child: Text('No hay pases en este mes.'));

    final estadosDe = {
      for (final f in columnas) f: Map<String, dynamic>.from(pases[f]!.data()['estados'] as Map? ?? const {}),
    };
    final alumnos = (widget.grupo.data()?['alumnos'] as List?) ?? const [];
    // Activos más quien tenga registros este mes aunque esté dado de baja.
    final filas = filasDelPase(alumnos, {for (final e in estadosDe.values) ...e});
    final pantalla = MediaQuery.sizeOf(context).width;
    final anchoFijo = anchoNombre(_anchoNombreElegido, pantalla);
    final cabecera = Theme.of(context).textTheme.labelMedium;

    Widget celdaFija(Widget child) => SizedBox(height: _alto, child: Align(alignment: Alignment.centerLeft, child: child));

    return ListView(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: anchoFijo,
              child: Column(
                children: [
                  celdaFija(Text('  N.L   Nombre', style: cabecera)),
                  for (final f in filas)
                    celdaFija(Row(
                      children: [
                        SizedBox(width: 32, child: Text(f.nl, textAlign: TextAlign.end)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            f.baja ? '${f.nombre} (baja)' : f.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )),
                ],
              ),
            ),
            _borde(alto: _alto * (filas.length + 1), ancho: anchoFijo, pantalla: pantalla),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  children: [
                    Row(children: [for (final c in columnas) _cabecera(c, pases[c]!, hoy, cabecera)]),
                    for (final f in filas)
                      Row(
                        children: [
                          for (final c in columnas) _celda(c, pases[c]!.id, f.nl, estadosDe[c]![f.nl], hoy),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Borde derecho de la columna Nombre: se arrastra para cambiar el ancho y con doble clic (o doble
  /// toque) vuelve al automático. El ancho elegido se guarda al soltar.
  Widget _borde({required double alto, required double ancho, required double pantalla}) {
    final colores = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Arrastra para cambiar el ancho · doble clic para restablecer',
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _sobreBorde = true),
        onExit: (_) => setState(() => _sobreBorde = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _sobreBorde = true),
          onHorizontalDragUpdate: (d) =>
              setState(() => _anchoNombreElegido = anchoNombre(ancho + d.delta.dx, pantalla)),
          onHorizontalDragEnd: (_) {
            _guardarAnchoNombre(_anchoNombreElegido);
            setState(() => _sobreBorde = false);
          },
          onDoubleTap: () => setState(() => _guardarAnchoNombre(null)),
          // Área de 16 px para atinarle con el dedo; la línea visible es delgada.
          child: SizedBox(
            width: 16,
            height: alto,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: _sobreBorde ? 3 : 1,
                color: _sobreBorde ? colores.primary : colores.outlineVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cabecera(String fecha, DocumentSnapshot<Object?> pase, DateTime hoy, TextStyle? estilo) {
    // En solo consulta no se marca ningún candado: no se edita ninguna columna.
    final editable = widget.soloLectura || esEditable(fecha, hoy);
    return SizedBox(
      width: _anchoDia,
      height: _alto,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!editable) const Tooltip(message: 'Solo lectura', child: Icon(Icons.lock_outline, size: 14)),
              if (pase.metadata.hasPendingWrites)
                const Tooltip(message: 'Pendiente de enviar', child: Icon(Icons.cloud_upload_outlined, size: 14)),
            ],
          ),
          Text(fecha, style: estilo),
        ],
      ),
    );
  }

  Widget _celda(String fecha, String paseId, String nl, Object? valor, DateTime hoy) {
    final editable = esEditable(fecha, hoy);
    final actual = (valor as num?)?.toInt();
    final celda = CeldaEstado(estado: actual);
    return SizedBox(
      width: _anchoDia,
      height: _alto,
      child: Center(
        child: widget.soloLectura
            ? celda
            : editable
                ? InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _tocar(paseId, fecha, nl, actual),
                    child: celda,
                  )
                : Opacity(opacity: 0.4, child: celda),
      ),
    );
  }
}

/// Elegir formato y meses. Devuelve `(meses: {"AAAA-MM", ...}, xlsx: true|false)` o `null` si se cancela.
class _DialogoExportar extends StatefulWidget {
  const _DialogoExportar({required this.diasPorMes});

  /// "AAAA-MM" → días con pase, en orden.
  final Map<String, int> diasPorMes;

  @override
  State<_DialogoExportar> createState() => _DialogoExportarState();
}

class _DialogoExportarState extends State<_DialogoExportar> {
  late final Set<String> _meses = {...widget.diasPorMes.keys};
  bool _xlsx = true;

  @override
  Widget build(BuildContext context) {
    final todos = _meses.length == widget.diasPorMes.length;
    final chico = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title: const Text('Exportar registro'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Excel (.xlsx)'), icon: Icon(Icons.table_chart_outlined)),
                ButtonSegment(value: false, label: Text('CSV plano'), icon: Icon(Icons.notes)),
              ],
              selected: {_xlsx},
              onSelectionChanged: (s) => setState(() => _xlsx = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _xlsx
                  ? 'Una hoja por mes con los colores de la app, totales y % de asistencia. '
                      'Con varios meses, también una hoja de resumen.'
                  : 'Una sola tabla sin formato: P, F o J por fecha y los totales. Para abrir en '
                      'cualquier programa o importar a otro sistema.',
              style: chico,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text('Meses', style: Theme.of(context).textTheme.titleSmall)),
                TextButton(
                  onPressed: () => setState(() {
                    if (todos) {
                      _meses.clear();
                    } else {
                      _meses.addAll(widget.diasPorMes.keys);
                    }
                  }),
                  child: Text(todos ? 'Ninguno' : 'Todos'),
                ),
              ],
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final MapEntry(key: mes, value: dias) in widget.diasPorMes.entries)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _meses.contains(mes),
                      title: Text(nombreMes(mes)),
                      subtitle: Text(dias == 1 ? '1 día con pase' : '$dias días con pase'),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _meses.add(mes);
                        } else {
                          _meses.remove(mes);
                        }
                      }),
                    ),
                ],
              ),
            ),
            // La casilla de computadora compartida protege la caché, pero no lo descargado.
            if (kIsWeb) ...[
              const SizedBox(height: 8),
              Text(
                'El archivo trae los nombres de los alumnos. En una computadora compartida, bórralo '
                'de Descargas al terminar.',
                style: chico,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: _meses.isEmpty ? null : () => Navigator.pop(context, (meses: {..._meses}, xlsx: _xlsx)),
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Exportar'),
        ),
      ],
    );
  }
}
