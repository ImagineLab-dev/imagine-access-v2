/// Señales crudas del navegador de las que se deriva el estado de conectividad.
///
/// Se extrae detrás de una interfaz para que [ConnectivityService] —donde vive
/// la lógica— pueda testearse en la VM de Dart, donde `package:web` no existe.
abstract class ConnectivitySignals {
  /// Espejo de `navigator.onLine`.
  ///
  /// Es una condición necesaria pero no suficiente: da `true` cuando el equipo
  /// está conectado a un portal cautivo o a un router sin salida a internet.
  bool get isOnline;

  /// Emite cuando el navegador dispara el evento `online`.
  Stream<void> get onOnline;

  /// Emite cuando el navegador dispara el evento `offline`.
  Stream<void> get onOffline;

  /// Comprueba si el backend responde de verdad.
  ///
  /// Devuelve `true` si contestó (cualquier respuesta HTTP cuenta como
  /// alcanzable) y `false` ante cualquier fallo o timeout.
  Future<bool> probe();
}
