import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'responsive.dart';

/// Armazón de pantalla.
///
/// Antes pintaba un degradado radial más un "orbe" de brillo detrás de todo:
/// el fondo azul-violeta difuminado que delata a la plantilla generada. Ahora
/// el fondo es plano con una **retícula técnica** de 32px encima, del mismo
/// gris del borde de los paneles. La textura se lee como papel milimetrado o
/// como la pantalla de un instrumento, y hace que los paneles rectos parezcan
/// apoyados en algo en vez de flotar.
///
/// Sigue llamándose `GlassScaffold` porque lo importan 19 pantallas.
class GlassScaffold extends StatelessWidget {
  const GlassScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.titulo,
    this.acciones,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.drawer,
    this.resizeToAvoidBottomInset = true,
    this.anchoCompleto = false,
    this.reticula = true,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;

  /// Título de la pantalla, dibujado DENTRO del contenido en vez de en una
  /// barra propia.
  ///
  /// Es el patrón del diseño: la barra de arriba es global y siempre igual
  /// —menú, marca, avatar—, y cada pantalla se presenta con su propio titular
  /// grande donde empieza el contenido. Antes cada pantalla traía su `AppBar`
  /// con el título, así que dentro del armazón quedaban dos barras apiladas.
  ///
  /// [appBar] sigue existiendo para las pantallas que NO van dentro del
  /// armazón —el asistente de ticket, crear evento, estadísticas—, que se
  /// abren encima y necesitan su propia barra con el botón de volver.
  final String? titulo;

  /// Acciones que acompañan al [titulo], a la derecha de la misma línea.
  final List<Widget>? acciones;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final bool resizeToAvoidBottomInset;

  /// Deja el contenido a ancho completo, sin el tope de [Responsive].
  ///
  /// Solo para pantallas donde el contenido ES la pantalla —una cámara, un
  /// mapa—, no una lista o un formulario. En todo lo demás el tope evita que
  /// en un monitor las tarjetas se estiren a mil píxeles con el contenido
  /// perdido en el centro.
  final bool anchoCompleto;

  /// Retícula de fondo. Se apaga en pantallas que ya tienen su propia imagen
  /// a sangre —la cámara del escáner— donde solo agregaría ruido.
  final bool reticula;

  @override
  Widget build(BuildContext context) {
    Widget contenido = body;

    if (titulo != null) {
      contenido = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    titulo!.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.titular(context, size: 24),
                  ),
                ),
                ...?acciones,
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      // El appBar ya no es transparente (tiene fondo de panel y borde
      // inferior), así que extender el cuerpo por detrás lo único que lograba
      // era que el contenido pasara por debajo del borde.
      extendBodyBehindAppBar: false,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: appBar,
      // Transparente cuando va dentro del armazón: el fondo y la retícula los
      // pinta esta pantalla, pero el color de base lo pone el armazón. Pintarlo
      // dos veces no rompe nada, pero deja una capa opaca de más por cuadro.
      backgroundColor: AppTheme.fondo(context),
      body: Stack(
        children: [
          if (reticula)
            Positioned.fill(
              child: CustomPaint(
                painter: _ReticulaPainter(color: AppTheme.borde(context)),
              ),
            ),
          SafeArea(
            child: anchoCompleto
                ? contenido
                : ContenidoCentrado(child: contenido),
          ),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      drawer: drawer,
    );
  }
}

/// Dibuja la retícula de fondo: líneas de un píxel cada 32.
class _ReticulaPainter extends CustomPainter {
  const _ReticulaPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      // Muy tenue a propósito: tiene que sentirse como textura, no leerse como
      // una grilla. Si se distingue línea por línea, compite con el contenido.
      ..color = color.withValues(alpha: 0.22)
      ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += AppTheme.gridPaso) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), pincel);
    }
    for (double y = 0; y <= size.height; y += AppTheme.gridPaso) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), pincel);
    }
  }

  @override
  bool shouldRepaint(_ReticulaPainter anterior) => anterior.color != color;
}

/// Barra superior del sistema.
///
/// Reemplaza al `AppBar` suelto que cada pantalla se armaba por su cuenta: el
/// título llevaba tipografías, tamaños y alineaciones distintas según quién lo
/// hubiera escrito. Acá el titular va en grotesca, mayúsculas y a la
/// izquierda, siempre, y el borde inferior lo separa del contenido.
class BarraSuperior extends StatelessWidget implements PreferredSizeWidget {
  const BarraSuperior({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.acciones,
    this.liderazgo,
    this.mostrarVolver = true,
    this.alVolver,
  });

  final String titulo;

  /// Línea de contexto en mono debajo del título: código de evento, estado,
  /// cantidad de resultados. Opcional.
  final String? subtitulo;

  final List<Widget>? acciones;
  final Widget? liderazgo;
  final bool mostrarVolver;
  final VoidCallback? alVolver;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final puedeVolver = mostrarVolver && Navigator.of(context).canPop();

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: puedeVolver || liderazgo != null ? 0 : 16,
      leading: liderazgo ??
          (puedeVolver
              ? IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: alVolver ?? () => Navigator.of(context).maybePop(),
                )
              : null),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            titulo.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.fontDisplay,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppTheme.texto(context),
            ),
          ),
          if (subtitulo != null)
            Text(
              subtitulo!,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.dato(
                context,
                size: 10.5,
                color: AppTheme.textoApagado(context),
              ),
            ),
        ],
      ),
      actions: acciones,
    );
  }
}
