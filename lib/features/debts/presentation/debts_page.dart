import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../core/routing/app_router.dart';
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
  const DebtsPage({super.key});
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

  Widget _metric(String name, int value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(name)),
        const SizedBox(width: 12),
        Text(MoneyMinor.display(value, 'BRL'))
      ]));
  @override
  Widget build(BuildContext context) {
    final debts = _debts;
    return Scaffold(
        appBar: AppBar(
            title: const Text('Dívidas e empréstimos'),
            leading: somiaMenuLeading(context),
            actions: [
              IconButton(
                  tooltip: 'Atualizar dívidas',
                  icon: const Icon(Icons.refresh),
                  onPressed: _busy ? null : _load)
            ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _busy ? null : () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Nova dívida')),
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (_busy) const LinearProgressIndicator(),
                      if (_error != null)
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                        'Saldo devedor cadastrado (BRL)'),
                                    const SizedBox(height: 8),
                                    Text(
                                        MoneyMinor.display(
                                            debts.fold(0,
                                                (s, d) => s + d.balanceMinor),
                                            'BRL'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium),
                                    _metric(
                                        'Após todas as parcelas vinculadas',
                                        debts.fold(
                                            0, (s, d) => s + d.projectedMinor)),
                                    const Text(
                                        'Somente pagamentos efetivados até hoje amortizam o saldo atual. A projeção considera todas as parcelas vinculadas, sem estimar juros futuros.'),
                                    TextButton(
                                        onPressed: () =>
                                            context.go(AppRoutes.assetsPath),
                                        child: const Text('Ver patrimônio'))
                                  ]))),
                      if (debts.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                                'Cadastre uma dívida e vincule as despesas já existentes. O cadastro não gera receitas nem despesas.')),
                      for (final d in debts)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(
                                            child: Text(d.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge)),
                                        IconButton(
                                            tooltip: 'Editar dívida',
                                            onPressed:
                                                _busy ? null : () => _edit(d),
                                            icon:
                                                const Icon(Icons.edit_outlined))
                                      ]),
                                      Text(
                                          '${d.kind.label} · ${d.creditor}${d.balanceMinor == 0 ? ' · Quitada' : ''}'),
                                      if (d.assetId != null)
                                        Text(
                                            'Bem: ${_assets.where((a) => a.id == d.assetId).firstOrNull?.name ?? 'Bem vinculado'}'),
                                      _metric('Saldo atual', d.balanceMinor),
                                      _metric(
                                          'Amortizado', d.paidPrincipalMinor),
                                      _metric(
                                          'Saldo projetado', d.projectedMinor),
                                      Text(
                                          'Saldo inicial em ${assetDate(d.referenceAt)}: ${MoneyMinor.display(d.initialMinor, 'BRL')}'),
                                      if (d.notes.isNotEmpty) Text(d.notes),
                                      const SizedBox(height: 12),
                                      OutlinedButton.icon(
                                          onPressed:
                                              _busy ? null : () => _link(d),
                                          icon: const Icon(Icons.link),
                                          label: const Text(
                                              'Vincular parcela / despesa')),
                                      ExpansionTile(
                                          tilePadding: EdgeInsets.zero,
                                          title: const Text(
                                              'Histórico de parcelas'),
                                          children: [
                                            for (final p in d.payments)
                                              ListTile(
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  title: Text(p.description),
                                                  subtitle: Text(
                                                      '${assetDate(p.date)} · ${p.unlinked ? 'Desvinculada' : p.deleted ? 'Despesa excluída' : p.effective ? 'Paga' : 'Prevista'}\nParcela: ${MoneyMinor.display(p.amountMinor, 'BRL')} · Amortização: ${MoneyMinor.display(p.principalMinor, 'BRL')}\nJuros e encargos: ${MoneyMinor.display(p.chargesMinor, 'BRL')}'),
                                                  trailing: p.unlinked
                                                      ? null
                                                      : IconButton(
                                                          tooltip:
                                                              'Desvincular parcela',
                                                          onPressed: _busy
                                                              ? null
                                                              : () =>
                                                                  _unlink(p),
                                                          icon: const Icon(
                                                              Icons.link_off)))
                                          ])
                                    ])))
                    ])));
  }
}
