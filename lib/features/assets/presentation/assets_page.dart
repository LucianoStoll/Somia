import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../accounts/domain/money_minor.dart';
import '../../investments/presentation/investment_forms.dart'
    show investmentError;
import '../domain/asset.dart';
import 'asset_form.dart';

class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key});
  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  late final _repo = getIt<AssetsRepository>();
  AssetOverview? _overview;
  String? _error;
  bool _busy = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() => _busy = true);
    try {
      final data = await _repo.load();
      if (mounted && request == _request) {
        setState(() {
          _overview = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _error = investmentError(e));
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _edit({Asset? asset, bool valuation = false}) async {
    final saved = await showMovementForm<bool>(
        context,
        (_) => AssetForm(
            repository: _repo, asset: asset, valuationOnly: valuation));
    if (saved == true && mounted) await _load();
  }

  Future<void> _archive(Asset asset) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(asset.archived
                    ? 'Reincluir no patrimônio?'
                    : 'Retirar do patrimônio?'),
                content: const Text(
                    'O histórico será preservado. O valor do bem sai do resumo, mas seu financiamento continua até ser informado como quitado. Registre recebimentos e pagamentos separadamente.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Confirmar'))
                ]));
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repo.archive(asset.id, !asset.archived);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(investmentError(e))));
      }
    }
  }

  Widget _metric(String label, int value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Text(MoneyMinor.display(value, 'BRL'))
      ]));
  @override
  Widget build(BuildContext context) {
    final data = _overview;
    return Scaffold(
        appBar: AppBar(
            title: const Text('Bens e patrimônio'),
            leading: IconButton(
                tooltip: 'Voltar a investimentos',
                onPressed: () => context.go(AppRoutes.investmentsPath),
                icon: const Icon(Icons.arrow_back)),
            actions: [
              IconButton(
                  tooltip: 'Atualizar patrimônio',
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh))
            ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _busy ? null : () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Novo bem')),
        body: data == null
            ? _busy
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: TextButton(
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
                                    const Text('Patrimônio líquido cadastrado'),
                                    const SizedBox(height: 8),
                                    Text(
                                        MoneyMinor.display(
                                            data.netMinor, 'BRL'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium),
                                    _metric('Contas e investimentos (BRL)',
                                        data.accountsMinor),
                                    _metric('Bens', data.assetsMinor),
                                    if (data.cardCreditMinor > 0)
                                      _metric('Créditos dos cartões',
                                          data.cardCreditMinor),
                                    _metric('Financiamentos dos bens',
                                        -data.assetDebtMinor),
                                    _metric('Outras dívidas e empréstimos',
                                        -data.otherDebtMinor),
                                    _metric('Dívidas dos cartões',
                                        -data.cardDebtMinor),
                                    const SizedBox(height: 8),
                                    const Text(
                                        'Investimentos entram pelas contas. Financiamentos vinculados substituem o saldo manual do bem; outras dívidas cadastradas entram uma vez.'),
                                  ]))),
                      if (data.assets.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                                'Cadastre veículos, imóveis e outros bens para acompanhar seu patrimônio.')),
                      for (final asset in data.assets)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(
                                            child: Text(asset.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge)),
                                        IconButton(
                                            tooltip: 'Editar bem',
                                            onPressed: _busy
                                                ? null
                                                : () => _edit(asset: asset),
                                            icon:
                                                const Icon(Icons.edit_outlined))
                                      ]),
                                      Text(
                                          '${asset.kind.label}${asset.archived ? ' · Fora do patrimônio' : ''}'),
                                      _metric('Valor atual', asset.valueMinor),
                                      _metric('Saldo do financiamento',
                                          -asset.debtMinor),
                                      _metric('Valor líquido',
                                          asset.valueMinor - asset.debtMinor),
                                      Text(
                                          'Aquisição: ${assetDate(asset.acquiredAt)} · ${MoneyMinor.display(asset.acquisitionMinor, 'BRL')}'),
                                      if (asset.current != null)
                                        Text(
                                            'Avaliação: ${assetDate(asset.current!.date)}'),
                                      if ((asset.managedCreditor ??
                                                  asset.current?.creditor)
                                              ?.isNotEmpty ??
                                          false)
                                        Text(
                                            'Credor: ${asset.managedCreditor ?? asset.current!.creditor}'),
                                      if (asset.notes.isNotEmpty)
                                        Text(asset.notes),
                                      const SizedBox(height: 12),
                                      Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            OutlinedButton.icon(
                                                onPressed: _busy
                                                    ? null
                                                    : () => _edit(
                                                        asset: asset,
                                                        valuation: true),
                                                icon: const Icon(Icons
                                                    .price_change_outlined),
                                                label: const Text(
                                                    'Atualizar avaliação')),
                                            TextButton(
                                                onPressed: _busy
                                                    ? null
                                                    : () => _archive(asset),
                                                child: Text(asset.archived
                                                    ? 'Reincluir'
                                                    : 'Retirar do patrimônio'))
                                          ]),
                                      ExpansionTile(
                                          tilePadding: EdgeInsets.zero,
                                          title: const Text(
                                              'Histórico de avaliações'),
                                          children: [
                                            for (final v in asset.history)
                                              ListTile(
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  title: Text(
                                                      '${assetDate(v.date)} · ${MoneyMinor.display(v.valueMinor, 'BRL')}'),
                                                  subtitle: Text(
                                                      'Financiamento: ${MoneyMinor.display(v.debtMinor, 'BRL')}${v.creditor.isEmpty ? '' : ' · ${v.creditor}'}${v.notes.isEmpty ? '' : '\n${v.notes}'}'))
                                          ]),
                                    ]))),
                    ])));
  }
}
