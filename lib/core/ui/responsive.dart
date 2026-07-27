import 'package:flutter/widgets.dart';

/// Utilidades de diseño adaptable.
///
/// La app nació como app de teléfono y sus grids tenían 2 columnas fijas. En
/// un monitor eso deja tarjetas de casi 1000px de ancho con un número en la
/// esquina: no se rompe, pero se ve roto.
class Responsive {
  const Responsive._();

  /// Anchos de referencia. No son marcas de dispositivo sino de espacio
  /// disponible: una ventana angosta en un monitor merece el mismo trato que
  /// un teléfono.
  static const double telefono = 600;
  static const double tablet = 1000;
  static const double escritorio = 1400;

  static bool esTelefono(BuildContext context) =>
      MediaQuery.sizeOf(context).width < telefono;

  /// Ancho máximo del contenido.
  ///
  /// Sin tope, en un monitor ultrapanorámico las tarjetas se estiran hasta
  /// volverse ilegibles y el ojo tiene que recorrer media pantalla para unir
  /// una etiqueta con su valor.
  static double anchoMaximo(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    if (ancho < tablet) return ancho;
    return 1280;
  }

  /// Cantidad de columnas para una grilla de tarjetas.
  ///
  /// Se calcula a partir de un ancho objetivo por tarjeta en lugar de fijar
  /// cortes por dispositivo: así el resultado sigue siendo razonable en
  /// tamaños que nadie previó, como una ventana partida a la mitad.
  static int columnas(
    BuildContext context, {
    double anchoObjetivo = 280,
    int minimo = 2,
    int maximo = 4,
  }) {
    final disponible = anchoMaximo(context);
    final calculado = (disponible / anchoObjetivo).floor();
    return calculado.clamp(minimo, maximo);
  }

  /// Proporción de las tarjetas de métrica.
  ///
  /// En teléfono conviene que sean más altas que anchas para que el número
  /// respire; a medida que hay más columnas, cada una se angosta y hay que
  /// acompañar o el texto se corta.
  static double proporcionTarjeta(BuildContext context) {
    final n = columnas(context);
    if (n >= 4) return 1.35;
    if (n == 3) return 1.5;
    return 1.75;
  }
}

/// Centra y limita el ancho del contenido.
///
/// Se usa para envolver el cuerpo de las pantallas de listado: en pantallas
/// anchas evita la línea de texto interminable, y en teléfono no hace nada.
class ContenidoCentrado extends StatelessWidget {
  const ContenidoCentrado({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Responsive.anchoMaximo(context)),
        child: child,
      ),
    );
  }
}
