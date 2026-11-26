import 'dart:async';

import 'package:flutter/material.dart';

import '../models/lote_csv.dart';
import '../models/lote_usuarios.dart';
import '../models/rol.dart';
import '../services/sesion.dart';
import 'inicio.dart';
import 'lote_comun.dart';

/// Invitar a varias personas a la vez desde un CSV `correo,rol`. El archivo se convierte en filas
/// que se pueden corregir o quitar; nada se guarda hasta tocar "Invitar".
class LoteUsuarios extends StatefulWidget {
  const LoteUsuarios({super.key});

  @override
  State<LoteUsuarios> createState() => _LoteUsuariosState();
}

class _LoteUsuariosState extends State<LoteUsuarios> {
  final _subs = <StreamSubscription<void>>[];
  Map<String, Rol?>? _usuarios;
  Map<String, Rol?>? _invitaciones;
  Object? _errorCarga;

  final _filas = <FilaInvitacion>[];
  Rol _porOmision = Rol.profesor;
  String? _archivo;
  String? _errorArchivo;

  @override
  void initState() {
    super.initState();
    void alFallar(Object e) => setState(() => _errorCarga = e);
    _subs.add(usuarios().listen(
      (s) => setState(() => _usuarios = {
            for (final d in s.docs) normalizarCorreo('${d.data()['email'] ?? ''}'): parseRol(d.data()['rol']),
          }),
      onError: alFallar,
    ));
    _subs.add(invitaciones().listen(
      (s) => setState(() => _invitaciones = {for (final d in s.docs) d.id: parseRol(d.data()['rol'])}),
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
      final lectura = leerInvitaciones(bytes);
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

  Map<String, String> get _opcionesRol => {for (final r in Rol.values) r.name: r.etiqueta};

  Future<void> _editar(FilaInvitacion f) async {
    final valores = await dialogoCampos(
      context,
      titulo: 'Corregir fila',
      campos: [
        CampoLote('Correo', f.correo, teclado: TextInputType.emailAddress),
        CampoLote('Rol', (f.rol ?? (f.rolTexto.trim().isEmpty ? _porOmision : null))?.name ?? '',
            opciones: _opcionesRol),
      ],
    );
    if (valores == null) return;
    setState(() {
      f.correo = valores[0].trim();
      f.rol = parseRol(valores[1]);
    });
  }

  Future<void> _agregar() async {
    final fila = FilaInvitacion(fila: 0, correo: '', rol: _porOmision);
    final valores = await dialogoCampos(
      context,
      titulo: 'Agregar persona',
      textoGuardar: 'Agregar',
      campos: [
        const CampoLote('Correo', '', teclado: TextInputType.emailAddress),
        CampoLote('Rol', _porOmision.name, opciones: _opcionesRol),
      ],
    );
    if (valores == null) return;
    fila
      ..correo = valores[0].trim()
      ..rol = parseRol(valores[1]);
    setState(() => _filas.add(fila));
  }

  Future<void> _invitar(List<({String correo, Rol rol})> personas) async {
    final ok = await confirmarLote(
      context,
      titulo: 'Invitar a ${personas.length} ${personas.length == 1 ? 'persona' : 'personas'}',
      mensaje: 'Se crean las invitaciones y cada quien entra con su cuenta de Google. '
          'Puedes cancelar una invitación que aún no se use desde la pestaña Usuarios.',
      boton: 'Invitar',
    );
    if (!ok || !mounted) return;
    // Sin `await`: sin internet el Future no se completa (ver CLAUDE.md); solo avisa si falla.
    avisarSiFallan(context, invitarVarios(personas), 'No se guardaron todas las invitaciones');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${personas.length} invitaciones creadas.')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final usuarios = _usuarios;
    final invitaciones = _invitaciones;
    final listo = usuarios != null && invitaciones != null;
    // Sin promoción por la variable `listo`: se compara directo para que Dart sepa que no son null.
    final resultados = usuarios != null && invitaciones != null
        ? validarInvitaciones(_filas, rolPorOmision: _porOmision, usuarios: usuarios, invitaciones: invitaciones)
        : const <ResultadoFila>[];
    final conteo = contarLote(resultados);
    final personas = <({String correo, Rol rol})>[
      if (listo)
        for (var i = 0; i < _filas.length; i++)
          if (resultados[i].seGuarda)
            (correo: normalizarCorreo(_filas[i].correo), rol: rolEfectivo(_filas[i], _porOmision)!),
    ];
    final puede = listo && personas.isNotEmpty && conteo.conError == 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Invitar varios usuarios')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CargaCsv(
            ayuda: 'Archivo CSV con una columna de correos y, si quieres, otra con el rol '
                '(profesor, orden o admin). El encabezado es opcional.',
            alLeer: _leer,
          ),
          if (_errorCarga != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('No se pudo revisar quién ya tiene acceso: $_errorCarga',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_errorArchivo != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_errorArchivo!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<Rol>(
            initialValue: _porOmision,
            decoration: const InputDecoration(
              labelText: 'Rol para las filas sin rol',
              border: OutlineInputBorder(),
            ),
            items: [for (final r in Rol.values) DropdownMenuItem(value: r, child: Text(r.etiqueta))],
            onChanged: (r) => setState(() => _porOmision = r ?? _porOmision),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(_archivo == null ? 'Personas' : 'Personas de $_archivo',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(onPressed: _agregar, icon: const Icon(Icons.add), label: const Text('Agregar')),
            ],
          ),
          if (_filas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Elige un archivo o agrega personas a mano.'),
            )
          else if (!listo)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else ...[
            ResumenLote(conteo: conteo),
            const SizedBox(height: 8),
            for (var i = 0; i < _filas.length; i++) ...[
              FilaLote(
                titulo: _filas[i].correo,
                detalle: rolEfectivo(_filas[i], _porOmision)?.etiqueta ??
                    (_filas[i].rolTexto.isEmpty ? 'Sin rol' : 'Rol: ${_filas[i].rolTexto}'),
                resultado: resultados[i],
                alEditar: () => _editar(_filas[i]),
                alQuitar: () => setState(() => _filas.removeAt(i)),
              ),
              const Divider(height: 1),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: puede ? () => _invitar(personas) : null,
                icon: const Icon(Icons.group_add),
                label: Text('Invitar (${personas.length})'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
