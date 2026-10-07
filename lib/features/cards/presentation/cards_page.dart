import 'package:go_router/go_router.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/filters/reference_month.dart';
import '../../../core/routing/somia_shell.dart';
import '../../../core/series/movement_series.dart';
import '../../../core/series/series_form.dart';
import '../../../core/widgets/month_selector.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../accounts/presentation/account_identity.dart';
import '../../categories/domain/category.dart';
import '../../categories/domain/categories_repository.dart';
import '../../transactions/domain/financial_transaction.dart';
import '../../transactions/presentation/transactions_page.dart';
import '../data/cards_repository.dart';
import '../domain/credit_card.dart';
import 'card_forms.dart';

class CardsPage extends StatefulWidget {
  const CardsPage({super.key, this.cardId, this.month});
  final String? cardId;
  final DateTime? month;
  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  CardsRepository get _repo => getIt<CardsRepository>();
  List<CreditCard> _cards = [];
  List<CardInvoice> _invoices = [];
  List<Account> _accounts = [];
  List<FinanceCategory> _categories = [];
  String? _cardId, _error;
  bool _loading = true, _acting = false, _cash = false, _statement = false;
  bool get _detail => widget.cardId != null;
  int _request = 0;
  DateTime get _month => referenceMonth.value;
  CreditCard? get _card => _cards.where((c) => c.id == _cardId).firstOrNull;
  CardInvoice? get _invoice => _invoices
      .where(
          (i) => i.month.year == _month.year && i.month.month == _month.month)
      .firstOrNull;
  @override
  void initState() {
    super.initState();
    _cardId = widget.cardId;
    if (widget.month != null) referenceMonth.select(widget.month!);
    referenceMonth.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    referenceMonth.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    if (mounted) setState(() => _loading = true);
    try {
      final cards = await _repo.list();
      final accounts = await getIt<AccountsRepository>().list();
      final categories = await getIt<CategoriesRepository>().list();
      final id = cards.any((c) => c.id == _cardId)
          ? _cardId
          : _detail
              ? null
              : cards.where((c) => !c.isArchived).firstOrNull?.id ??
                  cards.firstOrNull?.id;
      final invoices = id == null
          ? <CardInvoice>[]
          : await _repo.invoices(id, selected: _month);
      if (mounted && request == _request) {
        setState(() {
          _cards = cards;
          _accounts = accounts;
          _categories = categories;
          _cardId = id;
          _invoices = invoices;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível carregar os cartões.';
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) cardError(context, e);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
          context: context,
          builder: (dialog) =>
              AlertDialog(title: Text(title), content: Text(text), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('Confirmar'))
              ])) ==
      true;
  Future<void> _editCard([CreditCard? card]) async {
    final saved = await showMovementForm<bool>(
        context,
        (_) => CardForm(
            accounts: _accounts,
            month: _month,
            card: card,
            onSubmit: (draft, opening, month) => _repo.db.transaction(() async {
                  final id = await _repo.save(draft, id: card?.id);
                  if (opening != 0) await _repo.opening(id, month, opening);
                  _cardId = id;
                })));
    if (saved == true && mounted) await _load();
  }

  Future<void> _buy([CardEntry? entry]) async {
    final card = _card;
    if (card == null) return;
    final scope = entry != null && entry.count > 1
        ? await chooseSeriesScope(context, deleting: false)
        : SeriesScope.onlyThis;
    if (scope == null || !mounted) return;
    final draft = await showMovementForm<TransactionDraft>(
        context,
        (_) => TransactionForm(
            accounts: _accounts,
            categories: _categories,
            cards: _cards,
            initialCardId: card.id,
            fixedType: TransactionType.expense,
            scope: scope,
            item: entry == null ? null : _repo.movement(entry, card)));
    if (draft == null || !mounted) return;
    if (entry != null) {
      try {
        final hasPayments = await _repo.purchaseHasPayments(
            entry.id, draft.scope,
            invoiceMonth: draft.cardInvoiceMonth, purchaseDate: draft.date);
        if (!mounted) return;
        if (hasPayments &&
            !await _confirm('Corrigir compra em fatura com pagamento?',
                'Os pagamentos realizados ou agendados permanecerão vinculados às faturas atuais. A correção recalculará a dívida ou o crédito do cartão, sem alterar o saldo pago pela conta.')) {
          return;
        }
      } catch (e) {
        if (mounted) cardError(context, e);
        return;
      }
    }
    if (!mounted) return;
    await _run(() async {
      if (entry == null) {
        await _repo.createPurchase(draft);
      } else {
        await _repo.editPurchase(entry.id, draft);
      }
    });
  }

  Future<void> _pay() async {
    final card = _card, invoice = _invoice;
    if (card == null || invoice == null) return;
    final saved = await showMovementForm<bool>(
        context,
        (_) => CardPaymentForm(
            invoice: invoice,
            card: card,
            accounts: _accounts,
            onSubmit: (account, amount, date, fee, discount) => _repo.pay(
                invoice.id, account, amount, date,
                fee: fee, discount: discount)));
    if (saved == true && mounted) await _load();
  }

  Future<void> _refund(CardEntry entry) async {
    final saved = await showMovementForm<bool>(
        context,
        (_) => CardAdjustmentForm(
            title: 'Estornar compra',
            month: _month,
            initialAmount: entry.amountMinor,
            onSubmit: (amount, month, date) async {
              final invoiceId = await _repo.ensureInvoice(entry.cardId, month);
              await _repo.refund(entry.id, amount, invoiceId, date);
            }));
    if (saved == true && mounted) await _load();
  }

  Future<void> _opening() async {
    final card = _card;
    if (card == null) return;
    final saved = await showMovementForm<bool>(
        context,
        (_) => CardAdjustmentForm(
            title: 'Saldo inicial da fatura',
            month: _month,
            signed: true,
            onSubmit: (amount, month, date) =>
                _repo.opening(card.id, month, amount)));
    if (saved == true && mounted) await _load();
  }

  Future<void> _dates() async {
    final invoice = _invoice;
    if (invoice == null) return;
    final saved = await showMovementForm<bool>(
        context,
        (_) => CardDatesForm(
            invoice: invoice,
            onSubmit: (closing, due) =>
                _repo.adjustDates(invoice.id, closing, due)));
    if (saved == true && mounted) await _load();
  }

  Future<void> _anticipate() async {
    final card = _card, invoice = _invoice;
    if (card == null || invoice == null) return;
    final future = await _repo.entries(cardId: card.id);
    if (!mounted) return;
    final paidInvoices = {
      for (final i in _invoices)
        if (i.payments.isNotEmpty) i.id
    };
    final saved = await showMovementForm<bool>(
        context,
        (_) => CardAnticipationForm(
            invoice: invoice,
            entries: future
                .where((e) =>
                    e.kind == 'purchase' &&
                    e.count > 1 &&
                    e.invoiceMonth.isAfter(invoice.month) &&
                    !paidInvoices.contains(e.invoiceId))
                .toList(),
            onSubmit: (ids, discount) =>
                _repo.anticipate(ids, invoice.id, discount)));
    if (saved == true && mounted) await _load();
  }

  Future<void> _entryAction(CardEntry e, String action) async {
    if (action == 'edit') {
      await _buy(e);
      return;
    }
    if (action == 'refund') {
      await _refund(e);
      return;
    }
    if (action == 'history') {
      final history = await _repo.entryHistory(e.id);
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
                  title: const Text('Histórico da compra'),
                  content: SingleChildScrollView(
                      child: Text(history.isEmpty
                          ? 'Nenhuma mudança de fatura ou edição registrada.'
                          : history.join('\n'))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Fechar'))
                  ]));
      return;
    }
    final scope = e.kind == 'purchase' && e.count > 1
        ? await chooseSeriesScope(context, deleting: true)
        : SeriesScope.onlyThis;
    if (scope == null || !mounted) return;
    if (!await _confirm('Excluir registro?',
            'O registro sairá da fatura e dos cálculos. Os pagamentos realizados ou agendados serão preservados; o saldo restante ou crédito do cartão será recalculado. Para um reembolso real, use estorno. Compras com estorno ou antecipação devem preservar seus vínculos.') ||
        !mounted) {
      return;
    }
    await _run(() => e.kind == 'purchase'
        ? _repo.deletePurchase(e.id, scope)
        : _repo.removeAdjustment(e.id));
  }

  Widget _metric(String label, int amount) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text(label)),
        Text(cardMoney(amount),
            style: const TextStyle(fontWeight: FontWeight.w600))
      ]));
  Widget _cardMenu(CreditCard c) => PopupMenuButton<String>(
      enabled: !_acting,
      onSelected: (action) async {
        if (action == 'edit') {
          await _editCard(c);
          return;
        }
        if (action == 'history') {
          final history = await _repo.limitHistory(c.id);
          if (!mounted) return;
          await showDialog<void>(
              context: context,
              builder: (dialog) => AlertDialog(
                      title: const Text('Histórico de limite'),
                      content: SingleChildScrollView(
                          child: Text(history
                              .map((h) =>
                                  '${cardDateLabel(h.$1)} · ${h.$2 == null ? 'Sem controle' : cardMoney(h.$2!)}')
                              .join('\n'))),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(dialog),
                            child: const Text('Fechar'))
                      ]));
          return;
        }
        await _run(() => _repo.archive(c.id, !c.isArchived));
      },
      itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Editar cartão')),
            const PopupMenuItem(
                value: 'history', child: Text('Histórico de limite')),
            PopupMenuItem(
                value: 'archive',
                child: Text(c.isArchived ? 'Reativar' : 'Arquivar'))
          ]);

  Widget _cardTile(CreditCard c) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        color: SomiaColors.surface,
        child: InkWell(
          key: ValueKey('card-open-${c.id}'),
          onTap: _acting
              ? null
              : () => context.go(
                  '${AppRoutes.cardsPath}?card=${Uri.encodeComponent(c.id)}'),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [SomiaColors.surfaceHigh, SomiaColors.surface])),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                AccountAvatar(institutionId: c.institutionId),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(
                        '${c.name}${c.isArchived ? ' (arquivado)' : ''}',
                        style: Theme.of(context).textTheme.titleMedium)),
                _cardMenu(c)
              ]),
              const SizedBox(height: 20),
              Text(
                  c.availableMinor == null
                      ? 'Limite comprometido'
                      : 'Limite disponível',
                  style: const TextStyle(color: SomiaColors.muted)),
              Text(cardMoney(c.availableMinor ?? c.committedMinor),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600, color: SomiaColors.blue)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: Text(
                        'Fecha dia ${c.closingDay} · Vence dia ${c.dueDay}',
                        style: const TextStyle(
                            color: SomiaColors.muted, fontSize: 12))),
                const Icon(Icons.credit_card_outlined, color: SomiaColors.blue)
              ]),
            ]),
          ),
        ),
      ));

  Widget _cardSummary(CreditCard card, CardInvoice invoice) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              AccountAvatar(institutionId: card.institutionId),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(card.name,
                      style: Theme.of(context).textTheme.titleLarge)),
              _cardMenu(card)
            ]),
            const SizedBox(height: 12),
            _metric('Limite total', card.limitMinor ?? 0),
            if (card.limitMinor == null)
              const Text('Sem controle de limite',
                  style: TextStyle(color: SomiaColors.muted)),
            _metric('Limite comprometido', card.committedMinor),
            if (card.availableMinor != null) ...[
              _metric('Limite disponível', card.availableMinor!),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                  value: card.limitMinor! <= 0
                      ? (card.committedMinor > 0 ? 1 : 0)
                      : (card.committedMinor / card.limitMinor!)
                          .clamp(0.0, 1.0),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(8)),
            ],
            if (card.creditMinor > 0)
              _metric('Crédito do cartão', card.creditMinor),
            const SizedBox(height: 12),
            Text(
                'Fecha ${cardDateLabel(invoice.closingAt)} · Vence ${cardDateLabel(invoice.dueAt)}',
                style: const TextStyle(color: SomiaColors.muted)),
            _metric('Fatura do mês', invoice.chargesMinor),
            Text(invoice.status,
                style: const TextStyle(color: SomiaColors.blue)),
          ])));

  List<Widget> _dailyStatement(CardInvoice invoice) {
    final days = <int, List<Widget>>{};
    final entries = [...invoice.entries]
      ..sort((a, b) => a.description.compareTo(b.description));
    for (final entry in entries) {
      days
          .putIfAbsent(cardDay(entry.postedAt), () => [])
          .add(_entryTile(entry));
    }
    for (final payment in invoice.payments) {
      days
          .putIfAbsent(cardDay(payment.date), () => [])
          .add(_paymentTile(payment));
    }
    final dates = days.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      Text('Extrato · ${cardMonthLabel(invoice.month)}',
          style: Theme.of(context).textTheme.titleMedium),
      const Text(
          'Itens desta fatura por data da compra e pagamentos por data do pagamento.',
          style: TextStyle(color: SomiaColors.muted, fontSize: 12)),
      if (dates.isEmpty)
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nenhum lançamento nesta fatura.')),
      for (final day in dates) ...[
        Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 4),
            child: Text(cardDateLabel(cardDate(day)),
                key: ValueKey('card-statement-day-$day'),
                style: const TextStyle(
                    color: SomiaColors.blue, fontWeight: FontWeight.w600))),
        const Divider(height: 1),
        ...days[day]!,
      ],
    ];
  }

  Widget _entryTile(CardEntry e) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(e.description),
      subtitle: Text(
          '${e.label} · ${e.allocations.isEmpty ? e.categoryName ?? 'Sem categoria' : 'Rateio · ${e.allocations.length} categorias'}\nCompra: ${cardDateLabel(e.postedAt)}'),
      isThreeLine: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(cardMoney(e.amountMinor)),
        PopupMenuButton<String>(
            enabled: !_acting,
            onSelected: (a) => _entryAction(e, a),
            itemBuilder: (_) => [
                  if (e.kind == 'purchase') ...[
                    const PopupMenuItem(
                        value: 'edit', child: Text('Editar / mudar fatura')),
                    const PopupMenuItem(
                        value: 'refund', child: Text('Estornar')),
                    const PopupMenuItem(
                        value: 'history', child: Text('Histórico')),
                  ],
                  if (e.kind != 'fee' &&
                      (e.kind != 'discount' || e.sourceId == null))
                    const PopupMenuItem(
                        value: 'delete', child: Text('Excluir')),
                ])
      ]));
  Widget _paymentTile(CardPayment p) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Icon(Icons.account_balance_wallet_outlined),
      title: Text(cardMoney(p.amountMinor)),
      subtitle: Text(
          '${p.accountName} · ${cardDateLabel(p.date)}${cardDay(p.date) > cardDay(DateTime.now()) ? ' · Agendado' : ''}'),
      trailing: IconButton(
          tooltip: 'Desfazer pagamento',
          icon: const Icon(Icons.undo),
          onPressed: _acting
              ? null
              : () async {
                  if (await _confirm('Desfazer pagamento?',
                          'O débito sairá da conta e a dívida voltará à fatura. Encargos e desconto deste pagamento também serão desfeitos.') &&
                      mounted) {
                    await _run(() => _repo.undoPayment(p.id));
                  }
                }));
  @override
  Widget build(BuildContext context) {
    final card = _card, invoice = _invoice;
    final cashPayments = _invoices
        .expand((i) => i.payments)
        .where(
            (p) => p.date.year == _month.year && p.date.month == _month.month)
        .toList();
    final cashPaid = cashPayments
        .where((p) => cardDay(p.date) <= cardDay(DateTime.now()))
        .fold(0, (a, p) => a + p.amountMinor);
    final cashScheduled = cashPayments
        .where((p) => cardDay(p.date) > cardDay(DateTime.now()))
        .fold(0, (a, p) => a + p.amountMinor);
    return Scaffold(
        appBar: AppBar(
            title: Text(_detail ? 'Detalhes do cartão' : 'Cartões'),
            leading: _detail
                ? BackButton(onPressed: () => context.go(AppRoutes.cardsPath))
                : somiaMenuLeading(context),
            actions: [
              IconButton(
                  tooltip: 'Novo cartão',
                  onPressed: _loading || _acting ? null : () => _editCard(),
                  icon: const Icon(Icons.add))
            ]),
        floatingActionButton: const SomiaQuickActions(),
        body: _loading && _cards.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: TextButton(
                        onPressed: _load,
                        child: Text('$_error Tentar novamente')))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                        children: [
                          MonthSelector(
                              month: _month, onChanged: referenceMonth.select),
                          if (_loading || _acting)
                            const LinearProgressIndicator(),
                          if (_cards.isEmpty) ...[
                            const Padding(
                                padding: EdgeInsets.symmetric(vertical: 28),
                                child: Text(
                                    'Cadastre seu primeiro cartão para acompanhar compras, limite e faturas.')),
                            FilledButton.icon(
                                onPressed: () => _editCard(),
                                icon: const Icon(Icons.credit_card),
                                label: const Text('Cadastrar cartão'))
                          ],
                          if (!_detail)
                            for (final c in _cards) _cardTile(c),
                          if (_detail && card == null)
                            const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                    'Cartão não encontrado. Volte à lista de cartões.')),
                          if (_detail && card != null && invoice != null) ...[
                            _cardSummary(card, invoice),
                            const SizedBox(height: 16),
                            Text(
                                '${card.name} · ${cardMonthLabel(invoice.month)}',
                                style: Theme.of(context).textTheme.titleLarge),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              ChoiceChip(
                                  label: const Text('Competência / fatura'),
                                  selected: !_cash && !_statement,
                                  onSelected: (_) => setState(() {
                                        _cash = false;
                                        _statement = false;
                                      })),
                              ChoiceChip(
                                  label: const Text('Extrato'),
                                  selected: _statement,
                                  onSelected: (_) => setState(() {
                                        _statement = true;
                                        _cash = false;
                                      })),
                              ChoiceChip(
                                  label: const Text('Caixa / pagamentos'),
                                  selected: _cash,
                                  onSelected: (_) => setState(() {
                                        _cash = true;
                                        _statement = false;
                                      }))
                            ]),
                            if (_statement)
                              ..._dailyStatement(invoice)
                            else if (_cash) ...[
                              const SizedBox(height: 12),
                              const Text(
                                  'Débitos reais da conta no mês escolhido, mesmo que o pagamento pertença a outra fatura.'),
                              _metric('Pago no mês', cashPaid),
                              _metric('Agendado no mês', cashScheduled),
                              for (final p in cashPayments) _paymentTile(p),
                              if (cashPayments.isEmpty)
                                const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('Nenhum pagamento neste mês.')),
                            ] else ...[
                              Card(
                                  child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(invoice.status,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium),
                                            Text(
                                                'Fecha ${cardDateLabel(invoice.closingAt)} · Vence ${cardDateLabel(invoice.dueAt)}'),
                                            _metric(
                                                invoice.previousMinor < 0
                                                    ? 'Crédito anterior'
                                                    : 'Saldo da fatura anterior',
                                                invoice.previousMinor),
                                            _metric('Fatura do mês',
                                                invoice.chargesMinor),
                                            _metric('Pagamentos realizados',
                                                -invoice.paidMinor),
                                            const Divider(),
                                            _metric(
                                                invoice.balanceMinor < 0
                                                    ? 'Saldo credor'
                                                    : invoice.previousMinor != 0
                                                        ? 'Total a pagar com saldo anterior'
                                                        : 'Saldo a pagar',
                                                invoice.balanceMinor),
                                            if (invoice.scheduledMinor > 0) ...[
                                              _metric('Pagamentos agendados',
                                                  -invoice.scheduledMinor),
                                              _metric('Após agendamentos',
                                                  invoice.projectedMinor)
                                            ],
                                            if (invoice.balanceMinor > 0)
                                              const Text(
                                                  'O saldo não pago segue para a próxima fatura, mantendo o histórico. Juros e multas são informados no pagamento.'),
                                          ]))),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                FilledButton.icon(
                                    onPressed: _acting ? null : _pay,
                                    icon: const Icon(Icons.payments_outlined),
                                    label: const Text('Pagar fatura')),
                                OutlinedButton.icon(
                                    onPressed: _acting || card.isArchived
                                        ? null
                                        : () => _buy(),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Nova compra')),
                                OutlinedButton(
                                    onPressed: _acting ? null : _anticipate,
                                    child: const Text('Antecipar parcelas')),
                                OutlinedButton(
                                    onPressed: _acting ? null : _dates,
                                    child: const Text('Ajustar datas')),
                                OutlinedButton(
                                    onPressed: _acting ? null : _opening,
                                    child: const Text('Saldo inicial')),
                              ]),
                              const SizedBox(height: 20),
                              Text('Itens da fatura',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              for (final e in invoice.entries) _entryTile(e),
                              if (invoice.entries.isEmpty)
                                const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('Nenhum item nesta fatura.')),
                              const Divider(),
                              Text('Pagamentos',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              for (final p in invoice.payments) _paymentTile(p),
                              if (invoice.payments.isEmpty)
                                const Padding(
                                    padding: EdgeInsets.all(16),
                                    child:
                                        Text('Nenhum pagamento registrado.')),
                              const SizedBox(height: 12),
                              Text('Próximas faturas',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              for (final i in _invoices
                                  .where((i) => i.month.isAfter(invoice.month)))
                                ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(cardMonthLabel(i.month)),
                                    subtitle: Text(i.previousMinor == 0
                                        ? i.status
                                        : '${i.status} · anterior ${cardMoney(i.previousMinor)}'),
                                    trailing: Text(cardMoney(i.chargesMinor)),
                                    onTap: () =>
                                        referenceMonth.select(i.month)),
                            ],
                          ],
                        ])));
  }
}
