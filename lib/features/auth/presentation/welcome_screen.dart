import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/glass_scaffold.dart';
import '../../../core/ui/neon_button.dart';

/// Portada.
///
/// Era el ejemplo de manual de pantalla generada: dos orbes de colores
/// latiendo detrás, el título con degradado por `ShaderMask`, cuatro funciones
/// cada una con SU color de acento y su resplandor, y radios de 34, 26, 18 y 10
/// conviviendo en la misma vista.
///
/// Ahora es una ficha técnica: retícula de fondo, el logo, un panel con
/// escuadras en las esquinas, y las cuatro funciones en una grilla donde el
/// único color es el lima. Que las cuatro compartan acento es deliberado —
/// cuatro colores distintos no aportaban ninguna información, solo ruido.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return GlassScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- Encabezado ---
                Center(
                  child: SvgPicture.asset(
                    'assets/logos/shield_qr_final_v2.svg',
                    width: 84,
                    height: 84,
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 5),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppTheme.lima, width: 2),
                      ),
                    ),
                    child: Text(
                      l10n.appTitle.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: AppTheme.titular(context, size: 30),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 290),
                    child: Text(
                      l10n.welcomeTagline,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 13,
                        height: 1.55,
                        color: AppTheme.textoSecundario(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),

                // --- Funciones ---
                _PanelConEscuadras(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.welcomeMainFeatures.toUpperCase(),
                        style: AppTheme.etiqueta(context),
                      ),
                      const SizedBox(height: 14),
                      GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 1.55,
                        children: [
                          _Funcion(
                            icono: Icons.confirmation_number_outlined,
                            texto: l10n.createTicket,
                          ),
                          _Funcion(
                            icono: Icons.qr_code_scanner,
                            texto: l10n.scanner,
                          ),
                          _Funcion(
                            icono: Icons.bar_chart_rounded,
                            texto: l10n.reports,
                          ),
                          _Funcion(
                            icono: Icons.group_outlined,
                            texto: l10n.manageTeam,
                          ),
                        ],
                      ),
                    ],
                  ),
                ).animate().fade(delay: 120.ms),

                const SizedBox(height: 22),

                // --- Entradas al sistema ---
                NeonButton(
                  text: l10n.adminRRPP,
                  icon: Icons.shield_outlined,
                  onPressed: () => context.go('/login?mode=admin'),
                ).animate().fade(delay: 180.ms),
                const SizedBox(height: 10),
                NeonButton(
                  text: l10n.doorAccess,
                  icon: Icons.meeting_room_outlined,
                  isSecondary: true,
                  onPressed: () => context.go('/login?mode=door'),
                ).animate().fade(delay: 220.ms),

                const SizedBox(height: 20),
                const Center(child: TestigoDeSistema()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel con escuadras lima en las dos esquinas de arriba.
///
/// Es el gesto que el diseño usa para marcar el bloque principal de una
/// pantalla, en lugar de agrandarlo o ponerle sombra.
class _PanelConEscuadras extends StatelessWidget {
  const _PanelConEscuadras({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.panel(context),
            border: Border.all(color: AppTheme.borde(context)),
          ),
          child: child,
        ),
        const Positioned(top: 0, left: 0, child: _Escuadra(izquierda: true)),
        const Positioned(top: 0, right: 0, child: _Escuadra(izquierda: false)),
      ],
    );
  }
}

class _Escuadra extends StatelessWidget {
  const _Escuadra({required this.izquierda});

  final bool izquierda;

  @override
  Widget build(BuildContext context) {
    const lado = BorderSide(color: AppTheme.lima, width: 2);
    return SizedBox(
      width: 16,
      height: 16,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: lado,
            left: izquierda ? lado : BorderSide.none,
            right: izquierda ? BorderSide.none : lado,
          ),
        ),
      ),
    );
  }
}

class _Funcion extends StatelessWidget {
  const _Funcion({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.campo(context),
        border: Border.all(color: AppTheme.borde(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icono, size: 19, color: AppTheme.acentoTexto(context)),
          Text(
            texto.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.etiqueta(
              context,
              size: 10,
              color: AppTheme.texto(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Testigo de "sistema en línea": un cuadrado lima que late y una línea en
/// mono. Cuadrado y no círculo — en esta identidad no hay nada redondo.
class TestigoDeSistema extends StatelessWidget {
  const TestigoDeSistema({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, color: AppTheme.lima)
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .fade(begin: 0.3, end: 1, duration: 950.ms),
        const SizedBox(width: 8),
        Text(
          l10n.systemOnline.toUpperCase(),
          style: AppTheme.dato(
            context,
            size: 10.5,
            color: AppTheme.textoSecundario(context),
          ),
        ),
      ],
    );
  }
}
