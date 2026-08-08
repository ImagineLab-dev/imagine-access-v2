import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_controller.dart';
import '../../../core/billing/paises_dlocal.dart';
import '../../../core/platform/captcha.dart';
import '../../../core/ui/glass_scaffold.dart';
import '../../../core/ui/glass_card.dart';
import '../../../core/ui/custom_input.dart';
import '../../../core/ui/neon_button.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/utils/error_handler.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import '../../../core/platform/meta.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;

  /// Abrir directamente en modo registro. Lo activa `?registrar=1` desde la
  /// landing: "Probar gratis" tiene que mostrar el formulario de crear cuenta,
  /// no el de iniciar sesión.
  final bool initialRegister;

  const LoginScreen({
    super.key,
    this.initialTabIndex = 0,
    this.initialRegister = false,
  });

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late bool _isRegistering = widget.initialRegister;
  bool _acceptedTerms = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _orgController = TextEditingController();
  final _deviceIdController = TextEditingController();
  final _pinController = TextEditingController();

  /// País de facturación. Se precarga con lo que sugiere la zona horaria del
  /// dispositivo; queda en null si esa zona no es una plaza de dLocal, y ahí el
  /// campo obliga a elegir en vez de arriesgar un país al azar.
  String? _pais = paisSugerido();

  final _formKeyUser = GlobalKey<FormState>();
  final _formKeyDevice = GlobalKey<FormState>();

  // Rate limiting
  int _loginAttempts = 0;
  DateTime? _lockoutEnd;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.initialTabIndex.clamp(0, 1);
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: initialIndex,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {}); // Rebuild to switch tab content
      }
    });
    // El captcha se muestra solo acá. JS no puede saber en qué pantalla está la
    // app —Flutter dibuja sobre un canvas— así que lo gobierna la pantalla.
    mostrarCaptcha(true);
  }

  @override
  void dispose() {
    mostrarCaptcha(false);
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _orgController.dispose();
    _deviceIdController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  bool _isLockedOut() {
    if (_lockoutEnd != null && DateTime.now().isBefore(_lockoutEnd!)) {
      final remaining = _lockoutEnd!.difference(DateTime.now()).inSeconds;
      final l10n = AppLocalizations.of(context);
      ErrorHandler.showErrorSnackBar(
        context,
        l10n.lockoutWaitSeconds(remaining),
      );
      return true;
    }
    // Reset lockout if expired
    if (_lockoutEnd != null && DateTime.now().isAfter(_lockoutEnd!)) {
      _loginAttempts = 0;
      _lockoutEnd = null;
    }
    return false;
  }

  void _registerFailedAttempt() {
    _loginAttempts++;
    if (_loginAttempts >= 5) {
      _lockoutEnd = DateTime.now().add(const Duration(seconds: 30));
    }
  }

  Future<void> _handleUserAuth() async {
    if (!_formKeyUser.currentState!.validate()) return;
    if (_isRegistering && !_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).mustAcceptTerms)),
      );
      return;
    }
    if (_isLockedOut()) return;
    try {
      if (_isRegistering) {
        await ref.read(authControllerProvider.notifier).signUpEmail(
              _emailController.text.trim(),
              _passwordController.text.trim(),
              _nameController.text.trim(),
              _orgController.text.trim(),
              country: _pais,
            );
        // Alta de cuenta. Es el evento del que más volumen vas a tener, y con
        // pocas compras al mes es el único con el que Meta puede aprender algo.
        //
        // Va con value + currency: Meta los EXIGE para calcular el ROAS —sin
        // ellos el diagnóstico marca CompleteRegistration al 100% "falta el
        // campo del valor / de divisa"—. El valor es un PROXY del potencial de
        // un registro: el precio mensual del plan (USD 25), la misma cifra que
        // ya usan ViewContent e InitiateCheckout. NO es un ingreso real —ese lo
        // reporta Purchase desde el webhook de dLocal cuando el cobro se
        // confirma—, sino la señal de valor con la que la campaña de registro
        // optimiza. El plumbing ya lo reenvía por el pixel y por la CAPI
        // (meta_web → imagineMeta.evento → meta_evento, que conserva value y
        // currency en `datos`).
        eventoMeta('CompleteRegistration', valor: 25, moneda: 'USD');

        // Check if email verification is required (no session = OTP sent)
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null && mounted) {
          context.go('/verify-email', extra: {
            'email': _emailController.text.trim(),
            'displayName': _nameController.text.trim(),
            'organizationName': _orgController.text.trim(),
            'country': _pais,
          });
          return;
        }
      } else {
        await ref.read(authControllerProvider.notifier).loginEmail(
              _emailController.text.trim(),
              _passwordController.text.trim(),
            );
      }
      _loginAttempts = 0; // Reset on success
      // El destino lo decide `rutaTrasIngresar`, no esta pantalla. Antes acá
      // había un '/dashboard' fijo que pisaba la redirección del router y hacía
      // imposible aterrizar en el panel de super-admin.
      if (mounted) {
        context.go(rutaTrasIngresar(ref.read(userRoleProvider)));
      }
    } catch (e) {
      _registerFailedAttempt();
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        String message;
        if (_isRegistering) {
          final errorMsg = e.toString().toLowerCase();
          if (kDebugMode) dev.log('Registration error: $e', name: 'LoginScreen');
          if (errorMsg.contains('already registered') ||
              errorMsg.contains('already been registered') ||
              errorMsg.contains('user already') ||
              errorMsg.contains('duplicate')) {
            message = l10n.emailAlreadyRegistered;
          } else if (errorMsg.contains('rate') || errorMsg.contains('limit')) {
            message = l10n.tooManyAttempts;
          } else {
            message = l10n.registrationFailed;
          }
        } else {
          message = l10n.invalidCredentials;
        }
        ErrorHandler.showErrorSnackBar(context, message);
      }
    }
  }

  Future<void> _loginDevice() async {
    if (!_formKeyDevice.currentState!.validate()) return;
    if (_isLockedOut()) return;

    try {
      await ref.read(authControllerProvider.notifier).loginDevice(
            _deviceIdController.text.trim(),
            _pinController.text.trim(),
          );
      if (mounted) context.go('/dashboard');
    } catch (e) {
      _registerFailedAttempt();
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ErrorHandler.showErrorSnackBar(
          context,
          l10n.invalidCredentials,
          onRetry: _loginDevice,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;

    return GlassScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                Icon(Icons.shield_outlined,
                    size: 40, color: AppTheme.acentoTexto(context)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.only(bottom: 5),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppTheme.lima, width: 2),
                    ),
                  ),
                  child: Text(
                    l10n.appTitle.toUpperCase(),
                    style: AppTheme.titular(context, size: 26),
                  ),
                ),
                const SizedBox(height: 26),
                GlassCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Cabecera de formulario técnico: dice en qué modo está
                      // el sistema. Reemplaza al título suelto que había, que
                      // no distinguía entrar de registrarse.
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppTheme.campo(context),
                          border: Border(
                            bottom: BorderSide(color: AppTheme.borde(context)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                // Texto claro, no jerga. Antes decía
                                // 'SEC_AUTH_REQ' —"requisito de autenticación de
                                // seguridad" abreviado como una constante de
                                // sistema—: era lo PRIMERO que leía un usuario
                                // nuevo, y no significaba nada. El estilo mono en
                                // mayúsculas conserva el aire técnico sin costar
                                // comprensión.
                                (_isRegistering
                                        ? l10n.authHeaderRegister
                                        : l10n.authHeaderLogin)
                                    .toUpperCase(),
                                style: AppTheme.dato(
                                  context,
                                  size: 10.5,
                                  color: AppTheme.textoSecundario(context),
                                ),
                              ),
                            ),
                            Icon(Icons.lock_outline,
                                size: 14,
                                color: AppTheme.acentoTexto(context)),
                          ],
                        ),
                      ),
                      // Segmentos rectos: el activo se marca con una línea lima
                      // abajo, no con una píldora de color.
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AppTheme.borde(context)),
                          ),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicatorWeight: 2,
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          overlayColor:
                              WidgetStateProperty.all(Colors.transparent),
                          tabs: [
                            Tab(text: l10n.adminRRPP.toUpperCase()),
                            Tab(text: l10n.doorAccess.toUpperCase()),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _tabController.index == 0
                            ? Form(
                                key: _formKeyUser,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isRegistering) ...[
                                      CustomInput(
                                        label: l10n.displayName,
                                        controller: _nameController,
                                        prefixIcon: Icons.person_outline,
                                        validator: (v) => v?.isNotEmpty == true
                                            ? null
                                            : l10n.required,
                                      ),
                                      const SizedBox(height: 12),
                                      CustomInput(
                                        label: l10n.companyName,
                                        controller: _orgController,
                                        prefixIcon: Icons.business_outlined,
                                        validator: (v) => v?.isNotEmpty == true
                                            ? null
                                            : l10n.enterCompanyName,
                                      ),
                                      const SizedBox(height: 12),
                                      // País de facturación. Viene precargado
                                      // con lo que sugiere la zona horaria del
                                      // dispositivo, pero se puede cambiar: de
                                      // vacaciones o detrás de una VPN la
                                      // sugerencia es incorrecta.
                                      DropdownButtonFormField<String>(
                                        initialValue: _pais,
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                          labelText: l10n.billingCountry,
                                          helperText: l10n.billingCountryHelp,
                                          helperMaxLines: 2,
                                          prefixIcon: const Icon(
                                              Icons.public_outlined),
                                        ),
                                        items: [
                                          for (final p in paisesDLocal)
                                            DropdownMenuItem(
                                              value: p.codigo,
                                              child: Text(p.nombre),
                                            ),
                                        ],
                                        validator: (v) =>
                                            v == null ? l10n.required : null,
                                        onChanged: (v) =>
                                            setState(() => _pais = v),
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    CustomInput(
                                      label: l10n.email,
                                      controller: _emailController,
                                      prefixIcon: Icons.email_outlined,
                                      validator: (v) {
                                        if (v == null || v.isEmpty) {
                                          return l10n.required;
                                        }
                                        final emailRegex = RegExp(
                                            r'^[\w\-\.\+]+@([\w\-]+\.)+[\w\-]{2,}$');
                                        if (!emailRegex.hasMatch(v)) {
                                          return l10n.invalidEmail;
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    CustomInput(
                                      label: l10n.password,
                                      controller: _passwordController,
                                      prefixIcon: Icons.lock_outline,
                                      obscureText: true,
                                      onChanged: _isRegistering
                                          ? (_) => setState(() {})
                                          : null,
                                      validator: (v) {
                                        if (v?.isNotEmpty != true) {
                                          return l10n.required;
                                        }
                                        if (_isRegistering && v!.length < 8) {
                                          return l10n.passwordMinLength;
                                        }
                                        return null;
                                      },
                                    ),
                                    if (_isRegistering) ...[
                                      const SizedBox(height: 8),
                                      _PasswordStrengthIndicator(
                                        password: _passwordController.text,
                                        l10n: l10n,
                                        isDark: isDark,
                                      ),
                                      const SizedBox(height: 12),
                                      CustomInput(
                                        label: l10n.confirmPassword,
                                        controller:
                                            _confirmPasswordController,
                                        prefixIcon: Icons.lock_outline,
                                        obscureText: true,
                                        validator: (v) {
                                          if (v?.isNotEmpty != true) {
                                            return l10n.required;
                                          }
                                          if (v !=
                                              _passwordController.text) {
                                            return l10n.passwordsDoNotMatch;
                                          }
                                          return null;
                                        },
                                      ),
                                    ],
                                    if (_isRegistering) ...[
                                      const SizedBox(height: 12),
                                      _TermsCheckbox(
                                        accepted: _acceptedTerms,
                                        onChanged: (v) => setState(() => _acceptedTerms = v),
                                      ),
                                    ],
                                    const SizedBox(height: 16),
                                    NeonButton(
                                      text: (_isRegistering
                                              ? l10n.register
                                              : l10n.login)
                                          .toUpperCase(),
                                      isLoading: isLoading,
                                      onPressed: _handleUserAuth,
                                    ),
                                    if (!_isRegistering) ...[
                                      const SizedBox(height: 4),
                                      TextButton(
                                        onPressed: () => context.go('/reset-password'),
                                        child: Text(
                                          l10n.forgotPassword,
                                          style: TextStyle(
                                            color: AppTheme.neonBlue.withValues(alpha: 0.8),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    TextButton(
                                      onPressed: () => setState(() =>
                                          _isRegistering = !_isRegistering),
                                      child: Text(
                                        _isRegistering
                                            ? l10n.alreadyHaveAccount
                                            : l10n.doNotHaveAccount,
                                        style: TextStyle(
                                            color: textColor.withValues(
                                              alpha: 0.7,
                                            ),
                                            fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Form(
                                key: _formKeyDevice,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CustomInput(
                                      label: l10n.deviceID,
                                      controller: _deviceIdController,
                                      prefixIcon: Icons.devices,
                                      validator: (v) => v?.isNotEmpty == true
                                          ? null
                                          : l10n.required,
                                    ),
                                    const SizedBox(height: 12),
                                    CustomInput(
                                      label: l10n.pinCode,
                                      controller: _pinController,
                                      prefixIcon: Icons.pin,
                                      obscureText: true,
                                      keyboardType: TextInputType.number,
                                      validator: (v) => v?.isNotEmpty == true
                                          ? null
                                          : l10n.required,
                                    ),
                                    const SizedBox(height: 24),
                                    NeonButton(
                                      text: l10n.startAccess.toUpperCase(),
                                      isLoading: isLoading,
                                      onPressed: _loginDevice,
                                    ),
                                  ],
                                ),
                              ),
                      ),
                            const SizedBox(height: 22),
                            // Claro / oscuro. Antes eran un sol naranja y una
                            // luna azul con un interruptor de dos colores más:
                            // cuatro colores para una preferencia. Ahora el
                            // icono dice el modo y el acento marca cuál está
                            // puesto.
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.light_mode_outlined,
                                    size: 16,
                                    color: isDark
                                        ? AppTheme.textoApagado(context)
                                        : AppTheme.acentoTexto(context)),
                                const SizedBox(width: 10),
                                Switch(
                                  value: isDark,
                                  onChanged: (v) {
                                    HapticFeedback.selectionClick();
                                    ref
                                        .read(themeNotifierProvider.notifier)
                                        .toggleTheme();
                                  },
                                ),
                                const SizedBox(width: 10),
                                Icon(Icons.dark_mode_outlined,
                                    size: 16,
                                    color: isDark
                                        ? AppTheme.acentoTexto(context)
                                        : AppTheme.textoApagado(context)),
                              ],
                            ).animate().fade(delay: 200.ms),
                          ],
                        ),
                      ),
                    ],
                  ),
                ).animate().fade(delay: 100.ms).slideY(begin: 0.1, end: 0),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordStrengthIndicator extends StatelessWidget {
  final String password;
  final AppLocalizations l10n;
  final bool isDark;

  const _PasswordStrengthIndicator({
    required this.password,
    required this.l10n,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final hasMinLength = password.length >= 8;
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasLowercase = password.contains(RegExp(r'[a-z]'));
    final hasNumber = password.contains(RegExp(r'[0-9]'));
    final hasSpecial = password.contains(RegExp(r'[!@#\$%\^&\*\.\-_]'));

    // Cada requisito es una casilla cuadrada que se rellena de lima al
    // cumplirse. La lista entera se lee como una checklist de sistema, y el
    // avance se ve de un vistazo sin tener que leer regla por regla.
    Widget rule(String text, bool met) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: met ? AppTheme.lima : Colors.transparent,
                border: Border.all(
                  color: met ? AppTheme.lima : AppTheme.borde(context),
                  width: 1.2,
                ),
              ),
              child: met
                  ? const Icon(Icons.check,
                      size: 9, color: AppTheme.limaTinta)
                  : null,
            ),
            const SizedBox(width: 9),
            Text(
              text,
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 10.5,
                height: 1.3,
                color: met
                    ? AppTheme.texto(context)
                    : AppTheme.textoApagado(context),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        rule(l10n.passwordRuleMinLength, hasMinLength),
        rule(l10n.passwordRuleUppercase, hasUppercase),
        rule(l10n.passwordRuleLowercase, hasLowercase),
        rule(l10n.passwordRuleNumber, hasNumber),
        rule(l10n.passwordRuleSpecial, hasSpecial),
      ],
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  final bool accepted;
  final ValueChanged<bool> onChanged;

  const _TermsCheckbox({required this.accepted, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final linkColor = AppTheme.acentoTexto(context);
    final textColor = AppTheme.textoSecundario(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: accepted,
            onChanged: (v) => onChanged(v ?? false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(!accepted),
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 12,
                    height: 1.45,
                    color: textColor),
                children: [
                  TextSpan(text: l10n.acceptTermsPrefix),
                  TextSpan(
                    text: l10n.termsOfService,
                    style: TextStyle(
                      color: linkColor,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  TextSpan(text: l10n.acceptTermsSuffix),
                  TextSpan(
                    text: l10n.privacyPolicy,
                    style: TextStyle(
                      color: linkColor,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
