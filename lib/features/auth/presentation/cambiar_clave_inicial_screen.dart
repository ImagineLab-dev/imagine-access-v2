import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/custom_input.dart';
import '../../../core/ui/glass_card.dart';
import '../../../core/ui/glass_scaffold.dart';
import '../../../core/ui/neon_button.dart';
import '../../../core/utils/error_handler.dart';
import '../../profile/data/profile_repository.dart';
import 'auth_controller.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

/// Cambio de contraseña OBLIGATORIO en el primer ingreso.
///
/// A un RRPP o door invitado se le crea la cuenta con una contraseña temporal
/// que viaja por correo —de un solo uso—. Esta pantalla es la única puerta:
/// hasta que la persona elige una contraseña propia, el router la devuelve acá
/// desde cualquier ruta (ver `debesCambiarClaveProvider` + el redirect). No es
/// un recordatorio opcional en Perfil: es un paso que no se puede saltear.
///
/// La única salida sin cambiarla es cerrar sesión —por si alguien entró con la
/// cuenta equivocada—.
class CambiarClaveInicialScreen extends ConsumerStatefulWidget {
  const CambiarClaveInicialScreen({super.key});

  @override
  ConsumerState<CambiarClaveInicialScreen> createState() =>
      _CambiarClaveInicialScreenState();
}

class _CambiarClaveInicialScreenState
    extends ConsumerState<CambiarClaveInicialScreen> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _loading = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .establecerClaveDefinitiva(_passCtrl.text);

      // La sesión sigue viva (fue un cambio del admin, no revoca tokens), pero
      // el JWT actual todavía trae la bandera. Se refresca para que el router la
      // vea en falso y deje pasar. Si el refresco fallara, se sale a login: es
      // preferible pedir un ingreso más que dejar a alguien atrapado en esta
      // pantalla con la contraseña ya cambiada.
      final client = Supabase.instance.client;
      try {
        final refreshed = await client.auth.refreshSession();
        if (refreshed.user != null) {
          ref.read(userProvider.notifier).state = refreshed.user;
        }
      } catch (_) {
        await ref.read(authControllerProvider.notifier).logout();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.passwordChanged)),
          );
          context.go('/login');
        }
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.passwordChanged)),
      );
      // El router ya redirige solo al bajar la bandera; esto lo hace inmediato.
      context.go(rutaTrasIngresar(ref.read(userRoleProvider)));
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(
            context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cerrarSesion() async {
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textColor = AppTheme.texto(context);

    // Sin salida por "atrás": la pantalla no se puede esquivar. El router lo
    // respalda, pero atajar el gesto acá evita el parpadeo de irse y volver.
    return PopScope(
      canPop: false,
      child: GlassScaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_reset,
                      size: 44, color: AppTheme.acentoTexto(context)),
                  const SizedBox(height: 14),
                  Text(
                    l10n.mustChangeTitle,
                    textAlign: TextAlign.center,
                    style: AppTheme.titular(context, size: 22),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.mustChangeSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 14,
                      height: 1.5,
                      color: textColor.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 24),
                  GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CustomInput(
                            label: l10n.newPassword,
                            controller: _passCtrl,
                            prefixIcon: Icons.lock_outline,
                            obscureText: true,
                            validator: (v) {
                              if (v == null || v.isEmpty) return l10n.required;
                              if (v.length < 8) return l10n.passwordMinLength;
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          CustomInput(
                            label: l10n.confirmNewPassword,
                            controller: _confirmCtrl,
                            prefixIcon: Icons.lock_outline,
                            obscureText: true,
                            validator: (v) {
                              if (v == null || v.isEmpty) return l10n.required;
                              if (v != _passCtrl.text) {
                                return l10n.passwordsDoNotMatch;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 22),
                          NeonButton(
                            text: l10n.changePassword.toUpperCase(),
                            isLoading: _loading,
                            onPressed: _guardar,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _loading ? null : _cerrarSesion,
                    child: Text(
                      l10n.logout,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
