import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// El pase, dibujado como el objeto que es.
///
/// La app manejaba los tickets como filas de una tabla: etiqueta a la
/// izquierda, valor a la derecha, y listo. Pero un ticket **es una cosa** —el
/// cliente la recibe, la guarda y la muestra en la puerta— y cuando en pantalla
/// se ve como una cosa, se entiende sin leer.
///
/// De ahí la forma: cabecera maciza, muescas a los costados donde iría el
/// troquelado, línea de corte punteada y el serial abajo en monoespaciada.
///
/// No incluye QR: el código va firmado por el servidor y se manda por correo en
/// el PDF, así que la app nunca lo tuvo. Dibujar acá un QR distinto del que se
/// valida en la puerta sería peor que no mostrarlo.
class PaseTicket extends StatelessWidget {
  const PaseTicket({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.datos,
    required this.serial,
    required this.colorFondo,
    this.anulado = false,
    this.etiquetaSerial,
  });

  /// Línea grande de la cabecera: el nombre del evento.
  final String titulo;

  /// Línea chica encima del título: el tipo de acceso.
  final String subtitulo;

  /// Pares etiqueta/valor de la mitad de abajo. Se acomodan en dos columnas.
  final List<(String, String)> datos;

  /// El código del ticket.
  final String serial;

  /// Color de la pantalla detrás del pase. Las muescas se pintan de este color
  /// para que parezcan agujeros; si no coincide, se ven como dos lunares.
  final Color colorFondo;

  /// Ticket anulado: el pase se apaga y se cruza con una marca.
  final bool anulado;

  final String? etiquetaSerial;

  @override
  Widget build(BuildContext context) {
    // Un ticket anulado no puede seguir teniendo el borde lima de "válido":
    // es la diferencia entre entrar y no entrar.
    final acento = anulado
        ? AppTheme.textoApagado(context)
        : AppTheme.acentoTexto(context);
    final borde = anulado ? AppTheme.borde(context) : AppTheme.lima;

    return Opacity(
      opacity: anulado ? 0.55 : 1,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTheme.panelElevado(context),
              border: Border.all(color: borde),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // --- Cabecera ---
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.hover(context),
                    border: Border(
                      bottom: BorderSide(color: AppTheme.borde(context)),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        subtitulo.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.etiqueta(context, size: 10, color: acento),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        titulo.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.titular(context, size: 17),
                      ),
                    ],
                  ),
                ),

                // --- Cuerpo ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    children: [
                      if (datos.isNotEmpty) ...[
                        Wrap(
                          runSpacing: 14,
                          children: [
                            for (final (etiqueta, valor) in datos)
                              FractionallySizedBox(
                                widthFactor: 0.5,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        etiqueta.toUpperCase(),
                                        style: AppTheme.etiqueta(
                                          context,
                                          size: 9,
                                          color: AppTheme.textoApagado(context),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        valor,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            AppTheme.dato(context, size: 11.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Línea de corte
                      CustomPaint(
                        size: const Size(double.infinity, 1),
                        painter: _LineaDeCorte(color: AppTheme.borde(context)),
                      ),
                      const SizedBox(height: 16),

                      // Serial
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.campo(context),
                          border: Border.all(color: AppTheme.borde(context)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              (etiquetaSerial ?? 'ID').toUpperCase(),
                              style: AppTheme.etiqueta(
                                context,
                                size: 9,
                                color: AppTheme.textoApagado(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              serial,
                              textAlign: TextAlign.center,
                              style: AppTheme.dato(
                                context,
                                size: 14,
                                tracking: 1.6,
                                color: acento,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Muescas laterales, a la altura de la línea de corte.
          Positioned(
            left: -9,
            bottom: 62,
            child: _Muesca(colorFondo: colorFondo, borde: borde),
          ),
          Positioned(
            right: -9,
            bottom: 62,
            child: _Muesca(colorFondo: colorFondo, borde: borde),
          ),
        ],
      ),
    );
  }
}

class _Muesca extends StatelessWidget {
  const _Muesca({required this.colorFondo, required this.borde});

  final Color colorFondo;
  final Color borde;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: colorFondo,
        shape: BoxShape.circle,
        border: Border.all(color: borde),
      ),
    );
  }
}

/// Línea punteada horizontal: por dónde se cortaría el pase.
class _LineaDeCorte extends CustomPainter {
  const _LineaDeCorte({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = color
      ..strokeWidth = 1;

    const trazo = 4.0;
    const hueco = 4.0;
    double x = 0;
    while (x < size.width) {
      final fin = (x + trazo).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, 0), Offset(fin, 0), pincel);
      x = fin + hueco;
    }
  }

  @override
  bool shouldRepaint(_LineaDeCorte anterior) => anterior.color != color;
}
