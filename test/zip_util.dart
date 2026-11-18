// Ayuda de pruebas (no termina en _test.dart, así que `flutter test` no la corre sola).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/xlsx.dart';

/// Lee un ZIP sin compresión: nombre → contenido. Revisa firmas, CRC y que el directorio central
/// apunte a cada entrada.
Map<String, String> leerZip(Uint8List zip) {
  final d = ByteData.sublistView(zip);
  final archivos = <String, String>{};
  final offsets = <int>[];
  var i = 0;
  while (d.getUint32(i, Endian.little) == 0x04034b50) {
    expect(d.getUint16(i + 8, Endian.little), 0, reason: 'método store');
    final crc = d.getUint32(i + 14, Endian.little);
    final tam = d.getUint32(i + 18, Endian.little);
    final largoNombre = d.getUint16(i + 26, Endian.little);
    final nombre = utf8.decode(zip.sublist(i + 30, i + 30 + largoNombre));
    final datos = zip.sublist(i + 30 + largoNombre, i + 30 + largoNombre + tam);
    expect(crc32(datos), crc, reason: nombre);
    archivos[nombre] = utf8.decode(datos);
    offsets.add(i);
    i += 30 + largoNombre + tam;
  }
  final inicioCentral = i;
  for (final o in offsets) {
    expect(d.getUint32(i, Endian.little), 0x02014b50);
    expect(d.getUint32(i + 42, Endian.little), o);
    i += 46 + d.getUint16(i + 28, Endian.little);
  }
  expect(d.getUint32(i, Endian.little), 0x06054b50);
  expect(d.getUint16(i + 10, Endian.little), offsets.length);
  expect(d.getUint32(i + 16, Endian.little), inicioCentral);
  expect(i + 22, zip.length);
  return archivos;
}
