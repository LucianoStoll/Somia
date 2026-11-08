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
      final sideBySide = box.maxWidth >= 600 && scaler.scale(12) <= 16;
      final small = box.maxWidth < 500;
      final diameter = sideBySide
          ? (box.maxWidth * .34).clamp(104.0, 200.0)
          : math.min(260.0, box.maxWidth);
      final fontSize = 14.0;
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
…5184 tokens truncated…ortMonths[
                                                  item.month.month - 1],
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: SomiaColors.muted,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        const Wrap(
          alignment: WrapAlignment.center,
          spacing: 18,
          runSpacing: 6,
          children: [
            _Legend('Receitas', SomiaColors.green),
            _Legend('Despesas', SomiaColors.red),
          ],
        ),
      ],
    );
  }

  Widget _bar(int value, int ceiling, Color color) => Expanded(
        child: value <= 0
            ? const SizedBox()
            : FractionallySizedBox(
                heightFactor: (value / ceiling).clamp(0.01, 1.0),
                alignment: Alignment.bottomCenter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ),
              ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 4, backgroundColor: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: SomiaColors.muted),
          ),
        ],
      );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SomiaColors.outline
      ..strokeWidth = 0.6;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

class _RecentPanel extends StatelessWidget {
  const _RecentPanel({required this.recent});
  final List<DashboardActivity> recent;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Últimos cadastrados',
        action: TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(48, 36),
          ),
          onPressed: () => context.goNamed(AppRoutes.transactions),
          child: const Text('Ver todas', style: TextStyle(fontSize: 11)),
        ),
        child: Column(
          key: const ValueKey('mobile-recent'),
          children: [
            if (recent.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Nenhuma movimentação ainda.'),
              ),
            for (var i = 0; i < recent.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _RecentTile(item: recent[i]),
            ],
          ],
        ),
      );
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.item});
  final DashboardActivity item;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (item.type) {
      DashboardActivityType.income => (
          SomiaColors.green,
          Icons.work_outline_rounded,
        ),
      DashboardActivityType.expense => (
          SomiaColors.red,
          Icons.shopping_cart_outlined,
        ),
      DashboardActivityType.transfer => (
          SomiaColors.blue,
          Icons.swap_horiz,
        ),
    };
    return InkWell(
      onTap: () => showRecentActivityDetails(context, item),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.date.day.toString().padLeft(2, '0')}/${item.date.month.toString().padLeft(2, '0')} · ${item.accountLabel}${item.isEffective ? '' : ' · Pendente'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: SomiaColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${item.type == DashboardActivityType.income ? '+ ' : item.type == DashboardActivityType.expense ? '- ' : ''}${_money(item.amountMinor, item.currencyCode)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.chevron_right, size: 16, color: SomiaColors.muted),
          ],
        ),
      ),
    );
  }
}
