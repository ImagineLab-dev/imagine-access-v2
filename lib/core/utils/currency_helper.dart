import 'package:flutter/material.dart';

class CurrencyHelper {
  /// All supported currencies with display info
  static const Map<String, CurrencyInfo> currencies = {
    'PYG': CurrencyInfo('Gs', 'Guaraní (PYG)', 0, Icons.payments_outlined),
    'USD': CurrencyInfo('\$', 'Dólar (USD)', 2, Icons.attach_money),
    'ARS': CurrencyInfo('\$', 'Peso Argentino (ARS)', 2, Icons.attach_money),
    'CLP': CurrencyInfo('\$', 'Peso Chileno (CLP)', 0, Icons.attach_money),
    'COP': CurrencyInfo('\$', 'Peso Colombiano (COP)', 0, Icons.attach_money),
    'PEN': CurrencyInfo('S/', 'Sol Peruano (PEN)', 2, Icons.money),
    'UYU': CurrencyInfo('\$U', 'Peso Uruguayo (UYU)', 2, Icons.attach_money),
    'BOB': CurrencyInfo('Bs', 'Boliviano (BOB)', 2, Icons.money),
    'VES': CurrencyInfo('Bs.D', 'Bolívar (VES)', 2, Icons.money),
    'BRL': CurrencyInfo('R\$', 'Real (BRL)', 2, Icons.attach_money),
  };

  /// Moneda de cada plaza donde opera dLocal.
  ///
  /// Existe porque la moneda por defecto era `'PYG'` fija: un cliente de fuera
  /// de Paraguay que no tocara configuraciones creaba su primer evento en
  /// guaraníes, y recién lo notaba al ver los precios.
  ///
  /// Los países sin moneda propia en la lista de arriba —México, Centroamérica,
  /// Asia— caen en USD a propósito: mostrar un símbolo que no sabemos formatear
  /// sería peor que mostrar dólares, que se entienden en todos lados.
  static const Map<String, String> _monedaPorPais = {
    'PY': 'PYG',
    'AR': 'ARS',
    'UY': 'UYU',
    'BR': 'BRL',
    'CL': 'CLP',
    'BO': 'BOB',
    'CO': 'COP',
    'PE': 'PEN',
  };

  /// Moneda que le corresponde a un país. USD cuando no se conoce.
  static String monedaDePais(String? codigoPais) {
    if (codigoPais == null || codigoPais.isEmpty) return 'USD';
    return _monedaPorPais[codigoPais.toUpperCase()] ?? 'USD';
  }

  static String getSymbol(String currencyCode) {
    return currencies[currencyCode.toUpperCase()]?.symbol ?? currencyCode;
  }

  static String format(num amount, String currencyCode) {
    final info = currencies[currencyCode.toUpperCase()];
    final symbol = info?.symbol ?? currencyCode;
    final decimals = info?.decimals ?? 2;
    final formatted = _formatWithThousands(amount.toDouble(), decimals);
    return '$symbol $formatted';
  }

  /// Formats a number with dot as thousands separator and comma as decimal
  static String _formatWithThousands(double value, int decimals) {
    final isNeg = value < 0;
    final factor = _pow10(decimals);

    // Se redondea el número ENTERO de centavos y recién después se parte en
    // entera y decimal.
    //
    // Antes se truncaba la parte entera primero y se redondeaba el resto por
    // separado, así que el acarreo no llegaba a subir el entero: 99.999 salía
    // como "99,100" en vez de "100,00", y 1234.996 como "1.234,100". Aparece
    // solo, sin que nadie cargue esos números, cuando un total se divide entre
    // varios tickets y el punto flotante deja un x,99…
    final total = (value.abs() * factor).round();
    final intPart = total ~/ factor;
    final frac = total % factor;

    final intStr = intPart.toString();
    final buf = StringBuffer();
    for (var i = 0; i < intStr.length; i++) {
      if (i > 0 && (intStr.length - i) % 3 == 0) buf.write('.');
      buf.write(intStr[i]);
    }
    if (decimals > 0) {
      buf.write(',${frac.toString().padLeft(decimals, '0')}');
    }
    return isNeg ? '-${buf.toString()}' : buf.toString();
  }

  static int _pow10(int n) {
    var r = 1;
    for (var i = 0; i < n; i++) { r *= 10; }
    return r;
  }

  static IconData getIcon(String currencyCode) {
    return currencies[currencyCode.toUpperCase()]?.icon ?? Icons.money;
  }

  /// Get label for dropdown menus
  static String getLabel(String currencyCode) {
    return currencies[currencyCode.toUpperCase()]?.label ?? currencyCode;
  }
}

class CurrencyInfo {
  final String symbol;
  final String label;
  final int decimals;
  final IconData icon;

  const CurrencyInfo(this.symbol, this.label, this.decimals, this.icon);
}
