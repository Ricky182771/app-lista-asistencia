import 'package:flutter/material.dart';

import '../models/pase.dart';

const _nombres = {presente: 'Presente', falta: 'Falta', justificada: 'Falta justificada'};

/// Símbolo y colores de un estado; los mismos en la vista por día y en la mensual.
/// `estado == null` = sin registro: celda vacía.
class CeldaEstado extends StatelessWidget {
  const CeldaEstado({super.key, required this.estado});
  final int? estado;

  @override
  Widget build(BuildContext context) {
    final (Color? fondo, Widget? simbolo) = switch (estado) {
      presente => (const Color(0xFFDFF3E0), const Icon(Icons.check, color: Color(0xFF2E7D32))),
      falta => (const Color(0xFFFBE0E0), const Icon(Icons.close, color: Color(0xFFC62828))),
      justificada => (
          const Color(0xFFFFF4BF),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: Color(0xFF000000), shape: BoxShape.circle),
          ),
        ),
      _ => (null, null),
    };
    return Semantics(
      label: _nombres[estado] ?? 'Sin registro',
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(6),
          border: fondo == null ? Border.all(color: Theme.of(context).dividerColor) : null,
        ),
        child: simbolo,
      ),
    );
  }
}

class LeyendaEstados extends StatelessWidget {
  const LeyendaEstados({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final e in _nombres.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(child: CeldaEstado(estado: e.key)),
              const SizedBox(width: 6),
              Text(e.value),
            ],
          ),
      ],
    );
  }
}
