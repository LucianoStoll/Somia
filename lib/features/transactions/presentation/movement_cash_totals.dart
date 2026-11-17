import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../accounts/domain/money_minor.dart';
import '../../balances/domain/monthly_cash_flow.dart';

class MovementCashTotals extends StatelessWidget {
  const MovementCashTotals({super.key, required this.totals});
  final Map<String, MonthlyCashFlow> totals;
  @override
  Widget build(BuildContext context) {
    final codes = totals.keys.toList()..sort();
    if (codes.isEmpty) codes.add('BRL');
    Widget column(String title, bool paid) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(color: SomiaColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          for (final code in codes)
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                    MoneyMinor.display(
                            paid
                                ? totals[code]?.paidMinor ?? 0
                                : totals[code]?.incomeMinor ?? 0,
                            code)
                        .replaceAllMapped(
                            RegExp(r'\d{1,3}(?=(\d{3})+,)'), (m) => '${m[0]}.'),
                    style: TextStyle(
                        color: paid ? SomiaColors.red : SomiaColors.green,
                        fontSize: 20,
                        fontWeight: FontWeight.w700))),
        ]);
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Card(
            key: const ValueKey('movements-cash-totals'),
            child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Totais do mês · mesmas contas do Resumo',
                          style: TextStyle(
                              color: SomiaColors.muted, fontSize: 11)),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                          builder: (context, box) => box.maxWidth < 270 ||
                                  MediaQuery.textScalerOf(context).scale(16) >
                                      22
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                      column('Recebido no mês', false),
                                      const SizedBox(height: 12),
                                      column('Pago no mês', true)
                                    ])
                              : Row(children: [
                                  Expanded(
                                      child: column('Recebido no mês', false)),
                                  const SizedBox(
                                      height: 50, child: VerticalDivider()),
                                  Expanded(child: column('Pago no mês', true))
                                ])),
                    ]))));
  }
}
