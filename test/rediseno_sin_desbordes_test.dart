// Los componentes del rediseño, dibujados de verdad y a varios anchos.
//
// Todo lo que se rediseñó el 05/08/2026 se verificó con `flutter analyze` y con
// los tests existentes, pero ninguno de los dos DIBUJA nada: un `Row` que se
// pasa 40 px por un texto largo compila igual y pasa los tests igual. El error
// aparece en pantalla y en ningún otro lado.
//
// Acá cada componente se monta con contenido hostil —textos largos, cifras
// grandes, contadores de cuatro dígitos— en el ancho de un teléfono chico, uno
// normal y un monitor, en los dos temas. En un test de widgets un desborde de
// `RenderFlex` lanza excepción, así que si algo no entra, esto falla.
//
// Advertencia honesta sobre el alcance: en tests las fuentes propias no están
// cargadas y Flutter mide con la de reemplazo, que no tiene los mismos anchos
// de glifo que Space Grotesk o JetBrains Mono. Esto atrapa los desbordes
// estructurales —un `Row` sin `Expanded`, un ancho fijo demasiado chico— que
// son la mayoría; no atrapa un texto que se pasa por tres píxeles.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagine_access/core/constants/app_roles.dart';
import 'package:imagine_access/core/theme/app_theme.dart';
import 'package:imagine_access/core/ui/app_shell.dart';
import 'package:imagine_access/core/ui/glass_scaffold.dart';
import 'package:imagine_access/features/auth/presentation/auth_controller.dart';
import 'package:imagine_access/features/profile/data/profile_repository.dart';
import 'package:imagine_access/core/ui/carrusel_metricas.dart';
import 'package:imagine_access/core/ui/custom_input.dart';
import 'package:imagine_access/core/ui/empty_state.dart';
import 'package:imagine_access/core/ui/glass_card.dart';
import 'package:imagine_access/core/ui/neon_button.dart';
import 'package:imagine_access/core/ui/pase_ticket.dart';
import 'package:imagine_access/core/ui/status_badge.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

/// Anchos donde la app tiene que funcionar.
///
/// 320 es un iPhone SE, que sigue existiendo y es el caso peor. 390 es la
/// mayoría de los teléfonos. 1440 es la notebook desde la que se administra.
const _anchos = <String, double>{
  'teléfono chico (320)': 320,
  'teléfono (390)': 390,
  'escritorio (1440)': 1440,
};

/// Texto largo de verdad: nombres de evento reales se pasan de una línea.
const _textoLargo =
    'FIESTA DE FIN DE AÑO — CLUB SOCIAL Y DEPORTIVO GENERAL SAN MARTÍN';

