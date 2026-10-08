import '../../categories/presentation/category_visuals.dart';
import '../../../core/widgets/compact_movement_field.dart';
import '../../../core/allocations/category_allocation.dart';
import '../../../core/allocations/allocation_editor.dart';
import '../data/category_history_repository.dart';
import '../../cards/data/cards_repository.dart';
import '../../cards/domain/credit_card.dart';
import '../../../core/series/movement_series.dart';
import '../../../core/series/series_form.dart';
import '../../accounts/presentation/account_identity.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/movement_form_frame.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../../core/widgets/movement_list_row.dart';
import '../../../core/widgets/effectuation_feedback.dart';
import '../../../core/widgets/monetary_calculator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/filters/reference_month.dart';
import '../../../core/widgets/month_selector.dart';
import '../../../core/routing/somia_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/effectuation_date_dialog.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../accounts/domain/money_minor.dart';
import '../../categories/domain/categories_repository.dart';
import '../../categories/domain/category.dart';
import '../domain/financial_transaction.dart';
import '../domain/transactions_repository.dart';
import 'transactions_cubit.dart';

String _dateLabel(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

class TransactionsPage extends StatelessWidget {
  const TransactionsPage({super.key, this.initialCreateType, this.sectionType});
  final String? initialCreateType;
  final TransactionType? sectionType;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => TransactionsCubit(getIt<TransactionsRepository>(),
            getIt<AccountsRepository>(), getIt<CategoriesRepository>(),
            sectionType: sectionType, month: referenceMonth.value),
        child: _TransactionsView(
            initialCreateType: initialCreateType, sectionType: sectionType),
      );
}

class _TransactionsView extends StatefulWidget {
  const _TransactionsView({this.initialCreateType, this.sectionType});
  final String? initialCreateType;
  final TransactionType? sectionType;

  @override
  State<_TransactionsView> createState() => _TransactionsViewState();
}

class _TransactionsViewState extends State<_TransactionsView> {
  bool _openedInitial = false;
  final Set<String> _changingStatus = {};
  TransactionType? _type;
  String? _accountId;
  String? _categoryId;
  String? _subcategoryId;
  TransactionStatus _status = TransactionStatus.all;
  TransactionDateField _dateField = TransactionDateField.due;
  DateTimeRange? _range;
  bool _customPeriod = false;
  VoidCallback? _refreshFilters;
  DateTimeRange get _monthRange => DateTimeRange(
      start: referenceMonth.value,
      end: DateTime(
          referenceMonth.value.year, referenceMonth.value.month + 1, 0));

  void _monthChanged() {
    setState(() {
      _range = _monthRange;
      _customPeriod = false;
    });
    _apply();
  }

  @override
  void dispose() {
    referenceMonth.removeListener(_monthChanged);
    super.dispose();
  }

