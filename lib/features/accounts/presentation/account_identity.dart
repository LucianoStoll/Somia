import 'package:flutter/material.dart';

import '../domain/account.dart';
import '../domain/bank_institution.dart';

class AccountAvatar extends StatelessWidget {
  const AccountAvatar(
      {super.key,
      this.institutionId,
      this.type = AccountType.other,
      this.size = 40});

  final String? institutionId;
  final AccountType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bank = BankInstitution.find(institutionId);
    final fallback = Icon(
      type == AccountType.cash
          ? Icons.account_balance_wallet_outlined
          : Icons.account_balance_outlined,
      size: size * .6,
      color: Theme.of(context).colorScheme.primary,
    );
    return Semantics(
      label: bank?.name ?? type.label,
      image: true,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(bank == null ? 0 : size * .1),
        decoration: BoxDecoration(
          color: bank == null
              ? Theme.of(context).colorScheme.primary.withValues(alpha: .12)
              : Colors.white,
          borderRadius: BorderRadius.circular(size * .22),
        ),
        child: bank == null
            ? fallback
            : Image.asset(
                bank.assetPath,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                errorBuilder: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

/// O mesmo conteúdo no item aberto e no valor selecionado dos lançamentos.
class AccountOption extends StatelessWidget {
  const AccountOption(
      {super.key, required this.account, this.showCurrency = false});

  final Account account;
  final bool showCurrency;

  @override
  Widget build(BuildContext context) => Row(children: [
        AccountAvatar(
            institutionId: account.institutionId, type: account.type, size: 28),
        const SizedBox(width: 8),
        Expanded(
            child: Text(
          '${account.name}${showCurrency ? ' (${account.currencyCode})' : ''}'
          '${account.isArchived ? ' (arquivada)' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        )),
      ]);
}
