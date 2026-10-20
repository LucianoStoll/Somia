import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/module_surface.dart';
import '../../../core/widgets/month_selector.dart';
import '../../accounts/domain/money_minor.dart';
import '../domain/planning.dart';

class PlanningEntriesSheet extends StatefulWidget {
  const PlanningEntriesSheet({
    super.key,
    required this.title,
    required this.month,
    required this.currency,
    required this.type,
    required this.load,
  });
  final String title, currency, type;
  final DateTime month;
  final Future<List<PlanningEntry>> Function() load;
  @override
  State<PlanningEntriesSheet> createState() => _PlanningEntriesSheetState();
}

class _PlanningEntriesSheetState extends State<PlanningEntriesSheet> {
  late Future<List<PlanningEntry>> future = widget.load();
  String money(int value) => MoneyMinor.display(value, widget.currency)
      .replaceAllMapped(RegExp(r'\d{1,3}(?=(\d{3})+,)'), (m) => '${m[0]}.');
  String date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      key: const ValueKey('planning-entries'),
      padding: const EdgeInsets.all(20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
                '${widget.type == 'income' ? 'Receitas' : 'Despesas'} · '
                '${monthNames[widget.month.month - 1]} ${widget.month.year}',
                style: const TextStyle(color: SomiaColors.muted)),
            const SizedBox(height: 12),
            FutureBuilder<List<PlanningEntry>>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()));
                  }
                  if (snapshot.hasError) {
                    return Column(children: [
                      const Text('Não foi possível carregar os lançamentos.'),
                      TextButton(
                          onPressed: () {
                            final retry = widget.load();
                            setState(() {
                              future = retry;
                            });
                          },
                          child: const Text('Tentar novamente')),
                    ]);
                  }
                  final items = snapshot.data ?? const <PlanningEntry>[];
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ModuleValueRow(
                            label: 'Total dos lançamentos',
                            value: money(items.fold<int>(
                                0, (sum, e) => sum + e.amount))),
                        const Divider(),
                        if (items.isEmpty)
                          const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Text('Nenhum lançamento neste mês.')),
                        for (final item in items)
                          Padding(
                              key: ValueKey(
                                  'planning-entry-${item.isCard}-${item.id}'),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                              item.isCard
                                                  ? Icons.credit_card_outlined
                                                  : Icons
                                                      .account_balance_wallet_outlined,
                                              size: 18,
                                              color: SomiaColors.muted),
                                          const SizedBox(width: 8),
                                          Expanded(
                                              child: Text(item.description,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600))),
                                        ]),
                                    const SizedBox(height: 4),
                                    Text('${item.source} · ${date(item.date)}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: SomiaColors.muted)),
                                    const SizedBox(height: 4),
                                    Text(money(item.amount),
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: item.amount < 0
                                                ? SomiaColors.green
                                                : widget.type == 'income'
                                                    ? SomiaColors.green
                                                    : SomiaColors.red)),
                                    if (item.amount != item.fullAmount)
                                      Text(
                                          'Parte nesta subcategoria · lançamento total ${money(item.fullAmount)}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: SomiaColors.muted)),
                                  ])),
                      ]);
                }),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar')),
          ]));
}