  Future<void> _openFilters(TransactionsState state) async {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => StatefulBuilder(builder: (sheet, refresh) {
              _refreshFilters = () {
                if (sheet.mounted) refresh(() {});
              };
              return SafeArea(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Row(children: [
                          const Expanded(
                              child: Text('Filtros',
                                  style: TextStyle(fontSize: 20))),
                          TextButton(
                              onPressed: () {
                                setState(() {
                                  _type = widget.sectionType;
                                  _accountId = null;
                                  _categoryId = null;
                                  _subcategoryId = null;
                                  _status = TransactionStatus.all;
                                  _dateField = TransactionDateField.due;
                                  _range = _monthRange;
                                  _customPeriod = false;
                                });
                                _apply();
                              },
                              child: const Text('Limpar filtros')),
                          IconButton(
                              tooltip: 'Fechar filtros',
                              onPressed: () => Navigator.pop(sheet),
                              icon: const Icon(Icons.close)),
                        ]),
                        _filters(state),
                        TextButton(
                            onPressed: () {
                              setState(() {
                                _range = null;
                                _customPeriod = true;
                              });
                              _apply();
                            },
                            child: const Text('Todos os meses')),
                      ])));
            }));
    _refreshFilters = null;
  }

  @override
  void initState() {
    super.initState();
    _type = widget.sectionType;
    _range = _monthRange;
    referenceMonth.addListener(_monthChanged);
  }

  String get _sectionPath => widget.sectionType == TransactionType.income
      ? '/income'
      : widget.sectionType == TransactionType.expense
          ? '/expenses'
          : '/transactions';

  void _apply() {
    _refreshFilters?.call();
    context.read<TransactionsCubit>().load(TransactionFilter(
          type: _type,
          accountId: _accountId,
          categoryId: _subcategoryId ?? _categoryId,
          status: _status,
          from: _range?.start,
          to: _range?.end,
          dateField: _dateField,
        ));
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: _range ??
          DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
    );
    if (picked != null && mounted) {
      setState(() {
        _range = picked;
        _customPeriod = true;
      });
      _apply();
    }
  }

  Future<void> _edit([FinancialTransaction? item]) async {
    final scope = item?.series == null
        ? SeriesScope.onlyThis
        : await chooseSeriesScope(context, deleting: false);
    if (scope == null || !mounted) return;
    final cubit = context.read<TransactionsCubit>();
    final state = cubit.state;
    final cards = getIt.isRegistered<CardsRepository>()
        ? await getIt<CardsRepository>().list()
        : <CreditCard>[];
    if (!mounted) return;
    final draft = await showMovementForm<TransactionDraft>(
      context,
      (_) => TransactionForm(
          item: item,
          scope: scope,
          fixedType: widget.sectionType,
          initialType: (widget.sectionType == TransactionType.income ||
                  widget.initialCreateType == 'income')
              ? TransactionType.income
              : TransactionType.expense,
          cards: cards,
          accounts: state.accounts,
          categories: state.categories),
    );
    if (!mounted) return;
    if (draft == null) {
      if (item == null && widget.initialCreateType != null) {
        context.go(_sectionPath);
      }
      return;
    }
    try {
      await cubit.save(draft, id: item?.id);
    } catch (error) {
      if (mounted) _showError(error);
    }
    if (mounted && item == null && widget.initialCreateType != null) {
      context.go(_sectionPath);
    }
  }

  Future<void> _delete(FinancialTransaction item) async {
    final scope = item.series == null
        ? SeriesScope.onlyThis
        : await chooseSeriesScope(context, deleting: true);
    if (scope == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: Text(scope == SeriesScope.thisAndNext
            ? 'As ocorrências pendentes desta posição em diante sairão da lista e das projeções.'
            : '“${item.description}” sairá da lista e dos saldos.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<TransactionsCubit>().delete(item.id, scope: scope);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _markPending(FinancialTransaction item) async {
    if (item.effectiveDate == null) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await _changeDate(item.id, item.effectiveDate!);
  }

  Future<void> _editAmount(FinancialTransaction item) async {
    if (!mounted || _changingStatus.contains(item.id)) return;
    setState(() => _changingStatus.add(item.id));
    try {
      final amount = await showMonetaryCalculator(context,
          initialMinor: item.amountMinor,
          currencyCode: item.currencyCode,
          minimumMinor: 1);
      if (!mounted || amount == null || amount == item.amountMinor) return;
      final scope = item.series == null
          ? SeriesScope.onlyThis
          : await chooseSeriesScope(context, deleting: false);
      if (scope == null || !mounted) return;
      await context.read<TransactionsCubit>().updateAmount(item.id,
          expectedAmountMinor: item.amountMinor,
          amountMinor: amount,
          scope: scope);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _changingStatus.remove(item.id));
    }
  }

  Future<void> _quickEffective(FinancialTransaction item) async {
    if (!mounted || item.isEffective || _changingStatus.contains(item.id)) {
      return;
    }
    setState(() => _changingStatus.add(item.id));
    final today = DateUtils.dateOnly(DateTime.now());
    try {
      await context
          .read<TransactionsCubit>()
          .setEffective(item.id, effective: true, effectiveDate: today);
      if (!mounted) return;
      showEffectuationFeedback(context,
          message: item.type == TransactionType.income
              ? 'Receita recebida hoje.'
              : 'Despesa paga hoje.',
          undo: () => _changeDate(item.id, today, restore: item.effectiveDate),
          adjustDate: () => _changeDate(item.id, today, pick: true));
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _changingStatus.remove(item.id));
    }
  }

  Future<void> _changeDate(String id, DateTime expected,
      {DateTime? restore, bool pick = false}) async {
    if (!mounted || _changingStatus.contains(id)) return;
    setState(() => _changingStatus.add(id));
    try {
      final chosen = pick
          ? await showDatePicker(
              context: context,
              initialDate: expected,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100, 12, 31))
          : restore;
      if (!mounted || (pick && chosen == null)) return;
      await context.read<TransactionsCubit>().changeEffectiveDate(id,
          expectedDate: expected, effectiveDate: chosen);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _changingStatus.remove(id));
    }
  }

  void _showError(Object error) {
    final message = error is FormatException
        ? error.message
        : error is StateError
            ? error.message
            : 'Não foi possível salvar o lançamento.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.sectionType == TransactionType.income
              ? 'Receitas'
              : widget.sectionType == TransactionType.expense
                  ? 'Despesas'
                  : 'Lançamentos'),
          leading: somiaMenuLeading(context),
        ),
        floatingActionButton: const SomiaQuickActions(),
        body: BlocConsumer<TransactionsCubit, TransactionsState>(
          listener: (context, state) {
            if (!_openedInitial &&
                !state.loading &&
                state.error == null &&
                (widget.initialCreateType == 'income' ||
                    widget.initialCreateType == 'expense')) {
              _openedInitial = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _edit();
              });
            }
          },
          builder: (context, state) {
            if (state.loading &&
                state.accounts.isEmpty &&
                state.items.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.error != null) {
              return Center(
                  child: TextButton(
                onPressed: context.read<TransactionsCubit>().load,
                child: Text('${state.error} Tentar novamente'),
              ));
            }
            return Column(children: [
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        MonthSelector(
                            month: referenceMonth.value,
                            onChanged: (month) {
                              if (month == referenceMonth.value) {
                                _monthChanged();
                              } else {
                                referenceMonth.select(month);
                              }
                            }),
                        OutlinedButton.icon(
                            onPressed: () => _openFilters(state),
                            icon: const Icon(Icons.tune),
                            label: const Text('Filtros')),
                        if (_customPeriod)
                          Text(_range == null
                              ? 'Todos os meses'
                              : '${_dateLabel(_range!.start)} – ${_dateLabel(_range!.end)}'),
                      ])),
              Expanded(
                  child: state.items.isEmpty
                      ? Center(
                          child: Text(widget.sectionType ==
                                  TransactionType.income
                              ? 'Nenhuma receita para estes filtros.'
                              : widget.sectionType == TransactionType.expense
                                  ? 'Nenhuma despesa para estes filtros.'
                                  : 'Nenhum lançamento para estes filtros.'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                          itemCount: state.items.length,
                          itemBuilder: (context, index) =>
                              _itemTile(state.items[index]),
                        )),
            ]);
          },
        ),
      );

  Widget _filters(TransactionsState state) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.60),
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.sectionType == null) ...[
                  ChoiceChip(
                      label: const Text('Todos'),
                      selected: _type == null,
                      onSelected: (_) {
                        setState(() {
                          _type = null;
                          _categoryId = null;
                          _subcategoryId = null;
                        });
                        _apply();
                      }),
                  for (final type in TransactionType.values)
                    ChoiceChip(
                        label: Text(type.label),
                        selected: _type == type,
                        onSelected: (_) {
                          setState(() {
                            _type = type;
                            _categoryId = null;
                            _subcategoryId = null;
                          });
                          _apply();
                        }),
                ],
                SizedBox(
                    width: 220,
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _accountId ?? '',
                      hint: const Text('Conta'),
                      items: [
                        const DropdownMenuItem(
                            value: '', child: Text('Todas as contas')),
                        for (final account in state.accounts)
                          DropdownMenuItem(
                              value: account.id,
                              child: AccountOption(account: account))
                      ],
                      onChanged: (id) {
                        setState(() => _accountId = id == '' ? null : id);
                        _apply();
                      },
                    )),
                SizedBox(
                    width: 220,
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _categoryId ?? '',
                      hint: const Text('Categoria'),
                      items: [
                        const DropdownMenuItem(
                            value: '', child: Text('Todas as categorias')),
                        for (final category in state.categories.where((c) =>
                            c.parentId == null &&
                            (_type == null || c.type.name == _type!.name)))
                          DropdownMenuItem(
                              value: category.id,
                              child: Text(category.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: (id) {
                        setState(() {
                          _categoryId = id == '' ? null : id;
                          _subcategoryId = null;
                        });
                        _apply();
                      },
                    )),
                SizedBox(
                    width: 220,
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _subcategoryId ?? '',
                      hint: const Text('Subcategoria'),
                      items: [
                        const DropdownMenuItem(
                            value: '', child: Text('Todas as subcategorias')),
                        for (final category in state.categories.where((c) =>
                            c.parentId == _categoryId && _categoryId != null))
                          DropdownMenuItem(
                              value: category.id,
                              child: Text(category.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: _categoryId == null
                          ? null
                          : (id) {
                              setState(
                                  () => _subcategoryId = id == '' ? null : id);
                              _apply();
                            },
                    )),
                SizedBox(
                    width: 220,
                    child: DropdownButton<TransactionStatus>(
                      isExpanded: true,
                      value: _status,
                      items: const [
                        DropdownMenuItem(
                            value: TransactionStatus.all,
                            child: Text('Todos os estados')),
                        DropdownMenuItem(
                            value: TransactionStatus.effective,
                            child: Text('Efetivados')),
                        DropdownMenuItem(
                            value: TransactionStatus.pending,
                            child: Text('Pendentes')),
                      ],
                      onChanged: (status) {
                        if (status != null) {
                          setState(() => _status = status);
                          _apply();
                        }
                      },
                    )),
                SizedBox(
                    width: 220,
                    child: DropdownButton<TransactionDateField>(
                      isExpanded: true,
                      value: _dateField,
                      items: const [
                        DropdownMenuItem(
                            value: TransactionDateField.posted,
                            child: Text('Filtrar lançamento')),
                        DropdownMenuItem(
                            value: TransactionDateField.due,
                            child: Text('Filtrar vencimento')),
                        DropdownMenuItem(
                            value: TransactionDateField.effective,
                            child: Text('Filtrar efetivação')),
                      ],
                      onChanged: (field) {
                        if (field != null) {
                          setState(() => _dateField = field);
                          _apply();
                        }
                      },
                    )),
                OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range),
                  label: Text(_range == null
                      ? 'Período'
                      : '${_dateLabel(_range!.start)} – ${_dateLabel(_range!.end)}'),
                ),
                if (_range != null)
                  IconButton(
                    tooltip: 'Limpar período',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        _range = _monthRange;
                        _customPeriod = false;
                      });
                      _apply();
                    },
                  ),
              ],
            )),
      );

  void _openInvoice(FinancialTransaction item) => context.go(
      '/cards?card=${item.cardId}&month=${item.cardInvoiceMonth!.toIso8601String()}');

  Future<void> _invoiceAction(String id, Future<void> Function() action) async {
    if (!mounted || _changingStatus.contains(id)) return;
    setState(() => _changingStatus.add(id));
    try {
      await action();
      if (mounted) await context.read<TransactionsCubit>().load();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _changingStatus.remove(id));
    }
  }

  Future<void> _quickInvoice(FinancialTransaction item) =>
      _invoiceAction(item.id, () async {
        if (item.cardPreviousMinor != 0) {
          _openInvoice(item);
          return;
        }
        final repo = getIt<CardsRepository>();
        final settlement = await repo.settleInvoice(item.cardInvoiceId!,
            expectedBalance: item.cardBalanceMinor,
            expectedScheduled: item.cardScheduledMinor,
            expectedSignature: item.cardPaymentSignature,
            expectedAccountId: item.accountId,
            date: DateUtils.dateOnly(DateTime.now()));
        if (!mounted) return;
        showEffectuationFeedback(context,
            message: 'Fatura paga hoje.',
            undo: () =>
                _invoiceAction(item.id, () => repo.undoSettlement(settlement)),
            adjustDate: () => _invoiceAction(item.id, () async {
                  final date = await showDatePicker(
                      context: context,
                      initialDate: settlement.date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100, 12, 31));
                  if (date != null) {
                    await repo.changeSettlementDate(settlement, date);
                  }
                }));
      });

  Future<void> _undoInvoice(FinancialTransaction item) =>
      _invoiceAction(item.id, () async {
        final repo = getIt<CardsRepository>();
        final bill = await repo.invoice(item.cardInvoiceId!);
        if (!mounted) return;
        if (CardsRepository.paymentSignature(bill) !=
            item.cardPaymentSignature) {
          throw StateError(
              'A fatura mudou. Atualize a lista antes de desfazer.');
        }
        final payment =
            bill.payments.firstWhere((p) => p.id == item.cardLastPaymentId);
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
                  title: const Text('Desfazer último pagamento?'),
                  content: Text(
                      'O pagamento de ${MoneyMinor.display(payment.amountMinor, 'BRL')} em ${_dateLabel(payment.date)}, pela conta ${payment.accountName}, será removido. Os pagamentos anteriores serão preservados.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: const Text('Desfazer')),
                  ],
                ));
        if (confirmed == true) {
          await repo.undoInvoicePayment(
              bill.id, payment.id, item.cardPaymentSignature);
        }
      });

  Widget _invoiceTile(FinancialTransaction item) {
    final busy = _changingStatus.contains(item.id);
    final canUndo = item.isEffective && item.cardLastPaymentId != null;
    return MovementListRow(
        id: item.id,
        description: item.description,
        account: item.accountName,
        amount: '-${MoneyMinor.display(item.amountMinor, 'BRL')}',
        dueDate: item.dueDate!,
        effectiveDate: item.effectiveDate,
        effective: item.isEffective,
        busy: busy,
        color: SomiaColors.red,
        effectiveLabel: 'Pagar fatura hoje',
        pendingIcon: Icons.schedule,
        highlightLabel:
            'Fecha dia ${item.date.day.toString().padLeft(2, '0')}/${const [
          'jan',
          'fev',
          'mar',
          'abr',
          'mai',
          'jun',
          'jul',
          'ago',
          'set',
          'out',
          'nov',
          'dez'
        ][item.date.month - 1]}.',
        pendingLabel: 'Desfazer último pagamento',
        tags: [
          if (_categoryId != null || _subcategoryId != null) 'Fatura completa',
          if (item.cardPreviousMinor != 0)
            'Anterior ${MoneyMinor.display(item.cardPreviousMinor, 'BRL')}',
          if (!item.isEffective && item.cardBalanceMinor != item.amountMinor)
            '${item.cardPreviousMinor != 0 ? 'Total em aberto' : 'Restante'} ${MoneyMinor.display(item.cardBalanceMinor, 'BRL')}',
          if (item.cardScheduledMinor > 0)
            'Agendado ${MoneyMinor.display(item.cardScheduledMinor, 'BRL')}',
          if (item.cardBalanceMinor < 0)
            'Crédito ${MoneyMinor.display(-item.cardBalanceMinor, 'BRL')}',
        ],
        onEdit: () => _openInvoice(item),
        onAmount: () => _openInvoice(item),
        onEffective: () => _quickInvoice(item),
        onPending: canUndo ? () => _undoInvoice(item) : null,
        menu: PopupMenuButton<String>(
            key: ValueKey('movement-menu-${item.id}'),
            enabled: !busy,
            tooltip: 'Ações da fatura',
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (action) {
              if (action == 'open') _openInvoice(item);
              if (action == 'pay') _quickInvoice(item);
              if (action == 'undo') _undoInvoice(item);
            },
            itemBuilder: (_) => [
                  const PopupMenuItem(value: 'open', child: Text('Ver fatura')),
                  if (!item.isEffective)
                    const PopupMenuItem(
                        value: 'pay', child: Text('Pagar fatura hoje')),
                  if (canUndo)
                    const PopupMenuItem(
                        value: 'undo',
                        child: Text('Desfazer último pagamento')),
                ]));
  }

  Widget _itemTile(FinancialTransaction item) {
    if (item.cardInvoiceId != null) return _invoiceTile(item);
    final categories = context.read<TransactionsCubit>().state.categories;
    final category =
        categories.where((c) => c.id == item.categoryId).firstOrNull;
    final parent =
        categories.where((c) => c.id == category?.parentId).firstOrNull;
    final busy = _changingStatus.contains(item.id);
    return MovementListRow(
      id: item.id,
      description: item.description,
      account: item.accountName,
      amount:
          '${item.type == TransactionType.income ? '+' : '-'}${MoneyMinor.display(item.amountMinor, item.currencyCode)}',
      dueDate: item.dueDate ?? item.date,
      effectiveDate: item.effectiveDate,
      effective: item.isEffective,
      busy: busy,
      color: item.type == TransactionType.income
          ? SomiaColors.green
          : SomiaColors.red,
      effectiveLabel: item.cardId != null
          ? 'Abrir fatura'
          : item.type == TransactionType.income
              ? 'Receber hoje'
              : 'Pagar hoje',
      tags: [
        if (item.cardId != null) 'Compra no cartão',
        if (item.series != null) item.series!.label,
        if (item.allocations.isNotEmpty)
          'Rateio · ${item.allocations.length} categorias',
      ],
      categoryTags: [
        if (parent != null)
          MovementTag(parent.name, categoryDisplayColor(parent)),
        if (category != null)
          MovementTag(category.name, categoryDisplayColor(category))
      ],
      onEffective: () {
        if (item.cardId != null) {
          context.go(
              '/cards?card=${item.cardId}&month=${item.cardInvoiceMonth!.toIso8601String()}');
        } else {
          _quickEffective(item);
        }
      },
      onPending: () => _markPending(item),
      onAmount: () => _editAmount(item),
      onEdit: () => _edit(item),
      menu: PopupMenuButton<String>(
        key: ValueKey('movement-menu-${item.id}'),
        enabled: !busy,
        tooltip: 'Ações do lançamento',
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (action) {
          if (action == 'edit') _edit(item);
          if (action == 'delete') _delete(item);
          if (action == 'pending') _markPending(item);
          if (action == 'date' && item.effectiveDate != null) {
            _changeDate(item.id, item.effectiveDate!, pick: true);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Editar')),
          if (item.effectiveDate != null) ...[
            const PopupMenuItem(value: 'date', child: Text('Ajustar data')),
            const PopupMenuItem(
                value: 'pending', child: Text('Marcar como pendente')),
          ],
          const PopupMenuItem(value: 'delete', child: Text('Excluir')),
        ],
      ),
    );
  }
}

