import 'pais_stub.dart' if (dart.library.js_interop) 'pais_web.dart';

/// País de quien está usando la app, en formato ISO de dos letras.
///
/// Se usa para dos cosas al crear la cuenta:
///
///   - `organizations.country`, que dLocal recibe al crear el plan. Ese campo
///     decide QUÉ MEDIOS DE PAGO ofrece el checkout. Sin él, dLocal los muestra
///     todos: alguien en Paraguay se encuentra con métodos de media
///     Latinoamérica y tiene que buscar el suyo entre los demás.
///
///   - La moneda por defecto del primer evento. Hoy la columna `events.currency`
///     tiene default `'PYG'`, así que un cliente de fuera de Paraguay que no
///     toque configuraciones crea su primer evento en guaraníes.
///
/// Devuelve `null` cuando no se puede saber. Eso NO es un error: el servidor ya
/// trata el país desconocido descartándolo, porque quedarse sin cuenta por un
/// país mal detectado sería mucho peor que quedarse sin país —que el admin
/// corrige después desde su perfil—.
///
/// El import es condicional como en `host.dart` y `captcha.dart`: sin eso,
/// cualquier test que alcance el controlador de autenticación dejaría de
/// compilar en la VM de Dart.
String? get paisDetectado => detectarPais();

/// Zona horaria del navegador, tal cual la declara: `America/Lima`.
///
/// Se usa para preseleccionar la zona de un evento nuevo. Antes era Paraguay
/// siempre, así que alguien en Lima creaba su evento con dos horas corridas y
/// solo lo notaba si abría el desplegable.
///
/// Devuelve el identificador crudo, sin filtrar: quien la use tiene que
/// comprobar que esté entre las opciones que ofrece, porque hay zonas válidas
/// —`America/Argentina/Cordoba`— que no están en la lista.
String? get zonaHorariaDetectada => detectarZonaHoraria();
