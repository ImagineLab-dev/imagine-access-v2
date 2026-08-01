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
import 'package:imagine_access/features/events/presentation/create_event_screen.dart';

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
      expect(CurrencyHelper.monedaDePais('MX'), 'MXN');
      expect(CurrencyHelper.monedaDePais('CR'), 'CRC');
      expect(CurrencyHelper.monedaDePais('GT'), 'GTQ');
      expect(CurrencyHelper.monedaDePais('DO'), 'DOP');
    });

    test('Ecuador y Panamá reciben USD porque ES su moneda', () {
      // No es un reemplazo por desconocimiento: Ecuador está dolarizado desde
      // 2000 y en Panamá el dólar es moneda de curso legal. Si algún día
      // alguien "arregla" esto agregándoles una moneda propia, rompe.
      expect(CurrencyHelper.monedaDePais('EC'), 'USD');
      expect(CurrencyHelper.monedaDePais('PA'), 'USD');
    });

    test('todas las plazas donde dLocal cobra tienen moneda', () {
      // Los 14 países verificados contra la API. Ninguno debería quedar sin
      // una moneda que la app sepa formatear.
      for (final pais in ['PY','AR','UY','BR','CL','BO','CO','PE',
                          'EC','PA','DO','CR','GT','MX']) {
        final m = CurrencyHelper.monedaDePais(pais);
        expect(CurrencyHelper.currencies.containsKey(m), isTrue,
            reason: '$pais -> $m no se sabe formatear');
      }
    });

    test('las plazas sin moneda propia en la lista caen en USD', () {
      // Plazas de dLocal fuera de Latinoamérica, más EEUU y España. Mostrar
      // dólares es preferible a mostrar un símbolo que no sabemos formatear.
      for (final pais in ['US', 'ES', 'NG', 'KE', 'IN', 'ID', 'MY', 'PH', 'VN']) {
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

  group('monedas que se pueden elegir al crear un evento', () {
    test('están las 10 que la app sabe formatear, no dos', () {
      // El desplegable tenía escritas PYG y USD nada más, así que un peruano
      // no podía cobrar en soles aunque el formateador los soporte. Ahora sale
      // de `currencies`, y este test lo fija: si alguien vuelve a escribir una
      // lista a mano más corta, falla.
      expect(CurrencyHelper.currencies.length, greaterThanOrEqualTo(14));
      for (final esperada in ['PYG', 'USD', 'ARS', 'CLP', 'COP', 'PEN',
                              'UYU', 'BOB', 'VES', 'BRL',
                              'MXN', 'CRC', 'GTQ', 'DOP']) {
        expect(CurrencyHelper.currencies.containsKey(esperada), isTrue,
            reason: 'falta $esperada');
      }
    });

    test('todas tienen etiqueta legible para el desplegable', () {
      for (final codigo in CurrencyHelper.currencies.keys) {
        final etiqueta = CurrencyHelper.getLabel(codigo);
        expect(etiqueta, isNotEmpty);
        // La etiqueta tiene que decir cuál es: "Sol Peruano (PEN)". Si
        // devolviera solo el código, el desplegable sería ilegible.
        expect(etiqueta, contains(codigo), reason: codigo);
        expect(etiqueta.length, greaterThan(codigo.length), reason: codigo);
      }
    });
  });

  group('zona horaria del evento', () {
    test('sin navegador arranca en Paraguay', () {
      expect(zonaHorariaInicial(), 'America/Asuncion');
    });

    test('el valor inicial SIEMPRE está entre las opciones', () {
      // Si no lo estuviera, `DropdownButton` lanza en tiempo de ejecución al
      // abrir la pantalla. Es la razón por la que `zonaHorariaInicial()`
      // filtra contra esta misma lista.
      expect(zonasHorarias.containsKey(zonaHorariaInicial()), isTrue);
    });

    test('Perú está entre las opciones', () {
      expect(zonasHorarias.containsKey('America/Lima'), isTrue);
      expect(zonasHorarias['America/Lima'], contains('Perú'));
    });

    test('solo se ofrecen plazas donde dLocal acepta cobrar', () {
      // Verificado contra la API el 01/08/2026 creando un plan por país.
      // El Salvador fue el único rechazado: "The 'country' is invalid or
      // unsupported". Ofrecerlo dejaba crear un evento que después no podía
      // vender una sola entrada.
      expect(zonasHorarias.containsKey('America/El_Salvador'), isFalse,
          reason: 'dLocal rechaza SV: no se puede cobrar ahí');

      expect(zonasHorarias.length, 14,
          reason: 'son las 14 plazas que dLocal acepto; '
              'si cambia, hay que volver a comprobarlo contra la API');
    });
  });

  test('fuera del navegador no se detecta país, y no explota', () {
    // Los tests corren en la VM de Dart, donde no hay `Intl` ni `navigator`.
    // El import condicional tiene que resolver al stub: si resolviera a la
    // versión web, este archivo ni siquiera compilaría.
    expect(paisDetectado, isNull);
  });
}
