import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Carrusel de métricas tipo *coverflow*: la del centro grande y nítida, las de
/// los costados encogidas y apagadas.
///
/// Reemplaza a la grilla de ocho tarjetas iguales. Ese bloque tenía un problema
/// real —ocho cajas del mismo peso, ninguna destacando— y este lo resuelve
/// dándole todo el foco a una por vez.
///
/// A cambio hay un costo que conviene tener presente: solo se compara con las
/// vecinas. Por eso las de los lados se dejan **asomando** en vez de ocultas: se
/// ve que hay más, y se ven las dos contiguas.
///
/// Detalles que no son decorativos:
///
///   - **Se apoya en `PageController.page`**, no en un `AnimationController`
///     propio. El desplazamiento y la escala salen del mismo número, así que la
///     tarjeta acompaña al dedo en vez de animar después de soltarlo.
///   - **Respeta `disableAnimations`.** Con el sistema en "reducir movimiento"
///     las tarjetas no escalan ni se desvanecen: se muestran las tres derechas.
///     Para quien marcó esa preferencia, un carrusel que late es hostil.
///   - **Las flechas solo aparecen si hay espacio y hay a dónde ir.** En
///     teléfono se arrastra con el dedo y las flechas taparían las vecinas.
class CarruselMetricas extends StatefulWidget {
  const CarruselMetricas({
    super.key,
    required this.tarjetas,
    this.alto = 182,
    this.intervalo = const Duration(seconds: 4),
  });

  /// Las métricas, en orden. Cada una se dibuja tal cual dentro de la ranura.
  final List<Widget> tarjetas;

  final double alto;

  /// Cada cuánto avanza solo. La cuenta se pausa mientras se arrastra con el
  /// dedo y arranca de nuevo al soltar: nada se mueve debajo de la mano.
  final Duration intervalo;

  @override
  State<CarruselMetricas> createState() => _CarruselMetricasState();
}

class _CarruselMetricasState extends State<CarruselMetricas> {
  late final PageController _control;
  Timer? _reloj;

  /// Mientras es true el avance automático no corre: la persona está tocando.
  bool _enMano = false;

  /// Posición continua del carrusel. Es `double` y no `int` a propósito: entre
  /// dos tarjetas vale 1.4, y de ahí sale la escala intermedia mientras se
  /// arrastra.
  double _posicion = 0;

  @override
  void initState() {
    super.initState();
    _control = PageController(viewportFraction: 0.62)
      ..addListener(() {
        final p = _control.page;
        if (p != null && p != _posicion) setState(() => _posicion = p);
      });
    _arrancarReloj();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _control.dispose();
    super.dispose();
  }

