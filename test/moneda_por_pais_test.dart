// La moneda por defecto sale del país, no de un literal.
//
// Antes era `'PYG'` fijo: un cliente de Argentina o México que no entrara a
// configuraciones creaba su primer evento en guaraníes y lo descubría al ver
// los precios. Estos tests fijan las dos mitades que importan: que cada plaza
// reciba la suya, y que lo desconocido caiga en dólares en vez de en la moneda
// de un país cualquiera.

import 'package:flutter_test/flutter_test.dart';
import 'package:imagine_access/core/utils/currency_helper.dart';
import 'package:imagine_access/core/platform/pais.dart';

void main() {
  group('moneda que le toca a cada país', () {
    test('las plazas con moneda propia reciben la suya', () {
      expect(CurrencyHelper.monedaDePais('PY'), 'PYG');
      expect(CurrencyHelper.monedaDePais('AR'), 'ARS');
      expect(CurrencyHelper.monedaDePais('UY'), 'UYU');
      expect(CurrencyHelper.monedaDePais('BR'), 'BRL');
      expect(CurrencyHelper.monedaDePais('CL'), 'CLP');
      expect(CurrencyHelper.monedaDePais('BO'), 'BOB');
      expect(CurrencyHelper.monedaDePais('CO'), 'COP');
      expect(CurrencyHelper.monedaDePais('PE'), 'PEN');
    });

    test('las plazas sin moneda propia en la lista caen en USD', () {
      // Son países donde dLocal opera pero cuya moneda no sabemos formatear.
      // Mostrar dólares es preferible a mostrar un símbolo desconocido.
      for (final pais in ['MX', 'US', 'ES', 'CR', 'GT', 'PA', 'DO', 'EC',
                          'NG', 'KE', 'IN', 'ID', 'MY', 'PH', 'VN']) {
        expect(CurrencyHelper.monedaDePais(pais), 'USD', reason: pais);
      }
    });

    test('sin país conocido, USD y no la moneda de un país cualquiera', () {
      expect(CurrencyHelper.monedaDePais(null), 'USD');
      expect(CurrencyHelper.monedaDePais(''), 'USD');
      expect(CurrencyHelper.monedaDePais('XX'), 'USD');
      expect(CurrencyHelper.monedaDePais('zzzz'), 'USD');
    });

    test('no importa cómo venga escrito el código', () {
      expect(CurrencyHelper.monedaDePais('py'), 'PYG');
      expect(CurrencyHelper.monedaDePais('Ar'), 'ARS');
    });

    test('toda moneda que devuelve se sabe formatear', () {
      // Si alguna vez se agrega un país cuya moneda no está en `currencies`,
      // el importe saldría con el código en vez del símbolo. Esto lo detecta.
      for (final pais in ['PY','AR','UY','BR','CL','BO','CO','PE','MX','US','XX']) {
        final moneda = CurrencyHelper.monedaDePais(pais);
        expect(CurrencyHelper.currencies.containsKey(moneda), isTrue,
            reason: '$pais -> $moneda no está en currencies');
      }
    });
  });

  test('fuera del navegador no se detecta país, y no explota', () {
    // Los tests corren en la VM de Dart, donde no hay `Intl` ni `navigator`.
    // El import condicional tiene que resolver al stub: si resolviera a la
    // versión web, este archivo ni siquiera compilaría.
    expect(paisDetectado, isNull);
  });
}
