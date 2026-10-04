import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/filters/reference_month.dart';
import '../data/account_statement_repository.dart';
import '../domain/account_statement.dart';

class AccountStatementState {
  const AccountStatementState(
      {this.statement, this.loading = false, this.error});
  final AccountStatement? statement;
  final bool loading;
  final String? error;
}

class AccountStatementCubit extends Cubit<AccountStatementState> {
  AccountStatementCubit(this.repository, this.accountId,
      {ReferenceMonth? selection})
      : selection = selection ?? referenceMonth,
        super(const AccountStatementState()) {
    this.selection.addListener(_changed);
    load();
  }
  final AccountStatementRepository repository;
  final String accountId;
  final ReferenceMonth selection;
  int _request = 0;
  void _changed() => load();
  Future<void> load() async {
    final request = ++_request, month = selection.value;
    emit(AccountStatementState(statement: state.statement, loading: true));
    try {
      final statement = await repository.load(accountId, month);
      if (!isClosed && request == _request) {
        emit(AccountStatementState(statement: statement));
      }
    } catch (error) {
      if (!isClosed && request == _request) {
        emit(AccountStatementState(
            statement: state.statement,
            error: error is StateError
                ? error.message
                : 'Não foi possível carregar o extrato.'));
      }
    }
  }

  @override
  Future<void> close() {
    selection.removeListener(_changed);
    return super.close();
  }
}
