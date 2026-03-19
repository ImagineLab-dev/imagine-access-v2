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
    final abs = value.abs();
    final intPart = abs.truncate();
    final intStr = intPart.toString();
    final buf = StringBuffer();
    for (var i = 0; i < intStr.length; i++) {
      if (i > 0 && (intStr.length - i) % 3 == 0) buf.write('.');
      buf.write(intStr[i]);
    }
    if (decimals > 0) {
      final frac = ((abs - intPart) * _pow10(decimals)).round();
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
