import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:imagine_access/core/platform/file_download.dart';
import 'package:imagine_access/l10n/generated/app_localizations.dart';

final eventReportServiceProvider = Provider((ref) => EventReportService(ref));

// ──────────────────── Palette ────────────────────
const _kColors = [
  PdfColors.blue700,
  PdfColors.green700,
  PdfColors.orange700,
  PdfColors.purple700,
  PdfColors.red700,
  PdfColors.teal700,
  PdfColors.pink700,
  PdfColors.amber700,
  PdfColors.indigo700,
  PdfColors.cyan700,
];

PdfColor _palette(int i) => _kColors[i % _kColors.length];

// ──────────────────── Service ────────────────────
class EventReportService {
  EventReportService(Ref ref);
  SupabaseClient get _client => Supabase.instance.client;

  // ━━━━━━━━━ Public API ━━━━━━━━━
  Future<Uint8List> generatePdf(String eventId, String eventName, AppLocalizations l10n) async {
    final raw = await _client.rpc('export_event_full', params: {
      'p_event_id': eventId,
    });
    if (raw == null) throw Exception('export_event_full returned null');
    final data = Map<String, dynamic>.from(raw as Map);
    final eventInfo = Map<String, dynamic>.from(data['event'] ?? {});
    final tickets =
        List<Map<String, dynamic>>.from(data['tickets'] ?? []);
    final checkins =
        List<Map<String, dynamic>>.from(data['checkins'] ?? []);

    final pdf = pw.Document();
    final now = DateTime.now();
    final dateStr = _fmtDateFull(now.toIso8601String());
    final currency = eventInfo['currency']?.toString() ?? 'PYG';

    // ─── Data aggregation ───
    final nonVoid = tickets.where((t) => t['status'] != 'void').toList();
    final total = tickets.length;
    final valid = tickets.where((t) => t['status'] == 'valid').length;
    final used = tickets.where((t) => t['status'] == 'used').length;
    final voided = tickets.where((t) => t['status'] == 'void').length;
    final revenue = nonVoid.fold<double>(
        0, (s, t) => s + ((t['price'] as num?)?.toDouble() ?? 0));
    final scannedCount = tickets.where((t) => t['scanned_at'] != null).length;

    // Sales by RRPP
    final rrppMap = <String, _RrppStats>{};
    for (final t in tickets) {
      final name = t['created_by_name']?.toString() ?? l10n.reportSystem;
      final stat = rrppMap.putIfAbsent(name, () => _RrppStats(name));
      stat.count++;
      stat.revenue += (t['price'] as num?)?.toDouble() ?? 0;
      if (t['status'] != 'void') {
        stat.validCount++;
        stat.validRevenue += (t['price'] as num?)?.toDouble() ?? 0;
      }
      final cat = t['category']?.toString() ?? 'standard';
      stat.byCategory[cat] = (stat.byCategory[cat] ?? 0) + 1;
    }
    final rrppList = rrppMap.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    // Tickets by type (promo: count packs, not individual tickets)
    final typeMap = <String, int>{};
    final typeRevMap = <String, double>{};
    final seenPromoPackIds = <String>{};
    for (final t in nonVoid) {
      final tp = t['type']?.toString() ?? '?';
      final cat = t['category']?.toString() ?? 'standard';
      final packId = t['promo_pack_id']?.toString();

      // Revenue: always add (extra promo tickets have price=0)
      typeRevMap[tp] = (typeRevMap[tp] ?? 0) + ((t['price'] as num?)?.toDouble() ?? 0);

      if (cat == 'promo' && packId != null) {
        // Count only unique packs for promo type
        if (seenPromoPackIds.add(packId)) {
          typeMap[tp] = (typeMap[tp] ?? 0) + 1;
        }
      } else {
        typeMap[tp] = (typeMap[tp] ?? 0) + 1;
      }
    }

    // Tickets by day
    final dayMap = <String, Map<String, int>>{};
    for (final t in nonVoid) {
      final dt = _parseDate(t['created_at']);
      if (dt == null) continue;
      final dayKey =
          '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
      final tp = t['type']?.toString() ?? '?';
      dayMap.putIfAbsent(dayKey, () => {});
      dayMap[dayKey]![tp] = (dayMap[dayKey]![tp] ?? 0) + 1;
    }
    final sortedDays = dayMap.keys.toList()..sort();
    final allTypes = typeMap.keys.toList();

    // Checkins by hour
    final hourMap = <int, int>{};
    final allowedCheckins =
        checkins.where((c) => c['result'] == 'allowed').toList();
    for (final c in allowedCheckins) {
      final dt = _parseDate(c['scanned_at']);
      if (dt == null) continue;
      hourMap[dt.hour] = (hourMap[dt.hour] ?? 0) + 1;
    }
    final hourKeys = hourMap.keys.toList()..sort();

    // Checkins by operator
    final opMap = <String, int>{};
    for (final c in allowedCheckins) {
      final name = c['operator_name']?.toString() ?? l10n.reportUnknown;
      opMap[name] = (opMap[name] ?? 0) + 1;
    }
    final opList = opMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Category map (for RRPP breakdown)
    final catLabels = {
      'standard': l10n.reportCatSale,
      'guest': l10n.reportCatGuest,
      'staff': l10n.reportCatStaff,
      'invitation': l10n.reportCatInvitation,
      'promo': l10n.reportCatPromo,
    };

    // ━━━━━━━━━━━ PAGE 1: PORTADA + RESUMEN ━━━━━━━━━━━
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 40),
          pw.Center(
            child: pw.Text(l10n.reportFullTitle,
                style: pw.TextStyle(
                    fontSize: 22, fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900)),
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(eventInfo['name']?.toString() ?? eventName,
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue800)),
          ),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              [
                if (eventInfo['venue'] != null) eventInfo['venue'],
                if (eventInfo['city'] != null) eventInfo['city'],
                if (eventInfo['date'] != null)
                  _fmtDateFull(eventInfo['date'].toString()),
              ].join(' • '),
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(l10n.reportGenerated(dateStr),
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
          ),
          pw.SizedBox(height: 30),
          _sectionTitle(l10n.reportSummary),
          pw.SizedBox(height: 8),
          _summaryGrid([
            _KV(l10n.reportTotalTickets, '$total'),
            _KV(l10n.reportValid, '$valid'),
            _KV(l10n.reportUsedScanned, '$used'),
            _KV(l10n.reportVoided, '$voided'),
            _KV(l10n.reportConfirmedEntries, '$scannedCount'),
            _KV(l10n.reportCollected, '${_fmtNum(revenue)} $currency'),
          ]),
          pw.SizedBox(height: 20),
          _sectionTitle(l10n.reportDistByType),
          pw.SizedBox(height: 8),
          _buildTypeTable(allTypes, typeMap, typeRevMap, currency, l10n),
          pw.SizedBox(height: 20),
          _sectionTitle(l10n.reportChartTicketsByType),
          pw.SizedBox(height: 8),
          _buildHorizontalBar(
            allTypes.map((t) => t).toList(),
            allTypes.map((t) => (typeMap[t] ?? 0).toDouble()).toList(),
            allTypes.asMap().entries.map((e) => _palette(e.key)).toList(),
            maxWidth: 340,
            noDataLabel: l10n.reportNoData,
          ),
          pw.Spacer(),
          _footer('Imagine Access', l10n.reportPage(1)),
        ],
      ),
    ));

    // ━━━━━━━━━━━ PAGE 2: VENTAS POR RRPP ━━━━━━━━━━━
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pageHeader(eventInfo['name']?.toString() ?? eventName, dateStr),
          pw.SizedBox(height: 12),
          _sectionTitle(l10n.reportSalesByRrpp),
          pw.SizedBox(height: 8),
          _buildRrppTable(rrppList, currency, catLabels, l10n),
          pw.SizedBox(height: 20),
          _sectionTitle(l10n.reportChartRevenueByRrpp),
          pw.SizedBox(height: 8),
          _buildHorizontalBar(
            rrppList.map((r) => r.name).toList(),
            rrppList.map((r) => r.validRevenue).toList(),
            rrppList
                .asMap()
                .entries
                .map((e) => _palette(e.key))
                .toList(),
            maxWidth: 340,
            suffix: ' $currency',
            noDataLabel: l10n.reportNoData,
          ),
          pw.SizedBox(height: 20),
          _sectionTitle(l10n.reportChartTicketsByRrpp),
          pw.SizedBox(height: 8),
          _buildHorizontalBar(
            rrppList.map((r) => r.name).toList(),
            rrppList.map((r) => r.validCount.toDouble()).toList(),
            rrppList
                .asMap()
                .entries
                .map((e) => _palette(e.key))
                .toList(),
            maxWidth: 340,
            noDataLabel: l10n.reportNoData,
          ),
          pw.Spacer(),
          _footer('Imagine Access', l10n.reportPage(2)),
        ],
      ),
    ));

    // ━━━━━━━━━━━ PAGE 3: GRÁFICOS TEMPORALES ━━━━━━━━━━━
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pageHeader(eventInfo['name']?.toString() ?? eventName, dateStr),
          pw.SizedBox(height: 12),
          _sectionTitle(l10n.reportEmissionByDay),
          pw.SizedBox(height: 8),
          if (sortedDays.isNotEmpty)
            _buildStackedDayChart(sortedDays, dayMap, allTypes)
          else
            pw.Text(l10n.reportNoEmissionData,
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
          pw.SizedBox(height: 24),
          _sectionTitle(l10n.reportScansByHour),
          pw.SizedBox(height: 8),
          if (hourKeys.isNotEmpty)
            _buildHourChart(hourKeys, hourMap)
          else
            pw.Text(l10n.reportNoScanData,
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
          pw.SizedBox(height: 24),
          _sectionTitle(l10n.reportScansByOperator),
          pw.SizedBox(height: 8),
          if (opList.isNotEmpty)
            _buildHorizontalBar(
              opList.map((e) => e.key).toList(),
              opList.map((e) => e.value.toDouble()).toList(),
              opList.asMap().entries.map((e) => _palette(e.key)).toList(),
              maxWidth: 340,
              noDataLabel: l10n.reportNoData,
            )
          else
            pw.Text(l10n.reportNoOperatorData,
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
          pw.Spacer(),
          _footer('Imagine Access', l10n.reportPage(3)),
        ],
      ),
    ));

    // ━━━━━━━━━━━ PAGE 4+: DETALLE DE TICKETS ━━━━━━━━━━━
    final headers = ['#', l10n.reportHeaderName, 'Email', l10n.reportHeaderDoc, l10n.reportHeaderType, l10n.reportHeaderPrice, l10n.reportHeaderStatus, l10n.reportHeaderCreated, l10n.reportHeaderSeller];
    final dataRows = <List<String>>[];
    for (var i = 0; i < tickets.length; i++) {
      final t = tickets[i];
      dataRows.add([
        '${i + 1}',
        _str(t['buyer_name']),
        _str(t['buyer_email']),
        _str(t['buyer_doc']),
        _str(t['type']),
        _fmtNum((t['price'] as num?)?.toDouble() ?? 0),
        _statusLabel(t['status'], l10n),
        _fmtDateShort(t['created_at']),
        _str(t['created_by_name']),
      ]);
    }

    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(22),
      1: const pw.FlexColumnWidth(2),
      2: const pw.FlexColumnWidth(2.5),
      3: const pw.FlexColumnWidth(1.3),
      4: const pw.FlexColumnWidth(1.3),
      5: const pw.FixedColumnWidth(48),
      6: const pw.FixedColumnWidth(44),
      7: const pw.FixedColumnWidth(68),
      8: const pw.FlexColumnWidth(1.5),
    };

    const rowsPerPage = 30;
    final detailPages = (dataRows.length / rowsPerPage).ceil().clamp(1, 9999);

    for (var page = 0; page < detailPages; page++) {
      final start = page * rowsPerPage;
      final end = (start + rowsPerPage).clamp(0, dataRows.length);
      final pageRows = dataRows.sublist(start, end);
      final pageNum = 4 + page;

      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (page == 0) ...[
              _pageHeader(eventInfo['name']?.toString() ?? eventName, dateStr),
              pw.SizedBox(height: 6),
              _sectionTitle(l10n.reportDetailTitle),
              pw.SizedBox(height: 8),
            ],
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: pageRows,
              columnWidths: colWidths,
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              headerStyle: pw.TextStyle(
                  fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              headerAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 6.5),
              cellHeight: 16,
              cellAlignment: pw.Alignment.centerLeft,
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            ),
            pw.Spacer(),
            _footer('Imagine Access', l10n.reportPage(pageNum)),
          ],
        ),
      ));
    }

    return pdf.save();
  }

  Future<void> exportAndShare(
      String eventId, String eventName, AppLocalizations l10n) async {
    final bytes = await generatePdf(eventId, eventName, l10n);
    final fileName =
        'reporte_${_sanitize(eventName)}_${DateTime.now().millisecondsSinceEpoch}.pdf';

    downloadBytes(bytes, fileName, mimeType: 'application/pdf');
  }

  // ━━━━━━━━━ PDF Building blocks ━━━━━━━━━

  static pw.Widget _pageHeader(String name, String dateStr) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(name,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold,
                color: PdfColors.blueGrey800)),
        pw.Text(dateStr,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ],
    );
  }

  static pw.Widget _sectionTitle(String text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: const pw.BoxDecoration(
        color: PdfColors.blueGrey800,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
    );
  }

  static pw.Widget _summaryGrid(List<_KV> items) {
    final rows = <pw.Widget>[];
    for (var i = 0; i < items.length; i += 3) {
      final cols = <pw.Widget>[];
      for (var j = i; j < i + 3 && j < items.length; j++) {
        cols.add(pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            margin: const pw.EdgeInsets.all(2),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(items[j].value,
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text(items[j].key,
                    style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
              ],
            ),
          ),
        ));
      }
      rows.add(pw.Row(children: cols));
    }
    return pw.Column(children: rows);
  }

  static pw.Widget _buildTypeTable(
      List<String> types, Map<String, int> countMap, Map<String, double> revMap, String cur, AppLocalizations l10n) {
    return pw.TableHelper.fromTextArray(
      headers: [l10n.reportHeaderType, l10n.reportHeaderQuantity, l10n.reportHeaderPercent, '${l10n.reportHeaderRevenue} ($cur)'],
      data: types.map((t) {
        final cnt = countMap[t] ?? 0;
        final total = countMap.values.fold<int>(0, (s, v) => s + v);
        final pct = total > 0 ? (cnt / total * 100).toStringAsFixed(1) : '0';
        return [t, '$cnt', '$pct%', _fmtNum(revMap[t] ?? 0)];
      }).toList(),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellHeight: 20,
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
    );
  }

  static pw.Widget _buildRrppTable(
      List<_RrppStats> list, String cur, Map<String, String> catLabels, AppLocalizations l10n) {
    final headers = [l10n.reportHeaderRrpp, l10n.reportHeaderTotal, l10n.reportHeaderValidCount, '${l10n.reportHeaderRevenue} ($cur)', ...catLabels.values];
    final data = list.map((r) {
      return [
        r.name,
        '${r.count}',
        '${r.validCount}',
        _fmtNum(r.validRevenue),
        ...catLabels.keys.map((k) => '${r.byCategory[k] ?? 0}'),
      ];
    }).toList();

    // Totals row
    final totals = [
      l10n.reportHeaderTotal,
      '${list.fold<int>(0, (s, r) => s + r.count)}',
      '${list.fold<int>(0, (s, r) => s + r.validCount)}',
      _fmtNum(list.fold<double>(0, (s, r) => s + r.validRevenue)),
      ...catLabels.keys.map((k) =>
          '${list.fold<int>(0, (s, r) => s + (r.byCategory[k] ?? 0))}'),
    ];
    data.add(totals);

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellHeight: 18,
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
    );
  }

  // Horizontal bar chart (labels on left, bars on right)
  static pw.Widget _buildHorizontalBar(
    List<String> labels,
    List<double> values,
    List<PdfColor> colors, {
    double maxWidth = 300,
    String suffix = '',
    String noDataLabel = '',
  }) {
    if (values.isEmpty) {
      return pw.Text(noDataLabel, style: const pw.TextStyle(fontSize: 8));
    }
    final maxVal = values.reduce(max);
    if (maxVal == 0) {
      return pw.Text(noDataLabel, style: const pw.TextStyle(fontSize: 8));
    }
    return pw.Column(
      children: List.generate(labels.length, (i) {
        final barW = (values[i] / maxVal) * maxWidth;
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [
            pw.SizedBox(
              width: 90,
              child: pw.Text(labels[i],
                  style: const pw.TextStyle(fontSize: 7),
                  maxLines: 1),
            ),
            pw.Container(
              width: barW.clamp(2, maxWidth),
              height: 12,
              decoration: pw.BoxDecoration(
                color: colors[i],
                borderRadius: pw.BorderRadius.circular(2),
              ),
            ),
            pw.SizedBox(width: 4),
            pw.Text(
              '${_fmtNum(values[i])}$suffix',
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            ),
          ]),
        );
      }),
    );
  }

  // Stacked day chart: for each day show bars per type side by side
  static pw.Widget _buildStackedDayChart(
    List<String> days,
    Map<String, Map<String, int>> dayMap,
    List<String> types,
  ) {
    final maxPerDay = dayMap.values.map((m) => m.values.fold<int>(0, (s, v) => s + v)).reduce(max);
    const barMaxH = 120.0;
    final dayW = (400 / days.length).clamp(30.0, 70.0);

    return pw.Column(children: [
      // Legend
      pw.Row(
        children: types.asMap().entries.map((e) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(right: 12),
            child: pw.Row(children: [
              pw.Container(width: 8, height: 8, color: _palette(e.key)),
              pw.SizedBox(width: 3),
              pw.Text(e.value, style: const pw.TextStyle(fontSize: 7)),
            ]),
          );
        }).toList(),
      ),
      pw.SizedBox(height: 6),
      // Bars
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        mainAxisAlignment: pw.MainAxisAlignment.start,
        children: days.map((day) {
          final m = dayMap[day] ?? {};
          final dayTotal = m.values.fold<int>(0, (s, v) => s + v);
          return pw.SizedBox(
            width: dayW,
            child: pw.Column(children: [
              pw.Text('$dayTotal',
                  style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              ...types.asMap().entries.map((e) {
                final cnt = m[e.value] ?? 0;
                final h = maxPerDay > 0 ? (cnt / maxPerDay) * barMaxH : 0.0;
                return pw.Container(
                  width: dayW * 0.6,
                  height: h > 0 ? h.clamp(2, barMaxH) : 0,
                  margin: const pw.EdgeInsets.symmetric(vertical: 0.5),
                  decoration: pw.BoxDecoration(
                    color: _palette(e.key),
                    borderRadius: pw.BorderRadius.circular(1),
                  ),
                );
              }),
              pw.SizedBox(height: 3),
              pw.Text(day, style: const pw.TextStyle(fontSize: 6)),
            ]),
          );
        }).toList(),
      ),
    ]);
  }

  // Hour chart (bar for each hour)
  static pw.Widget _buildHourChart(List<int> hours, Map<int, int> hourMap) {
    final maxV = hourMap.values.reduce(max);
    const barMaxH = 110.0;
    // Fill all hours between min and max
    final minH = hours.first;
    final maxH = hours.last;
    final allHours = List.generate(maxH - minH + 1, (i) => minH + i);
    final hourW = (420 / allHours.length).clamp(18.0, 40.0);

    return pw.Column(children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        mainAxisAlignment: pw.MainAxisAlignment.start,
        children: allHours.map((h) {
          final cnt = hourMap[h] ?? 0;
          final barH = maxV > 0 ? (cnt / maxV) * barMaxH : 0.0;
          return pw.SizedBox(
            width: hourW,
            child: pw.Column(children: [
              if (cnt > 0)
                pw.Text('$cnt',
                    style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold))
              else
                pw.SizedBox(height: 8),
              pw.SizedBox(height: 2),
              pw.Container(
                width: hourW * 0.55,
                height: barH > 0 ? barH.clamp(2, barMaxH) : 1,
                decoration: pw.BoxDecoration(
                  color: cnt > 0 ? PdfColors.teal600 : PdfColors.grey300,
                  borderRadius: pw.BorderRadius.circular(1),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text('${h.toString().padLeft(2, '0')}h',
                  style: const pw.TextStyle(fontSize: 6)),
            ]),
          );
        }).toList(),
      ),
    ]);
  }

  static pw.Widget _footer(String brand, String pageLabel) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(brand,
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
        pw.Text(pageLabel,
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
      ],
    );
  }

  // ━━━━━━━━━ Helpers ━━━━━━━━━
  static String _str(dynamic val) => val?.toString() ?? '';

  static String _statusLabel(dynamic val, AppLocalizations l10n) {
    switch (val?.toString()) {
      case 'valid': return l10n.reportStatusValid;
      case 'used': return l10n.reportStatusUsed;
      case 'void': return l10n.reportStatusVoid;
      default: return val?.toString() ?? '';
    }
  }

  static DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    try {
      return DateTime.parse(val.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  static String _fmtDateShort(dynamic val) {
    final dt = _parseDate(val);
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static String _fmtDateFull(dynamic val) {
    final dt = _parseDate(val);
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static String _fmtNum(double v) {
    final intPart = v.truncate();
    final s = intPart.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _sanitize(String name) {
    return name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_').toLowerCase();
  }
}

// ──────────────────── Data classes ────────────────────
class _KV {
  final String key, value;
  const _KV(this.key, this.value);
}

class _RrppStats {
  final String name;
  int count = 0;
  int validCount = 0;
  double revenue = 0;
  double validRevenue = 0;
  Map<String, int> byCategory = {};
  _RrppStats(this.name);
}
