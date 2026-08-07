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
    double anchoObjetivo = 240,
    int minimo = 2,
    int maximo = 4,
  }) {
    final disponible = anchoMaximo(context);
    final calculado = (disponible / anchoObjetivo).floor();
    // Si quien llama pide un techo por debajo del piso, el piso cede. Sin esto
    // `clamp(minimo, maximo)` con minimo > maximo lanza ArgumentError y se lleva
    // puesta toda la grilla: Flutter la reemplaza por su recuadro de error gris.
    // Pasaba en el panel de RRPP —su única acción rápida hacía
    // `proporcionTarjeta(maximo: 1)`, y el piso por defecto es 2—, que quedaba
    // en un bloque gris en lugar del botón.
    final piso = minimo <= maximo ? minimo : maximo;
    return calculado.clamp(piso, maximo);
  }

  /// Proporción de una tarjeta de métrica, para que su ALTURA quede fija.
  ///
  /// `childAspectRatio` es ancho/alto, así que fijarlo por tramos da tarjetas
  /// que crecen en las dos direcciones: al pasar de 2 a 4 columnas en un
  /// monitor quedaban de 370x275px para mostrar un número y una etiqueta.
  ///
  /// Acá se hace al revés: se calcula el ancho real que va a tener cada
  /// tarjeta y se deriva la proporción que deja la altura en [alturaObjetivo].
  /// El contenido es el mismo en cualquier pantalla, así que la altura no
  /// tiene por qué cambiar — solo cuántas entran por fila.
  /// [alturaObjetivo] bajó de 118 a 74 cuando `MetricCard` pasó de apilar el
  /// ícono arriba del número a ponerlo al costado: el contenido dejó de
  /// necesitar dos "pisos". Nueve métricas que antes ocupaban unas dos
  /// pantallas ahora entran en poco más de una.
  static double proporcionTarjeta(
    BuildContext context, {
    double alturaObjetivo = 74,
    double separacion = 16,
    double paddingHorizontal = 40,
    // Tienen que coincidir con los del grid al que se aplica: si no, el ancho
    // se calcula sobre otra cantidad de columnas y la altura sale mal.
    double anchoObjetivo = 240,
    int maximo = 4,
  }) {
    final n = columnas(context, anchoObjetivo: anchoObjetivo, maximo: maximo);
    final disponible =
        anchoMaximo(context) - paddingHorizontal - separacion * (n - 1);
    final anchoTarjeta = disponible / n;
    // El clamp evita extremos absurdos si el contenedor es diminuto.
    return (anchoTarjeta / alturaObjetivo).clamp(1.1, 3.4);
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
