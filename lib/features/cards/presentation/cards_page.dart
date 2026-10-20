import '../../attachments/presentation/attachments_page.dart';
import '../../transactions/data/movement_management_repository.dart';
import '../../transactions/domain/movement_management.dart';
import '../../transactions/presentation/bulk_movement_toolbar.dart';

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
import '../../../core/widgets/somia_brand.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../accounts/presentation/account_identity.dart';
import '../../categories/domain/category.dart';
import '../../categories/domain/categories_repository.dart';
import '../../transactions/domain/financial_transaction.dart';
import '../../transactions/presentation/transactions_page.dart';
import '../data/cards_repository.dart';
import '../data/card_payment_coverage_repository.dart';
import '../domain/credit_card.dart';
import 'card_forms.dart';
import 'payment_coverage_form.dart';

class CardsPage extends StatefulWidget {
  const CardsPage({
    super.key,
    this.cardId,
    this.month,
    this.initialStatement = false,
  });
  final String? cardId;
  final DateTime? month;
  final bool initialStatement;
  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  Map<String, MovementReference> _bulkSelection = {};
  bool _bulkMode = false;

  void _cancelBulk() => setState(() {
        _bulkMode = false;
        _bulkSelection = {};
      });

  void _startBulk(MovementReference ref) => setState(() {
        _bulkMode = true;
        _bulkSelection = {ref.key: ref};
      });
  CardsRepository get _repo => getIt<CardsRepository>();
  List<CreditCard> _cards = [];
  List<CardInvoice> _invoices = [];
  String? _selectedChartInvoiceId;
  Map<String, CardInvoice> _summaries = {};
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
        (i) => i.month.year == _month.year && i.month.month == _month.month,
      )
      .firstOrNull;
  @override
  void initState() {
    super.initState();
    _cardId = widget.cardId;
    _statement = widget.initialStatement;
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
    if (mounted) _cancelBulk();
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
      final summaries = <String, CardInvoice>{};
      if (!_detail) {
        for (final card in cards) {
          final items = card.id == id
              ? invoices
              : await _repo.invoices(card.id, selected: _month);
          final selected = items
              .where(
                (i) =>
                    i.month.year == _month.year &&
                    i.month.month == _month.month,
              )
              .firstOrNull;
          if (selected != null) summaries[card.id] = selected;
        }
      }
      if (mounted && request == _request) {
        setState(() {
          _summaries = summaries;
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
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ==
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
        }),
      ),
    );
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
        item: entry == null ? null : _repo.movement(entry, card),
      ),
    );
    if (draft == null || !mounted) return;
    if (entry != null) {
      try {
        final hasPayments = await _repo.purchaseHasPayments(
          entry.id,
          draft.scope,
          invoiceMonth: draft.cardInvoiceMonth,
          purchaseDate: draft.date,
        );
        if (!mounted) return;
        if (hasPayments &&
            !await _confirm(
              'Corrigir compra em fatura com pagamento?',
              'Os pagamentos realizados ou agendados permanecerão vinculados às faturas atuais. A correção recalculará a dívida ou o crédito do cartão, sem alterar o saldo pago pela conta.',
            )) {
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

  Future<void> _pay([
    CreditCard? selectedCard,
    CardInvoice? selectedInvoice,
  ]) async {
    final card = selectedCard ?? _card, invoice = selectedInvoice ?? _invoice;
    if (card == null || invoice == null) return;
    final available =
        await CardPaymentCoverageRepository(_repo.db).available(invoice.id);
    if (!mounted) return;
    final saved = await showMovementForm<bool>(
      context,
      (_) => CardPaymentForm(
        invoice: invoice,
        card: card,
        accounts: _accounts,
        availableCoverage: available,
        onSubmitWithCoverage:
            (account, amount, date, fee, discount, coverage) => _repo.pay(
                invoice.id, account, amount, date,
                fee: fee,
                discount: discount,
                coverage: coverage.isEmpty &&
                        amount >= available.values.fold(0, (a, b) => a + b)
                    ? null
                    : coverage),
        onSubmit: (account, amount, date, fee, discount) => _repo.pay(
          invoice.id,
          account,
          amount,
          date,
          fee: fee,
          discount: discount,
        ),
      ),
    );
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
        },
      ),
    );
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
            _repo.opening(card.id, month, amount),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _dates() async {
    final invoice = _invoice;
    if (invoice == null) return;
    final saved = await showMovementForm<bool>(
      context,
      (_) => CardDatesForm(
        invoice: invoice,
        onSubmit: (closing, due) => _repo.adjustDates(invoice.id, closing, due),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _anticipate() async {
    final card = _card, invoice = _invoice;
    if (card == null || invoice == null) return;
    final future = await _repo.entries(cardId: card.id);
    if (!mounted) return;
    final paidInvoices = {
      for (final i in _invoices)
        if (i.payments.isNotEmpty) i.id,
    };
    final saved = await showMovementForm<bool>(
      context,
      (_) => CardAnticipationForm(
        invoice: invoice,
        entries: future
            .where(
              (e) =>
                  e.kind == 'purchase' &&
                  e.count > 1 &&
                  e.invoiceMonth.isAfter(invoice.month) &&
                  !paidInvoices.contains(e.invoiceId),
            )
            .toList(),
        onSubmit: (ids, discount) =>
            _repo.anticipate(ids, invoice.id, discount),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _entryAction(CardEntry e, String action) async {
    if (action == 'bulk') {
      _startBulk(MovementReference(MovementKind.cardEntry, e.id, e.revision));
      return;
    }
    if (action == 'attachments') {
      await showAttachments(
        context,
        MovementReference(MovementKind.cardEntry, e.id, ''),
      );
      return;
    }
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
            child: Text(
              history.isEmpty
                  ? 'Nenhuma mudança de fatura ou edição registrada.'
                  : history.join('\n'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
      return;
    }
    final scope = e.kind == 'purchase' && e.count > 1
        ? await chooseSeriesScope(context, deleting: true)
        : SeriesScope.onlyThis;
    if (scope == null || !mounted) return;
    if (!await _confirm(
          'Excluir registro?',
          'O registro sairá da fatura e dos cálculos. Os pagamentos realizados ou agendados serão preservados; o saldo restante ou crédito do cartão será recalculado. Para um reembolso real, use estorno. Compras com estorno ou antecipação devem preservar seus vínculos.',
        ) ||
        !mounted) {
      return;
    }
    await _run(
      () => e.kind == 'purchase'
          ? _repo.deletePurchase(e.id, scope)
          : _repo.removeAdjustment(e.id),
    );
  }

  Widget _metric(String label, int amount) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              cardMoney(amount),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
  Widget _cardMenu(CreditCard c, {bool detailActions = false}) =>
      PopupMenuButton<String>(
        enabled: !_acting,
        onSelected: (action) async {
          if (action == 'debit') {
            context.go(AppRoutes.debitCardsPath);
            return;
          }
          if (action == 'cashback') {
            context
                .go('/cashback?kind=credit&card=${Uri.encodeComponent(c.id)}');
            return;
          }
          if (action == 'new') {
            await _editCard();
            return;
          }
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
                  child: Text(
                    history
                        .map(
                          (h) =>
                              '${cardDateLabel(h.$1)} · ${h.$2 == null ? 'Sem controle' : cardMoney(h.$2!)}',
                        )
                        .join('\n'),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            );
            return;
          }
          await _run(() => _repo.archive(c.id, !c.isArchived));
        },
        itemBuilder: (_) => [
          if (detailActions) ...[
            const PopupMenuItem(
                value: 'debit', child: Text('Cartões de débito')),
            const PopupMenuItem(value: 'cashback', child: Text('Cashback')),
            const PopupMenuItem(value: 'new', child: Text('Novo cartão')),
            const PopupMenuDivider(),
          ],
          const PopupMenuItem(value: 'edit', child: Text('Editar cartão')),
          const PopupMenuItem(
              value: 'history', child: Text('Histórico de limite')),
          PopupMenuItem(
            value: 'archive',
            child: Text(c.isArchived ? 'Reativar' : 'Arquivar'),
          ),
        ],
      );

  Color _accent(CreditCard card) =>
      card.colorArgb == null ? SomiaColors.blue : Color(card.colorArgb!);

  Widget _limitProgress(CreditCard card) {
    final limit = card.limitMinor;
    if (limit == null) {
      return const Text(
        'Sem controle de limite',
        style: TextStyle(color: SomiaColors.muted, fontSize: 12),
      );
    }
    final ratio = limit <= 0 ? 0.0 : card.committedMinor / limit;
    final label = limit == 0
        ? (card.committedMinor > 0 ? 'Acima do limite' : 'Limite zero')
        : '${(ratio * 100).round()}%';
    return Row(
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: limit == 0 && card.committedMinor > 0
                ? 1
                : ratio.clamp(0.0, 1.0),
            color:
                card.committedMinor > limit ? SomiaColors.red : _accent(card),
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _cardTile(CreditCard card) {
    final invoice = _summaries[card.id];
    final accent = _accent(card);
    final account =
        _accounts.where((a) => a.id == card.paymentAccountId).firstOrNull;
    void open() => context.go(
          '${AppRoutes.cardsPath}?card=${Uri.encodeComponent(card.id)}',
        );
    Widget fact(String label, String value, {Color? color}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: SomiaColors.muted),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        color: SomiaColors.surface,
        child: InkWell(
          key: ValueKey('card-open-${card.id}'),
          onTap: _acting ? null : open,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    accent.withValues(alpha: .14),
                    SomiaColors.surfaceHigh,
                  ),
                  SomiaColors.surface,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AccountAvatar(institutionId: card.institutionId),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${card.name}${card.isArchived ? ' (arquivado)' : ''}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    _cardMenu(card),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  children: [
                    fact(
                      'Limite total',
                      card.limitMinor == null
                          ? 'Não informado'
                          : cardMoney(card.limitMinor!),
                    ),
                    fact('Limite comprometido', cardMoney(card.committedMinor)),
                    fact(
                      'Limite disponível',
                      card.availableMinor == null
                          ? 'Não informado'
                          : cardMoney(card.availableMinor!),
                      color: card.availableMinor != null &&
                              card.availableMinor! < 0
                          ? SomiaColors.red
                          : accent,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _limitProgress(card),
                if (card.creditMinor > 0) ...[
                  const SizedBox(height: 8),
                  fact('Crédito do cartão', cardMoney(card.creditMinor)),
                ],
                const Divider(height: 28),
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  children: [
                    fact('Conta', account?.name ?? 'Não definida'),
                    fact(
                      'Fechamento',
                      cardDateLabel(
                        invoice?.closingAt ?? card.closingFor(_month),
                      ),
                    ),
                    fact(
                      'Vencimento',
                      cardDateLabel(invoice?.dueAt ?? card.dueFor(_month)),
                    ),
                  ],
                ),
                if (invoice != null) ...[
                  const Divider(height: 28),
                  Row(
                    children: [
                      const Expanded(child: Text('Fatura do mês')),
                      Flexible(
                        child: Text(
                          cardMoney(invoice.chargesMinor),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: SomiaColors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    invoice.status,
                    style: TextStyle(
                      color:
                          invoice.status == 'Paga' ? SomiaColors.green : accent,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (invoice.balanceMinor > 0)
                        TextButton.icon(
                          onPressed: _acting ? null : () => _pay(card, invoice),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Registrar pagamento'),
                        ),
                      TextButton.icon(
                        onPressed: _acting
                            ? null
                            : () => context.go(
                                  '${AppRoutes.cardsPath}?card=${Uri.encodeComponent(card.id)}&view=statement',
                                ),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Extrato'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardSummary(CreditCard card, CardInvoice invoice) => Card(
        color: Color.alphaBlend(
          _accent(card).withValues(alpha: .08),
          SomiaColors.surface,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AccountAvatar(institutionId: card.institutionId),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      card.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  _cardMenu(card),
                ],
              ),
              const SizedBox(height: 12),
              _metric('Limite total', card.limitMinor ?? 0),
              if (card.limitMinor == null)
                const Text(
                  'Sem controle de limite',
                  style: TextStyle(color: SomiaColors.muted),
                ),
              _metric('Limite comprometido', card.committedMinor),
              if (card.availableMinor != null) ...[
                _metric('Limite disponível', card.availableMinor!),
                const SizedBox(height: 8),
                _limitProgress(card),
              ],
              if (card.creditMinor > 0)
                _metric('Crédito do cartão', card.creditMinor),
              const SizedBox(height: 12),
              Text(
                'Fecha ${cardDateLabel(invoice.closingAt)} · Vence ${cardDateLabel(invoice.dueAt)}',
                style: const TextStyle(color: SomiaColors.muted),
              ),
              _metric('Fatura do mês', invoice.chargesMinor),
              Text(invoice.status,
                  style: const TextStyle(color: SomiaColors.blue)),
            ],
          ),
        ),
      );

  String _referenceMoney(int minor) => cardMoney(minor).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+,)'),
        (match) => '${match[1]}.',
      );

  Widget _referenceMetric(String label, int amount,
      {IconData? icon, Color? color}) {
    final amountText =
        amount < 0 ? '-${_referenceMoney(-amount)}' : _referenceMoney(amount);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: icon == null ? 5 : 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (color ?? SomiaColors.blue).withValues(alpha: .16),
              ),
              child: Icon(icon, size: 23, color: color ?? SomiaColors.blue),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              amountText,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _referenceSummary(CreditCard card, CardInvoice invoice) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                AccountAvatar(institutionId: card.institutionId, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(card.name,
                      style: const TextStyle(
                          fontSize: 23, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 14),
              if (card.limitMinor != null)
                _referenceMetric('Limite total', card.limitMinor!)
              else
                const Text('Sem controle de limite'),
              _referenceMetric('Limite comprometido', card.committedMinor),
              if (card.availableMinor != null)
                _referenceMetric('Limite disponível', card.availableMinor!),
              if (card.creditMinor > 0)
                _referenceMetric('Crédito do cartão', card.creditMinor),
              const SizedBox(height: 12),
              _limitProgress(card),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              Text(
                'Fecha em ${cardDateLabel(invoice.closingAt)} · Vence em ${cardDateLabel(invoice.dueAt)}',
                style: const TextStyle(color: SomiaColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 6),
              _referenceMetric('Fatura atual', invoice.balanceMinor),
            ],
          ),
        ),
      );

  Widget _referenceTabs() => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(color: SomiaColors.outline),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            for (final tab in ['Fatura', 'Extrato', 'Pagamentos'])
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    foregroundColor: SomiaColors.muted,
                    backgroundColor:
                        (tab == 'Fatura' && !_statement && !_cash) ||
                                (tab == 'Extrato' && _statement) ||
                                (tab == 'Pagamentos' && _cash)
                            ? const Color(0xFF394E5D)
                            : Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                  ),
                  onPressed: () => setState(() {
                    _bulkMode = false;
                    _bulkSelection = {};
                    _statement = tab == 'Extrato';
                    _cash = tab == 'Pagamentos';
                  }),
                  child: Text(tab,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w400)),
                ),
              ),
          ],
        ),
      );

  Widget _referenceActions(CreditCard card) {
    Widget actionRow(String label, IconData icon, VoidCallback? onTap) =>
        InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Row(children: [
              Icon(icon, size: 20, color: SomiaColors.blue),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(label, style: const TextStyle(fontSize: 14))),
              const Icon(Icons.chevron_right,
                  size: 22, color: SomiaColors.muted),
            ]),
          ),
        );

    final buttonStyle = FilledButton.styleFrom(
      minimumSize: const Size(0, 46),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
    final outlinedStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 46),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
    return Card(
      key: const ValueKey('card-invoice-actions'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ações da fatura',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: buttonStyle,
                  onPressed: _acting ? null : _pay,
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Pagar fatura', maxLines: 1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: outlinedStyle,
                  onPressed: _acting || card.isArchived ? null : () => _buy(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nova compra', maxLines: 1),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            const Text('Mais ações',
                style: TextStyle(color: SomiaColors.muted, fontSize: 13)),
            const SizedBox(height: 8),
            const Divider(height: 1),
            actionRow('Antecipar parcelas', Icons.storage_outlined,
                _acting ? null : _anticipate),
            const Divider(height: 1),
            actionRow('Ajustar datas', Icons.calendar_today_outlined,
                _acting ? null : _dates),
            const Divider(height: 1),
            actionRow('Saldo inicial', Icons.receipt_long_outlined,
                _acting ? null : _opening),
          ],
        ),
      ),
    );
  }

  Widget _referenceInvoice(CardInvoice invoice) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Fatura de ${monthNames[invoice.month.month - 1].toLowerCase()}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              if (invoice.previousMinor != 0)
                _referenceMetric(
                    invoice.previousMinor < 0
                        ? 'Crédito anterior'
                        : 'Saldo anterior',
                    invoice.previousMinor,
                    icon: Icons.history),
              _referenceMetric('Compras', invoice.chargesMinor,
                  icon: Icons.shopping_cart_outlined),
              _referenceMetric('Pagamentos', -invoice.paidMinor,
                  icon: Icons.arrow_upward, color: SomiaColors.red),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
              _referenceMetric(
                  invoice.balanceMinor < 0 ? 'Saldo credor' : 'A pagar',
                  invoice.balanceMinor,
                  icon: Icons.description_outlined),
              if (invoice.scheduledMinor > 0) ...[
                _referenceMetric('Agendado', -invoice.scheduledMinor,
                    icon: Icons.schedule_outlined),
                _referenceMetric('Após agendamentos', invoice.projectedMinor),
              ],
            ],
          ),
        ),
      );

  Widget _invoicesChart(List<CardInvoice> invoices, DateTime currentMonth) {
    if (invoices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Nenhuma fatura disponível.'),
      );
    }
    final selectedIndex = invoices.indexWhere(
      (invoice) => invoice.id == _selectedChartInvoiceId,
    );
    final nextIndex = invoices.indexWhere(
      (invoice) => invoice.month.isAfter(currentMonth),
    );
    final currentIndex = invoices.indexWhere(
      (invoice) =>
          invoice.month.year == currentMonth.year &&
          invoice.month.month == currentMonth.month,
    );
    final index = selectedIndex >= 0
        ? selectedIndex
        : nextIndex >= 0
            ? nextIndex
            : currentIndex >= 0
                ? currentIndex
                : 0;
    final selected = invoices[index];
    return Card(
      key: const ValueKey('future-invoices-chart'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(builder: (context, constraints) {
          final visibleCount = constraints.maxWidth < 340 ? 6 : 8;
          final lastStart = invoices.length > visibleCount
              ? invoices.length - visibleCount
              : 0;
          final start = (index - visibleCount ~/ 2).clamp(0, lastStart);
          final shown = invoices.skip(start).take(visibleCount).toList();
          final peak = shown.fold<int>(
              0,
              (max, invoice) =>
                  invoice.chargesMinor > max ? invoice.chargesMinor : max);
          final chartMax = peak == 0 ? 1 : peak;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(
                  child: Text('Compras do mês',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: SomiaColors.blue.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(selected.status.toUpperCase(),
                      style: const TextStyle(
                          color: SomiaColors.blue,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 12),
              Text(_referenceMoney(selected.chargesMinor),
                  key: const ValueKey('future-invoice-amount'),
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 64,
                  height: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_referenceMoney(chartMax),
                          style: const TextStyle(
                              color: SomiaColors.muted, fontSize: 10)),
                      Text(_referenceMoney(chartMax ~/ 2),
                          style: const TextStyle(
                              color: SomiaColors.muted, fontSize: 10)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(children: [
                    SizedBox(
                      height: 140,
                      child: Stack(children: [
                        const Positioned.fill(
                            child:
                                CustomPaint(painter: _InvoiceGuidePainter())),
                        Row(children: [
                          for (final invoice in shown)
                            Expanded(
                              child: Semantics(
                                button: true,
                                selected: invoice.id == selected.id,
                                label: '${cardMonthLabel(invoice.month)}: '
                                    '${_referenceMoney(invoice.chargesMinor)}',
                                child: InkWell(
                                  key: ValueKey(
                                      'future-invoice-bar-${invoice.month.year}-${invoice.month.month}'),
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => setState(() =>
                                      _selectedChartInvoiceId = invoice.id),
                                  child: Center(
                                    child: FractionallySizedBox(
                                      widthFactor: 0.56,
                                      child: Container(
                                        height: 140,
                                        decoration: BoxDecoration(
                                          color: SomiaColors.muted
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        alignment: Alignment.bottomCenter,
                                        child: FractionallySizedBox(
                                          heightFactor:
                                              invoice.chargesMinor <= 0
                                                  ? 0
                                                  : (invoice.chargesMinor /
                                                          chartMax)
                                                      .clamp(0.04, 1.0),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: invoice.id == selected.id
                                                  ? SomiaColors.blue
                                                  : SomiaColors.muted
                                                      .withValues(alpha: 0.62),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ]),
                      ]),
                    ),
                    SizedBox(
                      height: 18,
                      child: Row(children: [
                        for (final invoice in shown)
                          Expanded(
                            child: invoice.id == selected.id
                                ? const Icon(Icons.arrow_drop_up,
                                    size: 18, color: SomiaColors.blue)
                                : const SizedBox.shrink(),
                          ),
                      ]),
                    ),
                    SizedBox(
                      height: 32,
                      child: Row(children: [
                        for (final invoice in shown)
                          Expanded(
                            child: Text(
                              '${monthNames[invoice.month.month - 1].substring(0, 3)}\n${invoice.month.year}',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: TextStyle(
                                color: invoice.id == selected.id
                                    ? SomiaColors.blue
                                    : SomiaColors.muted,
                                fontSize: 9,
                                fontWeight: invoice.id == selected.id
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                IconButton.filledTonal(
                  tooltip: 'Fatura anterior',
                  onPressed: index == 0
                      ? null
                      : () => setState(() =>
                          _selectedChartInvoiceId = invoices[index - 1].id),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => referenceMonth.select(selected.month),
                    child: Text(
                      '${monthNames[selected.month.month - 1]} ${selected.month.year}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Próxima fatura',
                  onPressed: index == invoices.length - 1
                      ? null
                      : () => setState(() =>
                          _selectedChartInvoiceId = invoices[index + 1].id),
                  icon: const Icon(Icons.chevron_right),
                ),
              ]),
            ],
          );
        }),
      ),
    );
  }

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
      Text(
        'Extrato · ${cardMonthLabel(invoice.month)}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const Text(
        'Itens desta fatura por data da compra e pagamentos por data do pagamento.',
        style: TextStyle(color: SomiaColors.muted, fontSize: 12),
      ),
      if (dates.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nenhum lançamento nesta fatura.'),
        ),
      for (final day in dates) ...[
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 4),
          child: Text(
            cardDateLabel(cardDate(day)),
            key: ValueKey('card-statement-day-$day'),
            style: const TextStyle(
              color: SomiaColors.blue,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Divider(height: 1),
        ...days[day]!,
      ],
    ];
  }

  Widget _entryTile(CardEntry e, {bool cardStyle = false}) {
    final row = cardStyle ? _mobileEntryContent(e) : _entryContent(e);
    if (!_bulkMode ||
        e.kind != 'purchase' ||
        !getIt.isRegistered<MovementManagementRepository>()) {
      return row;
    }
    return SelectableMovementRow(
      ref: MovementReference(MovementKind.cardEntry, e.id, e.revision),
      selection: _bulkSelection,
      onSelection: (selection) => setState(() => _bulkSelection = selection),
      child: row,
    );
  }

  Widget _mobileEntryContent(CardEntry e) {
    final category = e.allocations.isEmpty
        ? e.categoryName ?? 'Sem categoria'
        : 'Rateio · ${e.allocations.length} categorias';
    final color = e.amountMinor < 0 ? SomiaColors.green : SomiaColors.red;
    final icon = switch (e.kind) {
      'refund' => Icons.keyboard_return_outlined,
      'fee' => Icons.receipt_long_outlined,
      'discount' => Icons.sell_outlined,
      _ => Icons.shopping_cart_outlined,
    };
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(15) > 19.5;
            final leading = Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.17),
              ),
              child: Icon(icon, color: color),
            );
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(category,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: SomiaColors.muted, fontSize: 12)),
                const SizedBox(height: 3),
                Text(
                    'Compra: ${cardDateLabel(e.postedAt)}'
                    '${e.establishment.isEmpty ? '' : ' · ${e.establishment}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: SomiaColors.muted, fontSize: 11)),
              ],
            );
            final amount = Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    e.amountMinor < 0
                        ? '+${_referenceMoney(-e.amountMinor)}'
                        : '-${_referenceMoney(e.amountMinor)}',
                    maxLines: 1,
                    style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: SomiaColors.blue.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(e.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: SomiaColors.blue,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            );
            final menu = _entryMenu(e);
            if (compact) {
              return Column(
                children: [
                  Row(children: [
                    leading,
                    const SizedBox(width: 10),
                    Expanded(child: details),
                    menu,
                  ]),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 44, top: 6),
                      child: amount,
                    ),
                  ),
                ],
              );
            }
            return Row(children: [
              leading,
              const SizedBox(width: 10),
              Expanded(child: details),
              const SizedBox(width: 6),
              SizedBox(width: 110, child: amount),
              menu,
            ]);
          },
        ),
      ),
    );
  }

  Widget _entryContent(CardEntry e) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(e.description),
        subtitle: Text(
          '${e.label} · ${e.allocations.isEmpty ? e.categoryName ?? 'Sem categoria' : 'Rateio · ${e.allocations.length} categorias'}\nCompra: ${cardDateLabel(e.postedAt)}${e.establishment.isEmpty ? '' : ' · ${e.establishment}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(cardMoney(e.amountMinor)),
            _entryMenu(e),
          ],
        ),
      );

  Widget _entryMenu(CardEntry e) => PopupMenuButton<String>(
        enabled: !_acting,
        onSelected: (a) => _entryAction(e, a),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'attachments', child: Text('Anexos')),
          if (e.kind == 'purchase') ...[
            if (getIt.isRegistered<MovementManagementRepository>())
              const PopupMenuItem(
                value: 'bulk',
                child: Text('Editar em lote'),
              ),
            const PopupMenuItem(
              value: 'edit',
              child: Text('Editar / mudar fatura'),
            ),
            const PopupMenuItem(value: 'refund', child: Text('Estornar')),
            const PopupMenuItem(value: 'history', child: Text('Histórico')),
          ],
          if (e.kind != 'fee' && (e.kind != 'discount' || e.sourceId == null))
            const PopupMenuItem(value: 'delete', child: Text('Excluir')),
        ],
      );
  Future<void> _coverage(CardPayment payment) async {
    try {
      final repo = CardPaymentCoverageRepository(_repo.db);
      final data = await repo.forPayment(payment.id);
      final invoice = await _repo.invoice(data.invoiceId);
      if (!mounted) return;
      final chosen = await showMovementForm<Map<String, int>>(
          context,
          (_) => PaymentCoverageForm(
              payment: payment,
              entries: invoice.entries,
              available: data.available,
              selected: data.selected));
      if (chosen != null && mounted) {
        await _run(() => repo.replace(payment.id, chosen));
      }
    } catch (e) {
      if (mounted) cardError(context, e);
    }
  }

  Widget _paymentTile(CardPayment p) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: const Icon(Icons.account_balance_wallet_outlined),
        title: Text(cardMoney(p.amountMinor)),
        subtitle: Text(
          '${p.accountName} · ${cardDateLabel(p.date)}${cardDay(p.date) > cardDay(DateTime.now()) ? ' · Agendado' : ''}',
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              tooltip: 'Compras cobertas',
              onPressed: _acting ? null : () => _coverage(p),
              icon: const Icon(Icons.checklist)),
          IconButton(
            tooltip: 'Desfazer pagamento',
            icon: const Icon(Icons.undo),
            onPressed: _acting
                ? null
                : () async {
                    if (await _confirm(
                          'Desfazer pagamento?',
                          'O débito sairá da conta e a dívida voltará à fatura. Encargos e desconto deste pagamento também serão desfeitos.',
                        ) &&
                        mounted) {
                      await _run(() => _repo.undoPayment(p.id));
                    }
                  },
          ),
        ]),
      );
  @override
  Widget build(BuildContext context) {
    final card = _card, invoice = _invoice;
    final referenceDetail = _detail &&
        somiaUsesMobileNavigation(context) &&
        MediaQuery.sizeOf(context).width < 600;
    final cashPayments = _invoices
        .expand((i) => i.payments)
        .where(
          (p) => p.date.year == _month.year && p.date.month == _month.month,
        )
        .toList();
    final cashPaid = cashPayments
        .where((p) => cardDay(p.date) <= cardDay(DateTime.now()))
        .fold(0, (a, p) => a + p.amountMinor);
    final cashScheduled = cashPayments
        .where((p) => cardDay(p.date) > cardDay(DateTime.now()))
        .fold(0, (a, p) => a + p.amountMinor);
    return Scaffold(
      appBar: referenceDetail
          ? AppBar(
              automaticallyImplyLeading: false,
              toolbarHeight: 64,
              titleSpacing: 16,
              title: const SomiaBrand(height: 30),
            )
          : AppBar(
              title: Text(_detail ? 'Detalhes do cartão' : 'Cartões'),
              leading: _detail
                  ? BackButton(onPressed: () => context.go(AppRoutes.cardsPath))
                  : somiaMenuLeading(context),
              actions: [
                IconButton(
                    tooltip: 'Cartões de débito',
                    onPressed: () => context.go(AppRoutes.debitCardsPath),
                    icon: const Icon(Icons.payment_outlined)),
                IconButton(
                    tooltip: 'Cashback',
                    onPressed: () => context.go(
                        '/cashback${_cardId == null ? '' : '?kind=credit&card=$_cardId'}'),
                    icon: const Icon(Icons.paid_outlined)),
                IconButton(
                  tooltip: 'Novo cartão',
                  onPressed: _loading || _acting ? null : () => _editCard(),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
      floatingActionButton:
          somiaUsesMobileNavigation(context) ? null : const SomiaQuickActions(),
      body: _loading && _cards.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: TextButton(
                    onPressed: _load,
                    child: Text('$_error Tentar novamente'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                    children: [
                      if (referenceDetail) ...[
                        Row(children: [
                          BackButton(
                              onPressed: () => context.go(AppRoutes.cardsPath)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              card == null
                                  ? 'Cartão'
                                  : card.name.toLowerCase().startsWith('cartão')
                                      ? card.name
                                      : 'Cartão ${card.name}',
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (card != null)
                            _cardMenu(card, detailActions: true),
                        ]),
                        const SizedBox(height: 4),
                        MonthSelector(
                          month: _month,
                          centered: true,
                          onChanged: referenceMonth.select,
                        ),
                        const SizedBox(height: 12),
                      ] else
                        Center(
                          child: MonthSelector(
                            month: _month,
                            onChanged: referenceMonth.select,
                          ),
                        ),
                      if (_loading || _acting) const LinearProgressIndicator(),
                      if (_cards.isEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            'Cadastre seu primeiro cartão para acompanhar compras, limite e faturas.',
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () => _editCard(),
                          icon: const Icon(Icons.credit_card),
                          label: const Text('Cadastrar cartão'),
                        ),
                      ],
                      if (!_detail)
                        for (final c in _cards) _cardTile(c),
                      if (_detail && card == null)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Cartão não encontrado. Volte à lista de cartões.',
                          ),
                        ),
                      if (_detail && card != null && invoice != null) ...[
                        if (_bulkMode &&
                            getIt.isRegistered<MovementManagementRepository>())
                          BulkMovementToolbar(
                            onCancel: _cancelBulk,
                            selection: _bulkSelection,
                            card: true,
                            available: invoice.entries
                                .where((entry) => entry.kind == 'purchase')
                                .map(
                                  (entry) => MovementReference(
                                    MovementKind.cardEntry,
                                    entry.id,
                                    entry.revision,
                                  ),
                                )
                                .toList(),
                            onSelection: (selection) =>
                                setState(() => _bulkSelection = selection),
                            onCompleted: () async {
                              _cancelBulk();
                              await _load();
                            },
                          ),
                        if (referenceDetail)
                          _referenceSummary(card, invoice)
                        else
                          _cardSummary(card, invoice),
                        const SizedBox(height: 16),
                        if (referenceDetail)
                          _referenceTabs()
                        else ...[
                          Text(
                            '${card.name} · ${cardMonthLabel(invoice.month)}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('Competência / fatura'),
                                selected: !_cash && !_statement,
                                onSelected: (_) => setState(() {
                                  _bulkMode = false;
                                  _bulkSelection = {};
                                  _cash = false;
                                  _statement = false;
                                }),
                              ),
                              ChoiceChip(
                                label: const Text('Extrato'),
                                selected: _statement,
                                onSelected: (_) => setState(() {
                                  _bulkMode = false;
                                  _bulkSelection = {};
                                  _statement = true;
                                  _cash = false;
                                }),
                              ),
                              ChoiceChip(
                                label: const Text('Caixa / pagamentos'),
                                selected: _cash,
                                onSelected: (_) => setState(() {
                                  _bulkMode = false;
                                  _bulkSelection = {};
                                  _cash = true;
                                  _statement = false;
                                }),
                              ),
                            ],
                          ),
                        ],
                        if (referenceDetail) const SizedBox(height: 12),
                        if (_statement)
                          ..._dailyStatement(invoice)
                        else if (_cash) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Débitos reais da conta no mês escolhido, mesmo que o pagamento pertença a outra fatura.',
                          ),
                          _metric('Pago no mês', cashPaid),
                          _metric('Agendado no mês', cashScheduled),
                          for (final p in cashPayments) _paymentTile(p),
                          if (cashPayments.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Nenhum pagamento neste mês.'),
                            ),
                        ] else ...[
                          if (referenceDetail)
                            _referenceInvoice(invoice)
                          else
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      invoice.status,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    Text(
                                      'Fecha ${cardDateLabel(invoice.closingAt)} · Vence ${cardDateLabel(invoice.dueAt)}',
                                    ),
                                    _metric(
                                      invoice.previousMinor < 0
                                          ? 'Crédito anterior'
                                          : 'Saldo da fatura anterior',
                                      invoice.previousMinor,
                                    ),
                                    _metric(
                                        'Fatura do mês', invoice.chargesMinor),
                                    _metric(
                                      'Pagamentos realizados',
                                      -invoice.paidMinor,
                                    ),
                                    const Divider(),
                                    _metric(
                                      invoice.balanceMinor < 0
                                          ? 'Saldo credor'
                                          : invoice.previousMinor != 0
                                              ? 'Total a pagar com saldo anterior'
                                              : 'Saldo a pagar',
                                      invoice.balanceMinor,
                                    ),
                                    if (invoice.scheduledMinor > 0) ...[
                                      _metric(
                                        'Pagamentos agendados',
                                        -invoice.scheduledMinor,
                                      ),
                                      _metric(
                                        'Após agendamentos',
                                        invoice.projectedMinor,
                                      ),
                                    ],
                                    if (invoice.balanceMinor > 0)
                                      const Text(
                                        'O saldo não pago segue para a próxima fatura, mantendo o histórico. Juros e multas são informados no pagamento.',
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          if (referenceDetail) const SizedBox(height: 24),
                          if (referenceDetail)
                            _referenceActions(card)
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: _acting ? null : _pay,
                                  icon: const Icon(Icons.payments_outlined),
                                  label: const Text('Pagar fatura'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _acting || card.isArchived
                                      ? null
                                      : () => _buy(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Nova compra'),
                                ),
                                OutlinedButton(
                                  onPressed: _acting ? null : _anticipate,
                                  child: const Text('Antecipar parcelas'),
                                ),
                                OutlinedButton(
                                  onPressed: _acting ? null : _dates,
                                  child: const Text('Ajustar datas'),
                                ),
                                OutlinedButton(
                                  onPressed: _acting ? null : _opening,
                                  child: const Text('Saldo inicial'),
                                ),
                              ],
                            ),
                          const SizedBox(height: 20),
                          Text(
                            'Itens da fatura',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          for (final e in invoice.entries)
                            _entryTile(e, cardStyle: referenceDetail),
                          if (invoice.entries.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Nenhum item nesta fatura.'),
                            ),
                          const Divider(),
                          Text(
                            'Pagamentos',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          for (final p in invoice.payments) _paymentTile(p),
                          if (invoice.payments.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Nenhum pagamento registrado.'),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            referenceDetail ? 'Faturas' : 'Próximas faturas',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (referenceDetail)
                            _invoicesChart(_invoices, invoice.month)
                          else
                            for (final i in _invoices.where(
                              (i) => i.month.isAfter(invoice.month),
                            ))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(cardMonthLabel(i.month)),
                                subtitle: Text(
                                  i.previousMinor == 0
                                      ? i.status
                                      : '${i.status} · anterior ${cardMoney(i.previousMinor)}',
                                ),
                                trailing: Text(cardMoney(i.chargesMinor)),
                                onTap: () => referenceMonth.select(i.month),
                              ),
                        ],
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _InvoiceGuidePainter extends CustomPainter {
  const _InvoiceGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SomiaColors.outline
      ..strokeWidth = 1;
    for (final y in [0.0, size.height / 2, size.height - 1]) {
      for (var x = 0.0; x < size.width; x += 9) {
        canvas.drawLine(
            Offset(x, y), Offset((x + 5).clamp(0, size.width), y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _InvoiceGuidePainter oldDelegate) => false;
}
