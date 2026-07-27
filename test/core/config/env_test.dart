import 'package:flutter_test/flutter_test.dart';
import 'package:imagine_access/core/config/env.dart';

/// `String.fromEnvironment` se resuelve en tiempo de compilación, así que
/// estos tests describen el comportamiento con los valores que reciba la
/// corrida. Para ejercitar el camino feliz:
///
///   flutter test --dart-define=SUPABASE_URL=https://real.supabase.co \
///                --dart-define=SUPABASE_ANON_KEY=una_clave_de_mas_de_veinte_chars
void main() {
  group('Env', () {
    test('falla con un mensaje accionable cuando falta configuración', () {
      const url = String.fromEnvironment('SUPABASE_URL');

      if (url.isEmpty) {
        expect(
          () => Env.supabaseUrl,
          throwsA(predicate(
            (e) => e.toString().contains('--dart-define=SUPABASE_URL'),
            'el mensaje le dice al desarrollador exactamente qué hacer',
          )),
        );
      } else {
        expect(Env.supabaseUrl, url);
      }
    });

    test('rechaza valores placeholder', () {
      expect(Env.isPlaceholder('https://your-project.supabase.co'), isTrue);
      expect(Env.isPlaceholder('https://tu-proyecto.supabase.co'), isTrue);
      expect(Env.isPlaceholder('YOUR_SUPABASE_URL'), isTrue);
      expect(Env.isPlaceholder('https://abcdefgh.supabase.co'), isFalse);
    });

    test('rechaza claves demasiado cortas para ser reales', () {
      expect(Env.isTooShort('corta'), isTrue);
      expect(Env.isTooShort('una_clave_de_mas_de_veinte_caracteres'), isFalse);
    });
  });
}
