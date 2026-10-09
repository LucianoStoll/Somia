import '../../attachments/presentation/attachments_page.dart';
import '../../transactions/data/movement_management_repository.dart';
import '../../transactions/domain/movement_management.dart';
import '../../transactions/presentation/bulk_movement_toolbar.dart';
import '../../../core/widgets/compact_movement_field.dart';
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
import '../domain/transfer.dart';
import '../domain/transfers_repository.dart';
import 'transfers_cubit.dart';

String _dateLabel(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

class TransfersPage extends StatelessWidget {
  const TransfersPage({super.key, this.startCreate = false});
  final bool startCreate;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => TransfersCubit(
            getIt<TransfersRepository>(), getIt<AccountsRepository>(),
            month: referenceMonth.value),
        child: _TransfersView(startCreate: startCreate),
      );
}

class _TransfersView extends StatefulWidget {
  const _TransfersView({required this.startCreate});
  final bool startCreate;

  @override
  State<_TransfersView> createState() => _TransfersViewState();
}

class _TransfersViewState extends State<_TransfersView> {
  Map<String, MovementReference> _bulkSelection = {};
  bool _openedInitial = false;
  final _changingStatus = <String>{};
  DateTimeRange? _range;
  bool _customPeriod = false;
  String? _accountId;
  bool? _effective;
  TransferDateField _dateField = TransferDateField.due;
  VoidCallback? _refreshFilters;

  DateTimeRange get _monthRange => DateTimeRange(
      start: referenceMonth.value,
      end: DateTime(
          referenceMonth.value.year, referenceMonth.value.month + 1, 0));

  @override
  void initState() {
    super.initState();
    _range = _monthRange;
    referenceMonth.addListener(_monthChanged);
  }

  @override
  void dispose() {
    referenceMonth.removeListener(_monthChanged);
    super.dispose();
  }

  void _monthChanged() {
    setState(() {
      _range = _monthRange;
      _customPeriod = false;
    });
    _apply();
  }

  void _apply() {
    _refreshFilters?.call();
    context.read<TransfersCubit>().load(TransferFilter(
        from: _range?.start,
        to: _range?.end,
        accountId: _accountId,
        effective: _effective,
        dateField: _dateField));
  }

