import 'package:flutter_test/flutter_test.dart';
import 'package:imagine_access/core/billing/paises_dlocal.dart';

void main() {
  group('paisesDLocal', () {
    test('coincide con lo que acepta dLocal (verificado 29/07/2026)', () {
      // Consultado pais por pais contra la API real: se envia un cobro con un
      // order_id ya ocupado, de modo que un pais valido falla por duplicado y
      // uno no soportado responde "country is invalid or unsupported".
      const aceptados = {
        'AR','BO','BR','CL','CO','CR','DO','EC','GT','MX','PA','PY','PE','UY',
        'US','ES','NG','KE','IN','ID','MY','PH','VN',
      };
      expect(paisesDLocal.map((p) => p.codigo).toSet(), aceptados);
    });

    test('no incluye El Salvador, que dLocal rechaza', () {
      expect(paisesDLocal.any((p) => p.codigo == 'SV'), isFalse,
          reason: 'estaba en la lista y el pago habria fallado despues');
    });

    test('sin codigos repetidos', () {
      final codigos = paisesDLocal.map((p) => p.codigo).toList();
      expect(codigos.length, codigos.toSet().length);
    });

    test('todos los codigos son ISO alfa-2 en mayusculas', () {
      for (final p in paisesDLocal) {
        expect(p.codigo, matches(RegExp(r'^[A-Z]{2}$')), reason: p.nombre);
        expect(p.nombre.trim(), isNotEmpty);
      }
    });
  });
}
