import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El evento sobre el que opera toda la app.
///
/// Guarda **también la moneda**, y eso no es un detalle: sin ella, cada
/// pantalla que muestra un precio caía al guaraní por defecto. Un evento en
/// Buenos Aires con entradas a 52.000 pesos se leía "Gs 52.000" —guaraníes—,
/// que son dos monedas con una diferencia de cien a uno. El dato estaba en la
/// base y en la consulta; se perdía acá, al guardar solo id, nombre y slug.
class SelectedEventNotifier extends StateNotifier<Map<String, dynamic>?> {
  SelectedEventNotifier() : super(null) {
    _loadSelectedEvent();
  }

  static const String _eventIdKey = 'selected_event_id';
  static const String _eventNameKey = 'selected_event_name';
  static const String _eventSlugKey = 'selected_event_slug';
  static const String _eventCurrencyKey = 'selected_event_currency';

  Future<void> _loadSelectedEvent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_eventIdKey);
      final name = prefs.getString(_eventNameKey);
      final slug = prefs.getString(_eventSlugKey);

      if (id != null && name != null && slug != null) {
        state = {
          'id': id,
          'name': name,
          'slug': slug,
          // Puede faltar en quien ya tenía un evento elegido de antes de que
          // esto se guardara. `validate()` lo rellena en cuanto llega la lista.
          'currency': prefs.getString(_eventCurrencyKey),
        };
      }
    } catch (_) {
      // SharedPreferences failure is non-fatal; start with no selection.
    }
  }

  Future<void> selectEvent(String id, String name, String slug,
      {String? currency}) async {
    state = {'id': id, 'name': name, 'slug': slug, 'currency': currency};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_eventIdKey, id);
    await prefs.setString(_eventNameKey, name);
    await prefs.setString(_eventSlugKey, slug);
    if (currency != null && currency.isNotEmpty) {
      await prefs.setString(_eventCurrencyKey, currency);
    } else {
      await prefs.remove(_eventCurrencyKey);
    }
  }

  Future<void> clearEvent() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_eventIdKey);
    await prefs.remove(_eventNameKey);
    await prefs.remove(_eventSlugKey);
    await prefs.remove(_eventCurrencyKey);
  }

  /// Descarta la selección si el evento ya no está, y **repara la moneda** si
  /// falta.
  ///
  /// Lo segundo es lo que rescata a quien ya tenía un evento elegido antes de
  /// este cambio: en cuanto la lista llega, se le completa el dato sin que
  /// tenga que volver a elegirlo.
  Future<void> validate(List<Map<String, dynamic>> availableEvents) async {
    final actual = state;
    if (actual == null) return;

    Map<String, dynamic>? enLista;
    for (final e in availableEvents) {
      if (e['id'] == actual['id']) {
        enLista = e;
        break;
      }
    }

    if (enLista == null) {
      await clearEvent();
      return;
    }

    final monedaReal = enLista['currency']?.toString();
    if (monedaReal != null &&
        monedaReal.isNotEmpty &&
        actual['currency'] != monedaReal) {
      await selectEvent(
        actual['id'] as String,
        actual['name'] as String,
        actual['slug'] as String,
        currency: monedaReal,
      );
    }
  }
}

final selectedEventProvider =
    StateNotifierProvider<SelectedEventNotifier, Map<String, dynamic>?>((ref) {
  return SelectedEventNotifier();
});