  Future<void> _openFilters() async {
    final accounts = context.read<TransfersCubit>().state.accounts;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => StatefulBuilder(builder: (sheet, refresh) {
              _refreshFilters = () {
                if (sheet.mounted) refresh(() {});
              };
              return SafeArea(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Row(children: [
                          const Expanded(
                              child: Text('Filtros',
                                  style: TextStyle(fontSize: 20))),
                          TextButton(
                              onPressed: () {
                                setState(() {
                                  _accountId = null;
                                  _effective = null;
                                  _dateField = TransferDateField.due;
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
                        Flexible(
                            child: SingleChildScrollView(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                              DropdownButton<String>(
                                  isExpanded: true,
                                  value: _accountId ?? '',
                                  items: [
                                    const DropdownMenuItem(
                                        value: '',
                                        child: Text('Todas as contas')),
                                    for (final account in accounts)
                                      DropdownMenuItem(
                                          value: account.id,
                                          child:
                                              AccountOption(account: account))
                                  ],
                                  onChanged: (id) {
                                    setState(() =>
                                        _accountId = id == '' ? null : id);
                                    _apply();
                                  }),
                              DropdownButton<String>(
                                  isExpanded: true,
                                  value: _effective == null
                                      ? 'all'
                                      : _effective!
                                          ? 'effective'
                                          : 'pending',
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'all',
                                        child: Text('Todos os estados')),
                                    DropdownMenuItem(
                                        value: 'effective',
                                        child: Text('Efetivadas')),
                                    DropdownMenuItem(
                                        value: 'pending',
                                        child: Text('Pendentes'))
                                  ],
                                  onChanged: (status) {
                                    setState(() => _effective = status == 'all'
                                        ? null
                                        : status == 'effective');
                                    _apply();
                                  }),
                              DropdownButton<TransferDateField>(
                                  isExpanded: true,
                                  value: _dateField,
                                  items: const [
                                    DropdownMenuItem(
                                        value: TransferDateField.posted,
                                        child: Text('Filtrar lançamento')),
                                    DropdownMenuItem(
                                        value: TransferDateField.due,
                                        child: Text('Filtrar vencimento')),
                                    DropdownMenuItem(
                                        value: TransferDateField.effective,
                                        child: Text('Filtrar efetivação'))
                                  ],
                                  onChanged: (field) {
                                    if (field != null) {
                                      setState(() => _dateField = field);
                                      _apply();
                                    }
                                  }),
                              OutlinedButton.icon(
                                  icon: const Icon(Icons.date_range),
                                  label: Text(_range == null
                                      ? 'Período'
                                      : '${_dateLabel(_range!.start)} – ${_dateLabel(_range!.end)}'),
                                  onPressed: () async {
                                    final picked = await showDateRangePicker(
                                        context: context,
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100, 12, 31),
                                        initialDateRange:
                                            _range ?? _monthRange);
                                    if (picked != null && mounted) {
                                      setState(() {
                                        _range = picked;
                                        _customPeriod = true;
                                      });
                                      _apply();
                                    }
                                  }),
                              TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _range = null;
                                      _customPeriod = true;
                                    });
                                    _apply();
                                  },
                                  child: const Text('Todos os meses')),
                            ]))),
                      ])));
            }));
    _refreshFilters = null;
  }

  Future<void> _edit(BuildContext context, [Transfer? item]) async {
    final scope = item?.series == null
        ? SeriesScope.onlyThis
        : await chooseSeriesScope(context, deleting: false);
    if (scope == null || !context.mounted) return;
    final cubit = context.read<TransfersCubit>();
    final draft = await showMovementForm<TransferDraft>(
        context,
        (_) => TransferForm(
            item: item, scope: scope, accounts: cubit.state.accounts));
    if (!context.mounted) return;
    if (draft == null) {
      if (item == null && widget.startCreate) context.go('/transfers');
      return;
    }
    try {
      await cubit.save(draft, id: item?.id);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
    if (context.mounted && item == null && widget.startCreate) {
      context.go('/transfers');
    }
  }

  Future<void> _delete(BuildContext context, Transfer item) async {
    final scope = item.series == null
        ? SeriesScope.onlyThis
        : await chooseSeriesScope(context, deleting: true);
    if (scope == null || !context.mounted) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: const Text('Excluir transferência?'),
              content: Text(scope == SeriesScope.thisAndNext
                  ? 'As transferências pendentes desta posição em diante sairão da lista e das projeções das duas contas.'
                  : 'O valor sairá dos saldos das duas contas.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('Excluir')),
              ],
            ));
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<TransfersCubit>().delete(item.id, scope: scope);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _markPending(Transfer item) async {
    if (_changingStatus.contains(item.id) || item.effectiveDate == null) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await _changeDate(item.id, item.effectiveDate!);
  }

  Future<void> _editAmount(Transfer item) async {
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
      await context.read<TransfersCubit>().updateAmount(item.id,
          expectedAmountMinor: item.amountMinor,
          amountMinor: amount,
          scope: scope);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _changingStatus.remove(item.id));
    }
  }

  Future<void> _quickEffective(Transfer item) async {
    if (!mounted || item.isEffective || _changingStatus.contains(item.id)) {
      return;
    }
    setState(() => _changingStatus.add(item.id));
    final today = DateUtils.dateOnly(DateTime.now());
    try {
      await context
          .read<TransfersCubit>()
          .setEffective(item.id, effective: true, effectiveDate: today);
      if (!mounted) return;
      showEffectuationFeedback(context,
          message: 'Transferência efetivada hoje.',
          undo: () => _changeDate(item.id, today, restore: item.effectiveDate),
          adjustDate: () => _changeDate(item.id, today, pick: true));
    } catch (error) {
      if (mounted) _showError(context, error);
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
      await context.read<TransfersCubit>().changeEffectiveDate(id,
          expectedDate: expected, effectiveDate: chosen);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _changingStatus.remove(id));
    }
  }

  void _showError(BuildContext context, Object error) {
    final message = error is FormatException
        ? error.message
        : error is StateError
            ? error.message
            : 'Não foi possível salvar a transferência.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Transferências'),
            leading: somiaMenuLeading(context)),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(context),
          icon: const Icon(Icons.add),
          label: const Text('Nova transferência'),
        ),
        body: Column(children: [
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
                        onPressed: _openFilters,
                        icon: const Icon(Icons.tune),
                        label: const Text('Filtros')),
                    if (_customPeriod)
                      Text(_range == null
                          ? 'Todos os meses'
                          : '${_dateLabel(_range!.start)} – ${_dateLabel(_range!.end)}'),
                  ])),
          Expanded(
              child: BlocConsumer<TransfersCubit, TransfersState>(
                  listener: (context, state) {
            if (widget.startCreate &&
                !_openedInitial &&
                !state.loading &&
                state.error == null) {
              _openedInitial = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _edit(context);
              });
            }
          }, builder: (context, state) {
            if (state.loading && state.accounts.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.error != null) {
              return Center(
                  child: TextButton(
                onPressed: context.read<TransfersCubit>().load,
                child: Text('${state.error} Tentar novamente'),
              ));
            }
            if (state.items.isEmpty) {
              return const Center(
                  child: Text('Nenhuma transferência para estes filtros.'));
            }
            final list = ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: state.items.length,
              itemBuilder: (context, index) {
                final item = state.items[index];
                final row = MovementListRow(
                  id: item.id,
                  description: item.description,
                  tags: [if (item.series != null) item.series!.label],
                  account:
                      '${item.sourceAccountName} → ${item.destinationAccountName}',
                  amount:
                      MoneyMinor.display(item.amountMinor, item.currencyCode),
                  dueDate: item.dueDate ?? item.date,
                  effectiveDate: item.effectiveDate,
                  effective: item.isEffective,
                  busy: _changingStatus.contains(item.id),
                  color: SomiaColors.blue,
                  onEdit: () => _edit(context, item),
                  onEffective: () => _quickEffective(item),
                  onPending: () => _markPending(item),
                  onAmount: () => _editAmount(item),
                  menu: PopupMenuButton<String>(
                    key: ValueKey('movement-menu-${item.id}'),
                    enabled: !_changingStatus.contains(item.id),
                    tooltip: 'Ações da transferência',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (action) {
                      if (action == 'attachments')
                        showAttachments(
                            context, MovementReference.transfer(item));
                      if (action == 'edit') _edit(context, item);
                      if (action == 'delete') _delete(context, item);
                      if (action == 'pending') _markPending(item);
                      if (action == 'date' && item.effectiveDate != null) {
                        _changeDate(item.id, item.effectiveDate!, pick: true);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'attachments', child: Text('Anexos')),
                      const PopupMenuItem(value: 'edit', child: Text('Editar')),
                      if (item.effectiveDate != null) ...[
                        const PopupMenuItem(
                            value: 'date', child: Text('Ajustar data')),
                        const PopupMenuItem(
                            value: 'pending',
                            child: Text('Marcar como pendente')),
                      ],
                      const PopupMenuItem(
                          value: 'delete', child: Text('Excluir')),
                    ],
                  ),
                );
                return getIt.isRegistered<MovementManagementRepository>()
                    ? SelectableMovementRow(
                        ref: MovementReference.transfer(item),
                        selection: _bulkSelection,
                        onSelection: (selection) =>
                            setState(() => _bulkSelection = selection),
                        child: row)
                    : row;
              },
            );
            if (!getIt.isRegistered<MovementManagementRepository>()) {
              return list;
            }
            return Column(children: [
              BulkMovementToolbar(
                  selection: _bulkSelection,
                  available:
                      state.items.map(MovementReference.transfer).toList(),
                  transfer: true,
                  onSelection: (selection) =>
                      setState(() => _bulkSelection = selection),
                  onCompleted: context.read<TransfersCubit>().load),
              Expanded(child: list)
            ]);
          })),
        ]),
      );
}

