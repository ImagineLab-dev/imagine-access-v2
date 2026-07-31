import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:developer' as dev;
import 'package:imagine_access/l10n/generated/app_localizations.dart';
import '../../../core/ui/glass_scaffold.dart';
import '../../../core/ui/glass_card.dart';
import '../../../core/theme/app_theme.dart';
import '../data/dashboard_repository.dart';

/// Estadísticas del evento.
///
/// Rediseño 29/07/2026. Los tres gráficos anteriores medían 300 px de alto cada
/// uno —unos 1100 px con títulos y separaciones, casi tres pantallas de
/// teléfono— y NINGUNO tenía eje vertical (`leftTitles: showTitles: false` en
/// los tres). Sin eje, una barra alta no se puede leer como cantidad: se ve la
/// forma y no el dato. Además el gráfico de RRPP era un anillo, y con un solo
/// vendedor un anillo es un círculo entero que no informa nada.
///
/// Los tres principios de este rediseño:
///
///   1. El número primero. Cada tarjeta abre con el total en texto grande. Si
///      el gráfico no se entiende, el dato igual está dicho.
///   2. Eje vertical siempre. Con escala a la izquierda y líneas guía suaves.
///   3. La forma según el dato, no según la variedad. El desempeño de RRPP es
///      un ranking, así que se dibuja como ranking: filas ordenadas con barra
///      proporcional. Funciona con uno o con quince, y ningún nombre se corta.
class StatsScreen extends ConsumerWidget {
  final String eventId;