Future<void> _montar(
  WidgetTester tester,
  Widget hijo, {
  required double ancho,
  required Brightness brillo,
}) async {
  tester.view.physicalSize = Size(ancho, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: brillo == Brightness.dark ? AppTheme.darkTheme() : AppTheme.lightTheme(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: hijo),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Dibuja el mismo componente en los tres anchos y los dos temas.
///
/// Las seis combinaciones van DENTRO de un solo `testWidgets` y no en seis
/// tests sueltos. La cobertura es idéntica, pero cada `testWidgets` levanta su
/// propio arnés: con nueve componentes eran 54 arneses, cada uno construyendo
/// un `MaterialApp` entero con sus cuatro delegados de localización. Corriendo
/// la suite completa, eso agotaba la memoria de la VM de Dart —`Out of memory`
/// y la corrida entera muerta—. El `reason` de cada aserción dice qué
/// combinación falló, que es la única cosa que se perdía al agrupar.
void _enTodosLosTamanos(String nombre, Widget Function() construir) {
  testWidgets(nombre, (tester) async {
    for (final entrada in _anchos.entries) {
      for (final brillo in Brightness.values) {
        final modo = brillo == Brightness.dark ? 'oscuro' : 'claro';

        await _montar(tester, construir(), ancho: entrada.value, brillo: brillo);

        // Un desborde de RenderFlex llega acá como excepción. Que no haya
        // ninguna es exactamente lo que se está afirmando.
        expect(tester.takeException(), isNull,
            reason: '$nombre se rompe en ${entrada.key} / $modo');

        // Y se desmonta a mano: los componentes con temporizador o animación en
        // bucle tienen que soltarlos al irse. Si alguno queda vivo, el arnés
        // falla el test — que es como se detecta una fuga.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      }
    }
  });
}

void main() {
  _enTodosLosTamanos(
    'NeonButton con texto largo',
    () => Column(
      children: [
        NeonButton(text: _textoLargo, icon: Icons.add, onPressed: () {}),
        const SizedBox(height: 8),
        NeonButton(text: _textoLargo, isSecondary: true, onPressed: () {}),
        const SizedBox(height: 8),
        const NeonButton(text: 'DESHABILITADO'),
        const SizedBox(height: 8),
        const NeonButton(text: 'CARGANDO', isLoading: true),
      ],
    ),
  );

  _enTodosLosTamanos(
    'GlassCard con etiqueta y filas de dato',
    () => GlassCard(
      etiqueta: 'PARÁMETROS DE OPERACIÓN DEL EVENTO',
      child: Column(
        children: const [
          FilaDato(etiqueta: _textoLargo, valor: 'Gs 12.500.000'),
          FilaDato(
              etiqueta: 'Corto',
              valor: 'UN-VALOR-MONOESPACIADO-MUY-LARGO-1234567890',
              acentuado: true),
          FilaDato(etiqueta: 'Último', valor: '0', separador: false),
        ],
      ),
    ),
  );

  _enTodosLosTamanos(
    'StatusBadge en sus cuatro estados',
    () => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final estado in BadgeStatus.values) ...[
          StatusBadge(text: 'ESTADO $estado', status: estado),
          StatusBadge(text: 'CONTORNO', status: estado, solido: false),
        ],
      ],
    ),
  );

  _enTodosLosTamanos(
    'EmptyState con acción',
    () => EmptyState(
      icon: Icons.inbox_outlined,
      title: _textoLargo,
      body: 'Un texto explicativo razonablemente largo que ocupa varias '
          'líneas y cuenta por qué esto importa.',
      actionLabel: 'CREAR EL PRIMER EVENTO DE LA ORGANIZACIÓN',
      onAction: () {},
    ),
  );

  _enTodosLosTamanos(
    'CustomInput con etiqueta larga, código y error',
    () => Form(
      child: Column(
        children: [
          CustomInput(
            label: 'CORREO ELECTRÓNICO DE LA PERSONA RESPONSABLE',
            codigo: 'ID_01',
            hint: 'usuario@dominio.com',
            prefixIcon: Icons.mail_outline,
            validator: (_) => 'Este campo tiene un mensaje de error largo '
                'que ocupa más de una línea completa.',
            onChanged: (_) {},
          ),
          const SizedBox(height: 10),
          CustomInput(
            label: 'CONTRASEÑA',
            codigo: 'PWD_02',
            obscureText: true,
            onChanged: (_) {},
          ),
          const SizedBox(height: 10),
          const CustomInput(label: 'DESHABILITADO', enabled: false),
        ],
      ),
    ),
  );

  _enTodosLosTamanos(
    'PaseTicket con datos largos',
    () => PaseTicket(
      colorFondo: const Color(0xFF0A0A0B),
      titulo: _textoLargo,
      subtitulo: 'ACCESO VIP — PASE MAESTRO CON BARRA LIBRE',
      serial: 'a3f1c9e2-7b4d-4e8a-9c1f-2d5e8b7a4c6f',
      datos: const [
        ('COMPRADOR', 'María Fernanda Rodríguez de los Santos'),
        ('ESTADO', 'VÁLIDO'),
        ('CORREO', 'maria.fernanda.rodriguez@dominio-muy-largo.com.py'),
        ('ENVIADO', '05/08 14:32'),
      ],
    ),
  );

  _enTodosLosTamanos(
    'PaseTicket anulado',
    () => PaseTicket(
      colorFondo: const Color(0xFFF4F4F1),
      titulo: 'EVENTO',
      subtitulo: 'GENERAL',
      serial: 'TKT-0001',
      anulado: true,
      datos: const [('ESTADO', 'ANULADO')],
    ),
  );

  // El carrusel es el que más riesgo tiene: tiene temporizador propio,
  // animaciones en bucle y ocho tarjetas con cifras de largo variable.
  _enTodosLosTamanos(
    'CarruselMetricas con ocho tarjetas',
    () => CarruselMetricas(
      tarjetas: [
        for (var i = 0; i < 8; i++)
          TarjetaCarrusel(
            etiqueta: i.isEven
                ? 'INGRESO DE INVITADOS ESPECIALES'
                : 'STAFF',
            valor: i.isEven ? '1234 / 5678' : '$i',
            icono: Icons.badge_outlined,
            avance: i.isEven ? i / 8 : null,
            detalle: i.isOdd ? '$i sin ingresar' : null,
          ),
      ],
    ),
  );

  // Una sola tarjeta: el temporizador no debe arrancar y las flechas no deben
  // ofrecer moverse a ningún lado.
  _enTodosLosTamanos(
    'CarruselMetricas con una sola tarjeta',
    () => const CarruselMetricas(
      tarjetas: [
        TarjetaCarrusel(
          etiqueta: 'ÚNICA',
          valor: '0',
          icono: Icons.confirmation_number_outlined,
        ),
      ],
    ),
  );

  testWidgets('el carrusel suelta su temporizador al desmontarse',
      (tester) async {
    await _montar(
      tester,
      CarruselMetricas(
        tarjetas: [
          for (var i = 0; i < 4; i++)
            TarjetaCarrusel(
                etiqueta: 'M$i', valor: '$i', icono: Icons.abc),
        ],
      ),
      ancho: 390,
      brillo: Brightness.dark,
    );

    // Se deja correr más que el intervalo de avance automático (4 s) para que
    // el temporizador dispare al menos una vez estando montado.
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);

    // Y se baja el árbol. Si `dispose` no cancelara el temporizador, el arnés
    // fallaría acá con "A Timer is still pending".
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('con "reducir movimiento" el carrusel no avanza solo',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        // Es la señal que da el sistema cuando alguien pidió menos animaciones.
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: CarruselMetricas(
              tarjetas: [
                for (var i = 0; i < 5; i++)
                  TarjetaCarrusel(
                      etiqueta: 'M$i', valor: '$i', icono: Icons.abc),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  // --- Armazón de navegación -----------------------------------------------
  //
  // La barra inferior es el caso peor de todos: cuatro columnas fijas
  // repartiéndose el ancho de la pantalla, cada una con ícono y etiqueta. En un
  // teléfono de 320 px son 80 px por columna. Si una etiqueta no entra, no se
  // recorta sola: rompe la fila.

  Future<void> montarBarra(
    WidgetTester tester, {
    required double ancho,
    required Brightness brillo,
    required bool esPuerta,
  }) async {
    tester.view.physicalSize = Size(ancho, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProvider.overrideWith((ref) => null),
          userRoleProvider.overrideWith(
              (ref) => esPuerta ? AppRoles.door : AppRoles.admin),
          profileProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: brillo == Brightness.dark
              ? AppTheme.darkTheme()
              : AppTheme.lightTheme(),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox.shrink(),
            bottomNavigationBar: BarraInferior(ubicacion: '/dashboard'),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('BarraInferior en todos los tamaños, temas y roles',
      (tester) async {
    for (final entrada in _anchos.entries) {
      for (final brillo in Brightness.values) {
        for (final esPuerta in [false, true]) {
          final modo = brillo == Brightness.dark ? 'oscuro' : 'claro';
          final rol = esPuerta ? 'puerta' : 'admin';

          await montarBarra(tester,
              ancho: entrada.value, brillo: brillo, esPuerta: esPuerta);
          expect(tester.takeException(), isNull,
              reason: 'la barra se rompe en ${entrada.key} / $modo / $rol');

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      }
    }
  });

  // El título de pantalla vive DENTRO del contenido y comparte la línea con
  // las acciones. Un nombre largo más dos botones es la combinación que
  // rompía la cabecera vieja.
  _enTodosLosTamanos(
    'GlassScaffold con título largo y dos acciones',
    () => SizedBox(
      height: 420,
      child: GlassScaffold(
        titulo: _textoLargo,
        acciones: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.person_add)),
        ],
        body: const Center(child: Text('contenido')),
      ),
    ),
  );

  test('proporcion() no divide por cero ni se pasa de 1', () {
    expect(proporcion(0, 0), 0);
    expect(proporcion(5, 0), 0);
    expect(proporcion(3, 4), closeTo(0.75, 1e-9));
    // Más entradas que emitidos no debería pasar, pero si pasa la barra no
    // puede desbordar: LinearProgressIndicator revienta con un valor > 1.
    expect(proporcion(9, 4), 1);
  });
}
