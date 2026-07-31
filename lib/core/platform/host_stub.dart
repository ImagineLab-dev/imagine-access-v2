/// Host cuando no hay navegador: pruebas en la VM de Dart, y cualquier
/// compilación que no sea web.
///
/// Devuelve cadena vacía a propósito y no lanza: `esHostSuperAdmin` es una
/// comodidad de navegación, no un control de acceso, así que fuera del navegador
/// la respuesta correcta es "no es ese host" y seguir.
String zonaHostActual() => '';
