import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/pase.dart';
import '../services/pases.dart';
import 'celda_estado.dart';
import 'inicio.dart';
import 'pase_mensual.dart';

/// Pase de lista de una clase en un día: crear (Enviar) o editar (Guardar cambios).
class PaseDia extends StatefulWidget {
  const PaseDia({super.key, required this.clase, required this.grupo, required this.titulo});
  final DocumentSnapshot<Map<String, dynamic>> clase, grupo;
  final String titulo;

  @override
  State<PaseDia> createState() => _PaseDiaState();
}

class _PaseDiaState extends State<PaseDia> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  late final _salon = TextEditingController(text: '${widget.clase.data()?['salon'] ?? ''}');
  late final _duales = dualesDe(widget.grupo.data()?['duales']);
  String _fecha = fechaLocal(DateTime.now());
  /// N.L → estado tocado en pantalla y aún sin enviar o guardar.
  final _cambios = <String, int>{};
  QuerySnapshot<Map<String, dynamic>>? _snap;
  Object? _error;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _escuchar();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _salon.dispose();
    super.dispose();
  }

  void _escuchar() {
    _sub?.cancel();
    _snap = null;
    _error = null;
    _cambios.clear();
    _sub = paseDelDia(_uid, widget.clase.id, _fecha).listen(
      (s) => setState(() => _snap = s),
      onError: (Object e) => setState(() => _error = e),
    );
  }

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: esEditable(_fecha, hoy) ? DateTime.parse(_fecha) : hoy,
      firstDate: DateTime(hoy.year, hoy.month, hoy.day - diasEditables),
      lastDate: hoy,
    );
    if (elegida == null || fechaLocal(elegida) == _fecha || !await _descartarCambios()) return;
    setState(() {
      _fecha = fechaLocal(elegida);
      _escuchar();
    });
  }

  /// Estados con los que se comparan los cambios: los del pase, o los iniciales si es nuevo.
  Map<String, dynamic> _guardados(Map<String, dynamic>? pase) => pase == null
      ? estadosIniciales((widget.grupo.data()?['alumnos'] as List?) ?? const [], _duales)
      : Map<String, dynamic>.from(pase['estados'] as Map? ?? const {});

  /// Lo mismo que habilita "Guardar cambios": tocar un alumno y regresarlo a como estaba no cuenta.
  bool get _hayCambios => camposEditados(_guardados(_snap?.docs.firstOrNull?.data()), _cambios).isNotEmpty;

  /// `true` si no hay cambios sin guardar o el profe decide descartarlos.
  Future<bool> _descartarCambios() async {
    if (!_hayCambios) return true;
    final descartar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambios sin guardar'),
        content: Text('Tienes cambios sin guardar en el pase del $_fecha.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Descartar cambios')),
          FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Seguir editando')),
        ],
      ),
    );
    if (descartar != true || !mounted) return false;
    setState(_cambios.clear);
    return true;
  }

  Future<void> _abrirMensual() async {
    if (!await _descartarCambios() || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PaseMensual(
          claseId: widget.clase.id,
          grupo: widget.grupo,
          titulo: widget.titulo,
          mes: DateTime.parse(_fecha),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    return PopScope(
      canPop: !_hayCambios,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !await _descartarCambios() || !context.mounted) return;
        Navigator.pop(context);
      },
      child: _pantalla(snap),
    );
  }

  Widget _pantalla(QuerySnapshot<Map<String, dynamic>>? snap) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo),
        actions: [
          IconButton(
            tooltip: 'Vista mensual',
            icon: const Icon(Icons.calendar_view_month),
            onPressed: _abrirMensual,
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text('Error al cargar el pase: $_error'))
          : snap == null
              ? const Center(child: CircularProgressIndicator())
              : _contenido(snap),
    );
  }

  Widget _contenido(QuerySnapshot<Map<String, dynamic>> snap) {
    final alumnos = (widget.grupo.data()?['alumnos'] as List?) ?? const [];
    final doc = snap.docs.firstOrNull;
    final pase = doc?.data();
    final guardados = _guardados(pase);
    final editable = esEditable(_fecha, DateTime.now());
    final filas = filasDelPase(alumnos, guardados);
    final campos = pase == null ? const <String, int>{} : camposEditados(guardados, _cambios);

    final String estado;
    if (pase == null) {
      estado = editable ? 'Sin enviar' : 'No hay pase de este día';
    } else {
      estado = doc!.metadata.hasPendingWrites ? 'Pendiente de enviar' : 'Enviado';
    }

    final compacto = esCompacto(context);
    final denso = compacto ? VisualDensity.compact : null;
    final encabezado = Padding(
      padding: EdgeInsets.fromLTRB(16, compacto ? 8 : 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: compacto ? 8 : 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(visualDensity: denso),
                onPressed: _elegirFecha,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(_fecha),
              ),
              Chip(
                visualDensity: denso,
                avatar: Icon(
                  pase == null
                      ? Icons.edit_note
                      : doc!.metadata.hasPendingWrites
                          ? Icons.cloud_upload_outlined
                          : Icons.cloud_done_outlined,
                ),
                label: Text(estado),
              ),
              if (!editable && pase != null) Chip(visualDensity: denso, label: const Text('Solo lectura')),
            ],
          ),
          SizedBox(height: compacto ? 4 : 12),
          if (pase == null && editable)
            SizedBox(
              width: 260,
              child: TextField(
                controller: _salon,
                decoration: InputDecoration(
                  labelText: 'Salón',
                  isDense: compacto,
                  helperText: 'Después de enviar ya no se puede cambiar',
                  helperMaxLines: 2,
                ),
              ),
            )
          else if (pase != null)
            Text('Salón: ${pase['salon']}'),
          // Sin conexión y sin caché no se sabe si ya hay un pase de este día en otro dispositivo.
          if (pase == null && editable && snap.metadata.isFromCache)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Sin conexión: si ya pasaste lista de este día en otro dispositivo, '
                'espera a tener internet antes de enviar.',
              ),
            ),
          SizedBox(height: compacto ? 8 : 12),
          LeyendaEstados(compacta: compacto, conDual: _duales.isNotEmpty),
        ],
      ),
    );

    // El encabezado va dentro de la lista: en el teléfono se va con el scroll y deja toda la pantalla
    // para los alumnos. El botón de abajo sí queda fijo.
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              encabezado,
              const Divider(),
              if (filas.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('Este grupo no tiene alumnos activos.')),
                )
              else if (pase != null || editable)
                for (final f in filas) _fila(f, guardados, editable, compacto),
            ],
          ),
        ),
        if (editable && filas.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: compacto ? const EdgeInsets.fromLTRB(16, 8, 16, 12) : const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: pase == null
                    ? FilledButton.icon(
                        onPressed: () => _enviar(guardados),
                        icon: const Icon(Icons.send),
                        label: const Text('Enviar'),
                      )
                    : FilledButton.icon(
                        onPressed: campos.isEmpty ? null : () => _guardar(campos),
                        icon: const Icon(Icons.save),
                        label: Text(campos.isEmpty ? 'Sin cambios' : 'Guardar cambios (${campos.length})'),
                      ),
              ),
            ),
          ),
      ],
    );
  }

  /// [compacto]: letra un poco más chica y menos margen, para que la mayoría de los nombres quepan en
  /// una línea en el teléfono. La fila conserva su alto mínimo de 48 para tocarla con el dedo.
  Widget _fila(Fila f, Map<String, dynamic> guardados, bool editable, bool compacto) {
    final actual = _cambios[f.nl] ?? (guardados[f.nl] as num?)?.toInt();
    final texto = Theme.of(context).textTheme;
    return ListTile(
      shape: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      visualDensity: compacto ? VisualDensity.compact : null,
      contentPadding: compacto ? const EdgeInsets.symmetric(horizontal: 12) : null,
      minLeadingWidth: compacto ? 24 : null,
      horizontalTitleGap: compacto ? 10 : null,
      leading: SizedBox(
        width: compacto ? 24 : 32,
        child: Text(f.nl, textAlign: TextAlign.end, style: compacto ? texto.bodySmall : null),
      ),
      title: Text(f.nombre, style: compacto ? texto.bodyMedium : null),
      subtitle: f.baja ? const Text('Dado de baja') : null,
      trailing: CeldaEstado(estado: actual),
      onTap: editable ? () => setState(() => _cambios[f.nl] = _siguiente(f.nl, actual)) : null,
    );
  }

  /// Un alumno sin registro en un pase ya enviado empieza en presente (o dual) al tocarlo.
  int _siguiente(String nl, int? actual) {
    final esDual = _duales.contains(nl);
    return actual == null ? (esDual ? dual : presente) : siguienteEstado(actual, esDual: esDual);
  }

  void _enviar(Map<String, dynamic> iniciales) {
    final avisos = ScaffoldMessenger.of(context);
    final fecha = _fecha;
    // Sin `await`: sin internet el Future no se completa (ver CLAUDE.md); solo avisa si falla.
    enviarPase(
      claseId: widget.clase.id,
      clase: widget.clase.data()!,
      fecha: fecha,
      salon: _salon.text.trim(),
      estados: {...iniciales.cast<String, int>(), ..._cambios},
    ).catchError((Object e) {
      avisos.showSnackBar(SnackBar(content: Text(mensajeErrorEnvio(e, fecha))));
    });
    setState(_cambios.clear);
  }

  void _guardar(Map<String, int> campos) {
    avisarSiFalla(context, guardarCambios(paseId(widget.clase.id, _fecha), campos),
        'No se guardaron los cambios del $_fecha');
    setState(_cambios.clear);
  }
}
