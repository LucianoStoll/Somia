import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/account.dart';
import '../domain/account_statement.dart';
import '../domain/money_minor.dart';
import 'account_identity.dart';

/// The ledger and balances share the statement's month and effective-date cutoff.
class AccountSummaryCard extends StatelessWidget {
  const AccountSummaryCard(
      {super.key,
      required this.account,
      required this.statement,
      required this.onOpen,
      required this.onAdd,
      required this.onAction});

  final Account account;
  final AccountStatement statement;
  final VoidCallback onOpen, onAdd;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final realized = statement.realized;
    final tags = [
      if (account.isArchived) 'Arquivada',
      if (!account.includeInAnalytics) 'Fora das análises',
      if (!account.includeInBalance) 'Fora do saldo consolidado',
    ];
    return Card(
      key: ValueKey('account-card-${account.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(12),
            child: Row(children: [
              AccountAvatar(
                  institutionId: account.institutionId,
                  type: account.type,
                  size: 44),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(account.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('${account.type.label} · ${account.currencyCode}',
                        style: const TextStyle(color: SomiaColors.muted)),
                  ])),
            ]),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            IconButton(
                key: ValueKey('account-add-${account.id}'),
                tooltip: 'Adicionar movimento nesta conta',
                onPressed: account.isArchived ? null : onAdd,
                icon: const Icon(Icons.add, color: SomiaColors.blue)),
            IconButton(
                key: ValueKey('account-statement-${account.id}'),
                tooltip: 'Abrir extrato',
                onPressed: onOpen,
                icon: const Icon(Icons.receipt_long_outlined,
                    color: SomiaColors.blue)),
            PopupMenuButton<String>(
              key: ValueKey('account-menu-${account.id}'),
              tooltip: 'Ações da conta',
              icon: const Icon(Icons.more_vert),
              onSelected: onAction,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(
                    value: 'balance',
                    child: Text(account.includeInBalance
                        ? 'Excluir do saldo do mês'
                        : 'Incluir no saldo do mês')),
                PopupMenuItem(
                    value: 'archive',
                    child: Text(account.isArchived ? 'Reativar' : 'Arquivar')),
              ],
            ),
          ]),
          if (tags.isNotEmpty) ...[
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final tag in tags)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: SomiaColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(tag,
                      style: const TextStyle(
                          fontSize: 12, color: SomiaColors.blue)),
                ),
            ]),
            const SizedBox(height: 8),
          ],
          const Divider(height: 20),
          _row(context, 'Saldo inicial do mês', realized.openingMinor,
              icon: Icons.account_balance_wallet_outlined),
          _row(context, 'Receitas', realized.total(StatementKind.income),
              icon: Icons.add, color: SomiaColors.green),
          _row(context, 'Transferências recebidas',
              realized.total(StatementKind.transferIn),
              icon: Icons.south, color: SomiaColors.green),
          _row(context, 'Transferências enviadas',
              realized.total(StatementKind.transferOut),
              icon: Icons.north, color: SomiaColors.red),
          _row(
              context,
              'Despesas',
              realized.total(StatementKind.expense) +
                  realized.total(StatementKind.cardPayment),
              icon: Icons.remove,
              color: SomiaColors.red),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: SomiaColors.surfaceHigh,
                borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              _row(context, 'Saldo atual', realized.closingMinor,
                  prominent: true,
                  color: realized.closingMinor < 0 ? SomiaColors.red : null),
              _row(context, 'Saldo previsto', statement.projected.closingMinor,
                  color: SomiaColors.blue),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, String label, int amount,
      {IconData? icon, Color? color, bool prominent = false}) {
    final value = Text(MoneyMinor.display(amount, account.currencyCode),
        textAlign: TextAlign.end,
        style: TextStyle(
            color: amount == 0 && !prominent ? SomiaColors.muted : color,
            fontSize: prominent ? 20 : 14,
            fontWeight: prominent ? FontWeight.w700 : FontWeight.w500));
    final caption = Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[
        Icon(icon, size: 18, color: color ?? SomiaColors.blue),
        const SizedBox(width: 8)
      ],
      Flexible(
          child: Text(label,
              style: TextStyle(
                  fontSize: prominent ? 18 : 14,
                  fontWeight: prominent ? FontWeight.w600 : FontWeight.normal,
                  color: prominent ? null : SomiaColors.muted))),
    ]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: LayoutBuilder(builder: (context, constraints) {
        // Keep large amounts and accessibility text readable without clipping.
        if (constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) > 19) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                caption,
                const SizedBox(height: 4),
                value,
              ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: caption),
          const SizedBox(width: 12),
          Flexible(
              flex: 2,
              child: Align(alignment: Alignment.centerRight, child: value)),
        ]);
      }),
    );
  }
}
