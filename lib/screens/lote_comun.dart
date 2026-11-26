import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/lote_csv.dart';
import 'importar_csv.dart' show ZonaArchivo;

// Piezas compartidas por las tres herramientas por lote (invitar usuarios, importar grupos y dar de
// alta clases): elegir el CSV, la barra de resumen, las filas de la vista previa y el diálogo para
// corregir una fila a mano.

/// Zona para elegir o soltar un .csv; entrega el nombre y los bytes a [alLeer].
class CargaCsv extends StatefulWidget {
  const CargaCsv({super.key, required this.ayuda, required this.alLeer});

  /// Qué columnas lleva el archivo (se muestra arriba de la zona).
  final String ayuda;
  final void Function(String nombre, List<int> bytes) alLeer;

  @override
  State<CargaCsv> createState() => _CargaCsvState();
}

class _CargaCsvState extends State<CargaCsv> {
  String? _archivo;
  String? _error;
  bool _arrastrando = false;

  Future<void> _elegir() async {
    try {
      final archivo = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['csv']);
      if (archivo == null) return; // canceló
      await _cargar(archivo.name, archivo.readAsBytes());
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo abrir el archivo: $e');
    }
  }

  Future<void> _soltar(DropDoneDetails detalle) async {
    setState(() => _arrastrando = false);
    if (detalle.files.isEmpty) return;
    if (detalle.files.length > 1) {
      setState(() => _error = 'Suelta un solo archivo a la vez.');
      return;
    }
    final archivo = detalle.files.single;
    await _cargar(archivo.name, archivo.readAsBytes());
  }

  Future<void> _cargar(String nombre, Future<List<int>> bytes) async {
    if (!nombre.toLowerCase().endsWith('.csv')) {
      setState(() => _error = '"$nombre" no es un archivo .csv. En Excel usa Guardar como → CSV.');
      return;
    }
    try {
      final datos = await bytes;
      if (!mounted) return;
      setState(() {
        _archivo = nombre;
        _error = null;
      });
      widget.alLeer(nombre, datos);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo leer "$nombre": $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.ayuda),
        const SizedBox(height: 12),
        DropTarget(
          onDragEntered: (_) => setState(() => _arrastrando = true),
          onDragExited: (_) => setState(() => _arrastrando = false),
          onDragDone: _soltar,
          child: ZonaArchivo(resaltada: _arrastrando, archivo: _archivo, alTocar: _elegir),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }
}

/// Un campo del diálogo de edición. Con [opciones] (valor → etiqueta) se elige de una lista.
class CampoLote {
  const CampoLote(this.etiqueta, this.valor, {this.opciones, this.maxLength, this.teclado});
  final String etiqueta;
  final String valor;
  final Map<String, String>? opciones;
  final int? maxLength;
  final TextInputType? teclado;
}

/// Diálogo para corregir una fila: devuelve los valores nuevos en el orden de [campos], o `null` si
/// cancela.
Future<List<String>?> dialogoCampos(
  BuildContext context, {
  required String titulo,
  required List<CampoLote> campos,
  String textoGuardar = 'Guardar',
}) =>
    showDialog<List<String>>(
      context: context,
      builder: (_) => _DialogoCampos(titulo: titulo, campos: campos, textoGuardar: textoGuardar),
    );

class _DialogoCampos extends StatefulWidget {
  const _DialogoCampos({required this.titulo, required this.campos, required this.textoGuardar});
  final String titulo;
  final List<CampoLote> campos;
  final String textoGuardar;

  @override
  State<_DialogoCampos> createState() => _DialogoCamposState();
}

class _DialogoCamposState extends State<_DialogoCampos> {
  late final List<TextEditingController> _controles = [
    for (final c in widget.campos) TextEditingController(text: c.valor),
  ];
  late final List<String> _elegidos = [for (final c in widget.campos) c.valor];

  @override
  void dispose() {
    for (final c in _controles) {
      c.dispose();
    }
    super.dispose();
  }