class TransactionForm extends StatefulWidget {
  const TransactionForm(
      {super.key,
      required this.accounts,
      required this.categories,
      this.cards = const [],
      this.initialCardId,
      this.item,
      this.scope = SeriesScope.onlyThis,
      this.fixedType,
      this.initialType = TransactionType.expense});
  final FinancialTransaction? item;
  final SeriesScope scope;
  final TransactionType? fixedType;
  final TransactionType initialType;
  final String? initialCardId;
  final List<CreditCard> cards;
  final List<Account> accounts;
  final List<FinanceCategory> categories;

  @override
  State<TransactionForm> createState() => TransactionFormState();
}

class TransactionFormState extends State<TransactionForm> {
  final _formKey = GlobalKey<FormState>();
  final _series = SeriesFormController();
  bool get _forcePending =>
      _cardId != null ||
      _series.active ||
      widget.scope == SeriesScope.thisAndNext;
  void _seriesChanged() {
    if (mounted) setState(() {});
  }

  late final TextEditingController _description;
  late final TextEditingController _amount;
  final _descriptionFocus = FocusNode();
  final _amountFocus = FocusNode();
  late TransactionType _type;
  late DateTime _date;
  late DateTime _dueDate;
  DateTime? _effectiveDate;
  late bool _isEffective;
  String? _accountId;
  String? _cardId;
  DateTime? _cardMonth;
  final _firstInstallment = TextEditingController(text: '1');
  String? _categoryId;
  String? _subcategoryId;
  bool _rateioEnabled = false;
  List<CategoryAllocation> _allocations = [];
  void _amountChanged() {
    if (mounted) setState(() {});
  }

