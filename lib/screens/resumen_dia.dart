import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/clase.dart';
import '../models/grupo.dart' show sinAcentos;
import '../models/pase.dart';
import '../models/resumen_dia.dart';
import '../services/pases.dart';
import 'pase_mensual.dart';

/// Primera pestaña del admin: qué clases ya pasaron lista en un día (hoy por omisión) y cuáles no,
/// con las faltas de cada pase. Solo lee. Las clases, los grupos y los usuarios los escucha
/// `AdminHome`; los pases del día los escucha esta pantalla, porque cambian con la fecha.
class ResumenDia extends StatefulWidget {
  const ResumenDia({
    super.key,
    required this.clases,
    required this.grupos,
    required this.usuarios,
    this.errorClases,
  });

  final QuerySnapshot<Map<String, dynamic>>? clases;
  final QuerySnapshot<Map<String, dynamic>>? grupos;
  final QuerySnapshot<Map<String, dynamic>>? usuarios;
  final Object? errorClases;

  @override
  State<ResumenDia> createState() => _ResumenDiaState();
}

class _ResumenDiaState extends State<ResumenDia> {
  String _fecha = fechaLocal(DateTime.now());
  FiltroDia _filtro = FiltroDia.todas;

  /// Grupo elegido para filtrar; `null` = todos.
  String? _grupoId;
  QuerySnapshot<Map<String, dynamic>>? _pases;
  Object? _errorPases;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _escuchar();
  }

  void _escuchar() {
    _sub?.cancel();
    _sub = pasesDeLaFecha(_fecha).listen(
      (s) => setState(() => _pases = s),
      onError: (Object e) => setState(() => _errorPases = e),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _cambiarFecha(String fecha) {
    if (fecha == _fecha) return;
    setState(() {
      _fecha = fecha;
      _pases = null;
      _errorPases = null;
    });
    _escuchar();
  }

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_fecha),
      firstDate: DateTime(hoy.year - 1),
      lastDate: hoy,
    );
    if (elegida != null) _cambiarFecha(fechaLocal(elegida));
  }

  static String _hora(BuildContext context, Object? marcadoEn) => marcadoEn is Timestamp
      ? MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(marcadoEn.toDate()))
      : '';

  @override
  Widget build(BuildContext context) {
    final error = widget.errorClases ?? _errorPases;
    final clasesSnap = widget.clases;
    final pasesSnap = _pases;
    final hoy = fechaLocal(DateTime.now());

    final cabecera = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _elegirFecha,
          icon: const Icon(Icons.calendar_today),
          label: Text(_fecha),
        ),
        if (_fecha != hoy) TextButton(onPressed: () => _cambiarFecha(hoy), child: const Text('Hoy')),
      ],
    );

    final List<Widget> cuerpo;
    if (error != null) {
      cuerpo = [Text('Error al cargar: $error')];
    } else if (clasesSnap == null || pasesSnap == null) {
      cuerpo = const [
        Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      ];
    } else {
      cuerpo = _contenido(context, clasesSnap, pasesSnap);
    }

    return ListView(
      key: const PageStorageKey('resumen'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [cabecera, const SizedBox(height: 8), ...cuerpo],
    );
  }

  List<Widget> _contenido(
    BuildContext context,
    QuerySnapshot<Map<String, dynamic>> clasesSnap,
    QuerySnapshot<Map<String, dynamic>> pasesSnap,
  ) {
    final nombresGrupo = {
      for (final d in [...?widget.grupos?.docs]) d.id: '${d.data()['nombre'] ?? d.id}',
    };
    final nombresProfe = {
      for (final d in [...?widget.usuarios?.docs])
        if ('${d.data()['nombre'] ?? ''}'.trim().isNotEmpty) d.id: '${d.data()['nombre']}'.trim(),
    };
    final resumen = resumenDelDia(
      [for (final d in clasesSnap.docs) ?claseDe(d.id, d.data())],
      [for (final d in pasesSnap.docs) d.data()],
    );
    final grupos = nombresGrupo.entries.toList()
      ..sort((a, b) => sinAcentos(a.value).compareTo(sinAcentos(b.value)));
    // Si el grupo elegido se borró mientras tanto, se vuelve a mostrar todo.
    final grupoElegido = grupos.any((g) => g.key == _grupoId) ? _grupoId : null;
    final lista = listarDelDia(
      resumen,
      filtro: _filtro,
      grupoId: grupoElegido,
      nombresGrupo: nombresGrupo,
      nombresProfe: nombresProfe,
    );
    final colores = Theme.of(context).colorScheme;
    final textos = Theme.of(context).textTheme;
    final sinPase = resumen.profesSinPase;
    String profeDe(Clase c) => nombresProfe[c.profesorUid] ?? c.profesorNombre;

    return [
      if (pasesSnap.metadata.isFromCache || clasesSnap.metadata.isFromCache)
        const ListTile(
          leading: Icon(Icons.cloud_off),
          title: Text('Sin conexión: puede faltar información reciente'),
        ),
      if (resumen.total == 0)
        const ListTile(
          leading: Icon(Icons.class_outlined),
          title: Text('Aún no hay clases dadas de alta.'),
          subtitle: Text('Se dan de alta desde la pantalla de cada grupo, o en bloque desde '
              'Herramientas avanzadas.'),
        )
      else ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${resumen.conPase} de ${resumen.total} clases con pase', style: textos.titleMedium),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: resumen.conPase / resumen.total),
                const SizedBox(height: 8),
                Text('Faltas sin justificar: ${resumen.faltas} · Justificadas: ${resumen.justificadas}'),
                if (!resumen.huboPases)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Nadie ha pasado lista este día (fin de semana, día festivo o todavía temprano).',
                      style: textos.bodySmall?.copyWith(color: colores.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (sinPase.isNotEmpty)
          ExpansionTile(
            leading: Icon(Icons.person_off_outlined, color: colores.error),
            title: Text(sinPase.length == 1
                ? '1 profesor sin ningún pase'
                : '${sinPase.length} profesores sin ningún pase'),
            childrenPadding: const EdgeInsets.only(left: 16, bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final uid in sinPase)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• ${_lineaProfeSinPase(resumen, uid, nombresGrupo, nombresProfe)}'),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'La app no guarda horarios: una clase sin pase puede simplemente no haber tenido '
            'clase ese día.',
            style: textos.bodySmall?.copyWith(color: colores.onSurfaceVariant),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final f in FiltroDia.values)
              ChoiceChip(
                label: Text(f.etiqueta),
                selected: _filtro == f,
                onSelected: (_) => setState(() => _filtro = f),
              ),
            DropdownButton<String?>(
              value: grupoElegido,
              onChanged: (g) => setState(() => _grupoId = g),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todos los grupos')),
                for (final g in grupos) DropdownMenuItem<String?>(value: g.key, child: Text(g.value)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (lista.isEmpty)
          const ListTile(title: Text('Ninguna clase coincide con el filtro.'))
        else
          for (final c in lista) _fila(context, c, resumen, nombresGrupo, profeDe(c.clase)),
      ],
    ];
  }

  /// "Ana López: IA 3A · Matemáticas, IA 3B · Física" para la lista de profes sin pase.
  String _lineaProfeSinPase(
    ResumenDelDia resumen,
    String uid,
    Map<String, String> nombresGrupo,
    Map<String, String> nombresProfe,
  ) {
    final suyas = [for (final c in resumen.clases) if (c.clase.profesorUid == uid) c.clase];
    final nombre = nombresProfe[uid] ?? suyas.first.profesorNombre;
    final clases = [
      for (final c in suyas) '${nombresGrupo[c.grupoId] ?? c.grupoId} · ${c.materia}',
    ]..sort();
    return '${nombre.isEmpty ? 'Profesor sin nombre' : nombre}: ${clases.join(', ')}';
  }

  Widget _fila(
    BuildContext context,
    ClaseDelDia c,
    ResumenDelDia resumen,
    Map<String, String> nombresGrupo,
    String profe,
  ) {
    final clase = c.clase;
    final colores = Theme.of(context).colorScheme;
    final resaltar = resumen.resaltar(c);
    final grupo = nombresGrupo[clase.grupoId] ?? clase.grupoId;
    // El salón real de ese día va en el pase; el de siempre, en la clase.
    final salon = '${c.pase?['salon'] ?? clase.salon}';
    final detalle = [
      profeYSalon(profe, salon),
      if (c.conPase) ...[
        _hora(context, c.pase?['marcadoEn']),
        'Faltas: ${c.faltas}',
        if (c.justificadas > 0) 'Justificadas: ${c.justificadas}',
      ] else
        'Sin pase',
    ].where((t) => t.isNotEmpty).join(' · ');
    final grupoDoc = widget.grupos?.docs.where((g) => g.id == clase.grupoId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: resaltar ? colores.errorContainer : null,
        textColor: resaltar ? colores.onErrorContainer : null,
        iconColor: resaltar ? colores.onErrorContainer : null,
        leading: Icon(
          c.conPase
              ? Icons.check_circle_outline
              : resaltar
                  ? Icons.warning_amber_rounded
                  : Icons.radio_button_unchecked,
          color: c.conPase ? colores.primary : null,
        ),
        title: Text('$grupo · ${clase.materia}'),
        subtitle: Text(detalle),
        trailing: grupoDoc == null ? null : const Icon(Icons.chevron_right),
        onTap: grupoDoc == null
            ? null
            : () => abrirConsultaMensual(
                  context,
                  claseId: clase.id,
                  grupo: grupoDoc,
                  titulo: '$grupo · ${clase.materia}',
                  subtitulo: profeYSalon(profe, clase.salon),
                  mes: DateTime.parse(_fecha),
                ),
      ),
    );
  }
}
