import '../../balances/domain/monthly_cash_flow.dart';
import '../../../core/series/movement_series.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../categories/domain/categories_repository.dart';
import '../../categories/domain/category.dart';
import '../domain/financial_transaction.dart';
import '../domain/transactions_repository.dart';
import '../domain/transfer_movement_filter.dart';
import '../../transfers/domain/transfer.dart';
import '../../transfers/domain/transfers_repository.dart';

class TransactionsState {
  const TransactionsState({
    this.items = const [],
    this.transfers = const [],
    this.cashFlow,
    this.accounts = const [],
    this.categories = const [],
    this.filter = const TransactionFilter(),
    this.loading = false,
    this.error,
  });

  final List<FinancialTransaction> items;
  final List<Transfer> transfers;
  final Map<String, MonthlyCashFlow>? cashFlow;
  final List<Account> accounts;
  final List<FinanceCategory> categories;
  final TransactionFilter filter;
  final bool loading;
  final String? error;
}

class TransactionsCubit extends Cubit<TransactionsState> {
  TransactionsCubit(this._transactions, this._accounts, this._categories,
      {TransactionType? sectionType,
      DateTime? month,
      TransfersRepository? transfers,
      MonthlyCashFlowRepository? cashFlow})
      : _transfers = sectionType == null ? transfers : null,
        _cashFlow = sectionType == null ? cashFlow : null,
        _summaryMonth =
            month ?? DateTime(DateTime.now().year, DateTime.now().month),
        super(TransactionsState(
            filter: TransactionFilter(
                dateField: TransactionDateField.activity,
                type: sectionType,
                from: month == null ? null : DateTime(month.year, month.month),
                to: month == null
                    ? null
                    : DateTime(month.year, month.month + 1, 0)))) {
    load();
  }

  int _request = 0;
  final TransactionsRepository _transactions;
  final AccountsRepository _accounts;
  final CategoriesRepository _categories;
  final TransfersRepository? _transfers;
  final MonthlyCashFlowRepository? _cashFlow;
  DateTime _summaryMonth;

  Future<void> load([TransactionFilter? filter, DateTime? month]) async {
    final request = ++_request;
    final nextFilter = filter ?? state.filter;
    final monthChanged = month != null && month != _summaryMonth;
    _summaryMonth = month ?? _summaryMonth;
    final selectedMonth = _summaryMonth;
    emit(TransactionsState(
        items: state.items,
        transfers: state.transfers,
        cashFlow: monthChanged && _cashFlow != null ? const {} : state.cashFlow,
        accounts: state.accounts,
        categories: state.categories,
        filter: nextFilter,
        loading: true));
    try {
      final items = await _transactions.list(nextFilter);
      final transfers = _transfers == null
          ? <Transfer>[]
          : (await _transfers.list(accountId: nextFilter.accountId))
              .where((item) => matchesTransferMovement(item, nextFilter))
              .toList();
      final cashFlow = await _cashFlow?.load(selectedMonth);
      final accounts = await _accounts.list();
      final categories = await _categories.list();
      if (!isClosed && request == _request) {
        emit(TransactionsState(
            items: items,
            transfers: transfers,
            cashFlow: cashFlow,
            accounts: accounts,
            categories: categories,
            filter: nextFilter));
      }
    } catch (_) {
      if (!isClosed && request == _request) {
        emit(TransactionsState(
            items: state.items,
            transfers: state.transfers,
            cashFlow: state.cashFlow,
            accounts: state.accounts,
            categories: state.categories,
            filter: nextFilter,
            error: 'Não foi possível carregar os lançamentos.'));
      }
    }
  }

  Future<void> save(TransactionDraft draft, {String? id}) async {
    if (id == null) {
      await _transactions.create(draft);
    } else {
      await _transactions.update(id, draft);
    }
    if (!isClosed) {
      await load();
    }
  }

  Future<void> updateAmount(String id,
      {required int expectedAmountMinor,
      required int amountMinor,
      SeriesScope scope = SeriesScope.onlyThis}) async {
    await _transactions.updateAmount(id,
        expectedAmountMinor: expectedAmountMinor,
        amountMinor: amountMinor,
        scope: scope);
    if (!isClosed) await load();
  }

  Future<void> delete(String id,
      {SeriesScope scope = SeriesScope.onlyThis}) async {
    await _transactions.delete(id, scope: scope);
    if (!isClosed) {
      await load();
    }
  }

  Future<void> setEffective(String id,
      {required bool effective, DateTime? effectiveDate}) async {
    await _transactions.setEffective(id,
        effective: effective, effectiveDate: effectiveDate);
    if (!isClosed) await load();
  }

  Future<void> changeEffectiveDate(String id,
      {required DateTime expectedDate, DateTime? effectiveDate}) async {
    await _transactions.changeEffectiveDate(id,
        expectedDate: expectedDate, effectiveDate: effectiveDate);
    if (!isClosed) await load();
  }
}
