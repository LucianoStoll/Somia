import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../accounts/domain/money_minor.dart';
import '../../../cards/data/cards_repository.dart';
import '../../../transactions/domain/transactions_repository.dart';
import '../../../transactions/domain/financial_transaction.dart';
import '../../../transfers/domain/transfers_repository.dart';
import '../../domain/entities/dashboard_summary.dart';

Future<void> showRecentActivityDetails(
  BuildContext context,
  DashboardActivity activity,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RecentActivityDetails(activity: activity),
    );

/// Reads the selected record without applying the dashboard's month filter.
class RecentActivityDetails extends StatefulWidget {
  const RecentActivityDetails({super.key, required this.activity});
  final DashboardActivity activity;

  @override
  State<RecentActivityDetails> createState() => _RecentActivityDetailsState();
}

class _RecentActivityDetailsState extends State<RecentActivityDetails> {
  late Future<_Details?> _future = _load();

  String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  String _status(bool effective, DateTime? effectiveDate) => effective
      ? 'Efetivado'
      : effectiveDate == null
          ? 'Previsto'
          : 'Agendado';

  Future<_Details?> _load() async {
    final activity = widget.activity;
    if (activity.cardId != null) {
      final repository = getIt<CardsRepository>();
      final entries = await repository.entries(
        cardId: activity.cardId,
      );
      final item = entries.where((e) => e.id == activity.id).firstOrNull;
      if (item == null) return null;
      final cards = await repository.list();
      final card = cards.where((e) => e.id == item.cardId).firstOrNull;
      return _Details(
        item.description,
        MoneyMinor.display(item.amountMinor, 'BRL'),
        [
          'Compra no cartão · ${item.label}',
          if (card != null) card.name,
          if (item.categoryName != null) item.categoryName!,
          'Compra: ${_date(item.postedAt)}',
          'Vencimento da fatura: ${_date(item.dueAt)}',
          if (item.allocations.isNotEmpty)
            'Rateio · ${item.allocations.length} categorias',
          if (item.establishment.isNotEmpty) 'Local: ${item.establishment}',
          ...item.tags.map((tag) => '#$tag'),
        ],
        Uri(
          path: '/cards',
          queryParameters: {
            'card': item.cardId,
            'month': item.invoiceMonth.toIso8601String(),
            'view': 'statement',
          },
        ).toString(),
        'Ver extrato do cartão',
      );
    }
    if (activity.type == DashboardActivityType.transfer) {
      final items = await getIt<TransfersRepository>().list();
      final item = items.where((e) => e.id == activity.id).firstOrNull;
      if (item == null) return null;
      return _Details(
        item.description,
        MoneyMinor.display(item.amountMinor, item.currencyCode),
        [
          '${item.sourceAccountName} → ${item.destinationAccountName}',
          _status(item.isEffective, item.effectiveDate),
          'Lançamento: ${_date(item.date)}',
          'Vencimento: ${_date(item.dueDate ?? item.date)}',
          if (item.effectiveDate != null)
            'Efetivação: ${_date(item.effectiveDate!)}',
          if (item.series != null) item.series!.label,
        ],
        '/transfers',
        'Ver transferências',
      );
    }
    final items = await getIt<TransactionsRepository>().list();
    final item = items.where((e) => e.id == activity.id).firstOrNull;
    if (item == null) return null;
    return _Details(
      item.description,
      MoneyMinor.display(item.amountMinor, item.currencyCode),
      [
        item.type.label,
        item.accountName,
        _status(item.isEffective, item.effectiveDate),
        if (item.categoryName != null) item.categoryName!,
        'Lançamento: ${_date(item.date)}',
        'Vencimento: ${_date(item.dueDate ?? item.date)}',
        if (item.effectiveDate != null)
          'Efetivação: ${_date(item.effectiveDate!)}',
        if (item.settlementCount > 0)
          'Baixado: ${MoneyMinor.display(item.settledMinor, item.currencyCode)} · Restante: ${MoneyMinor.display(item.amountMinor - item.settledMinor, item.currencyCode)}',
        if (item.allocations.isNotEmpty)
          'Rateio · ${item.allocations.length} categorias',
        if (item.series != null) item.series!.label,
        if (item.establishment.isNotEmpty) 'Local: ${item.establishment}',
        ...item.tags.map((tag) => '#$tag'),
      ],
      item.type == TransactionType.income ? '/income' : '/expenses',
      item.type == TransactionType.income ? 'Ver receitas' : 'Ver despesas',
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        key: const ValueKey('recent-activity-details'),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Detalhes do lançamento',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            FutureBuilder<_Details?>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      const Text('Não foi possível carregar este lançamento.'),
                      TextButton(
                        onPressed: () => setState(() => _future = _load()),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  );
                }
                final detail = snapshot.data;
                if (detail == null) {
                  return const Text(
                    'Este lançamento não está mais disponível. Atualize o resumo.',
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      detail.description,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      detail.amount,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    for (final line in detail.lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(line),
                      ),
                    TextButton(
                      onPressed: () {
                        final router = GoRouter.of(context);
                        Navigator.pop(context);
                        router.go(detail.location);
                      },
                      child: Text(detail.action),
                    ),
                  ],
                );
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
}

class _Details {
  const _Details(
    this.description,
    this.amount,
    this.lines,
    this.location,
    this.action,
  );
  final String description, amount, location, action;
  final List<String> lines;
}
