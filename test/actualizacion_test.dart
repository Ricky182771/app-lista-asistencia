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

  pruebasConfig();
}

void pruebasConfig() {
  const bien = (version: '1.2.0', buildActual: '3', buildMinimo: '', urlApk: urlApkPorOmision);

  group('borradorDeConfig', () {
    test('lee lo guardado', () {
      final b = borradorDeConfig({
        'versionActual': ' 1.2.0 ',
        'buildActual': 3,
        'buildMinimo': 2.0,
        'urlApk': 'https://x.mx/a.apk',
      });
      expect(b, (version: '1.2.0', buildActual: '3', buildMinimo: '2', urlApk: 'https://x.mx/a.apk'));
    });
    test('sin config/app, todo vacío', () {
      expect(borradorDeConfig(null), (version: '', buildActual: '', buildMinimo: '', urlApk: ''));
    });
  });

  group('validarConfig', () {
    test('un formulario bueno no tiene errores, con o sin buildMinimo', () {
      expect(validarConfig(bien).hayErrores, isFalse);
      expect(validarConfig((version: '1.2.0', buildActual: '3', buildMinimo: '3', urlApk: urlApkPorOmision)).hayErrores,
          isFalse);
    });
    test('versión vacía o mal escrita', () {
      expect(validarConfig((version: '', buildActual: '3', buildMinimo: '', urlApk: urlApkPorOmision)).version, isNotNull);
      expect(validarConfig((version: 'v1.2', buildActual: '3', buildMinimo: '', urlApk: urlApkPorOmision)).version,
          isNotNull);
      expect(validarConfig((version: '1', buildActual: '3', buildMinimo: '', urlApk: urlApkPorOmision)).version, isNotNull);
    });
    test('buildActual debe ser entero positivo', () {
      for (final mal in ['', 'x', '0', '-1', '2.5']) {
        expect(validarConfig((version: '1.2.0', buildActual: mal, buildMinimo: '', urlApk: urlApkPorOmision)).buildActual,
            isNotNull, reason: mal);
      }
    });
    test('buildMinimo: entero positivo y no mayor que buildActual', () {
      String? error(String minimo) =>
          validarConfig((version: '1.2.0', buildActual: '3', buildMinimo: minimo, urlApk: urlApkPorOmision)).buildMinimo;
      expect(error('2'), isNull);
      expect(error('3'), isNull);
      expect(error('4'), contains('mayor'));
      expect(error('x'), isNotNull);
      expect(error('0'), isNotNull);
    });
    test('el enlace debe ser https', () {
      String? error(String url) =>
          validarConfig((version: '1.2.0', buildActual: '3', buildMinimo: '', urlApk: url)).urlApk;
      expect(error('http://x.mx/a.apk'), isNotNull);
      expect(error('x.mx/a.apk'), isNotNull);
      expect(error(''), isNotNull);
      expect(error('https://x.mx/mi apk.apk'), isNotNull);
      expect(error('https://x.mx/a.apk'), isNull);
    });
    test('lo que valida la pantalla lo acepta avisoActualizacion', () {
      final config = configParaGuardar((version: '1.2.0', buildActual: '5', buildMinimo: '4', urlApk: urlApkPorOmision));
      final aviso = avisoActualizacion(3, config);
      expect(aviso, isNotNull);
      expect(aviso!.obligatoria, isTrue);
      expect(avisoActualizacion(4, config)!.obligatoria, isFalse);
      expect(avisoActualizacion(5, config), isNull);
    });
  });

  group('configParaGuardar', () {
    test('números como enteros y buildMinimo vacío = null (se borra)', () {
      expect(configParaGuardar((version: ' 1.2.0 ', buildActual: ' 3 ', buildMinimo: '', urlApk: ' https://x.mx/a.apk ')), {
        'versionActual': '1.2.0',
        'buildActual': 3,
        'buildMinimo': null,
        'urlApk': 'https://x.mx/a.apk',
      });
    });
  });

  group('advertenciaConfig', () {
    test('sin buildMinimo no hay nada que advertir', () {
      expect(advertenciaConfig(bien, null), isNull);
    });
    test('un buildMinimo nuevo o distinto advierte; el mismo de antes, no', () {
      const nuevo = (version: '1.2.0', buildActual: '3', buildMinimo: '3', urlApk: urlApkPorOmision);
      expect(advertenciaConfig(nuevo, bien), contains('menor que 3'));
      expect(advertenciaConfig(nuevo, null), isNotNull);
      expect(advertenciaConfig(nuevo, nuevo), isNull);
    });
  });
}