  void _arrancarReloj() {
    _reloj?.cancel();
    if (widget.tarjetas.length < 2) return;
    _reloj = Timer.periodic(widget.intervalo, (_) {
      if (!mounted || _enMano || !_control.hasClients) return;
      final siguiente = (_posicion.round() + 1) % widget.tarjetas.length;
      _control.animateToPage(
        siguiente,
        // Más lenta que el toque manual: un movimiento que nadie pidió tiene
        // que ser suave, si no se lee como un salto y distrae.
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _mover(int delta) {
    _arrancarReloj();   // tocar una flecha reinicia la cuenta
    final destino = (_posicion.round() + delta).clamp(0, widget.tarjetas.length - 1);
    _control.animateToPage(
      destino,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tarjetas.isEmpty) return const SizedBox.shrink();

    final sinMovimiento = MediaQuery.disableAnimationsOf(context);
    final actual = _posicion.round();

    // Quien pidió reducir movimiento no quiere un carrusel que se mueva solo.
    if (sinMovimiento) _reloj?.cancel();

    return Column(
      children: [
        SizedBox(
          height: widget.alto,
          child: Stack(
            alignment: Alignment.center,
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (aviso) {
                  if (aviso is ScrollStartNotification) {
                    _enMano = true;
                  } else if (aviso is ScrollEndNotification) {
                    _enMano = false;
                    _arrancarReloj();
                  }
                  return false;
                },
                child: PageView.builder(
                controller: _control,
                itemCount: widget.tarjetas.length,
                padEnds: true,
                itemBuilder: (context, i) {
                  // Distancia al centro, de 0 (justo en el medio) a 1 o más.
                  final distancia = sinMovimiento
                      ? 0.0
                      : (i - _posicion).abs().clamp(0.0, 1.0);
                  final escala = 1 - distancia * 0.14;
                  final opacidad = 1 - distancia * 0.55;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Transform.scale(
                      scale: escala,
                      child: Opacity(
                        opacity: opacidad,
                        child: widget.tarjetas[i],
                      ),
                    ),
                  );
                },
              ),
              ),

              // Flechas. `LayoutBuilder` para no dibujarlas en pantallas donde
              // taparían las tarjetas vecinas.
              LayoutBuilder(
                builder: (context, medidas) {
                  if (medidas.maxWidth < 520) return const SizedBox.shrink();
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Flecha(
                        icono: Icons.chevron_left,
                        alTocar: actual > 0 ? () => _mover(-1) : null,
                      ),
                      _Flecha(
                        icono: Icons.chevron_right,
                        alTocar: actual < widget.tarjetas.length - 1
                            ? () => _mover(1)
                            : null,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Indicador(cantidad: widget.tarjetas.length, actual: actual),
      ],
    );
  }
}

class _Flecha extends StatelessWidget {
  const _Flecha({required this.icono, required this.alTocar});

  final IconData icono;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final habilitada = alTocar != null;

    return Opacity(
      opacity: habilitada ? 1 : 0.3,
      child: Material(
        color: AppTheme.panelElevado(context),
        child: InkWell(
          onTap: alTocar,
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hover(context),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.borde(context)),
            ),
            child: Icon(icono, size: 20, color: AppTheme.texto(context)),
          ),
        ),
      ),
    );
  }
}

/// Marcas de posición: un guion por tarjeta, el actual en lima y más ancho.
///
/// Guiones y no puntos: en esta identidad no hay nada redondo.
class _Indicador extends StatelessWidget {
  const _Indicador({required this.cantidad, required this.actual});

  final int cantidad;
  final int actual;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < cantidad; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: i == actual ? 16 : 6,
            height: 3,
            color: i == actual
                ? AppTheme.lima
                : AppTheme.borde(context),
          ),
      ],
    );
  }
}

/// Tarjeta de métrica para el carrusel.
///
/// Es más alta que la de la grilla porque acá hay lugar: una sola ocupa el
/// centro, así que el número puede ser grande de verdad y la barra de avance
/// entra sin apretar.
class TarjetaCarrusel extends StatelessWidget {
  const TarjetaCarrusel({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.icono,
    this.detalle,
    this.avance,
  });

  final String etiqueta;
  final String valor;
  final IconData icono;

  /// Línea chica bajo el número. Opcional.
  final String? detalle;

  /// De 0 a 1. Si es null no se dibuja la barra.
  final double? avance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: AppTheme.panel(context),
        border: Border.all(color: AppTheme.borde(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  etiqueta.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.etiqueta(context, size: 12),
                ),
              ),
              const SizedBox(width: 8),
              _IconoVivo(icono: icono),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor, style: AppTheme.titular(context, size: 42)),
          ),
          if (avance != null)
            SizedBox(
              height: 5,
              child: LinearProgressIndicator(
                value: avance!.clamp(0.0, 1.0),
                backgroundColor: AppTheme.campo(context),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.lima),
              ),
            )
          else if (detalle != null)
            Text(
              detalle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.dato(
                context,
                size: 12,
                peso: FontWeight.w500,
                color: AppTheme.textoSecundario(context),
              ),
            )
          else
            const SizedBox(height: 3),
        ],
      ),
    );
  }
}

