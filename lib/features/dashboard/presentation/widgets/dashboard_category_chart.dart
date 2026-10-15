import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routing/app_router.dart';
import '../../../accounts/domain/money_minor.dart';
import '../../domain/entities/dashboard_summary.dart';
import 'dashboard_palette.dart';

const _colors = [
  Color(0xFFA5CDE2),
  SomiaColors.red,
  Color(0xFFF0C895),
  SomiaColors.purple
];

String _money(int value, String code) => MoneyMinor.display(value, code)
    .replaceAllMapped(RegExp(r'\d{1,3}(?=(\d{3})+,)'), (m) => '${m[0]}.');

class DashboardCategoryChart extends StatelessWidget {
  const DashboardCategoryChart({super.key, required this.currency});
  final DashboardCurrencySummary currency;
  @override
  Widget build(BuildContext context) {
    final sorted = currency.expensesByCategory
        .where((c) => c.amountMinor > 0)
        .toList()
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    final total = sorted.fold<int>(0, (sum, c) => sum + c.amountMinor);
    final items = sorted.length <= 4
        ? sorted
        : [
            ...sorted.take(3),
            DashboardCategoryExpense('Outras',
                sorted.skip(3).fold<int>(0, (sum, c) => sum + c.amountMinor))
          ];
    if (total == 0) {
      return const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Nenhuma despesa neste mês.'));
    }
    return LayoutBuilder(builder: (context, box) {
      final scaler = MediaQuery.textScalerOf(context);
      final sideBySide = box.maxWidth >= 300 && scaler.scale(12) <= 16;
      final small = box.maxWidth < 500;
      final diameter =
          sideBySide ? (box.maxWidth * .34).clamp(104.0, 200.0) : 180.0;
      final fontSize = small && sideBySide ? 10.0 : 14.0;
      final style =
          Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: fontSize);
      double measure(String text) => (TextPainter(
              text: TextSpan(text: text, style: style),
              textScaler: scaler,
              textDirection: Directionality.of(context))
            ..layout())
          .width;
      final amountWidth = items
              .map((e) => measure(_money(e.amountMinor, currency.currencyCode)))
              .reduce(math.max) +
          2;
      final percentWidth = measure('100%') + 2;
      final legend = LayoutBuilder(builder: (context, available) {
        final stacked = available.maxWidth <
            amountWidth + percentWidth + scaler.scale(fontSize) * 5 + 24;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++)
                Padding(
                    padding: EdgeInsets.symmetric(
                        vertical: small && sideBySide ? 8 : 10),
                    child: Semantics(
                        label:
                            '${items[i].name}, ${(items[i].amountMinor * 100 / total).round()}%, ${_money(items[i].amountMinor, currency.currencyCode)}',
                        child: ExcludeSemantics(
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                              Container(
                                  width: small ? 8 : 12,
                                  height: small ? 8 : 12,
                                  decoration: BoxDecoration(
                                      color: _colors[i],
                                      shape: BoxShape.circle)),
                              SizedBox(width: small ? 6 : 10),
                              if (stacked)
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(items[i].name, style: style),
                                      Wrap(
                                          spacing: 12,
                                          runSpacing: 4,
                                          children: [
                                            Text(
                                                '${(items[i].amountMinor * 100 / total).round()}%',
                                                style: style.copyWith(
                                                    color: SomiaColors.muted)),
                                            Text(
                                                _money(items[i].amountMinor,
                                                    currency.currencyCode),
                                                style: style),
                                          ]),
                                    ]))
                              else ...[
                                Expanded(
                                    child: Text(items[i].name, style: style)),
                                const SizedBox(width: 4),
                                SizedBox(
                                    width: percentWidth,
                                    child: Text(
                                        '${(items[i].amountMinor * 100 / total).round()}%',
                                        textAlign: TextAlign.right,
                                        style: style.copyWith(
                                            color: SomiaColors.muted))),
                                SizedBox(width: small ? 6 : 20),
                                SizedBox(
                                    width: amountWidth,
                                    child: Text(
                                        _money(items[i].amountMinor,
                                            currency.currencyCode),
                                        textAlign: TextAlign.right,
                                        style: style)),
                              ],
                            ]))))
            ]);
      });
      final chart = Semantics(
          label: 'Total de despesas: ${_money(total, currency.currencyCode)}',
          child: ExcludeSemantics(
              child: SizedBox(
                  width: diameter,
                  height: diameter,
                  child: CustomPaint(
                      painter: _DonutPainter(items, total),
                      child: Center(
                          child: SizedBox(
                              width: diameter * .61,
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('Despesas',
                                        style: TextStyle(
                                            color: SomiaColors.muted,
                                            fontSize:
                                                small && sideBySide ? 10 : 12)),
                                    const SizedBox(height: 4),
                                    FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                            _money(
                                                total, currency.currencyCode),
                                            style: TextStyle(
                                                fontSize: small && sideBySide
                                                    ? 12
                                                    : 17,
                                                fontWeight: FontWeight.w600))),
                                  ])))))));
      return Tooltip(
          message:
              'Inclui efetivados e previstos. Toque para abrir a análise de despesas.',
          child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.go(AppRoutes.analysisPath),
              child: sideBySide
                  ? Row(children: [
                      chart,
                      SizedBox(width: small ? 14 : 30),
                      Expanded(child: legend)
                    ])
                  : Column(
                      children: [chart, const SizedBox(height: 16), legend])));
    });
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.items, this.total);
  final List<DashboardCategoryExpense> items;
  final int total;
  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final stroke = size.width * .17;
    final rect = Rect.fromLTWH(stroke / 2 + 1, stroke / 2 + 1,
        size.width - stroke - 2, size.height - stroke - 2);
    var start = -math.pi / 2;
    for (var i = 0; i < items.length; i++) {
      final angle = items[i].amountMinor / total * math.pi * 2;
      final gap = items.length == 1 ? 0.0 : math.min(.009, angle * .1);
      canvas.drawArc(
          rect,
          start + gap / 2,
          angle - gap,
          false,
          Paint()
            ..color = _colors[i]
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke);
      start += angle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.items != items || old.total != total;
}
