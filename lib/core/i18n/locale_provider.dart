import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleNotifier extends StateNotifier<Locale> {
  // Español por defecto: es el idioma del negocio y el de la mayoría de los
  // usuarios. Antes arrancaba en inglés, así que todo el que no entraba a
  // cambiarlo veía la app en un idioma que no era el suyo.
  LocaleNotifier() : super(const Locale('es')) {
    _loadSavedLocale();
  }

  static const String _localeKey = 'app_locale';

  Future<void> _loadSavedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final languageCode = prefs.getString(_localeKey);
      if (languageCode != null) {
        state = Locale(languageCode);
      }
    } catch (_) {
      // SharedPreferences not ready — keep default locale
    }
  }

  Future<void> changeLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
     await prefs.setString(_localeKey, locale.languageCode);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});
