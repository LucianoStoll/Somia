import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/filters/reference_month.dart';
import '../domain/account.dart';
import '../domain/accounts_repository.dart';

class AccountsState {
  const AccountsState(
      {required this.month,
      this.accounts = const [],
      this.loading = false,
      this.error});

  final DateTime month;
  final List<Account> accounts;
  final bool loading;
  final String? error;
}

class AccountsCubit extends Cubit<AccountsState> {
  AccountsCubit(this._repository, {ReferenceMonth? selection})
      : _selection = selection ?? referenceMonth,
        super(AccountsState(month: (selection ?? referenceMonth).value)) {
    _selection.addListener(_monthChanged);
    load();
  }

  final AccountsRepository _repository;
  final ReferenceMonth _selection;
  int _request = 0;

  void _monthChanged() => load();

  Future<void> load() async {
    final request = ++_request;
    final month = _selection.value;
    final end = DateTime(month.year, month.month + 1, 0);
    emit(AccountsState(month: month, accounts: state.accounts, loading: true));
    try {
      final accounts = await _repository.list(asOf: end, through: end);
      if (isClosed || request != _request) return;
      emit(AccountsState(month: month, accounts: accounts));
    } catch (_) {
      if (isClosed || request != _request) return;
      emit(AccountsState(
          month: month,
          accounts: state.accounts,
          error: 'Não foi possível carregar as contas.'));
    }
  }

  Future<void> save(AccountDraft draft, {String? id}) async {
    if (id == null) {
      await _repository.create(draft);
    } else {
      await _repository.update(id, draft);
    }
    await load();
  }

  Future<void> toggleBalance(Account account) => save(
      AccountDraft(
          name: account.name,
          type: account.type,
          currencyCode: account.currencyCode,
          initialBalanceMinor: account.initialBalanceMinor,
          includeInAnalytics: account.includeInAnalytics,
          includeInBalance: !account.includeInBalance,
          institutionId: account.institutionId),
      id: account.id);

  Future<void> setArchived(Account account) async {
    await _repository.setArchived(account.id, archived: !account.isArchived);
    await load();
  }

  @override
  Future<void> close() {
    _selection.removeListener(_monthChanged);
    return super.close();
  }
}