class TransferForm extends StatefulWidget {
  const TransferForm(
      {super.key,
      required this.accounts,
      this.item,
      this.scope = SeriesScope.onlyThis});

  final List<Account> accounts;
  final Transfer? item;
  final SeriesScope scope;

  @override
  State<TransferForm> createState() => TransferFormState();
}

class TransferFormState extends State<TransferForm> {
  final _formKey = GlobalKey<FormState>();
  final _series = SeriesFormController();
  bool get _forcePending =>
      _series.active || widget.scope == SeriesScope.thisAndNext;
  void _seriesChanged() {
    if (mounted) setState(() {});
  }

  late final TextEditingController _amount;
  late final TextEditingController _description;
  final _descriptionFocus = FocusNode();
  final _amountFocus = FocusNode();
  String? _sourceId;
  String? _destinationId;
  late DateTime _date;
  late DateTime _dueDate;
  DateTime? _effectiveDate;
  late bool _isEffective;

  List<Account> get _sources => widget.accounts
      .where((a) => !a.isArchived || a.id == widget.item?.sourceAccountId)
      .toList();

  List<Account> get _destinations {
    final source = widget.accounts.where((a) => a.id == _sourceId).firstOrNull;
    return widget.accounts
        .where((a) =>
            a.id != _sourceId &&
            a.currencyCode == source?.currencyCode &&
            (!a.isArchived || a.id == widget.item?.destinationAccountId))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _series.addListener(_seriesChanged);
    _description = TextEditingController(text: widget.item?.description ?? '');
    _amount = TextEditingController(
        text: MoneyMinor.plain(widget.item?.amountMinor ?? 0));
    _sourceId = widget.item?.sourceAccountId ?? _sources.firstOrNull?.id;
    _destinationId =
        widget.item?.destinationAccountId ?? _destinations.firstOrNull?.id;
    _date = widget.item?.date ?? DateTime.now();
    _dueDate = widget.item?.dueDate ?? _date;
    _effectiveDate = widget.item?.effectiveDate;
    _isEffective = widget.item == null || widget.item!.effectiveDate != null;
  }

