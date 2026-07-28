import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:imagine_access/core/utils/currency_helper.dart';

void main() {
  group('CurrencyHelper', () {
    // La app formatea con la convención latinoamericana: punto para los miles
    // y coma para los decimales. Estos tests afirmaban la convención
    // estadounidense y fallaban desde siempre, contradiciendo a la
    // implementación en vez de verificarla. Cinco fallos permanentes enseñan a
    // ignorar la corrida entera, que es como se cuelan las regresiones de
    // verdad.
    group('format', () {
      test('PYG va sin decimales y con punto de miles', () {
        expect(CurrencyHelper.format(150000.0, 'PYG'), 'Gs 150.000');
      });

      test('USD lleva dos decimales, con coma', () {
        expect(CurrencyHelper.format(99.99, 'USD'), '\$ 99,99');
      });

      test('una moneda desconocida usa su código y dos decimales', () {
        expect(CurrencyHelper.format(1000.0, 'XYZ'), 'XYZ 1.000,00');
      });

      test('el cero se muestra completo', () {
        expect(CurrencyHelper.format(0.0, 'USD'), '\$ 0,00');
      });

      test('el signo va delante del número, no del símbolo', () {
        expect(CurrencyHelper.format(-50.0, 'USD'), '\$ -50,00');
      });

      // Regresión: antes se truncaba la parte entera y se redondeaba el resto
      // por separado, así que el acarreo nunca subía al entero.
      test('el redondeo arrastra al entero en vez de desbordarse', () {
        expect(CurrencyHelper.format(99.999, 'USD'), '\$ 100,00');
        expect(CurrencyHelper.format(1.999, 'USD'), '\$ 2,00');
        expect(CurrencyHelper.format(1234.996, 'USD'), '\$ 1.235,00');
      });

      test('una moneda sin decimales redondea, no trunca', () {
        expect(CurrencyHelper.format(999999.6, 'PYG'), 'Gs 1.000.000');
      });
    });

    group('getIcon', () {
      test('should return attach_money for USD', () {
        expect(CurrencyHelper.getIcon('USD'), equals(Icons.attach_money));
      });

      test('should return payments_outlined for PYG', () {
        expect(CurrencyHelper.getIcon('PYG'), equals(Icons.payments_outlined));
      });

      test('should return money for unknown currency', () {
        expect(CurrencyHelper.getIcon('XYZ'), equals(Icons.money));
      });
    });

    group('getSymbol', () {
      test('should return \$ for USD', () {
        expect(CurrencyHelper.getSymbol('USD'), equals('\$'));
      });

      test('should return Gs for PYG', () {
        expect(CurrencyHelper.getSymbol('PYG'), equals('Gs'));
      });

      test('should return currency code for unknown currency', () {
        expect(CurrencyHelper.getSymbol('XYZ'), equals('XYZ'));
      });

      test('should handle uppercase conversion', () {
        expect(CurrencyHelper.getSymbol('usd'), equals('\$'));
        expect(CurrencyHelper.getSymbol('pyg'), equals('Gs'));
      });
    });
  });
}
