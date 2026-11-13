import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/orden.dart';
import '../models/pase.dart';
import '../services/pases.dart';
import 'inicio.dart';

typedef _Snap = QuerySnapshot<Map<String, dynamic>>;

/// Lo que escucha [OrdenHome]; el detalle del grupo lo escucha también para actualizarse solo.
class _Datos extends ChangeNotifier {
  _Snap? grupos, clases, pases;
  Object? error;

  void poner(void Function() cambio) {
    cambio();
    notifyListeners();
  }

  bool get sinConexion => [grupos, clases, pases].any((s) => s?.metadata.isFromCache ?? false);

  List<Map<String, dynamic>> pasesDe(String grupoId) => [
    for (final p in [...?pases?.docs])
      if (p.data()['grupoId'] == grupoId) p.data(),
  ];
}

/// Solo lee: ausentes por grupo y el mensaje para el grupo de padres.
class OrdenHome extends StatefulWidget {
  const OrdenHome({super.key, required this.usuario});
  final Map<String, dynamic> usuario;

  @override
  State<OrdenHome> createState() => _OrdenHomeState();
}

class _OrdenHomeState extends State<OrdenHome> {
  final _datos = _Datos();
  String _fecha = fechaLocal(DateTime.now());
  late final List<StreamSubscription<void>> _subs;
  StreamSubscription<void>? _subPases;

  void _error(Object e) => _datos.poner(() => _datos.error = e);

  @override
  void initState() {
    super.initState();
    // Tres consultas para todos los grupos; nada de una consulta por grupo.
    _subs = [
      todosLosGrupos().listen((s) => _datos.poner(() => _datos.grupos = s), onError: _error),
      todasLasClases().listen((s) => _datos.poner(() => _datos.clases = s), onError: _error),
    ];
    _escucharPases();
  }

  void _escucharPases() {
    _subPases?.cancel();
    _datos.poner(() => _datos.pases = null);
    _subPases = pasesDeLaFecha(_fecha).listen((s) => _datos.poner(() => _datos.pases = s), onError: _error);
  }

  @override
  void dispose() {
    for (final s in [..._subs, _subPases]) {
      s?.cancel();
    }
    _datos.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_fecha),
      firstDate: DateTime(hoy.year - 1),
      lastDate: hoy,
    );
    if (elegida == null || fechaLocal(elegida) == _fecha) return;
    setState(() => _fecha = fechaLocal(elegida));
    _escucharPases();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _datos,
      builder: (context, _) {
        final d = _datos;
        return Inicio(
          usuario: widget.usuario,
          children: [
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Grupos', style: Theme.of(context).textTheme.titleMedium),
                OutlinedButton.icon(
                  onPressed: _elegirFecha,
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_fecha),
                ),
              ],
            ),
            if (d.sinConexion) const _AvisoSinConexion(),
            if (d.error != null)
              Text('Error al cargar: ${d.error}')
            else if (d.grupos == null || d.clases == null || d.pases == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (d.grupos!.docs.isEmpty)
              const ListTile(title: Text('Aún no hay grupos.'))
            else
              for (final g in [...d.grupos!.docs]..sort((a, b) => _nombre(a).compareTo(_nombre(b)))) _tile(context, g),
          ],
        );
      },
    );
  }

  Widget _tile(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> g) {
    final claseIds = {
      for (final c in _datos.clases!.docs)
        if (c.data()['grupoId'] == g.id) c.id,
    };
    final r = resumenDelGrupo(claseIds, _datos.pasesDe(g.id));
    // Los que el encargado tiene que ir a revisar: tienen clases y nadie ha pasado lista.
    final revisar = r.manana == null && r.clases > 0;
    final colores = Theme.of(context).colorScheme;
    final estado = r.manana == null ? 'Sin pase de la mañana' : 'Faltas sin justificar: ${r.faltas}';
    final fecha = _fecha;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: revisar ? colores.errorContainer : null,
        textColor: revisar ? colores.onErrorContainer : null,
        iconColor: revisar ? colores.onErrorContainer : null,
        leading: Icon(revisar ? Icons.warning_amber_rounded : Icons.groups_outlined),
        title: Text(_nombre(g)),
        subtitle: Text('Pases: ${r.conPase} de ${r.clases} clases · $estado'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => _GrupoDetalle(datos: _datos, grupoId: g.id, fecha: fecha),
          ),
        ),
      ),
    );
  }
}

String _nombre(DocumentSnapshot<Map<String, dynamic>> g) => '${g.data()?['nombre'] ?? g.id}';

