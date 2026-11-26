import 'package:flutter/material.dart';

import 'lote_clases.dart';
import 'lote_grupos.dart';
import 'lote_usuarios.dart';

/// Sección aparte del admin para el trabajo en bloque: cada herramienta lee un CSV, muestra una
/// vista previa donde se corrige lo que haga falta y solo entonces guarda.
class HerramientasAvanzadas extends StatelessWidget {
  const HerramientasAvanzadas({super.key});

  @override
  Widget build(BuildContext context) {
    void ir(Widget pantalla) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => pantalla));
    return Scaffold(
      appBar: AppBar(title: const Text('Herramientas avanzadas')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Para cargar muchos datos de una vez desde archivos CSV. Antes de guardar siempre ves una vista '
            'previa donde puedes corregir o quitar filas; lo que ya existe se omite en vez de duplicarse. '
            'Orden recomendado: invitar profesores, importar grupos y luego dar de alta las clases.',
          ),
          const SizedBox(height: 16),
          _Herramienta(
            icono: Icons.group_add,
            titulo: 'Invitar varios usuarios',
            texto: 'Un CSV con correo y rol. Avisa de correos repetidos, con errata o que ya tienen acceso.',
            alTocar: () => ir(const LoteUsuarios()),
          ),
          _Herramienta(
            icono: Icons.groups_2_outlined,
            titulo: 'Importar grupos por lote',
            texto: 'Un solo CSV con grupo, N.L y nombre. Crea todos los grupos nuevos y, si quieres, '
                'actualiza la lista de los que ya existen.',
            alTocar: () => ir(const LoteGrupos()),
          ),
          _Herramienta(
            icono: Icons.playlist_add_check,
            titulo: 'Dar de alta clases por lote',
            texto: 'Un CSV con profesor, grupo, materia y salón. Detecta materias repetidas, profesores '
                'sin acceso y grupos que no existen.',
            alTocar: () => ir(const LoteClases()),
          ),
        ],
      ),
    );
  }
}

class _Herramienta extends StatelessWidget {
  const _Herramienta({required this.icono, required this.titulo, required this.texto, required this.alTocar});
  final IconData icono;
  final String titulo;
  final String texto;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icono),
        title: Text(titulo),
        subtitle: Text(texto),
        trailing: const Icon(Icons.chevron_right),
        isThreeLine: true,
        onTap: alTocar,
      ),
    );
  }
}
