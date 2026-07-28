import 'dart:async';

/// Tiempos límite para las llamadas a las funciones del servidor.
///
/// Sin un límite, una función que no responde deja el `await` esperando para
/// siempre: el botón queda deshabilitado, la rueda girando, y la única salida
/// es recargar la app. Para quien está en la puerta de un evento, eso es que el
/// sistema se colgó.
///
/// Los valores son generosos a propósito. La idea no es cortar operaciones
/// lentas —mandar un correo por SMTP compartido tarda— sino que exista un
/// techo: es preferible un error claro a los treinta segundos que una pantalla
/// congelada indefinidamente.
class TiempoLimite {
  const TiempoLimite._();

  /// Operaciones que mandan correo. El SMTP puede tardar hasta ~25 s entre
  /// conexión, saludo y envío, así que el techo va por encima de eso.
  static const conCorreo = Duration(seconds: 40);

  /// Lecturas y escrituras normales contra la base.
  static const normal = Duration(seconds: 20);

  /// Validación en la puerta. Más corto que el resto: con gente esperando,
  /// pasar a la cola sin conexión es mejor que seguir esperando una respuesta.
  static const puerta = Duration(seconds: 12);
}

/// Excepción de tiempo agotado, reconocible por [ErrorHandler].
///
/// El texto contiene "timeout" a propósito: es lo que busca `analyzeError`
/// para clasificarlo y mostrar el mensaje traducido correcto.
class TiempoAgotadoException implements Exception {
  const TiempoAgotadoException(this.operacion);

  final String operacion;

  @override
  String toString() =>
      'timeout: la operación "$operacion" superó el tiempo de espera';
}

/// Aplica un tiempo límite a una operación, con un error clasificable.
extension ConTiempoLimite<T> on Future<T> {
  Future<T> conLimite(Duration limite, String operacion) {
    return timeout(
      limite,
      onTimeout: () => throw TiempoAgotadoException(operacion),
    );
  }
}
