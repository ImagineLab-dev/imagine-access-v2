/// Estado de la instalación fuera del navegador.
///
/// Se responde "ya instalada" a propósito: es lo que hace que la opción no
/// aparezca en un entorno donde no significa nada.
class EstadoInstalacion {
  const EstadoInstalacion({
    this.instalada = true,
    this.listo = false,
    this.esIOS = false,
  });

  final bool instalada;
  final bool listo;
  final bool esIOS;

  /// Se ofrece instalar solo si no lo está y hay forma de hacerlo.
  bool get sePuedeOfrecer => false;
}

EstadoInstalacion estadoInstalacion() => const EstadoInstalacion();

Future<String> pedirInstalacion() async => 'instalada';
