import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Zonas horarias -> país, para las plazas donde dLocal opera.
///
/// La zona horaria se prefiere al idioma porque dice DÓNDE ESTÁ la persona, no
/// qué idioma eligió. Un paraguayo con el sistema en inglés declara `en-US`
/// pero su reloj sigue en `America/Asuncion`, y para decidir medios de pago lo
/// que importa es lo segundo.
///
/// Solo están los 23 países que acepta `ensure_profile`. Cualquier otra zona
/// cae en `null` y el alta sigue sin país, que es el comportamiento que ya
/// había.
const Map<String, String> _porZona = {
  // --- Cono Sur
  'America/Asuncion': 'PY',
  'America/Montevideo': 'UY',
  'America/Santiago': 'CL',
  'America/Punta_Arenas': 'CL',
  'Pacific/Easter': 'CL',
  'America/La_Paz': 'BO',
  // --- Brasil
  'America/Sao_Paulo': 'BR', 'America/Bahia': 'BR', 'America/Fortaleza': 'BR',
  'America/Recife': 'BR', 'America/Manaus': 'BR', 'America/Belem': 'BR',
  'America/Cuiaba': 'BR', 'America/Campo_Grande': 'BR', 'America/Maceio': 'BR',
  'America/Porto_Velho': 'BR', 'America/Boa_Vista': 'BR', 'America/Rio_Branco': 'BR',
  'America/Araguaina': 'BR', 'America/Santarem': 'BR', 'America/Eirunepe': 'BR',
  'America/Noronha': 'BR',
  // --- Andes y Centroamérica
  'America/Bogota': 'CO',
  'America/Lima': 'PE',
  'America/Guayaquil': 'EC', 'Pacific/Galapagos': 'EC',
  'America/Panama': 'PA',
  'America/Santo_Domingo': 'DO',
  'America/Costa_Rica': 'CR',
  'America/Guatemala': 'GT',
  // --- México
  'America/Mexico_City': 'MX', 'America/Tijuana': 'MX', 'America/Monterrey': 'MX',
  'America/Cancun': 'MX', 'America/Merida': 'MX', 'America/Chihuahua': 'MX',
  'America/Hermosillo': 'MX', 'America/Mazatlan': 'MX', 'America/Matamoros': 'MX',
  'America/Ojinaga': 'MX', 'America/Bahia_Banderas': 'MX',
  // --- Estados Unidos
  'America/New_York': 'US', 'America/Chicago': 'US', 'America/Denver': 'US',
  'America/Los_Angeles': 'US', 'America/Phoenix': 'US', 'America/Anchorage': 'US',
  'America/Detroit': 'US', 'America/Boise': 'US', 'America/Juneau': 'US',
  'America/Adak': 'US', 'America/Nome': 'US', 'America/Sitka': 'US',
  'America/Menominee': 'US', 'America/Metlakatla': 'US', 'America/Yakutat': 'US',
  'Pacific/Honolulu': 'US',
  // --- Europa
  'Europe/Madrid': 'ES', 'Atlantic/Canary': 'ES', 'Africa/Ceuta': 'ES',
  // --- África
  'Africa/Lagos': 'NG',
  'Africa/Nairobi': 'KE',
  // --- Asia
  'Asia/Kolkata': 'IN', 'Asia/Calcutta': 'IN',
  'Asia/Jakarta': 'ID', 'Asia/Makassar': 'ID', 'Asia/Jayapura': 'ID',
  'Asia/Pontianak': 'ID',
  'Asia/Kuala_Lumpur': 'MY', 'Asia/Kuching': 'MY',
  'Asia/Manila': 'PH',
  'Asia/Ho_Chi_Minh': 'VN', 'Asia/Saigon': 'VN',
};

/// Zonas que llegan agrupadas bajo un prefijo, para no listar las decenas de
/// variantes una por una.
const Map<String, String> _porPrefijo = {
  'America/Argentina/': 'AR',
  'America/Indiana/': 'US',
  'America/Kentucky/': 'US',
  'America/North_Dakota/': 'US',
};

/// Los 23 países que acepta el servidor. Se repite acá a propósito: mandar uno
/// que no esté haría que `ensure_profile` lo descarte en silencio, y es mejor
/// no mandarlo que mandar algo que se va a tirar.
const Set<String> _aceptados = {
  'PY', 'AR', 'UY', 'BR', 'CL', 'BO', 'CO', 'PE', 'EC', 'PA', 'DO', 'CR',
  'GT', 'MX', 'US', 'ES', 'NG', 'KE', 'IN', 'ID', 'MY', 'PH', 'VN',
};

String? detectarPais() {
  try {
    final porZona = _desdeZonaHoraria();
    if (porZona != null) return porZona;
    return _desdeIdioma();
  } catch (_) {
    // Detectar el país es una comodidad. Si algo del entorno no está donde se
    // espera, el alta sigue sin país.
    return null;
  }
}

/// `Intl.DateTimeFormat().resolvedOptions().timeZone`
String? _desdeZonaHoraria() {
  final intl = globalContext.getProperty<JSObject?>('Intl'.toJS);
  if (intl == null) return null;
  final constructor = intl.getProperty<JSFunction?>('DateTimeFormat'.toJS);
  if (constructor == null) return null;

  final formateador = constructor.callAsConstructor<JSObject>();
  final opciones = formateador.callMethod<JSObject?>('resolvedOptions'.toJS);
  final zona = opciones?.getProperty<JSString?>('timeZone'.toJS)?.toDart;
  if (zona == null || zona.isEmpty) return null;

  final exacto = _porZona[zona];
  if (exacto != null) return exacto;

  for (final entrada in _porPrefijo.entries) {
    if (zona.startsWith(entrada.key)) return entrada.value;
  }
  return null;
}

/// Región del idioma del navegador: `es-PY` -> `PY`.
///
/// Es la reserva y no la fuente principal porque muchos navegadores declaran
/// solo el idioma (`es`, sin región), y cuando traen región suele reflejar la
/// preferencia de formato antes que la ubicación.
String? _desdeIdioma() {
  final navegador = globalContext.getProperty<JSObject?>('navigator'.toJS);
  final idioma = navegador?.getProperty<JSString?>('language'.toJS)?.toDart;
  if (idioma == null) return null;

  final partes = idioma.split(RegExp('[-_]'));
  if (partes.length < 2) return null;

  final region = partes[1].toUpperCase();
  return _aceptados.contains(region) ? region : null;
}
