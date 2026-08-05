import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/events/presentation/event_state.dart';
import '../../features/profile/data/profile_repository.dart';
import '../constants/app_roles.dart';
import '../theme/app_theme.dart';

/// Armazón de navegación: cabecera fija arriba, barra de destinos abajo.
///
/// La app venía con el patrón de Material —un `AppBar` con el título de la
/// pantalla y un cajón lateral—, que es el que trae Flutter de fábrica y por eso
/// mismo no dice nada de la marca. Este armazón es el del diseño:
///
///   - **Cabecera global**, siempre igual: menú, el nombre del producto y el
///     avatar. No cambia de pantalla en pantalla, así que funciona de ancla.
///   - **Los títulos van DENTRO del contenido**, no en la cabecera. Por eso
///     `GlassScaffold` toma `titulo` en vez de un `AppBar`.
///   - **Barra inferior con los cuatro destinos** que se usan durante un
///     evento. Estaban todos a dos toques dentro del cajón lateral; en la
///     puerta, con gente esperando, dos toques son muchos.
///
/// La barra se adapta al rol: un dispositivo de puerta no puede entrar a la
/// lista de invitados —lo bloquea el guard del router—, así que en vez de
/// mostrarle un botón que lo rebota, le muestra la búsqueda por documento, que
/// es lo que sí necesita cuando alguien llega sin el QR.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.ubicacion});

  final Widget child;

  /// Ruta activa, que baja desde el `ShellRoute`.
  ///
  /// **No** se lee con `GoRouterState.of(context)` dentro de la barra: eso la
  /// suscribe a los cambios del router, y cuando una redirección se resuelve en
  /// medio del build —cerrar sesión, por ejemplo— el router queda marcado como
  /// "necesita reconstruirse" mientras ya se está construyendo. Flutter aborta
  /// con `setState() called during build` y la app se queda en negro.
  ///
  /// El `ShellRoute` ya recibe el estado resuelto; pasarlo hacia abajo es
  /// gratis y no crea ninguna suscripción.
  final String ubicacion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTheme.fondo(context),
      appBar: CabeceraApp(ubicacion: ubicacion),
      body: child,
      bottomNavigationBar: BarraInferior(ubicacion: ubicacion),
    );
  }
}

/// Los destinos de la barra inferior, según quién esté usando la app.
///
/// Las etiquetas van en su versión corta —`navPanel`, no `dashboard`— porque
/// en cuatro columnas de teléfono "Panel de Control" y "DOCUMENTO (CI / DNI)"
/// no entran: se cortaban con puntos suspensivos y no se entendía cuál era
/// cuál.
List<_Destino> _destinos(BuildContext context, {required bool esPuerta}) {
  final l10n = AppLocalizations.of(context);
  return [
    _Destino('/dashboard', l10n.navPanel, Icons.dashboard_outlined,
        Icons.dashboard),
    _Destino('/events', l10n.events, Icons.calendar_today_outlined,
        Icons.calendar_today),
    _Destino('/scanner', l10n.scanner, Icons.qr_code_scanner,
        Icons.qr_code_scanner),
    if (esPuerta)
      _Destino('/document_search', l10n.navDocument, Icons.badge_outlined,
          Icons.badge)
    else
      _Destino('/tickets', l10n.tickets, Icons.confirmation_number_outlined,
          Icons.confirmation_number),
  ];
}

class _Destino {
  const _Destino(this.ruta, this.etiqueta, this.icono, this.iconoActivo);

  final String ruta;
  final String etiqueta;
  final IconData icono;
  final IconData iconoActivo;
}

/// Navega a un destino, comprobando antes que haya un evento elegido.
///
/// Escanear y buscar por documento operan SOBRE un evento: sin uno elegido, el
/// escáner abre la cámara, lee un QR y recién ahí avisa que no hay evento —con
/// la persona ya parada delante—. El guard vivía en las acciones rápidas del
/// panel; al pasar esos destinos a la barra, se vino con ellos.
///
/// En vez de bloquear y no hacer nada, lleva a elegir evento: el destino al que
/// se quería ir era imposible, pero el paso que falta está a la vista.
void _irA(BuildContext context, WidgetRef ref, String ruta) {
  const necesitanEvento = {'/scanner', '/document_search'};

  if (necesitanEvento.contains(ruta) &&
      ref.read(selectedEventProvider) == null) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).pleaseSelectEvent),
      ));
    context.go('/events');
    return;
  }

  context.go(ruta);
}

