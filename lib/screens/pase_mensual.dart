import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/pase.dart';
import '../services/pases.dart';
import 'celda_estado.dart';
import 'inicio.dart';

const _alto = 48.0;
const _anchoDia = 96.0;

/// Vista mensual de una clase: una columna por cada día con pase. N.L y Nombre quedan fijos y las
/// fechas se desplazan en horizontal.
class PaseMensual extends StatefulWidget {
  const PaseMensual({
    super.key,
    required this.clase,
    required this.grupo,
    required this.titulo,
    required this.mes,
  });
  final DocumentSnapshot<Map<String, dynamic>> clase, grupo;
  final String titulo;
  final DateTime mes;

  @override
  State<PaseMensual> createState() => _PaseMensualState();
}

class _PaseMensualState extends State<PaseMensual> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  late DateTime _mes = DateTime(widget.mes.year, widget.mes.month);
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
    super.dispose();
  }

  void _escuchar() {
    _sub?.cancel();
    _snap = null;
    _error = null;
    _sub = pasesDelMes(_uid, widget.clase.id, rangoDelMes(_mes.year, _mes.month)).listen(
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

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final esMesActual = _mes.year == hoy.year && _mes.month == hoy.month;
    final snap = _snap;
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                LeyendaEstados(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 18),
                    SizedBox(width: 6),
                    Text('Más de $diasEditables días: solo lectura'),
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
    final anchoFijo = min(240.0, MediaQuery.sizeOf(context).width * 0.45);
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

  Widget _cabecera(String fecha, DocumentSnapshot<Object?> pase, DateTime hoy, TextStyle? estilo) {
    final editable = esEditable(fecha, hoy);
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
        child: editable
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
