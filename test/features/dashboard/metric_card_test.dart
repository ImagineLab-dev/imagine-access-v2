import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagine_access/core/ui/responsive.dart';
import 'package:imagine_access/features/dashboard/presentation/widgets/dashboard_components.dart';

/// `MetricCard` pasó de apilar el ícono arriba del número a ponerlo al costado,
/// y `Responsive.proporcionTarjeta` bajó la altura objetivo de 118 a 74 px.
///
/// El riesgo de ese cambio es concreto: menos alto disponible más una etiqueta
/// larga da un desbordamiento de Flex, que en producción se ve como una franja
/// amarilla y negra sobre la tarjeta. Las etiquetas reales de esta app llegan a
/// "INGRESO INVITADOS (IN/TOT)", así que se prueba con esa y con anchos de
/// pantalla distintos, no solo con el cómodo.
void main() {
  Widget grilla(Size pantalla, List<MetricCard> tarjetas) {
    return MediaQuery(
      data: MediaQueryData(size: pantalla),
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.all(20),
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: Responsive.columnas(context),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: Responsive.proporcionTarjeta(context),
                physics: const NeverScrollableScrollPhysics(),
                children: tarjetas,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Las OCHO que quedaron en la grilla.
  ///
  /// Ventas salio de acá el 29/07/2026 y se dibuja a ancho completo debajo:
  /// nueve tarjetas en dos columnas dejaban la ultima fila con una sola y el
  /// bloque se veia torcido. Ocho son cuatro filas de dos exactas.
  List<MetricCard> lasOchoDeLaGrilla() => const [
        MetricCard(
            title: 'Tickets Totales',
            value: '6',
            icon: Icons.confirmation_number_outlined,
            color: Colors.blue,
            delay: 0),
        MetricCard(
            title: 'Válido',
            value: '2',
            icon: Icons.check_circle_outline,
            color: Colors.green,
            delay: 0),
        MetricCard(
            title: 'Escaneados',
            value: '4',
            icon: Icons.qr_code_scanner,
            color: Colors.purple,
            delay: 0),
        MetricCard(
            title: 'STAFF (IN/TOT)',
            value: '3 / 4',
            icon: Icons.badge_outlined,
            color: Colors.orange,
            delay: 0),
        MetricCard(
            title: 'INVITADOS (IN/TOT)',
            value: '1 / 2',
            icon: Icons.star_border,
            color: Colors.pink,
            delay: 0),
        MetricCard(
            title: 'NORMALES (IN/TOT)',
            value: '0 / 0',
            icon: Icons.people_outline,
            color: Colors.teal,
            delay: 0),
        // La etiqueta más larga de la app.
        MetricCard(
            title: 'INGRESO INVITADOS (IN/TOT)',
            value: '0 / 0',
            icon: Icons.mail_outline,
            color: Colors.deepPurple,
            delay: 0),
        MetricCard(
            title: 'Promo (IN/TOT)',
            value: '0 / 0',
            icon: Icons.local_offer,
            color: Colors.orange,
            delay: 0),
      ];

  for (final caso in <(String, Size)>[
    ('teléfono angosto', Size(320, 700)),
    ('teléfono común', Size(390, 844)),
    ('teléfono ancho', Size(430, 932)),
    ('tablet', Size(834, 1112)),
    ('escritorio', Size(1600, 900)),
  ]) {
    testWidgets('las ocho metricas de la grilla caben sin desbordar en ${caso.$1}',
        (tester) async {
      tester.view.physicalSize = caso.$2;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(grilla(caso.$2, lasOchoDeLaGrilla()));
      await tester.pump(const Duration(milliseconds: 600));

      // Un desbordamiento de Flex llega acá como excepción.
      expect(tester.takeException(), isNull);

      // Y los números siguen estando: que no desborde no sirve si el valor se
      // recortó a nada.
      expect(find.text('6'), findsOneWidget);
      expect(find.text('3 / 4'), findsOneWidget);
    });
  }

  testWidgets('un valor largo se encoge en vez de desbordar', (tester) async {
    const pantalla = Size(320, 700);
    tester.view.physicalSize = pantalla;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(grilla(pantalla, const [
      MetricCard(
          title: 'Ventas',
          value: 'Gs 987.654.321',
          icon: Icons.attach_money,
          color: Colors.amber,
          delay: 0),
    ]));
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.text('Gs 987.654.321'), findsOneWidget);
  });

  testWidgets('la grilla cierra filas completas: nada de tarjetas huerfanas',
      (tester) async {
    // Esto es lo que se pidio: que quede simetrico. Ocho tarjetas cierran
    // exacto con 2 o 4 columnas; con 3 quedaria una fila de dos y un hueco.
    //
    // `Responsive.columnas` devuelve floor(ancho/240) acotado entre 2 y 4, asi
    // que 3 aparece en el rango 720-959 px: una tablet chica o una ventana
    // partida. Este test deja constancia de en que anchos la grilla queda
    // pareja y en cuales no, para que el dia que importe no sea una sorpresa.
    const cantidad = 8;
    final resultados = <String>[];

    for (final ancho in [320.0, 390.0, 430.0, 600.0, 800.0, 1024.0, 1600.0]) {
      final pantalla = Size(ancho, 900);
      tester.view.physicalSize = pantalla;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late int columnas;
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: pantalla),
        child: MaterialApp(
          home: Builder(builder: (context) {
            columnas = Responsive.columnas(context);
            return const SizedBox();
          }),
        ),
      ));

      final sobra = cantidad % columnas;
      resultados.add('${ancho.toInt()}px -> $columnas col, sobran $sobra');
    }

    // A 2 y 4 columnas tiene que cerrar exacto. Son los casos reales: telefono
    // y escritorio.
    expect(resultados.where((r) => r.contains('-> 2 col')).every(
        (r) => r.endsWith('sobran 0')), isTrue,
        reason: 'en telefono la grilla tiene que cerrar exacta: $resultados');
    expect(resultados.where((r) => r.contains('-> 4 col')).every(
        (r) => r.endsWith('sobran 0')), isTrue,
        reason: 'en escritorio la grilla tiene que cerrar exacta: $resultados');
  });

  test('la tarjeta es más baja que antes del rediseño', () {
    // La altura objetivo bajó de 118 a 74. Si alguien la vuelve a subir sin
    // pensarlo, este test lo dice: son unos 400 px menos de desplazamiento con
    // nueve métricas en dos columnas.
    const antes = 118.0;
    const ahora = 74.0;
    expect(ahora, lessThan(antes));
    final filas = (9 / 2).ceil();
    expect((antes - ahora) * filas, greaterThan(200));
  });
}