/// Barra inferior de destinos.
class BarraInferior extends ConsumerWidget {
  const BarraInferior({super.key, required this.ubicacion});

  final String ubicacion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final esPuerta = ref.watch(deviceProvider) != null ||
        ref.watch(userRoleProvider) == AppRoles.door;
    final destinos = _destinos(context, esPuerta: esPuerta);
    final actual = ubicacion;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.panel(context),
        border: Border(top: BorderSide(color: AppTheme.borde(context))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (final d in destinos)
                Expanded(
                  child: _BotonDestino(
                    destino: d,
                    activo: actual == d.ruta || actual.startsWith('${d.ruta}/'),
                    alNavegar: (ruta) => _irA(context, ref, ruta),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonDestino extends StatelessWidget {
  const _BotonDestino({
    required this.destino,
    required this.activo,
    required this.alNavegar,
  });

  final _Destino destino;
  final bool activo;
  final void Function(String ruta) alNavegar;

  @override
  Widget build(BuildContext context) {
    final color =
        activo ? AppTheme.acentoTexto(context) : AppTheme.textoSecundario(context);

    return Semantics(
      button: true,
      selected: activo,
      label: destino.etiqueta,
      child: InkWell(
        // La navegación usa `go` y no `push`: la barra cambia de destino, no
        // apila pantallas. Con push, tocar cuatro veces la barra dejaba cuatro
        // pantallas encima y el botón de atrás tardaba cuatro toques en salir.
        onTap: activo ? null : () => alNavegar(destino.ruta),
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hover(context),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              // La línea lima arriba es la marca del destino activo. Se dibuja
              // siempre, transparente cuando no toca, para que el contenido no
              // se mueva 2px al cambiar de pestaña.
              top: BorderSide(
                color: activo ? AppTheme.lima : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(activo ? destino.iconoActivo : destino.icono,
                  size: 21, color: color),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  destino.etiqueta.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cabecera global: menú, nombre del producto y avatar.
class CabeceraApp extends ConsumerWidget implements PreferredSizeWidget {
  const CabeceraApp({super.key, required this.ubicacion});

  final String ubicacion;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final enPerfil = ubicacion == '/profile';
    final avatar = ref.watch(profileProvider).valueOrNull?.avatarUrl;

    // Las subpantallas —ajustes › usuarios, ajustes › dispositivos— se apilan
    // dentro del armazón, así que ahí el botón tiene que ser "volver" y no
    // "menú": sin esto quedaban sin forma de salir salvo por la barra de abajo,
    // que las saca del todo en vez de retroceder un paso.
    final puedeVolver = Navigator.of(context).canPop();

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppTheme.panel(context),
        border: Border(bottom: BorderSide(color: AppTheme.borde(context))),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (puedeVolver)
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 22),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
              )
            else
              IconButton(
                icon: const Icon(Icons.menu, size: 22),
                tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                onPressed: () => MenuPantallaCompleta.abrir(context),
              ),
            Expanded(
              child: GestureDetector(
                onTap: () => context.go('/dashboard'),
                child: Text(
                  l10n.appTitle.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppTheme.texto(context),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12, left: 8),
              child: GestureDetector(
                onTap: () => context.go('/profile'),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.campo(context),
                    border: Border.all(
                      color: enPerfil ? AppTheme.lima : AppTheme.borde(context),
                      width: enPerfil ? 2 : 1,
                    ),
                    image: (avatar != null && avatar.isNotEmpty)
                        ? DecorationImage(
                            image: NetworkImage(avatar), fit: BoxFit.cover)
                        : null,
                  ),
                  child: (avatar == null || avatar.isEmpty)
                      ? Icon(Icons.person_outline,
                          size: 17, color: AppTheme.textoSecundario(context))
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Menú a pantalla completa.
///
/// Reemplaza al cajón lateral. La diferencia no es solo estética: el cajón
/// entraba desde el borde y dejaba la pantalla anterior a medio ver, con
/// entradas de lista chicas una debajo de la otra. Acá cada opción ocupa una
/// franja entera con el texto grande, que se acierta con el pulgar sin mirar —
/// que es como se usa esto en la puerta de un evento.
class MenuPantallaCompleta extends ConsumerWidget {
  const MenuPantallaCompleta({super.key});

  static void abrir(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, _, _) => const MenuPantallaCompleta(),
      transitionBuilder: (_, animacion, _, hijo) => FadeTransition(
        opacity: animacion,
        child: hijo,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final rol = ref.watch(userRoleProvider);
    final esPuerta =
        ref.watch(deviceProvider) != null || rol == AppRoles.door;

    void ir(String ruta) {
      Navigator.of(context).pop();
      context.go(ruta);
    }

    // El menú lleva SOLO lo que la barra de abajo no tiene.
    //
    // Antes repetía Panel, Eventos y Tickets, que están a un dedo en la barra:
    // el menú se volvía una lista donde la mitad de las opciones sobraban y
    // había que leerla entera para encontrar las que no. Ahora es lo de fondo
    // —cuenta, plan, configuración— y nada más.
    //
    // Un dispositivo de puerta no llega a ninguna de esas —el guard del router
    // solo le permite panel, escáner, documento y eventos, y las cuatro están
    // en su barra—, así que para él el menú es únicamente cerrar sesión.
    final opciones = <(String, String)>[
      if (!esPuerta) ...[
        ('/profile', l10n.profile),
        ('/subscription', l10n.subscription),
        ('/settings', l10n.settings),
        if (AppRoles.isSuperadmin(rol)) ('/super-admin', l10n.superAdmin),
      ],
    ];

    return Material(
      color: AppTheme.fondo(context),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Container(
            decoration:
                BoxDecoration(border: Border.all(color: AppTheme.borde(context))),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.appTitle.toUpperCase(),
                        style: AppTheme.titular(context, size: 18),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 22),
                      tooltip: l10n.close,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                Divider(color: AppTheme.borde(context), height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (ruta, etiqueta) in opciones)
                          _OpcionMenu(etiqueta: etiqueta, alTocar: () => ir(ruta)),
                        const SizedBox(height: 10),
                        _OpcionMenu(
                          etiqueta: l10n.logout,
                          destructiva: true,
                          // `logout()` sirve para los dos casos: adentro llama
                          // a `clearSession()`, que es lo que cierra la sesión
                          // de un dispositivo de puerta.
                          alTocar: () async {
                            Navigator.of(context).pop();
                            await ref
                                .read(authControllerProvider.notifier)
                                .logout();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const _PieTecnico(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OpcionMenu extends StatelessWidget {
  const _OpcionMenu({
    required this.etiqueta,
    required this.alTocar,
    this.destructiva = false,
  });

  final String etiqueta;
  final VoidCallback alTocar;
  final bool destructiva;

  @override
  Widget build(BuildContext context) {
    final color = destructiva
        ? AppTheme.peligroTexto(context)
        : AppTheme.texto(context);

    return InkWell(
      onTap: alTocar,
      splashFactory: NoSplash.splashFactory,
      highlightColor: AppTheme.hover(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: destructiva
            ? null
            : BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppTheme.bordeSuave(context))),
              ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                etiqueta.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.titular(context, size: 19, color: color),
              ),
            ),
            Icon(destructiva ? Icons.logout : Icons.arrow_forward,
                size: 19, color: color),
          ],
        ),
      ),
    );
  }
}

/// Pie del menú: versión y estado de la conexión.
///
/// En el diseño es puro decorado. Acá dice la verdad —la versión que salió del
/// build— porque cuando alguien reporta un problema desde la puerta, lo primero
/// que hace falta saber es qué versión tiene cargada.
class _PieTecnico extends StatelessWidget {
  const _PieTecnico();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Container(width: 6, height: 6, color: AppTheme.lima),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'IMAGINE ACCESS · v${const String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.dato(
                context,
                size: 9.5,
                peso: FontWeight.w400,
                color: AppTheme.textoApagado(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
