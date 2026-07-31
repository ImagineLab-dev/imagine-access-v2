import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import 'package:imagine_access/features/dashboard/data/dashboard_repository.dart';
import 'package:imagine_access/features/dashboard/presentation/stats_screen.dart';

/// La pantalla de estadísticas se rediseñó el 29/07/2026 y la parte frágil no es
/// el aspecto sino la aritmética del eje: `fl_chart` lanza una aserción si el
/// intervalo de la grilla sale 0, NaN o infinito, y eso depende del máximo de
/// los datos. Un evento sin ventas, con un solo día, o con cifras en millones
/// pasan por esa cuenta.
///
/// Estos casos son los que existían de verdad y no estaban cubiertos: la
/// pantalla anterior escondía el problema porque no tenía eje vertical.
void main() {
  Widget envolver(Map<String, dynamic> stats) {
    return ProviderScope(
      overrides: [
        eventStatsProvider('evento-de-prueba').overrideWith((ref) async => stats),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(),
        home: const StatsScreen(eventId: 'evento-de-prueba'),
      ),
    );
  }

  Future<void> render(WidgetTester tester, Map<String, dynamic> stats) async {
    await tester.pumpWidget(envolver(stats));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  testWidgets('todo vacío: no explota y muestra ceros', (tester) async {
    await render(tester, {
      'attendance_by_hour': [],
      'rrpp_performance': [],
      'sales_timeline': [],
    });

    expect(tester.takeException(), isNull);
    // El total se dice en texto aunque no haya gráfico que dibujar.
    expect(find.text('0'), findsWidgets);
  });

  testWidgets('claves ausentes: no explota', (tester) async {
    await render(tester, <String, dynamic>{});
    expect(tester.takeException(), isNull);
  });

  testWidgets('un solo punto en cada serie: no explota', (tester) async {
    await render(tester, {
      'attendance_by_hour': [
        {'hour': '22:00', 'count': 4}
      ],
      'rrpp_performance': [
        {'name': 'PATRICIO', 'count': 6}
      ],
      'sales_timeline': [
        {'day': '2026-07-29', 'revenue': 50000}
      ],
    });

    expect(tester.takeException(), isNull);
    // El nombre del vendedor entero, sin recortar: era lo que fallaba con el
    // anillo, que lo mostraba como "PATRICI...".
    expect(find.text('PATRICIO'), findsOneWidget);
    expect(find.text('22h'), findsOneWidget);
  });

  testWidgets('todo en cero: el intervalo del eje no puede ser 0', (tester) async {
    await render(tester, {
      'attendance_by_hour': [
        {'hour': '20:00', 'count': 0},
        {'hour': '21:00', 'count': 0},
      ],
      'rrpp_performance': [
        {'name': 'Sin ventas', 'count': 0}
      ],
      'sales_timeline': [
        {'day': '2026-07-28', 'revenue': 0},
        {'day': '2026-07-29', 'revenue': 0},
      ],
    });

    expect(tester.takeException(), isNull);
  });

  testWidgets('cifras grandes: el eje se abrevia y no desborda', (tester) async {
    await render(tester, {
      'attendance_by_hour': [
        {'hour': '19:00', 'count': 1200},
        {'hour': '20:00', 'count': 3400},
      ],
      'rrpp_performance': [
        {'name': 'Vendedor con un nombre bastante largo', 'count': 900},
        {'name': 'Otro', 'count': 300},
      ],
      'sales_timeline': [
        {'day': '2026-07-27', 'revenue': 12500000},
        {'day': '2026-07-28', 'revenue': 48000000},
      ],
    });

    expect(tester.takeException(), isNull);
    // 60,5M de total: se abrevia en vez de escribir todos los dígitos.
    expect(find.textContaining('M'), findsWidgets);
  });

  testWidgets('valores nulos entre los datos: no explota', (tester) async {
    await render(tester, {
      'attendance_by_hour': [
        {'hour': null, 'count': null},
        {'hour': '23:00', 'count': 3},
      ],
      'rrpp_performance': [
        {'name': null, 'count': null}
      ],
      'sales_timeline': [
        {'day': null, 'revenue': null}
      ],
    });

    expect(tester.takeException(), isNull);
  });

  testWidgets('más de seis vendedores: se recorta con aviso', (tester) async {
    await render(tester, {
      'attendance_by_hour': [],
      'sales_timeline': [],
      'rrpp_performance': [
        for (var i = 1; i <= 9; i++) {'name': 'Vendedor $i', 'count': 10 - i}
      ],
    });

    expect(tester.takeException(), isNull);
    expect(find.text('Vendedor 1'), findsOneWidget);
    // El séptimo ya no se dibuja, pero se dice cuántos quedaron afuera: un
    // recorte silencioso se lee como "no hay más".
    expect(find.text('Vendedor 7'), findsNothing);
    expect(find.textContaining('3 más'), findsOneWidget);
  });
}
