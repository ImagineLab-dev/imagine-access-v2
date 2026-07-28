import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'responsive.dart';

class GlassScaffold extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
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

  const GlassScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.drawer,
    this.resizeToAvoidBottomInset = true,
    this.anchoCompleto = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: appBar,
      body: Stack(
        children: [
          // Background Gradient (adapts to theme)
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topLeft,
                radius: 1.5,
                colors: isDark
                  ? [
                      const Color(0xFF0F1520),
                      AppTheme.scaffoldBackgroundColor,
                    ]
                  : [
                      const Color(0xFFE8EEF7),
                      AppTheme.lightScaffoldBackgroundColor,
                    ],
              ),
            ),
          ),
          // Subtle glow orb (adapts to theme)
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    AppTheme.primaryColor.withValues(alpha: isDark ? 0.05 : 0.03),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor
                        .withValues(alpha: isDark ? 0.1 : 0.05),
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),

           // Content
          SafeArea(
            child: anchoCompleto ? body : ContenidoCentrado(child: body),
          ),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      drawer: drawer,
    );
  }
}
