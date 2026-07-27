/// Configuración de la app, provista en tiempo de compilación.
///
/// Deliberadamente **no** se lee de un archivo `.env`: en web los assets de
/// Flutter se sirven por HTTP, así que un `.env` empaquetado queda público en
/// `/assets/.env`. Todo entra por `--dart-define`.
///
/// Build:
/// ```
/// flutter build web --release \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=xxxx
/// ```
class Env {
  const Env._();

  static const _placeholders = <String>[
    'your-project.supabase.co',
    'tu-proyecto.supabase.co',
    'your-anon-key',
    'tu-anon-key',
    'YOUR_SUPABASE_URL',
    'YOUR_SUPABASE_ANON_KEY',
  ];

  /// `true` si [value] es uno de los valores de ejemplo de `.env.example`.
  static bool isPlaceholder(String value) =>
      _placeholders.any(value.contains);

  /// `true` si [value] es demasiado corto para ser una credencial real.
  static bool isTooShort(String value) => value.length < 20;

  static String get supabaseUrl =>
      _require(const String.fromEnvironment('SUPABASE_URL'), 'SUPABASE_URL');

  static String get supabaseAnonKey {
    final value = _require(
      const String.fromEnvironment('SUPABASE_ANON_KEY'),
      'SUPABASE_ANON_KEY',
    );
    if (isTooShort(value)) {
      throw Exception('SUPABASE_ANON_KEY parece inválida (demasiado corta).');
    }
    return value;
  }

  static String _require(String raw, String name) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw Exception(
        '$name no está configurada. Compilá con --dart-define=$name=...',
      );
    }
    if (isPlaceholder(value)) {
      throw Exception(
        '$name tiene un valor de ejemplo. Reemplazalo por el valor real.',
      );
    }
    return value;
  }
}
