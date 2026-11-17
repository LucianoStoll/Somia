import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injection.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../categories/domain/categories_repository.dart';
import '../../transactions/domain/financial_transaction.dart';
import '../../transactions/domain/transactions_repository.dart';
import '../../transactions/presentation/transactions_page.dart';
import '../../transfers/domain/transfer.dart';
import '../../transfers/domain/transfers_repository.dart';
import '../../transfers/presentation/transfers_page.dart';
import '../domain/account.dart';
import '../domain/accounts_repository.dart';
import 'accounts_cubit.dart';

Future<void> showAccountMovementActions(
    BuildContext context, Account account) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
          padding: const EdgeInsets.all(16),
          child:
              Text(account.name, style: Theme.of(sheet).textTheme.titleLarge)),
      for (final (id, title, icon, color) in [
        ('income', 'Receita', Icons.add, SomiaColors.green),
        ('expense', 'Despesa', Icons.remove, SomiaColors.red),
        ('transfer', 'Transferência', Icons.swap_vert, SomiaColors.yellow),
      ])
        ListTile(
            leading: Icon(icon, color: color),
            title: Text(title),
            onTap: () => Navigator.pop(sheet, id)),
      const SizedBox(height: 16),
    ])),
  );
  if (action == null || !context.mounted) return;
  final cubit = context.read<AccountsCubit>();
  try {
    final all = await getIt<AccountsRepository>().list();
    // Existing forms select the first active account. Put the tapped account
    // first while preserving all other choices and currency validation.
    final accounts = [
      ...all.where((a) => a.id == account.id && !a.isArchived),
      ...all.where((a) => a.id != account.id && !a.isArchived),
    ];
    if (!context.mounted) return;
    if (!accounts.any((a) => a.id == account.id)) {
      throw StateError('Esta conta não está disponível para novos movimentos.');
    }
    if (action == 'transfer') {
      final draft = await showMovementForm<TransferDraft>(
          context, (_) => TransferForm(accounts: accounts));
      if (draft == null) return;
      await getIt<TransfersRepository>().create(draft);
    } else {
      final categories = await getIt<CategoriesRepository>().list();
      if (!context.mounted) return;
      final type =
          action == 'income' ? TransactionType.income : TransactionType.expense;
      final draft = await showMovementForm<TransactionDraft>(
          context,
          (_) => TransactionForm(
              accounts: accounts,
              categories: categories,
              initialType: type,
              fixedType: type));
      if (draft == null) return;
      await getIt<TransactionsRepository>().create(draft);
    }
    if (!cubit.isClosed) await cubit.load();
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error is StateError
            ? error.message
            : error is FormatException
                ? error.message
                : 'Não foi possível salvar o movimento.')));
  }
}
