import '../../../core/widgets/module_surface.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/routing/somia_shell.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../accounts/domain/money_minor.dart';
import '../../assets/domain/asset.dart';
import '../../assets/presentation/asset_form.dart' show assetDate;
import '../../investments/presentation/investment_forms.dart'
    show investmentError;
import '../domain/debt.dart';
import 'debt_forms.dart';

class DebtsPage extends StatefulWidget {
  const DebtsPage({super.key, this.debtId});
  final String? debtId;
  @override
  State<DebtsPage> createState() => _DebtsPageState();
}

class _DebtsPageState extends State<DebtsPage> {
  late final _repo = getIt<DebtsRepository>();
  List<Debt>? _debts;
  List<Asset> _assets = [];
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _selectedId = widget.debtId;
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final debts = await _repo.load();
      final assets = await getIt<AssetsRepository>().load();
      if (mounted) {
        setState(() {
          _debts = debts;
          _assets = assets.assets;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = investmentError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Debt? debt]) async {
    final used = (_debts ?? []).map((d) => d.assetId).toSet();
    final saved = await showMovementForm<bool>(
        context,
        (_) => DebtForm(
            repository: _repo,
            debt: debt,
            assets: _assets
                .where((a) => !used.contains(a.id) || debt?.assetId == a.id)
                .toList()));
    if (saved == true && mounted) await _load();
  }

  Future<void> _link(Debt debt) async {
    setState(() => _busy = true);
    try {
      final expenses = await _repo.expenses(debt.id);
      if (!mounted) return;
      final saved = await showMovementForm<bool>(
          context,
          (_) => DebtPaymentForm(
              repository: _repo, debt: debt, expenses: expenses));
      if (saved == true && mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(investmentError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlink(DebtPayment payment) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Desvincular parcela?'),
                content: const Text(
                    'A despesa permanece nas contas. Sua amortização sai desta dívida e o vínculo fica no histórico.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Desvincular'))
                ]));
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repo.unlink(payment.id);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(investmentError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _selectedId;
  bool _showSettled = false;
  bool _showData = false;

  @override
  void didUpdateWidget(covariant DebtsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.debtId != widget.debtId) {
      _selectedId = widget.debtId;
      _showData = false;
    }
  }

  String _money(int value) => MoneyMinor.display(value, 'BRL');
  double _progress(Debt debt) => debt.initialMinor <= 0
      ? 0
      : (debt.paidPrincipalMinor / debt.initialMinor)
          .clamp(0.0, 1.0)
          .toDouble();
  String _percent(Debt debt) => '${(_progress(debt) * 100).round()}%';
  IconData _icon(Debt debt) => debt.kind == DebtKind.financing
      ? Icons.directions_car_outlined
      : Icons.account_balance_outlined;

  void _open(Debt? debt) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go(debt == null
          ? AppRoutes.debtsPath
          : '${AppRoutes.debtsPath}?debt=${Uri.encodeQueryComponent(debt.id)}');
    } else {
      setState(() {
        _selectedId = debt?.id;
        _showData = false;
      });
    }
  }

  Widget _card(List<Widget> children, {Key? key}) => Card(
      key: key,
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children)));

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: SomiaColors.muted, fontSize: 13));
  Widget _value(int value, {double size = 24}) => Text(_money(value),
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w700));
  Widget _badge(Debt debt, {double size = 48}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: SomiaColors.blue.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14)),
      child: Icon(_icon(debt), color: SomiaColors.blue, size: size * 0.55));

  Widget _bar(Debt debt) => Row(children: [
        Expanded(
            child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                    value: _progress(debt),
                    minHeight: 10,
                    color: SomiaColors.blue,
                    backgroundColor: SomiaColors.outline,
                    semanticsLabel: 'Percentual amortizado',
                    semanticsValue: _percent(debt)))),
        const SizedBox(width: 12),
        _label(_percent(debt)),
      ]);

  Widget _menu(Debt debt) => PopupMenuButton<String>(
      tooltip: 'Opções da dívida',
      enabled: !_busy,
      onSelected: (value) => value == 'edit' ? _edit(debt) : _link(debt),
      itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Editar dívida')),
            PopupMenuItem(value: 'link', child: Text('Vincular despesa')),
          ]);

  Widget _debtCard(Debt debt) => _card([
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _badge(debt),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(debt.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                _label('${debt.kind.label} · ${debt.creditor}'),
              ])),
          _menu(debt),
        ]),
        const SizedBox(height: 14),
        _label('Saldo atual'),
        const SizedBox(height: 4),
        _value(debt.balanceMinor),
        const SizedBox(height: 12),
        _bar(debt),
        const SizedBox(height: 8),
        _label(
            '${_money(debt.paidPrincipalMinor)} amortizados · ${_percent(debt)}'),
        const SizedBox(height: 12),
        const Divider(height: 1),
        InkWell(
            key: ValueKey('debt-open-${debt.id}'),
            onTap: () => _open(debt),
            child: const Padding(
                padding: EdgeInsets.only(top: 14, bottom: 2),
                child: Row(children: [
                  Expanded(child: Text('Ver detalhes')),
                  Icon(Icons.chevron_right, size: 20),
                ]))),
      ], key: ValueKey('debt-card-${debt.id}'));

  Widget _stat(String label, String value, IconData icon, Color color) =>
      _card([
        Row(children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _label(label),
                const SizedBox(height: 4),
                Text(value,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ])),
        ]),
      ]);

  List<Widget> _overview(List<Debt> debts) {
    final active = debts.where((d) => d.balanceMinor > 0).toList();
    final settled = debts.where((d) => d.balanceMinor <= 0).toList();
    final filtered = _showSettled ? settled : active;
    final stats = [
      _stat(
          'Amortizado',
          _money(debts.fold<int>(0, (s, d) => s + d.paidPrincipalMinor)),
          Icons.donut_large,
          SomiaColors.green),
      _stat('Dívidas ativas', '${active.length}', Icons.receipt_long_outlined,
          SomiaColors.blue),
    ];
    return [
      _card([
        Row(children: [
          _label('Saldo devedor'),
          const SizedBox(width: 6),
          const Tooltip(
              message: 'Somente pagamentos efetivados amortizam o saldo atual. '
                  'A projeção considera as parcelas vinculadas, sem juros futuros.',
              child:
                  Icon(Icons.info_outline, size: 18, color: SomiaColors.muted)),
        ]),
        const SizedBox(height: 8),
        _value(debts.fold<int>(0, (s, d) => s + d.balanceMinor), size: 30),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1)),
        _label('Após parcelas vinculadas'),
        const SizedBox(height: 6),
        _value(debts.fold<int>(0, (s, d) => s + d.projectedMinor), size: 22),
        const SizedBox(height: 16),
        _label('Projeção sem juros futuros.'),
      ]),
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(children: stats);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: stats[0]),
          const SizedBox(width: 8),
          Expanded(child: stats[1]),
        ]);
      }),
      SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: false, label: Text('Ativas  ${active.length}')),
                ButtonSegment(
                    value: true, label: Text('Quitadas  ${settled.length}')),
              ],
              selected: {_showSettled},
              onSelectionChanged: (values) =>
                  setState(() => _showSettled = values.single))),
      const SizedBox(height: 18),
      const Text('Suas dívidas',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      if (filtered.isEmpty)
        _card([
          Text(debts.isEmpty
              ? 'Cadastre uma dívida e vincule as despesas já existentes. '
                  'O cadastro não gera receitas nem despesas.'
              : _showSettled
                  ? 'Nenhuma dívida quitada.'
                  : 'Nenhuma dívida ativa.')
        ]),
      for (final debt in filtered) _debtCard(debt),
    ];
  }

  Future<void> _paymentDetails(DebtPayment payment) async {
    await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
            top: false,
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(payment.description,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      _label(
                          '${assetDate(payment.date)} · ${_status(payment)}'),
                      const SizedBox(height: 12),
                      ModuleValueRow(
                          label: 'Parcela', value: _money(payment.amountMinor)),
                      ModuleValueRow(
                          label: 'Amortização',
                          value: _money(payment.principalMinor)),
                      ModuleValueRow(
                          label: 'Juros e encargos',
                          value: _money(payment.chargesMinor)),
                      if (!payment.unlinked) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () {
                                    Navigator.of(sheetContext).pop();
                                    _unlink(payment);
                                  },
                            icon: const Icon(Icons.link_off),
                            label: const Text('Desvincular parcela')),
                      ],
                    ]))));
  }

  String _status(DebtPayment payment) => payment.unlinked
      ? 'Desvinculada'
      : payment.deleted
          ? 'Despesa excluída'
          : payment.effective
              ? 'Efetivada'
              : 'Pendente';

  Widget _payment(DebtPayment payment) {
    final color = !payment.active
        ? SomiaColors.muted
        : payment.effective
            ? SomiaColors.green
            : SomiaColors.red;
    return Card(
        child: ListTile(
            key: ValueKey('debt-payment-${payment.id}'),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Icon(
                payment.active && payment.effective
                    ? Icons.event_available_outlined
                    : Icons.event_outlined,
                color: color,
                size: 28),
            title: Text(payment.description,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${assetDate(payment.date)} · ${_status(payment)}',
                style: const TextStyle(fontSize: 12, color: SomiaColors.muted)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_money(payment.amountMinor),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18),
            ]),
            onTap: () => _paymentDetails(payment)));
  }

  List<Widget> _detail(Debt debt) {
    final asset = _assets.where((a) => a.id == debt.assetId).firstOrNull;
    final payments = [...debt.payments]
      ..sort((a, b) => a.date.compareTo(b.date));
    return [
      Row(children: [
        _badge(debt, size: 64),
        const SizedBox(width: 16),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(debt.name,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _label(
              '${debt.creditor}${asset == null ? '' : ' · Vinculado a ${asset.name}'}'),
        ])),
      ]),
      const SizedBox(height: 22),
      _card([
        _label('Saldo atual'),
        const SizedBox(height: 6),
        _value(debt.balanceMinor, size: 32),
        const SizedBox(height: 16),
        _bar(debt),
        const SizedBox(height: 22),
        Wrap(spacing: 28, runSpacing: 12, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('Saldo inicial'),
            const SizedBox(height: 6),
            _value(debt.initialMinor, size: 18),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('Amortizado'),
            const SizedBox(height: 6),
            _value(debt.paidPrincipalMinor, size: 18),
          ]),
        ]),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Divider(height: 1)),
        _label('Após parcelas vinculadas'),
        const SizedBox(height: 6),
        _value(debt.projectedMinor, size: 22),
        const SizedBox(height: 18),
        FilledButton.icon(
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: _busy ? null : () => _link(debt),
            icon: const Icon(Icons.link),
            label: const Text('Vincular despesa')),
        const SizedBox(height: 10),
        const Text('Vincule pagamentos já registrados.',
            textAlign: TextAlign.center,
            style: TextStyle(color: SomiaColors.muted, fontSize: 12)),
      ]),
      Row(children: [
        Expanded(child: _tab('Parcelas vinculadas', !_showData, false)),
        Expanded(child: _tab('Dados', _showData, true)),
      ]),
      const SizedBox(height: 16),
      if (_showData)
        _card([
          _label('Tipo'),
          Text(debt.kind.label),
          const SizedBox(height: 12),
          _label('Credor'),
          Text(debt.creditor),
          const SizedBox(height: 12),
          _label('Saldo inicial em ${assetDate(debt.referenceAt)}'),
          _value(debt.initialMinor, size: 18),
          if (asset != null) ...[
            const SizedBox(height: 12),
            _label('Bem vinculado'),
            Text(asset.name)
          ],
          if (debt.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            _label('Observações'),
            Text(debt.notes)
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: _busy ? null : () => _edit(debt),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar dívida')),
        ])
      else ...[
        const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 16, color: SomiaColors.blue),
              SizedBox(width: 8),
              Expanded(
                  child: Text(
                      'Só pagamentos efetivados amortizam o saldo atual.',
                      style:
                          TextStyle(color: SomiaColors.muted, fontSize: 12))),
            ])),
        if (payments.isEmpty) _card([const Text('Nenhuma parcela vinculada.')]),
        for (final payment in payments) _payment(payment),
      ],
      const SizedBox(height: 4),
      _card([
        const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 18, color: SomiaColors.muted),
          SizedBox(width: 10),
          Expanded(
              child: Text('O cadastro da dívida não altera o saldo das contas.',
                  style: TextStyle(color: SomiaColors.muted, fontSize: 12))),
        ])
      ]),
    ];
  }

  Widget _tab(String title, bool selected, bool data) => InkWell(
      onTap: () => setState(() => _showData = data),
      child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: selected ? SomiaColors.blue : SomiaColors.outline,
                      width: selected ? 3 : 1))),
          child: Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: selected ? SomiaColors.blue : SomiaColors.muted,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400))));

  @override
  Widget build(BuildContext context) {
    final debts = _debts;
    final debt = debts?.where((d) => d.id == _selectedId).firstOrNull;
    return ModuleSurface(
        child: Scaffold(
            appBar: AppBar(
                toolbarHeight: debt == null ? 76 : 64,
                title: debt == null
                    ? const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text('Dívidas',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            SizedBox(height: 4),
                            Text('Acompanhe seus compromissos',
                                style: TextStyle(
                                    fontSize: 12, color: SomiaColors.muted)),
                          ])
                    : const Text('Detalhes da dívida',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                leading: debt == null
                    ? somiaMenuLeading(context)
                    : BackButton(onPressed: () => _open(null)),
                actions: [
                  if (debt != null)
                    _menu(debt)
                  else
                    IconButton(
                        tooltip: 'Atualizar dívidas',
                        icon: const Icon(Icons.refresh),
                        onPressed: _busy ? null : _load),
                ]),
            floatingActionButton: debt != null
                ? null
                : FloatingActionButton(
                    shape: const CircleBorder(),
                    onPressed: _busy ? null : () => _edit(),
                    tooltip: 'Nova dívida',
                    child: const Icon(Icons.add)),
            body: debts == null
                ? Center(
                    child: _busy
                        ? const CircularProgressIndicator()
                        : TextButton(
                            onPressed: _load,
                            child: Text(_error ?? 'Tentar novamente')))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                        key: ValueKey('debts-${debt?.id ?? 'overview'}'),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          if (_busy) const LinearProgressIndicator(),
                          if (_error != null)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(_error!,
                                    style: const TextStyle(
                                        color: SomiaColors.red))),
                          if (debt == null)
                            ..._overview(debts)
                          else
                            ..._detail(debt),
                        ]))));
  }
}
