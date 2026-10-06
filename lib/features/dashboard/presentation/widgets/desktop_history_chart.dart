import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/dashboard_summary.dart';
import 'history_tooltip_chart.dart';

/// Five ticks, computed in integer cents so even one-cent totals have a scale.
int historyAxisStep(int maximum) {
  if (maximum <= 0) return 100;
  final desired = (maximum + 3) ~/ 4;
  var magnitude = 1;
  while (magnitude * 10 <= desired) {
    magnitude *= 10;
  }
  for (final multiple in [1, 2, 5, 10]) {
    if (multiple * magnitude >= desired) return multiple * magnitude;
  }
  return magnitude * 10;
}

String historyAxisLabel(int minor) {
  for (final unit in [
    (100000000000, 'bi'),
    (100000000, 'mi'),
    (100000, 'mil')
  ]) {
    if (minor >= unit.$1) {
      final value = minor / unit.$1;
      return '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2).replaceAll('.', ',')} ${unit.$2}';
    }
  }
  return (minor / 100)
      .toStringAsFixed(minor % 100 == 0 ? 0 : 2)
      .replaceAll('.', ',');
}

class DesktopHistoryChart extends StatelessWidget {
  const DesktopHistoryChart({super.key, required this.currency});
  final DashboardCurrencySummary currency;
  static const months = [
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez'
  ];

  @override
  Widget build(BuildContext context) {
    final maximum = currency.history.fold<int>(
        0,
        (value, item) =>
            math.max(value, math.max(item.incomeMinor, item.expenseMinor)));
    final step = historyAxisStep(maximum), ceiling = step * 4;
    final scaler = MediaQuery.textScalerOf(context);
    final style = Theme.of(context)
        .textTheme
        .bodySmall!
        .copyWith(fontSize: 11, height: 1.2, color: SomiaColors.muted);
    final labels = [for (var i = 4; i >= 0; i--) historyAxisLabel(step * i)];
    final measures = [
      for (final label in [...labels, currency.currencyCode])
        TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler)
          ..layout()
    ];
    final axisWidth =
        measures.fold<double>(0, (v, p) => math.max(v, p.width)) + 8;
    final labelHeight = measures.first.height;
    for (final painter in measures) {
      painter.dispose();
    }
    final plotHeight = math.max(160.0, labelHeight * 8);
    final footer = labelHeight + 8;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(currency.currencyCode, style: style),
      const SizedBox(height: 6),
      LayoutBuilder(builder: (context, box) {
        final plotWidth = math.max(box.maxWidth - axisWidth - 8,
            currency.history.length * math.max(38.0, scaler.scale(32)));
        return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
                width: axisWidth + 8 + plotWidth,
                height: plotHeight + footer + labelHeight,
                child: Padding(
                    padding: EdgeInsets.only(
                        top: labelHeight / 2, bottom: labelHeight / 2),
                    child: Row(children: [
                      SizedBox(
                          width: axisWidth,
                          child: Stack(clipBehavior: Clip.none, children: [
                            for (var i = 0; i < 5; i++)
                              Positioned(
                                  top: plotHeight * i / 4 - labelHeight / 2,
                                  right: 0,
                                  child: Text(labels[i],
                                      key: ValueKey(
                                          'history-axis-${step * (4 - i)}'),
                                      style: style))
                          ])),
                      const SizedBox(width: 8),
                      Expanded(
                          child: HistoryTooltipChart(
                              history: currency.history,
                              currencyCode: currency.currencyCode,
                              builder: (target) => Stack(children: [
                                    for (var i = 0; i < 5; i++)
                                      Positioned(
                                          top: plotHeight * i / 4,
                                          left: 0,
                                          right: 0,
                                          child: Container(
                                              key: ValueKey(
                                                  'history-grid-${step * (4 - i)}'),
                                              height: 1,
                                              color: SomiaColors.outline)),
                                    Row(children: [
                                      for (final item in currency.history)
                                        Expanded(
                                            child: target(
                                                item,
                                                ExcludeSemantics(
                                                    child: Column(children: [
                                                  SizedBox(
                                                      height: plotHeight,
                                                      child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      4),
                                                          child: Row(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .end,
                                                              children: [
                                                                for (final entry
                                                                    in [
                                                                  (
                                                                    'income',
                                                                    item.incomeMinor,
                                                                    SomiaColors
                                                                        .green
                                                                  ),
                                                                  (
                                                                    'expense',
                                                                    item.expenseMinor,
                                                                    SomiaColors
                                                                        .red
                                                                  )
                                                                ]) ...[
                                                                  Expanded(
                                                                      child: Align(
                                                                          alignment: Alignment
                                                                              .bottomCenter,
                                                                          child: Container(
                                                                              key: ValueKey('history-bar-${entry.$1}-${item.month.month}'),
                                                                              height: plotHeight * (entry.$2 / ceiling).clamp(0.0, 1.0),
                                                                              decoration: BoxDecoration(color: entry.$3, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))))),
                                                                  if (entry
                                                                          .$1 ==
                                                                      'income')
                                                                    const SizedBox(
                                                                        width:
                                                                            3)
                                                                ]
                                                              ]))),
                                                  SizedBox(
                                                      height: footer,
                                                      child: Align(
                                                          alignment: Alignment
                                                              .bottomCenter,
                                                          child: Text(
                                                              months[item.month
                                                                      .month -
                                                                  1],
                                                              style: style)))
                                                ]))))
                                    ])
                                  ])))
                    ]))));
      })
    ]);
  }
}