  @override
  void dispose() {
    _series.dispose();
    _description.dispose();
    _descriptionFocus.dispose();
    _amountFocus.dispose();
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
                : _effectiveDate ?? DateTime.now(),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
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
    final isEffective = !_forcePending && _isEffective;
    var effective = isEffective ? _effectiveDate ?? DateTime.now() : null;
    if (isEffective &&
        widget.item?.effectiveDate == null &&
        !DateUtils.isSameDay(_dueDate, DateTime.now())) {
      effective = await chooseEffectuationDate(context, _dueDate);
      if (effective == null || !mounted) return;
    }
    if (!mounted) return;
    Navigator.pop(
        context,
        TransferDraft(
            description: _description.text.trim(),
            sourceAccountId: _sourceId!,
            destinationAccountId: _destinationId!,
            amountMinor: MoneyMinor.parse(_amount.text),
            date: _date,
            dueDate: _dueDate,
            effectiveDate: effective,
            isEffective: isEffective,
            seriesPlan: _series.plan,
            scope: widget.scope));
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      value: () => (
            _description.text,
            _amount.text,
            _sourceId,
            _destinationId,
            _date,
            _dueDate,
            _effectiveDate,
            _isEffective,
            _series.snapshot
          ),
      builder: (context, cancel) => MovementFormFrame(
            onCancel: cancel,
            compact: true,
            title: widget.item == null
                ? 'Nova transferência'
                : 'Editar transferência',
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
                    scrollPadding: const EdgeInsets.all(100),
                    decoration: const InputDecoration(labelText: 'Descrição'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Informe a descrição.'
                        : null,
                    onFieldSubmitted: (_) {
                      _amountFocus.requestFocus();
                      _amount.selection = TextSelection(
                          baseOffset: 0, extentOffset: _amount.text.length);
                    },
                  ),
                  MonetaryCalculatorField(
                      controller: _amount,
                      labelText: _series.kind == SeriesKind.installments
                          ? (_series.amountIsTotal
                              ? 'Valor total'
                              : 'Valor por parcela')
                          : 'Valor',
                      focusNode: _amountFocus,
                      currencyCode: widget.accounts
                              .where((a) => a.id == _sourceId)
                              .firstOrNull
                              ?.currencyCode ??
                          'BRL'),
                  DropdownButtonFormField<String>(
                    menuMaxHeight: 280,
                    borderRadius: BorderRadius.circular(16),
                    itemHeight: 48,
                    key: ValueKey('source-$_sourceId'),
                    isExpanded: true,
                    initialValue: _sourceId,
                    decoration:
                        const InputDecoration(labelText: 'Conta de origem'),
                    items: _sources
                        .map((a) => DropdownMenuItem(
                            value: a.id,
                            child:
                                AccountOption(account: a, showCurrency: true)))
                        .toList(),
                    validator: (id) =>
                        id == null ? 'Selecione uma conta de origem.' : null,
                    onChanged: (id) => setState(() {
                      _sourceId = id;
                      if (!_destinations.any((a) => a.id == _destinationId)) {
                        _destinationId = _destinations.firstOrNull?.id;
                      }
                    }),
                  ),
                  DropdownButtonFormField<String>(
                    menuMaxHeight: 280,
                    borderRadius: BorderRadius.circular(16),
                    itemHeight: 48,
                    key: ValueKey('destination-$_sourceId'),
                    isExpanded: true,
                    initialValue: _destinationId,
                    decoration:
                        const InputDecoration(labelText: 'Conta de destino'),
                    items: _destinations
                        .map((a) => DropdownMenuItem(
                            value: a.id,
                            child:
                                AccountOption(account: a, showCurrency: true)))
                        .toList(),
                    validator: (id) => id == null
                        ? 'Selecione outra conta da mesma moeda.'
                        : null,
                    onChanged: (id) => setState(() => _destinationId = id),
                  ),
                  CompactMovementDate(
                      label: 'Vencimento',
                      date: _dueDate,
                      onTap: () => _pickDate('due')),
                  SwitchListTile(
                      title: const Text('Efetivada'),
                      value: !_forcePending && _isEffective,
                      onChanged: _forcePending
                          ? null
                          : (value) => setState(() => _isEffective = value)),
                  if (!_forcePending && _isEffective)
                    CompactMovementDate(
                        label: 'Data de efetivação',
                        date: _effectiveDate ?? DateTime.now(),
                        onTap: () => _pickDate('effective')),
                  const Divider(),
                  const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Mais opções')),
                  if (widget.item == null || widget.item?.series != null)
                    SeriesFormFields(
                        controller: _series,
                        amount: _amount,
                        dueDate: _dueDate,
                        currencyCode: widget.accounts
                                .where((a) => a.id == _sourceId)
                                .firstOrNull
                                ?.currencyCode ??
                            'BRL',
                        existing: widget.item?.series),
                  CompactMovementDate(
                      label: 'Lançamento',
                      date: _date,
                      onTap: () => _pickDate('posted')),
                ],
              ),
            ),
          ));
}