String _hora(BuildContext context, Object? marcadoEn) => marcadoEn is Timestamp
    ? MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(marcadoEn.toDate()))
    : 'sin hora';

Map<String, dynamic> _estados(Map<String, dynamic> pase) =>
    Map<String, dynamic>.from(pase['estados'] as Map? ?? const {});

class _AvisoSinConexion extends StatelessWidget {
  const _AvisoSinConexion();

  @override
  Widget build(BuildContext context) =>
      const ListTile(leading: Icon(Icons.cloud_off), title: Text('Sin conexión: puede faltar información reciente'));
}

/// Pase de la mañana, otras clases del día y el mensaje para padres. Escucha [datos], así que si un
/// profe justifica una falta después, se actualiza solo.
class _GrupoDetalle extends StatelessWidget {
  const _GrupoDetalle({required this.datos, required this.grupoId, required this.fecha});
  final _Datos datos;
  final String grupoId, fecha;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: datos,
      builder: (context, _) {
        final grupo = datos.grupos?.docs.where((g) => g.id == grupoId).firstOrNull;
        final nombre = grupo == null ? grupoId : _nombre(grupo);
        final alumnos = (grupo?.data()['alumnos'] as List?) ?? const [];
        final pases = datos.pasesDe(grupoId);
        final manana = paseDeLaManana(pases);
        final otras = [...pases]
          ..remove(manana)
          ..sort((a, b) => _ms(a).compareTo(_ms(b)));
        final faltas = manana == null ? const <String>[] : alumnosConEstado(alumnos, _estados(manana), falta);
        final titulo = Theme.of(context).textTheme.titleMedium;

        return Scaffold(
          appBar: AppBar(title: Text('Grupo $nombre · $fecha')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (datos.sinConexion) const _AvisoSinConexion(),
              if (datos.error != null) Text('Error al cargar: ${datos.error}'),
              Text('Pase de la mañana', style: titulo),
              if (manana == null)
                const Padding(padding: EdgeInsets.only(top: 8), child: Text('Todavía no hay pase de este día.'))
              else ...[
                Text(
                  '${manana['materia'] ?? ''} · Salón ${manana['salon'] ?? ''} · ${_hora(context, manana['marcadoEn'])}',
                ),
                ..._lista(context, 'Faltas sin justificar', faltas),
                ..._lista(context, 'Faltas justificadas', alumnosConEstado(alumnos, _estados(manana), justificada)),
              ],
              const Divider(height: 32),
              Text('Otras clases del día', style: titulo),
              if (otras.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 8), child: Text('No hay otras clases con pase este día.'))
              else
                for (final p in otras) _otraClase(context, p, alumnos),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: manana == null
                    ? null
                    : () => _mostrarMensaje(context, mensajeParaPadres(nombre, fecha, DateTime.now(), faltas)),
                icon: const Icon(Icons.message_outlined),
                label: const Text('Generar mensaje'),
              ),
            ),
          ),
        );
      },
    );
  }

  static int _ms(Map<String, dynamic> p) => (p['marcadoEn'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;

  Widget _otraClase(BuildContext context, Map<String, dynamic> p, List<dynamic> alumnos) {
    final faltas = alumnosConEstado(alumnos, _estados(p), falta);
    final justificadas = alumnosConEstado(alumnos, _estados(p), justificada);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text('${p['materia'] ?? ''} · ${_hora(context, p['marcadoEn'])}'),
      subtitle: Text('Salón ${p['salon'] ?? ''} · Faltas: ${faltas.length} · Justificadas: ${justificadas.length}'),
      children: [
        ..._lista(context, 'Faltas sin justificar', faltas),
        ..._lista(context, 'Faltas justificadas', justificadas),
      ],
    );
  }

  List<Widget> _lista(BuildContext context, String titulo, List<String> nombres) => [
    Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text('$titulo (${nombres.length})', style: Theme.of(context).textTheme.titleSmall),
    ),
    if (nombres.isEmpty) const Text('Ninguna') else for (final n in nombres) Text('• $n'),
  ];

  void _mostrarMensaje(BuildContext context, String texto) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mensaje para padres'),
        content: SingleChildScrollView(child: SelectableText(texto)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          FilledButton.icon(
            onPressed: () async {
              final avisos = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: texto));
              if (context.mounted) Navigator.pop(context);
              avisos.showSnackBar(const SnackBar(content: Text('Mensaje copiado')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar'),
          ),
        ],
      ),
    );
  }
}
