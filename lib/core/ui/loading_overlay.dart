import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

import '../theme/app_theme.dart';

final loadingProvider = StateProvider<bool>((ref) => false);

/// Velo de "procesando".
///
/// Antes difuminaba toda la pantalla con un `BackdropFilter` y le pasaba un
/// brillo en bucle al recuadro. Dos animaciones infinitas y un desenfoque de
/// pantalla completa para decir "esperá" —justo en el momento en que el
/// dispositivo está ocupado haciendo otra cosa—.
///
/// Ahora es lo que usa un instrumento: la pantalla se apaga detrás de un velo
/// plano y aparece una barra de progreso. El movimiento es uno solo y significa
/// algo: mientras se mueve, el sistema está trabajando.
class LoadingOverlay extends ConsumerWidget {
  const LoadingOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cargando = ref.watch(loadingProvider);

    return Stack(
      children: [
        child,
        if (cargando)
          Positioned.fill(
            child: Container(
              color: AppTheme.darkBg.withValues(alpha: 0.86),
              child: Center(
                child: Container(
                  width: 260,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCardElevated,
                    border: Border.all(color: AppTheme.darkBorder),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // El punto que late es el único indicador de "vivo"
                          // que el diseño usa. Acá cumple la misma función.
                          Container(
                            width: 7,
                            height: 7,
                            color: AppTheme.lima,
                          ),
                          const SizedBox(width: 9),
                          Text(
                            AppLocalizations.of(context).processing.toUpperCase(),
                            style: const TextStyle(
                              fontFamily: AppTheme.fontDisplay,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                              color: AppTheme.darkText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(
                        minHeight: 3,
                        color: AppTheme.lima,
                        backgroundColor: AppTheme.darkInput,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
