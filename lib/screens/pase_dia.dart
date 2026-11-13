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
    if (elegida == null || fechaLocal(elegida) == _fecha) return;
    setState(() {
      _fecha = fechaLocal(elegida);
      _escuchar();
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo),
        actions: [
          IconButton(
            tooltip: 'Vista mensual',
            icon: const Icon(Icons.calendar_view_month),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => PaseMensual(
                  clase: widget.clase,
                  grupo: widget.grupo,
                  titulo: widget.titulo,
                  mes: DateTime.parse(_fecha),
                ),
              ),
            ),
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
    final guardados = pase == null
        ? estadosIniciales(alumnos)
        : Map<String, dynamic>.from(pase['estados'] as Map? ?? const {});
    final editable = esEditable(_fecha, DateTime.now());
    final filas = filasDelPase(alumnos, guardados);
    final campos = pase == null ? const <String, int>{} : camposEditados(guardados, _cambios);

    final String estado;
    if (pase == null) {
      estado = editable ? 'Sin enviar' : 'No hay pase de este día';
    } else {
      estado = doc!.metadata.hasPendingWrites ? 'Pendiente de enviar' : 'Enviado';
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _elegirFecha,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_fecha),
                  ),
                  Chip(
                    avatar: Icon(
                      pase == null
                          ? Icons.edit_note
                          : doc!.metadata.hasPendingWrites
                              ? Icons.cloud_upload_outlined
                              : Icons.cloud_done_outlined,
                    ),
                    label: Text(estado),
                  ),
                  if (!editable && pase != null) const Chip(label: Text('Solo lectura')),
                ],
              ),
              const SizedBox(height: 12),
              if (pase == null && editable)
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _salon,
                    decoration: const InputDecoration(
                      labelText: 'Salón',
                      helperText: 'Después de enviar ya no se puede cambiar',
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
              const SizedBox(height: 12),
              const LeyendaEstados(),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: filas.isEmpty
              ? const Center(child: Text('Este grupo no tiene alumnos activos.'))
              : ListView(
                  children: [
                    if (pase != null || editable)
                      for (final f in filas) _fila(f, guardados, editable),
                  ],
                ),
        ),
        if (editable && filas.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
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

  Widget _fila(Fila f, Map<String, dynamic> guardados, bool editable) {
    final actual = _cambios[f.nl] ?? (guardados[f.nl] as num?)?.toInt();
    return ListTile(
      leading: SizedBox(width: 32, child: Text(f.nl, textAlign: TextAlign.end)),
      title: Text(f.nombre),
      subtitle: f.baja ? const Text('Dado de baja') : null,
      trailing: CeldaEstado(estado: actual),
      // Un alumno sin registro en un pase ya enviado empieza en presente al tocarlo.
      onTap: editable
          ? () => setState(() => _cambios[f.nl] = actual == null ? presente : siguienteEstado(actual))
          : null,
    );
  }

  void _enviar(Map<String, dynamic> iniciales) {
    avisarSiFalla(
      context,
      enviarPase(
        claseId: widget.clase.id,
        clase: widget.clase.data()!,
        fecha: _fecha,
        salon: _salon.text.trim(),
        estados: {...iniciales.cast<String, int>(), ..._cambios},
      ),
      'No se envió el pase del $_fecha',
    );
    setState(_cambios.clear);
  }

  void _guardar(Map<String, int> campos) {
    avisarSiFalla(context, guardarCambios(paseId(widget.clase.id, _fecha), campos),
        'No se guardaron los cambios del $_fecha');
    setState(_cambios.clear);
  }
}
