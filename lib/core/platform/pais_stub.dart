/// País cuando no hay navegador: pruebas en la VM de Dart y cualquier
/// compilación que no sea web.
///
/// Devuelve `null` y no lanza, igual que `host_stub.dart` devuelve cadena
/// vacía: fuera del navegador la respuesta honesta es "no sé", y quien llama ya
/// sabe seguir sin país.
String? detectarPais() => null;
