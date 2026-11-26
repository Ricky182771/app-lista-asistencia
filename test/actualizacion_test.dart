import 'package:flutter_test/flutter_test.dart';

import 'package:app_lista_asistencia/models/actualizacion.dart';

void main() {
  const config = {
    'versionActual': '1.2.0',
    'buildActual': 5,
    'urlApk': 'https://github.com/ejemplo/app/releases/latest/download/PaseLista.apk',
  };

  test('al día: mismo build o uno más nuevo (versión de prueba)', () {
    expect(avisoActualizacion(5, config), isNull);
    expect(avisoActualizacion(6, config), isNull);
  });

  test('build más viejo: aviso con versión y enlace, sin obligar', () {
    final a = avisoActualizacion(4, config)!;
    expect(a.version, '1.2.0');
    expect(a.url.toString(), config['urlApk']);
    expect(a.obligatoria, isFalse);
  });

  test('debajo de buildMinimo es obligatoria; en el mínimo o arriba, no', () {
    final conMinimo = {...config, 'buildMinimo': 3};
    expect(avisoActualizacion(2, conMinimo)!.obligatoria, isTrue);
    expect(avisoActualizacion(3, conMinimo)!.obligatoria, isFalse);
    expect(avisoActualizacion(5, conMinimo), isNull);
  });

  test('sin versionActual se avisa igual, con versión vacía', () {
    expect(avisoActualizacion(1, {...config}..remove('versionActual'))!.version, '');
  });

  test('sin config/app o mal llenado no avisa ni bloquea', () {
    expect(avisoActualizacion(1, null), isNull);
    expect(avisoActualizacion(1, const {}), isNull);
    expect(avisoActualizacion(1, {...config, 'buildActual': '5'}), isNull);
    expect(avisoActualizacion(1, {...config}..remove('urlApk')), isNull);
    expect(avisoActualizacion(1, {...config, 'urlApk': 'http://ejemplo.com/PaseLista.apk'}), isNull);
    expect(avisoActualizacion(1, {...config, 'urlApk': 'no es un enlace'}), isNull);
  });

  test('un buildMinimo que no es número no bloquea', () {
    expect(avisoActualizacion(1, {...config, 'buildMinimo': '9'})!.obligatoria, isFalse);
  });
}
