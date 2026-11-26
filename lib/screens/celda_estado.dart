import 'package:flutter/material.dart';

import '../models/pase.dart';

const _nombres = {presente: 'Presente', falta: 'Falta', justificada: 'Falta justificada', dual: 'Dual'};

/// En la leyenda compacta "Falta justificada" no cabe junto a las otras en un teléfono.
const _nombresCortos = {presente: 'Presente', falta: 'Falta', justificada: 'Justificada', dual: 'Dual'};

/// Azul del modo dual: fondo de la celda y del botón que lo activa.
const azulDual = Color(0xFF1565C0);

/// Ancho a partir del cual la pantalla ya no se considera teléfono: debajo, la vista por día y la
/// mensual usan su versión compacta.
const anchoCompacto = 600.0;

bool esCompacto(BuildContext context) => MediaQuery.sizeOf(context).width < anchoCompacto;

/// Símbolo y colores de un estado; los mismos en la vista por día y en la mensual.
/// `estado == null` = sin registro: celda vacía.
class CeldaEstado extends StatelessWidget {
  const CeldaEstado({super.key, required this.estado, this.tamano = 36});
  final int? estado;

  /// Lado del cuadro. 36 en las listas (con el área de toque de su fila); más chico en la leyenda.
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final (Color? fondo, Widget? simbolo) = switch (estado) {
      presente => (const Color(0xFFDFF3E0), Icon(Icons.check, color: const Color(0xFF2E7D32), size: tamano * 2 / 3)),
      falta => (const Color(0xFFFBE0E0), Icon(Icons.close, color: const Color(0xFFC62828), size: tamano * 2 / 3)),
      justificada => (
          const Color(0xFFFFF4BF),
          Container(
            width: tamano * 2 / 9,
            height: tamano * 2 / 9,
            decoration: const BoxDecoration(color: Color(0xFF000000), shape: BoxShape.circle),
          ),
        ),
      dual => (
          azulDual,
          Container(width: tamano / 4, height: tamano / 4, color: const Color(0xFFFFFFFF)),
        ),
      _ => (null, null),
    };
    return Semantics(
      label: _nombres[estado] ?? 'Sin registro',
      child: Container(
        width: tamano,
        height: tamano,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(tamano / 6),
          border: fondo == null ? Border.all(color: Theme.of(context).dividerColor) : null,
        ),
        child: simbolo,
      ),
    );
  }
}

/// Qué significa cada color. [compacta]: cuadros chicos, texto chico y "Justificada" en vez de
/// "Falta justificada", para que quepa en una sola línea en un teléfono. [conDual]: el grupo tiene
/// alumnos duales; si no, "Dual" no aparece.
class LeyendaEstados extends StatelessWidget {
  const LeyendaEstados({super.key, this.compacta = false, this.conDual = false});
  final bool compacta;
  final bool conDual;

  @override
  Widget build(BuildContext context) {
    final nombres = {...compacta ? _nombresCortos : _nombres}..removeWhere((e, _) => e == dual && !conDual);
    return Wrap(
      spacing: compacta ? 12 : 16,
      runSpacing: compacta ? 4 : 8,
      children: [
        for (final e in nombres.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(child: CeldaEstado(estado: e.key, tamano: compacta ? 20 : 36)),
              SizedBox(width: compacta ? 4 : 6),
              Text(e.value, style: compacta ? Theme.of(context).textTheme.bodySmall : null),
            ],
          ),
      ],
    );
  }
}
