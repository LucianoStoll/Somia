import '../../../core/widgets/module_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/routing/somia_shell.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../accounts/domain/money_minor.dart';
import '../domain/investment.dart';
import 'investment_forms.dart';
import 'investments_cubit.dart';

class InvestmentsPage extends StatelessWidget {
  const InvestmentsPage({super.key});
  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => InvestmentsCubit(getIt<InvestmentsRepository>()),
        child: const _InvestmentsView(),
      );
}

class _InvestmentsView extends StatelessWidget {
  const _InvestmentsView();
  Future<void> _edit(
    BuildContext context,
    InvestmentOverview overview, [
    Investment? item,
  ]) async {
    final cubit = context.read<InvestmentsCubit>();
    final saved = await showMovementForm<bool>(
      context,
      (_) => InvestmentForm(
        repository: cubit.repository,
        overview: overview,
        investment: item,
      ),
    );
    if (saved == true && !cubit.isClosed) await cubit.load();
  }

  Future<void> _operation(
    BuildContext context,
    InvestmentOverview overview,
    Investment item,
    InvestmentAction action,
  ) async {
    final cubit = context.read<InvestmentsCubit>();
    final saved = await showMovementForm<bool>(
      context,
      (_) => InvestmentOperationForm(
        repository: cubit.repository,
        investment: item,
        accounts: overview.accounts,
        action: action,
      ),
    );
    if (saved == true && !cubit.isClosed) await cubit.load();
  }

  Future<void> _archive(BuildContext context, Investment item) async {
    final cubit = context.read<InvestmentsCubit>();
    final archived = item.account.isArchived;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(archived ? 'Reativar aplicação?' : 'Arquivar aplicação?'),
        content: Text(
          archived
              ? 'A conta vinculada será reativada para novos movimentos.'
              : 'A conta vinculada também será arquivada. O saldo e o histórico serão preservados.',
        ),
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
    );
    if (confirmed != true || cubit.isClosed) return;
    try {
      await cubit.repository.setArchived(item.id, !archived);
      await cubit.load();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(investmentError(e))));
      }
    }
  }

  Future<void> _delete(BuildContext context, Investment item) async {
    final cubit = context.read<InvestmentsCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Excluir aplicação?'),
        content: Text(
          'Excluir “${item.name}” libera o vínculo com a conta ${item.account.name}. A conta, o saldo e todas as movimentações serão preservados. Se estiver arquivada, reative a conta em Contas para voltar a utilizá-la.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Excluir aplicação'),
          ),
        ],
      ),
    );
    if (confirmed != true || cubit.isClosed) return;
    try {
      await cubit.repository.delete(item.id);
      await cubit.load();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(investmentError(e))));
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) =>
      BlocBuilder<InvestmentsCubit, InvestmentsState>(
        builder: (context, state) {
          final overview = state.overview;
          return ModuleSurface(
              child: Scaffold(
            appBar: AppBar(
              title: const Text('Investimentos'),
              leading: somiaMenuLeading(context),
              actions: [
                IconButton(
                  tooltip: 'Atualizar aplicações',
                  onPressed: state.loading
                      ? null
                      : context.read<InvestmentsCubit>().load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            floatingActionButton: overview == null
                ? null
                : FloatingActionButton(
                    shape: const CircleBorder(),
                    onPressed:
                        state.loading ? null : () => _edit(context, overview),
                    tooltip: 'Nova aplicação',
                    child: const Icon(Icons.add),
                  ),
            body: overview == null && state.loading
                ? const Center(child: CircularProgressIndicator())
                : state.error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(state.error!),
                            TextButton(
                              onPressed: context.read<InvestmentsCubit>().load,
                              child: const Text('Tentar novamente'),
                            ),
                          ],
                        ),
                      )
                    : overview == null
                        ? const SizedBox.shrink()
                        : RefreshIndicator(
                            onRefresh: context.read<InvestmentsCubit>().load,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 100),
                              children: [
                                ModuleHero(
                                    label: 'Saldo atual das aplicações',
                                    value: MoneyMinor.display(
                                        overview.investedMinor, 'BRL'),
                                    icon: Icons.savings_outlined,
                                    children: [
                                      Text(
                                          'Total em contas (BRL): ${MoneyMinor.display(overview.financialAssetsMinor, 'BRL')}',
                                          style: const TextStyle(fontSize: 13)),
                                      const ModuleDetails(
                                          title: 'Como o saldo é calculado',
                                          children: [
                                            Text(
                                                'Soma os saldos das contas em reais, incluindo as aplicações e as contas fora do saldo do mês.')
                                          ]),
                                    ]),
                                if (overview.investments.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      'Cadastre um CDB, uma conta remunerada pelo CDI ou uma poupança. '
                                      'Você pode vincular uma conta que já utiliza no Somia.',
                                    ),
                                  ),
                                for (final item in overview.investments)
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.name,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'Editar aplicação',
                                                onPressed: () => _edit(
                                                    context, overview, item),
                                                icon: const Icon(
                                                    Icons.edit_outlined),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            [
                                              item.kind.label,
                                              if (item.institution.isNotEmpty)
                                                item.institution,
                                              if (item.account.isArchived)
                                                'Arquivada',
                                            ].join(' · '),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            MoneyMinor.display(
                                              item.account.currentBalanceMinor,
                                              'BRL',
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                    fontWeight:
                                                        FontWeight.w700),
                                          ),
                                          Text('Conta: ${item.account.name}'),
                                          if (item.maturityDate != null)
                                            Text(
                                              'Vencimento: ${item.maturityDate!.day}/${item.maturityDate!.month}/${item.maturityDate!.year}',
                                            ),
                                          if (item.notes.isNotEmpty)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 8),
                                              child: ModuleDetails(
                                                  title: 'Observações',
                                                  children: [Text(item.notes)]),
                                            ),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              if (!item.account.isArchived)
                                                PopupMenuButton<
                                                    InvestmentAction>(
                                                  tooltip:
                                                      'Movimentar aplicação',
                                                  onSelected: (action) =>
                                                      _operation(
                                                          context,
                                                          overview,
                                                          item,
                                                          action),
                                                  itemBuilder: (_) => [
                                                    for (final action
                                                        in InvestmentAction
                                                            .values)
                                                      PopupMenuItem(
                                                          value: action,
                                                          child: Text(
                                                              action.label))
                                                  ],
                                                  child: const Chip(
                                                      avatar: Icon(
                                                          Icons.swap_vert,
                                                          size: 18),
                                                      label:
                                                          Text('Movimentar')),
                                                ),
                                              TextButton(
                                                onPressed: () => context.go(
                                                  '${AppRoutes.accountsPath}/${item.account.id}',
                                                ),
                                                child:
                                                    const Text('Ver extrato'),
                                              ),
                                              ModuleDetails(
                                                  title: 'Gerenciar aplicação',
                                                  children: [
                                                    TextButton(
                                                      onPressed: () => _delete(
                                                          context, item),
                                                      child: const Text(
                                                          'Excluir aplicação'),
                                                    ),
                                                    TextButton(
                                                      onPressed: () => _archive(
                                                          context, item),
                                                      child: Text(
                                                        item.account.isArchived
                                                            ? 'Reativar'
                                                            : 'Arquivar',
                                                      ),
                                                    ),
                                                  ]),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
          ));
        },
      );
}
