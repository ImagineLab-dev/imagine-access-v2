import 'zona_horaria_stub.dart'
    if (dart.library.js_interop) 'zona_horaria_web.dart';

/// Países donde dLocal opera y en los que se puede cobrar la suscripción.
///
/// La misma lista que ofrece el selector de zona horaria del evento. Los
/// nombres van en su forma local y no traducidos: un selector de países se lee
/// igual en los tres idiomas de la app, y mantener 45 traducciones para que
/// "Brasil" diga "Brazil" en inglés es costo sin beneficio.
class PaisDLocal {
  const PaisDLocal(this.codigo, this.nombre);

  /// ISO 3166-1 alfa-2. Es lo que se guarda en `organizations.country` y lo que
  /// espera dLocal al crear un pago.
  final String codigo;
  final String nombre;
}

const paisesDLocal = <PaisDLocal>[
  // América Latina, que es el mercado del producto.
  PaisDLocal('PY', 'Paraguay'),
  PaisDLocal('AR', 'Argentina'),
  PaisDLocal('UY', 'Uruguay'),
  PaisDLocal('BR', 'Brasil'),
  PaisDLocal('CL', 'Chile'),
  PaisDLocal('BO', 'Bolivia'),
  PaisDLocal('CO', 'Colombia'),
  PaisDLocal('PE', 'Perú'),
  PaisDLocal('EC', 'Ecuador'),
  PaisDLocal('PA', 'Panamá'),
  PaisDLocal('DO', 'República Dominicana'),
  PaisDLocal('CR', 'Costa Rica'),
  PaisDLocal('GT', 'Guatemala'),
  PaisDLocal('MX', 'México'),
  // El resto de las plazas. Van abajo porque son improbables para este
  // producto, pero excluirlas dejaría afuera a alguien que sí puede pagar.
  PaisDLocal('US', 'Estados Unidos'),
  PaisDLocal('ES', 'España'),
  PaisDLocal('NG', 'Nigeria'),
  PaisDLocal('KE', 'Kenia'),
  PaisDLocal('IN', 'India'),
  PaisDLocal('ID', 'Indonesia'),
  PaisDLocal('MY', 'Malasia'),
  PaisDLocal('PH', 'Filipinas'),
  PaisDLocal('VN', 'Vietnam'),
];

/// Zona horaria exacta → país, para los casos de una sola zona.
const _porZona = <String, String>{
  'America/Asuncion': 'PY',
  'America/Montevideo': 'UY',
  'America/Santiago': 'CL',
  'America/Punta_Arenas': 'CL',
  'Pacific/Easter': 'CL',
  'America/La_Paz': 'BO',
  'America/Bogota': 'CO',
  'America/Lima': 'PE',
  'America/Guayaquil': 'EC',
  'Pacific/Galapagos': 'EC',
  'America/Panama': 'PA',
  'America/Santo_Domingo': 'DO',
  'America/Costa_Rica': 'CR',
  'America/Guatemala': 'GT',
};

/// Prefijos para los países con muchas zonas. Argentina, Brasil y México tienen
/// una decena cada uno, y listarlas todas envejece mal: la base de datos IANA
/// agrega y renombra zonas.
const _porPrefijo = <String, String>{
  'America/Argentina/': 'AR',
  'America/Buenos_Aires': 'AR',
  'America/Cordoba': 'AR',
  'America/Mendoza': 'AR',
  'America/Sao_Paulo': 'BR',
  'America/Bahia': 'BR',
  'America/Fortaleza': 'BR',
  'America/Recife': 'BR',
  'America/Belem': 'BR',
  'America/Manaus': 'BR',
  'America/Cuiaba': 'BR',
  'America/Campo_Grande': 'BR',
  'America/Porto_Velho': 'BR',
  'America/Boa_Vista': 'BR',
  'America/Rio_Branco': 'BR',
  'America/Noronha': 'BR',
  'America/Maceio': 'BR',
  'America/Araguaina': 'BR',
  'America/Santarem': 'BR',
  'America/Eirunepe': 'BR',
  'America/Mexico_City': 'MX',
  'America/Monterrey': 'MX',
  'America/Cancun': 'MX',
  'America/Merida': 'MX',
  'America/Chihuahua': 'MX',
  'America/Hermosillo': 'MX',
  'America/Mazatlan': 'MX',
  'America/Tijuana': 'MX',
  'America/Matamoros': 'MX',
  'America/Ojinaga': 'MX',
  'America/Bahia_Banderas': 'MX',
};

/// País probable de quien está creando la cuenta.
///
/// Se deduce de la zona horaria del dispositivo, no de la IP: no hace falta un
/// servicio externo, no se pide permiso de ubicación y funciona sin conexión.
/// Es una *sugerencia* — siempre queda un selector para corregirla, porque
/// alguien de vacaciones o detrás de una VPN va a ver el país equivocado.
///
/// Devuelve `null` si la zona no corresponde a ninguna plaza de dLocal, y en
/// ese caso no se preselecciona nada: es preferible un campo vacío que obligue
/// a elegir, a uno prellenado con un país al azar que nadie mira y termina
/// facturando mal.
String? paisSugerido() {
  final zona = zonaHorariaDelDispositivo();
  if (zona == null || zona.isEmpty) return null;

  String? codigo = _porZona[zona];
  if (codigo == null) {
    for (final entrada in _porPrefijo.entries) {
      if (zona.startsWith(entrada.key)) {
        codigo = entrada.value;
        break;
      }
    }
  }
  if (codigo == null) return null;

  // La sugerencia SIEMPRE se valida contra la lista.
  //
  // Un DropdownButton cuyo valor no está entre sus opciones lanza excepción:
  // la pantalla de registro quedaría rota para quien viva en esa zona horaria,
  // y solo para esa gente. Pasó de verdad — El Salvador estaba en el mapa
  // después de que dLocal dejara de aceptarlo.
  final existe = paisesDLocal.any((p) => p.codigo == codigo);
  return existe ? codigo : null;
}