  const StatsScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statsAsync = ref.watch(eventStatsProvider(eventId));

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.statistics),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(eventStatsProvider(eventId)),
        child: statsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) {
            if (kDebugMode) dev.log('Stats error: $e', name: 'StatsScreen');
            return Center(
                child: Text('${l10n.error}\n$e', textAlign: TextAlign.center));
          },
          data: (stats) {
            if (kDebugMode) {
              dev.log('Stats data received: $stats', name: 'StatsScreen');
            }
            final attendance = stats['attendance_by_hour'] as List? ?? [];
            final rrpp = stats['rrpp_performance'] as List? ?? [];
            final sales = stats['sales_timeline'] as List? ?? [];
            final noData = l10n.noDataAvailable;

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TarjetaIngresosPorHora(
                    datos: attendance,
                    titulo: l10n.enteringPerHour,
                    sinDatos: noData,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 14),
                  _TarjetaRrpp(
                    datos: rrpp,
                    titulo: l10n.rrppPerformance,
                    sinDatos: noData,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 14),
                  _TarjetaVentas(
                    datos: sales,
                    titulo: l10n.salesTrend,
                    sinDatos: noData,
                    isDark: isDark,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas compartidas
// ---------------------------------------------------------------------------

/// Encabezado de una tarjeta: rótulo chico, número grande y una línea de apoyo.
///
/// El número va acá y no dentro del gráfico a propósito. Es lo único que se lee
/// de un vistazo, y tiene que sobrevivir a que el gráfico esté vacío, tenga un
/// solo punto, o no se entienda.
class _Encabezado extends StatelessWidget {
  const _Encabezado({
    required this.rotulo,
    required this.valor,
    required this.apoyo,
    required this.isDark,
    required this.color,
  });

  final String rotulo;
  final String valor;
  final String? apoyo;
  final bool isDark;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rotulo.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              valor,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                height: 1,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            if (apoyo != null) ...[
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  apoyo!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Aviso de tarjeta sin datos, en el alto mínimo posible.
///
/// Antes cada gráfico vacío reservaba 200 px para decir una frase. Tres
/// secciones sin datos daban 600 px de nada.
class _SinDatos extends StatelessWidget {
  const _SinDatos({required this.texto, required this.isDark});

  final String texto;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Row(
        children: [
          Icon(Icons.bar_chart_outlined,
              size: 16, color: isDark ? Colors.white24 : Colors.black26),
          const SizedBox(width: 8),
          Text(
            texto,
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }
}

/// Intervalo "redondo" para el eje vertical.
///
/// Sin esto la escala sale con marcas en 3,33 o 16,67 y el eje estorba en vez
/// de ayudar. Se busca el 1/2/5 × 10^n más chico que deje unas cuatro marcas.
double _intervaloAgradable(double maximo) {
  if (maximo <= 0) return 1;
  final crudo = maximo / 4;

  // Se recorre la escala 1-2-5-10-20-50... en vez de usar logaritmos: son pocos
  // pasos, no hay redondeos raros y se lee de un vistazo.
  const bases = <double>[1, 2, 5];
  var factor = 1.0;
  while (factor <= 1e12) {
    for (final b in bases) {
      final paso = b * factor;
      if (paso >= crudo) return paso;
    }
    factor *= 10;
  }
  // Solo se llega acá con cifras absurdas; devolver el crudo es mejor que 0,
  // porque un intervalo 0 hace que fl_chart no dibuje el eje.
  return crudo;
}

/// Número corto para las marcas del eje: 1200 -> "1,2k", 45000 -> "45k".
String _corto(double v) {
  if (v >= 1000000) {
    final m = v / 1000000;
    return '${m.toStringAsFixed(m < 10 ? 1 : 0).replaceAll('.', ',')}M';
  }
  if (v >= 1000) {
    final k = v / 1000;
    return '${k.toStringAsFixed(k < 10 ? 1 : 0).replaceAll('.', ',')}k';
  }
  return v.toStringAsFixed(0);
}

FlLine _lineaGuia(bool isDark) => FlLine(
      color: (isDark ? Colors.white : Colors.black).withValues(alpha: .07),
      strokeWidth: 1,
    );

TextStyle _estiloEje(bool isDark) => TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      color: isDark ? Colors.white38 : Colors.black38,
    );

// ---------------------------------------------------------------------------
// Ingresos por hora
// ---------------------------------------------------------------------------

class _TarjetaIngresosPorHora extends StatelessWidget {
  const _TarjetaIngresosPorHora({
    required this.datos,
    required this.titulo,
    required this.sinDatos,
    required this.isDark,
  });

  final List datos;
  final String titulo;
  final String sinDatos;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    var total = 0.0;
    var pico = 0.0;
    String? horaPico;
    for (final d in datos) {
      final c = ((d['count'] as num?) ?? 0).toDouble();
      total += c;
      if (c > pico) {
        pico = c;
        horaPico = (d['hour'] as String?)?.split(':').first;
      }
    }

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Encabezado(
            rotulo: titulo,
            valor: total.toStringAsFixed(0),
            apoyo: horaPico == null ? null : 'pico a las ${horaPico}h',
            isDark: isDark,
            color: AppTheme.accentBlue,
          ),
          if (datos.isEmpty)
            _SinDatos(texto: sinDatos, isDark: isDark)
          else ...[
            const SizedBox(height: 14),
            SizedBox(
              // 148 px en vez de 300. Alcanza para comparar alturas, que es
              // todo lo que se le pide a un gráfico de barras.
              height: 148,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: pico <= 0 ? 4 : pico * 1.25,
                  barTouchData: BarTouchData(enabled: true),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _intervaloAgradable(pico),
                    getDrawingHorizontalLine: (_) => _lineaGuia(isDark),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    show: true,
                    // El eje que faltaba. Sin él las barras eran decoración.
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: _intervaloAgradable(pico),
                        getTitlesWidget: (valor, meta) {
                          if (valor < 0) return const SizedBox.shrink();
                          return Text(valor.toStringAsFixed(0),
                              style: _estiloEje(isDark));
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (valor, meta) {
                          final i = valor.toInt();
                          if (i < 0 || i >= datos.length) {
                            return const SizedBox.shrink();
                          }
                          final h =
                              (datos[i]['hour'] as String?)?.split(':').first;
                          // Con la "h" se lee como hora. Antes decía "17" y
                          // parecía una cantidad más.
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(h == null ? '-' : '${h}h',
                                style: _estiloEje(isDark)),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  barGroups: datos.asMap().entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: ((e.value['count'] as num?) ?? 0).toDouble(),
                          color: AppTheme.accentBlue,
                          width: 14,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3)),
                        )
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desempeño de RRPP — ranking, no anillo
// ---------------------------------------------------------------------------

class _TarjetaRrpp extends StatelessWidget {
  const _TarjetaRrpp({
    required this.datos,
    required this.titulo,
    required this.sinDatos,
    required this.isDark,
  });

  final List datos;
  final String titulo;
  final String sinDatos;
  final bool isDark;

  static const _colores = <Color>[
    AppTheme.accentBlue,
    AppTheme.accentPurple,
    AppTheme.accentGreen,
    AppTheme.accentYellow,
    Colors.pinkAccent,
  ];

  @override
  Widget build(BuildContext context) {
    final porNombre = <String, double>{};
    for (final item in datos) {
      final nombre = (item['name'] as String?) ?? '';
      porNombre[nombre] =
          (porNombre[nombre] ?? 0) + ((item['count'] as num?) ?? 0).toDouble();
    }
    final ordenados = porNombre.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final total = ordenados.fold<double>(0, (s, e) => s + e.value);
    final maximo = ordenados.isEmpty ? 0.0 : ordenados.first.value;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Encabezado(
            rotulo: titulo,
            valor: total.toStringAsFixed(0),
            apoyo: ordenados.isEmpty
                ? null
                : ordenados.length == 1
                    ? 'de ${ordenados.first.key}'
                    : 'entre ${ordenados.length} vendedores',
            isDark: isDark,
            color: AppTheme.accentPurple,
          ),
          if (ordenados.isEmpty)
            _SinDatos(texto: sinDatos, isDark: isDark)
          else ...[
            const SizedBox(height: 14),
            // Ranking: nombre, barra proporcional al primero, y cantidad.
            //
            // Reemplaza al anillo. Un anillo necesita al menos tres porciones
            // para decir algo, se corta las etiquetas cuando los nombres son
            // largos —pasaba con "PATRICIO"— y gastaba 300 px. Estas filas
            // miden 34 px cada una, muestran el nombre completo y se leen igual
            // con un vendedor que con quince.
            ...ordenados.take(6).toList().asMap().entries.map((entrada) {
              final i = entrada.key;
              final e = entrada.value;
              final color = _colores[i % _colores.length];
              final fraccion = maximo <= 0 ? 0.0 : (e.value / maximo);

              return Padding(
                padding: EdgeInsets.only(bottom: i == ordenados.length - 1 ? 0 : 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.key.isEmpty ? '—' : e.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          e.value.toStringAsFixed(0),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: fraccion,
                        minHeight: 6,
                        backgroundColor: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: .07),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (ordenados.length > 6)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'y ${ordenados.length - 6} más',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tendencia de ventas
// ---------------------------------------------------------------------------

class _TarjetaVentas extends StatelessWidget {
  const _TarjetaVentas({
    required this.datos,
    required this.titulo,
    required this.sinDatos,
    required this.isDark,
  });

  final List datos;
  final String titulo;
  final String sinDatos;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    var total = 0.0;
    var maximo = 0.0;
    for (final d in datos) {
      final v = ((d['revenue'] as num?) ?? 0).toDouble();
      total += v;
      if (v > maximo) maximo = v;
    }

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Encabezado(
            rotulo: titulo,
            valor: _corto(total),
            apoyo: datos.isEmpty
                ? null
                : datos.length == 1
                    ? 'en un solo día'
                    : 'en ${datos.length} días',
            isDark: isDark,
            color: AppTheme.accentPurple,
          ),
          if (datos.isEmpty)
            _SinDatos(texto: sinDatos, isDark: isDark)
          else ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 148,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maximo <= 0 ? 4 : maximo * 1.25,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _intervaloAgradable(maximo),
                    getDrawingHorizontalLine: (_) => _lineaGuia(isDark),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    show: true,
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 38,
                        interval: _intervaloAgradable(maximo),
                        getTitlesWidget: (valor, meta) {
                          if (valor < 0) return const SizedBox.shrink();
                          return Text(_corto(valor), style: _estiloEje(isDark));
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (valor, meta) {
                          final i = valor.toInt();
                          if (i < 0 || i >= datos.length) {
                            return const SizedBox.shrink();
                          }
                          final dia = (datos[i]['day'] as String?) ?? '';
                          if (dia.length < 2) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(dia.substring(dia.length - 2),
                                style: _estiloEje(isDark)),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: datos
                          .asMap()
                          .entries
                          .map((e) => FlSpot(
                              e.key.toDouble(),
                              ((e.value['revenue'] as num?) ?? 0).toDouble()))
                          .toList(),
                      // Recta y no curva: con pocos puntos una curva inventa
                      // subidas y bajadas que los datos no tienen.
                      isCurved: false,
                      color: AppTheme.accentPurple,
                      barWidth: 2.5,
                      isStrokeCapRound: true,
                      // Los puntos SIEMPRE visibles. Con un único día no hay
                      // línea que trazar, y sin punto la tarjeta se veía vacía
                      // como si hubiera fallado la carga.
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppTheme.accentPurple.withValues(alpha: 0.13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