/// Ícono de la métrica: recuadro con escuadras que respiran.
///
/// Es la única animación en bucle de la app y se permite acá con dos reglas:
///
///   1. **Escala y opacidad, nunca destello.** El brillo que barre —el que
///      tenía el botón viejo— es la firma más reconocible de la plantilla
///      generada. Un cambio de tamaño se lee como algo vivo; un barrido de luz
///      se lee como un banner.
///   2. **Vocabulario propio.** Las escuadras de las esquinas son las mismas de
///      la mira del escáner. Que el ícono de una métrica "encuadre" el dato es
///      el mismo gesto que encuadrar un QR: la app se explica sola.
///
/// Se apaga entera con "reducir movimiento".
class _IconoVivo extends StatefulWidget {
  const _IconoVivo({required this.icono});

  final IconData icono;

  @override
  State<_IconoVivo> createState() => _IconoVivoState();
}

class _IconoVivoState extends State<_IconoVivo>
    with SingleTickerProviderStateMixin {
  static const double _lado = 52;
  static const double _escuadra = 13;

  late final AnimationController _control;

  @override
  void initState() {
    super.initState();
    _control = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Se consulta acá y no en initState porque MediaQuery necesita el árbol ya
    // montado, y porque la preferencia puede cambiar con la app abierta.
    if (MediaQuery.disableAnimationsOf(context)) {
      _control.stop();
      _control.value = 0;
    } else if (!_control.isAnimating) {
      _control.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final acento = AppTheme.acentoTexto(context);

    return SizedBox(
      width: _lado,
      height: _lado,
      child: AnimatedBuilder(
        animation: _control,
        builder: (context, hijo) {
          final t = Curves.easeInOut.transform(_control.value);
          return Stack(
            children: [
              // Caja de fondo. Fija: si también se moviera, el conjunto
              // vibraría en vez de respirar.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.campo(context),
                    border: Border.all(color: AppTheme.borde(context)),
                  ),
                ),
              ),

              // Escuadras: se abren hacia afuera y suben de opacidad a la vez.
              // El desplazamiento es de 2 px —lo suficiente para percibirse,
              // no tanto como para que parezca que la caja se descuadra—.
              Positioned(
                top: -t * 2,
                left: -t * 2,
                child: _Escuadra(
                  color: acento.withValues(alpha: 0.35 + t * 0.65),
                  arriba: true,
                  izquierda: true,
                ),
              ),
              Positioned(
                bottom: -t * 2,
                right: -t * 2,
                child: _Escuadra(
                  color: acento.withValues(alpha: 0.35 + t * 0.65),
                  arriba: false,
                  izquierda: false,
                ),
              ),

              // El ícono, latiendo con la misma curva.
              Center(
                child: Transform.scale(scale: 1 + t * 0.10, child: hijo),
              ),
            ],
          );
        },
        child: Icon(widget.icono, size: 26, color: acento),
      ),
    );
  }
}

/// Escuadra de esquina: dos lados de un recuadro, sin cerrar.
class _Escuadra extends StatelessWidget {
  const _Escuadra({
    required this.color,
    required this.arriba,
    required this.izquierda,
  });

  final Color color;
  final bool arriba;
  final bool izquierda;

  @override
  Widget build(BuildContext context) {
    final lado = BorderSide(color: color, width: 2);
    return SizedBox(
      width: _IconoVivoState._escuadra,
      height: _IconoVivoState._escuadra,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: arriba ? lado : BorderSide.none,
            bottom: arriba ? BorderSide.none : lado,
            left: izquierda ? lado : BorderSide.none,
            right: izquierda ? BorderSide.none : lado,
          ),
        ),
      ),
    );
  }
}

/// Proporción segura: evita la división por cero y el infinito.
double proporcion(int parte, int total) =>
    total <= 0 ? 0 : math.min(parte / total, 1);