  bool _categoryChosenManually = false;
  bool _categoryFromHistory = false;
  Map<String, String> _categoryHistory = {};
  List<HistorySuggestion> _historySuggestions = [];
  final Set<String> _hiddenSuggestions = {};
  bool _showSuggestions = false;
  int _historyRequest = 0;

  void _descriptionChanged() {
    _applyCategoryHistory();
    if (mounted && widget.item == null) {
      setState(() => _showSuggestions = true);
    }
  }

  List<HistorySuggestion> get _matchingSuggestions {
    final query = CategoryHistoryRepository.normalize(_description.text);
    if (!_showSuggestions || query.isEmpty || widget.item != null) {
      return [];
    }
    return _historySuggestions
        .where((s) =>
            !_hiddenSuggestions.contains(s.id) &&
            (widget.initialCardId == null || s.cardId != null) &&
            CategoryHistoryRepository.normalize(s.description).contains(query))
        .take(8)
        .toList();
  }

  void _selectSuggestion(HistorySuggestion suggestion) {
    final account = widget.accounts
        .where((a) => a.id == suggestion.accountId && !a.isArchived)
        .firstOrNull;
    final card = widget.cards
        .where((c) => c.id == suggestion.cardId && !c.isArchived)
        .firstOrNull;
    if (account == null || (suggestion.cardId != null && card == null)) {
      return;
    }
    _categoryChosenManually = true;
    _description.text = suggestion.description;
    _amount.text = MoneyMinor.plain(suggestion.amountMinor);
    final category = widget.categories
        .where((c) =>
            c.id == suggestion.categoryId &&
            !c.isArchived &&
            c.type.name == _type.name)
        .firstOrNull;
    final parent = category?.parentId == null
        ? category
        : widget.categories
            .where((c) => c.id == category!.parentId && !c.isArchived)
            .firstOrNull;
    setState(() {
      _accountId = account.id;
      _cardId = card?.id;
      _cardMonth = null;
      _categoryId = parent?.id;
      _subcategoryId =
          parent != null && category?.parentId != null ? category?.id : null;
      _categoryFromHistory = parent != null;
      _showSuggestions = false;
      if (card != null) {
        _series.change(() {
          if (_series.kind == SeriesKind.recurring) {
            _series.kind = SeriesKind.single;
          }
          _series.unit = SeriesUnit.month;
          _series.interval.text = '1';
        });
      }
    });
    _descriptionFocus.unfocus();
  }

