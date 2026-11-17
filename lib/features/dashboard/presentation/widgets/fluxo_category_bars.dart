import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../accounts/domain/money_minor.dart';
import '../../domain/entities/dashboard_summary.dart';

String _money(int minor, String code) => MoneyMinor.display(minor, code)
    .replaceAllMapped(RegExp(r'\d{1,3}(?=(\d{3})+,)'), (m) => '${m[0]}.');

/// Gastos por categoria na direção Fluxo: total, barra empilhada e legenda.
class FluxoCategoryBars extends StatelessWidget {
  const FluxoCategoryBars({super.key, required this.currency});
  final DashboardCurrencySummary currency;

  @override
  Widget build(BuildContext context) {
    final t = context.somia;
    final sorted = [...currency.expensesByCategory]
      ..removeWhere((c) => c.amountMinor <= 0)
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    final total = sorted.fold<int>(0, (sum, c) => sum + c.amountMinor);
    if (total == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SomiaSpace.md),
        child: Text('Nenhuma despesa neste mês.',
            style: TextStyle(color: t.muted)),
      );
    }
    final items = <(String, int)>[
      for (final c in sorted.take(6)) (c.name, c.amountMinor),
      if (sorted.length > 6)
        ('Outras', sorted.skip(6).fold<int>(0, (s, c) => s + c.amountMinor)),
    ];
    Color color(int i) => t.categories[i % t.categories.length];
    String pct(int value) => '${(value * 100 / total).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Total de despesas',
                  style: TextStyle(color: t.muted, fontSize: 13)),
            ),
            const SizedBox(width: SomiaSpace.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(_money(total, currency.currencyCode),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
        const SizedBox(height: SomiaSpace.md),
        Semantics(
          label: [
            for (final (name, value) in items) '$name ${pct(value)}',
          ].join(', '),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    flex: (items[i].$2 * 1000 / total).round().clamp(1, 1000),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color(i),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth < 260 ? 1 : 2;
            final width = (box.maxWidth - (columns - 1) * 16) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 10,
              children: [
                for (var i = 0; i < items.length; i++)
                  SizedBox(
                    width: width,
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: color(i), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: SomiaSpace.sm),
                        Expanded(
                          child: Text(items[i].$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14)),
                        ),
                        Text(pct(items[i].$2),
                            style: TextStyle(color: t.muted, fontSize: 14)),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: SomiaSpace.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => context.go(AppRoutes.analysisPath),
            child: const Text('Abrir a análise completa de despesas'),
          ),
        ),
      ],
    );
  }
}
