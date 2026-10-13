import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routing/app_router.dart';
import '../../../accounts/domain/money_minor.dart';
import '../../domain/entities/dashboard_summary.dart';
import 'dashboard_palette.dart';

const _colors = [
  SomiaColors.blue,
  SomiaColors.red,
  SomiaColors.yellow,
  SomiaColors.purple,
  SomiaColors.green
];

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
    final items = sorted.length <= 5
        ? sorted
        : [
            ...sorted.take(4),
            DashboardCategoryExpense('Outras',
                sorted.skip(4).fold<int>(0, (sum, c) => sum + c.amountMinor))
          ];
    final legend =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < items.length; i++)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: CircleAvatar(radius: 5, backgroundColor: _colors[i])),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(items[i].name),
                    Text(
                        '${MoneyMinor.display(items[i].amountMinor, currency.currencyCode)} · ${(items[i].amountMinor * 100 / math.max(1, total)).toStringAsFixed(1).replaceAll('.', ',')}%',
                        style: const TextStyle(
                            color: SomiaColors.muted, fontSize: 12))
                  ]))
            ]))
    ]);
    final chart = Semantics(
        label:
            'Total de despesas: ${MoneyMinor.display(total, currency.currencyCode)}',
        child: SizedBox(
            width: 190,
            height: 190,
            child: CustomPaint(
                painter: _DonutPainter(items, total),
                child: Center(
                    child: SizedBox(
                        width: 126,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('Despesas',
                              style: TextStyle(
                                  color: SomiaColors.muted, fontSize: 12)),
                          const SizedBox(height: 4),
                          FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                  MoneyMinor.display(
                                      total, currency.currencyCode),
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)))
                        ]))))));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Inclui efetivados e previstos',
          style: TextStyle(color: SomiaColors.muted, fontSize: 12)),
      const SizedBox(height: 16),
      if (total == 0)
        const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Nenhuma despesa neste mês.'))
      else
        LayoutBuilder(
            builder: (context, box) => box.maxWidth >= 450 &&
                    MediaQuery.textScalerOf(context).scale(16) < 24
                ? Row(children: [
                    chart,
                    const SizedBox(width: 24),
                    Expanded(child: legend)
                  ])
                : Column(
                    children: [chart, const SizedBox(height: 12), legend])),
      Align(
          alignment: Alignment.centerRight,
          child: TextButton(
              onPressed: () => context.go(AppRoutes.analysisPath),
              child: const Text('Ver todas'))),
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.items, this.total);
  final List<DashboardCategoryExpense> items;
  final int total;
  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final rect = Rect.fromLTWH(12, 12, size.width - 24, size.height - 24);
    var start = -math.pi / 2;
    for (var i = 0; i < items.length; i++) {
      final angle = items[i].amountMinor / total * math.pi * 2;
      final gap = items.length == 1 ? 0.0 : math.min(.035, angle * .2);
      canvas.drawArc(
          rect,
          start + gap / 2,
          angle - gap,
          false,
          Paint()
            ..color = _colors[i]
            ..style = PaintingStyle.stroke
            ..strokeWidth = 20);
      start += angle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.items != items || old.total != total;
}