  Widget _suggestionsPanel() => Material(
      color: SomiaColors.surfaceHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView.builder(
              shrinkWrap: true,
              primary: false,
              itemCount: _matchingSuggestions.length,
              itemBuilder: (_, index) {
                final suggestion = _matchingSuggestions[index];
                return ListTile(
                    key: ValueKey('history-suggestion-${suggestion.id}'),
                    leading: Icon(
                        suggestion.cardId == null
                            ? Icons.history
                            : Icons.credit_card,
                        color: _type == TransactionType.income
                            ? SomiaColors.green
                            : SomiaColors.red),
                    title: Text(suggestion.description,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(suggestion.accountName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: SizedBox(
                        width: 140,
                        child: Row(children: [
                          Expanded(
                              child: Text(
                                  MoneyMinor.display(suggestion.amountMinor,
                                      suggestion.currencyCode),
                                  textAlign: TextAlign.right,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis)),
                          IconButton(
                              tooltip: 'Ocultar sugestão',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(
                                  () => _hiddenSuggestions.add(suggestion.id)))
                        ])),
                    onTap: () => _selectSuggestion(suggestion));
              })));

  Future<void>? _historyLoading;

  Future<void> _loadCategoryHistory() async {
    if (widget.item != null ||
        !getIt.isRegistered<CategoryHistoryRepository>()) {
      return;
    }
    final request = ++_historyRequest;
    final type = _type;
    try {
      final history = await getIt<CategoryHistoryRepository>().load(type);
      if (!mounted || request != _historyRequest || type != _type) {
        return;
      }
      _categoryHistory = history;
      _applyCategoryHistory();
      final suggestions =
          await getIt<CategoryHistoryRepository>().suggestions(type);
      if (!mounted || request != _historyRequest || type != _type) {
        return;
      }
      setState(() => _historySuggestions = suggestions);
    } catch (_) {
      // A sugestão é opcional; o cadastro manual continua disponível.
    }
  }

  void _applyCategoryHistory() {
    if (!mounted || widget.item != null || _categoryChosenManually) {
      return;
    }
    final id = _categoryHistory[
        CategoryHistoryRepository.normalize(_description.text)];
    final category = widget.categories
        .where((c) => c.id == id && !c.isArchived && c.type.name == _type.name)
        .firstOrNull;
    final parent = category?.parentId == null
        ? category
        : widget.categories
            .where((c) =>
                c.id == category!.parentId &&
                c.parentId == null &&
                !c.isArchived &&
                c.type.name == _type.name)
            .firstOrNull;
    final rootId = parent?.id;
    final childId =
        parent != null && category?.parentId != null ? category?.id : null;
    if (_categoryId == rootId &&
        _subcategoryId == childId &&
        _categoryFromHistory == (rootId != null)) {
      return;
    }
    setState(() {
      _categoryId = rootId;
      _subcategoryId = childId;
      _categoryFromHistory = rootId != null;
    });
  }

  @override
  void initState() {
    super.initState();
    _series.addListener(_seriesChanged);
    final item = widget.item;
    _description = TextEditingController(text: item?.description ?? '');
    _amount =
        TextEditingController(text: MoneyMinor.plain(item?.amountMinor ?? 0));
    _allocations = List.of(item?.allocations ?? const []);
    _rateioEnabled = _allocations.isNotEmpty;
    _amount.addListener(_amountChanged);
    _type = item?.type ?? widget.initialType;
    _date = item?.date ?? DateTime.now();
    _dueDate = item?.dueDate ?? _date;
    _effectiveDate = item?.effectiveDate;
    _isEffective = item == null || item.effectiveDate != null;
    _cardId = item?.cardId ?? widget.initialCardId;
    _cardMonth = item?.cardInvoiceMonth;
    _accountId = item?.cardId == null
        ? item?.accountId ?? _availableAccounts.firstOrNull?.id
        : _availableAccounts.firstOrNull?.id;
    final selected = widget.categories
        .where((category) => category.id == item?.categoryId)
        .firstOrNull;
    _categoryId = selected?.parentId ?? selected?.id;
    _subcategoryId = selected?.parentId == null ? null : selected?.id;
    _description.addListener(_descriptionChanged);
    _historyLoading = _loadCategoryHistory();
  }

  List<Account> get _availableAccounts => widget.accounts
      .where((account) =>
          !account.isArchived || account.id == widget.item?.accountId)
      .toList();

  @override
  void dispose() {
    _firstInstallment.dispose();
    _descriptionFocus.dispose();
    _amountFocus.dispose();
    _series.dispose();
    _description.removeListener(_descriptionChanged);
    _description.dispose();
    _amount.removeListener(_amountChanged);
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate(String field) async {
    final picked = await showDatePicker(
        context: context,
        initialDate: field == 'posted'
            ? _date
            : field == 'due'
                ? _dueDate
                : _effectiveDate ??
                    (_type == TransactionType.expense
                        ? _dueDate
                        : DateTime.now()),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100, 12, 31));
    if (picked != null && mounted) {
      setState(() {
        if (field == 'posted') {
          _date = picked;
        } else if (field == 'due') {
          _dueDate = picked;
        } else {
          _effectiveDate = picked;
        }
      });
    }
  }

  CreditCard? get _selectedCard =>
      widget.cards.where((c) => c.id == _cardId).firstOrNull;
  DateTime get _invoiceMonth =>
      _cardMonth ??
      _selectedCard?.invoiceMonthFor(_date) ??
      DateTime(_date.year, _date.month);
  Future<void> _pickInvoiceMonth() async {
    final chosen = await showDatePicker(
        context: context,
        initialDate: _invoiceMonth,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100, 12, 31),
        helpText: 'Mês da fatura (vencimento)');
    if (chosen != null && mounted) {
      setState(() => _cardMonth = DateTime(chosen.year, chosen.month));
    }
  }