  void _guardar() => Navigator.pop(context, [
        for (var i = 0; i < widget.campos.length; i++)
          widget.campos[i].opciones == null ? _controles[i].text : _elegidos[i],
      ]);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.campos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: widget.campos[i].opciones == null
                      ? TextField(
                          controller: _controles[i],
                          autofocus: i == 0,
                          maxLength: widget.campos[i].maxLength,
                          keyboardType: widget.campos[i].teclado,
                          decoration: InputDecoration(
                            labelText: widget.campos[i].etiqueta,
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _guardar(),
                        )
                      : DropdownButtonFormField<String>(
                          initialValue: widget.campos[i].opciones!.containsKey(_elegidos[i])
                              ? _elegidos[i]
                              : null,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: widget.campos[i].etiqueta,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            for (final e in widget.campos[i].opciones!.entries)
                              DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => setState(() => _elegidos[i] = v ?? ''),
                        ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: Text(widget.textoGuardar)),
      ],
    );
  }
}

// Mismo amarillo pastel que la falta justificada: llama la atención sin parecer error.
const _amarillo = Color(0xFFFFF3C4);

/// Una fila de la vista previa: en rojo si tiene errores, amarilla si solo avisos y gris si se omite.
/// [titulo] y [detalle] son lo que se va a guardar; abajo van los mensajes de [resultado].
class FilaLote extends StatelessWidget {
  const FilaLote({
    super.key,
    required this.titulo,
    this.detalle,
    required this.resultado,
    this.alEditar,
    this.alQuitar,
  });

  final String titulo;
  final String? detalle;
  final ResultadoFila resultado;
  final VoidCallback? alEditar;
  final VoidCallback? alQuitar;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final textos = Theme.of(context).textTheme;
    final conError = resultado.errores.isNotEmpty;
    final omitida = resultado.omitida != null;
    final Color? fondo = conError
        ? colores.errorContainer
        : omitida
            ? colores.surfaceContainerHighest
            : resultado.avisos.isNotEmpty
                ? _amarillo
                : null;
    final Color base = omitida ? colores.outline : colores.onSurface;
    return Container(
      color: fondo,
      padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo.isEmpty ? '(vacío)' : titulo,
                      style: textos.bodyLarge?.copyWith(color: base)),
                  if (detalle != null && detalle!.isNotEmpty)
                    Text(detalle!, style: textos.bodySmall?.copyWith(color: base)),
                  for (final e in resultado.errores)
                    Text(e, style: textos.bodySmall?.copyWith(color: colores.onErrorContainer)),
                  for (final a in resultado.avisos)
                    Text(a, style: textos.bodySmall?.copyWith(color: const Color(0xFF5F4B00))),
                  if (resultado.omitida != null)
                    Text('Se omite: ${resultado.omitida}', style: textos.bodySmall?.copyWith(color: base)),
                ],
              ),
            ),
          ),
          if (alEditar != null)
            IconButton(tooltip: 'Corregir', onPressed: alEditar, icon: const Icon(Icons.edit_outlined)),
          if (alQuitar != null)
            IconButton(tooltip: 'Quitar del lote', onPressed: alQuitar, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }
}

/// "3 se guardarán · 1 omitida · 2 con error" y, si hay, cuántas filas traen un aviso.
class ResumenLote extends StatelessWidget {
  const ResumenLote({super.key, required this.conteo, this.extra});
  final ConteoLote conteo;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          resumenLote(conteo),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: conteo.conError > 0 ? colores.error : null,
              ),
        ),
        if (conteo.conAviso > 0)
          Text('${conteo.conAviso} con aviso: se guardan, pero conviene revisarlas.'),
        if (extra != null) Text(extra!),
        if (conteo.conError > 0)
          Text('Corrige las filas en rojo (lápiz) o quítalas del lote (✕) para poder guardar.',
              style: TextStyle(color: colores.error)),
      ],
    );
  }
}

/// Confirma antes de escribir: dice qué se va a guardar y que se puede deshacer a mano.
Future<bool> confirmarLote(BuildContext context, {required String titulo, required String mensaje, required String boton}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(boton)),
      ],
    ),
  );
  return ok == true;
}