  Future<void> _submit() async {
    await _historyLoading;
    if (!mounted || !_formKey.currentState!.validate()) return;
    if (_series.active) {
      try {
        _series.plan!.amounts(MoneyMinor.parse(_amount.text));
        if (_series.plan!.dateAt(_date, _series.plan!.count - 1).year > 2100 ||
            _series.plan!.dateAt(_dueDate, _series.plan!.count - 1).year >
                2100) {
          throw const FormatException('A série deve terminar até o ano 2100.');
        }
      } on FormatException catch (error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
        return;
      }
    }
    if (_cardId != null && _selectedCard?.availableMinor != null) {
      final total = _series.plan
              ?.amounts(MoneyMinor.parse(_amount.text))
              .fold(0, (a, b) => a + b) ??
          MoneyMinor.parse(_amount.text);
      final extra =
          widget.item == null ? total : total - widget.item!.amountMinor;
      if (extra > _selectedCard!.availableMinor! + _selectedCard!.creditMinor) {
        final ok = await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
                    title: const Text('Limite disponível excedido'),
                    content: const Text(
                        'Esta compra ultrapassa o limite cadastrado. Deseja continuar?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog, false),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('Continuar'))
                    ]));
        if (ok != true || !mounted) return;
      }
    }
    final isEffective = !_forcePending && _isEffective;
    var effective = isEffective
        ? _effectiveDate ??
            (_type == TransactionType.expense ? _dueDate : DateTime.now())
        : null;
    if (isEffective &&
        _type != TransactionType.expense &&
        widget.item?.effectiveDate == null &&
        !DateUtils.isSameDay(_dueDate, DateTime.now())) {
      effective = await chooseEffectuationDate(context, _dueDate);
      if (effective == null || !mounted) return;
    }
    if (!mounted) return;
    Navigator.pop(
        context,
        TransactionDraft(
          description: _description.text.trim(),
          type: _type,
          amountMinor: MoneyMinor.parse(_amount.text),
          date: _date,
          dueDate: _dueDate,
          effectiveDate: effective,
          isEffective: isEffective,
          seriesPlan: _series.plan,
          scope: widget.scope,
          cardId: _cardId,
          cardInvoiceMonth: _cardMonth,
          cardFirstInstallment: int.tryParse(_firstInstallment.text) ?? 1,
          accountId: _cardId ?? _accountId!,
          allocations: _rateioEnabled ? _allocations : const [],
          categoryId: _rateioEnabled ? null : _subcategoryId ?? _categoryId,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final roots = widget.categories
        .where((category) =>
            category.parentId == null &&
            category.type.name == _type.name &&
            (!category.isArchived || category.id == _categoryId))
        .toList();
    final children = widget.categories
        .where((category) =>
            category.parentId == _categoryId &&
            _categoryId != null &&
            (!category.isArchived || category.id == _subcategoryId))
        .toList();
    final kind = _type == TransactionType.income ? 'receita' : 'despesa';
    return UnsavedChangesGuard(
        value: () => (
              _description.text,
              _amount.text,
              _type,
              _date,
              _dueDate,
              _effectiveDate,
              _isEffective,
              _accountId,
              _categoryId,
              _subcategoryId,
              _rateioEnabled,
              CategoryAllocation.encode(_allocations),
              _series.snapshot,
              _cardId,
              _cardMonth,
              _firstInstallment.text
            ),
        builder: (context, cancel) => MovementFormFrame(
              onCancel: cancel,
              compact: true,
              title: widget.item == null ? 'Nova $kind' : 'Editar $kind',
              onSave: _submit,
              child: Form(
                key: _formKey,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      TextFormField(
                          controller: _description,
                          focusNode: _descriptionFocus,
                          autofocus: widget.item == null &&
                              usesFullScreenMovementForm(context),
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) {
                            _amountFocus.requestFocus();
                            _amount.selection = TextSelection(
                                baseOffset: 0,
                                extentOffset: _amount.text.length);
                          },
                          scrollPadding: const EdgeInsets.all(100),
                          decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.notes_outlined),
                              labelText: 'Descrição',
                              helperText: _categoryFromHistory
                                  ? 'Categoria preenchida pelo histórico.'
                                  : null),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Informe a descrição.'
                                  : null),
                      if (_matchingSuggestions.isNotEmpty) _suggestionsPanel(),
                      MonetaryCalculatorField(
                          controller: _amount,
                          labelText: _series.kind == SeriesKind.installments
                              ? (_series.amountIsTotal
                                  ? 'Valor total'
                                  : 'Valor por parcela')
                              : 'Valor',
                          focusNode: _amountFocus,
                          currencyCode: _availableAccounts
                                  .where((a) => a.id == _accountId)
                                  .firstOrNull
                                  ?.currencyCode ??
                              'BRL'),
                      if (_type == TransactionType.expense &&
                          widget.initialCardId == null &&
                          widget.item == null &&
                          widget.cards.any((c) => !c.isArchived))
                        KeyedSubtree(
                            key: ValueKey('payment-kind-${_cardId != null}'),
                            child: DropdownButtonFormField<bool>(
                                menuMaxHeight: 280,
                                borderRadius: BorderRadius.circular(16),
                                itemHeight: 48,
                                key: const ValueKey('payment-method'),
                                initialValue: _cardId != null,
                                decoration: const InputDecoration(
                                    labelText: 'Forma de pagamento'),
                                items: const [
                                  DropdownMenuItem(
                                      value: false, child: Text('Conta')),
                                  DropdownMenuItem(
                                      value: true, child: Text('Cartão'))
                                ],
                                onChanged: (value) => setState(() {
                                      _cardId = value == true
                                          ? widget.cards
                                              .where((c) => !c.isArchived)
                                              .first
                                              .id
                                          : null;
                                      _cardMonth = null;
                                      _series.change(() {
                                        if (value == true) {
                                          if (_series.kind ==
                                              SeriesKind.recurring) {
                                            _series.kind = SeriesKind.single;
                                          }
                                          _series.unit = SeriesUnit.month;
                                          _series.interval.text = '1';
                                        }
                                      });
                                    }))),
                      if (_cardId != null) ...[
                        DropdownButtonFormField<String>(
                            menuMaxHeight: 280,
                            borderRadius: BorderRadius.circular(16),
                            itemHeight: 48,
                            key: ValueKey('card-choice-$_cardId'),
                            initialValue: _cardId,
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: 'Cartão'),
                            items: [
                              for (final card in widget.cards.where(
                                  (c) => !c.isArchived || c.id == _cardId))
                                DropdownMenuItem(
                                    value: card.id, child: Text(card.name))
                            ],
                            onChanged: widget.item != null
                                ? null
                                : (value) => setState(() {
                                      _cardId = value;
                                      _cardMonth = null;
                                    })),
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Fatura (mês do vencimento)'),
                            subtitle: Text(
                                '${_invoiceMonth.month.toString().padLeft(2, '0')}/${_invoiceMonth.year}${_cardMonth == null ? ' · Automática pelo fechamento' : ''}'),
                            trailing: IconButton(
                                tooltip: 'Voltar à fatura automática',
                                onPressed: () =>
                                    setState(() => _cardMonth = null),
                                icon: const Icon(Icons.restart_alt)),
                            onTap: _pickInvoiceMonth),
                      ],
                      if (_cardId == null)
                        DropdownButtonFormField<String>(
                          menuMaxHeight: 280,
                          borderRadius: BorderRadius.circular(16),
                          itemHeight: 48,
                          key: ValueKey('account-choice-$_accountId'),
                          isExpanded: true,
                          initialValue: _accountId,
                          decoration: const InputDecoration(labelText: 'Conta'),
                          items: _availableAccounts
                              .map((account) => DropdownMenuItem(
                                    value: account.id,
                                    child: AccountOption(account: account),
                                  ))
                              .toList(),
                          validator: (value) => value == null
                              ? 'Cadastre uma conta ativa.'
                              : null,
                          onChanged: (id) => setState(() => _accountId = id),
                        ),
                      if (!_rateioEnabled)
                        DropdownButtonFormField<String>(
                          menuMaxHeight: 280,
                          borderRadius: BorderRadius.circular(16),
                          itemHeight: 48,
                          isExpanded: true,
                          key: ValueKey('category-${_type.name}-$_categoryId'),
                          initialValue: _categoryId,
                          decoration:
                              const InputDecoration(labelText: 'Categoria'),
                          items: [
                            const DropdownMenuItem(
                                value: '', child: Text('Sem categoria')),
                            for (final category in roots)
                              DropdownMenuItem(
                                  value: category.id,
                                  child: Row(children: [
                                    Icon(Icons.label_outline,
                                        size: 18,
                                        color: categoryDisplayColor(category)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Text(
                                            '${category.name}${category.isArchived ? ' (arquivada)' : ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis))
                                  ]))
                          ],
                          onChanged: (id) => setState(() {
                            _categoryChosenManually = true;
                            _categoryFromHistory = false;
                            _categoryId = id == null || id.isEmpty ? null : id;
                            _subcategoryId = null;
                          }),
                        ),
                      if (!_rateioEnabled)
                        DropdownButtonFormField<String>(
                          menuMaxHeight: 280,
                          borderRadius: BorderRadius.circular(16),
                          itemHeight: 48,
                          isExpanded: true,
                          key: ValueKey(
                              'subcategory-${_type.name}-$_categoryId-$_subcategoryId'),
                          initialValue: _subcategoryId,
                          decoration:
                              const InputDecoration(labelText: 'Subcategoria'),
                          items: [
                            const DropdownMenuItem(
                                value: '', child: Text('Nenhuma')),
                            for (final category in children)
                              DropdownMenuItem(
                                  value: category.id,
                                  child: Row(children: [
                                    Icon(Icons.label_outline,
                                        size: 18,
                                        color: categoryDisplayColor(category)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Text(
                                            '${category.name}${category.isArchived ? ' (arquivada)' : ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis))
                                  ]))
                          ],
                          onChanged: _categoryId == null
                              ? null
                              : (id) => setState(() {
                                    _categoryChosenManually = true;
                                    _categoryFromHistory = false;
                                    _subcategoryId =
                                        id == null || id.isEmpty ? null : id;
                                  }),
                        ),
                      if (_cardId == null)
                        CompactMovementDate(
                            label: 'Vencimento',
                            date: _dueDate,
                            onTap: () => _pickDate('due')),
                      if (_cardId != null)
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Data da compra'),
                            subtitle: Text(_dateLabel(_date)),
                            trailing: const Icon(Icons.calendar_today),
                            onTap: () => _pickDate('posted')),
                      if (_cardId == null)
                        SwitchListTile(
                          title: Text(_type == TransactionType.income
                              ? 'Recebido'
                              : 'Pago'),
                          value: !_forcePending && _isEffective,
                          onChanged: _forcePending
                              ? null
                              : (value) => setState(() {
                                    _isEffective = value;
                                    if (value &&
                                        _type == TransactionType.expense) {
                                      _effectiveDate = null;
                                    }
                                  }),
                        ),
                      const Divider(),
                      ExpansionTile(
                        key: const ValueKey('transaction-more-options'),
                        title: const Text('Mais opções'),
                        tilePadding: EdgeInsets.zero,
                        maintainState: true,
                        initiallyExpanded:
                            _rateioEnabled || widget.item?.series != null,
                        children: [
                          if (!_forcePending && _isEffective)
                            CompactMovementDate(
                                label: 'Data de efetivação',
                                date: _effectiveDate ??
                                    (_type == TransactionType.expense
                                        ? _dueDate
                                        : DateTime.now()),
                                onTap: () => _pickDate('effective')),
                          if (widget.item == null ||
                              widget.item?.series != null)
                            SeriesFormFields(
                                key: ValueKey('series-card-${_cardId != null}'),
                                controller: _series,
                                amount: _amount,
                                dueDate: _cardId == null
                                    ? _dueDate
                                    : _selectedCard?.dueFor(_invoiceMonth) ??
                                        _dueDate,
                                currencyCode: _availableAccounts
                                        .where((a) => a.id == _accountId)
                                        .firstOrNull
                                        ?.currencyCode ??
                                    'BRL',
                                cardMode: _cardId != null,
                                existing: widget.item?.series),
                          if (_cardId != null && widget.item == null)
                            TextFormField(
                                controller: _firstInstallment,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                    labelText: 'Primeira parcela a cadastrar',
                                    helperText: _series.active
                                        ? 'Ex.: 4 para cadastrar apenas da 4ª em diante. A quantidade acima é a restante.'
                                        : 'Use 1 para compra à vista. Para apenas a última parcela, informe seu número.'),
                                validator: (v) {
                                  final n = int.tryParse(v ?? '');
                                  return n == null ||
                                          n < 1 ||
                                          n +
                                                  (_series.active
                                                      ? int.tryParse(_series
                                                              .count.text) ??
                                                          0
                                                      : 1) -
                                                  1 >
                                              1000
                                      ? 'Numeração entre 1 e 1000.'
                                      : null;
                                }),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Dividir entre categorias'),
                            value: _rateioEnabled,
                            onChanged: (v) => setState(() {
                              _rateioEnabled = v;
                              _categoryChosenManually = true;
                              if (!v) _allocations = [];
                            }),
                          ),
                          if (_rateioEnabled)
                            AllocationEditor(
                              key: ValueKey('allocation-$_type'),
                              categories: widget.categories,
                              type: _type.name,
                              currencyCode: _cardId != null
                                  ? 'BRL'
                                  : _availableAccounts
                                          .where((a) => a.id == _accountId)
                                          .firstOrNull
                                          ?.currencyCode ??
                                      'BRL',
                              total: MoneyMinor.parse(_amount.text),
                              initial: _allocations,
                              onChanged: (v) => _allocations = v,
                            ),
                          if (_cardId == null)
                            CompactMovementDate(
                                label: 'Lançamento',
                                date: _date,
                                onTap: () => _pickDate('posted')),
                          if (widget.fixedType == null)
                            ExpansionTile(
                              title: const Text('Mais detalhes'),
                              tilePadding: EdgeInsets.zero,
                              children: [
                                DropdownButtonFormField<TransactionType>(
                                  menuMaxHeight: 280,
                                  borderRadius: BorderRadius.circular(16),
                                  itemHeight: 48,
                                  isExpanded: true,
                                  initialValue: _type,
                                  decoration:
                                      const InputDecoration(labelText: 'Tipo'),
                                  items: TransactionType.values
                                      .map((type) => DropdownMenuItem(
                                          value: type, child: Text(type.label)))
                                      .toList(),
                                  onChanged: (type) {
                                    if (type != null) {
                                      setState(() {
                                        _type = type;
                                        _rateioEnabled = false;
                                        _allocations = [];
                                        if (type == TransactionType.income) {
                                          _cardId = null;
                                        }
                                        _categoryId = null;
                                        _subcategoryId = null;
                                        _categoryChosenManually = false;
                                        _categoryFromHistory = false;
                                        _categoryHistory = {};
                                        _historySuggestions = [];
                                        _showSuggestions = true;
                                      });
                                      _historyLoading = _loadCategoryHistory();
                                    }
                                  },
                                ),
                              ],
                            ),
                        ],
                      ),
                    ]),
              ),
            ));
  }
}
