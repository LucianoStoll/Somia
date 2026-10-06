import '../../../core/series/movement_series.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../domain/transfer.dart';
import '../domain/transfers_repository.dart';

class TransfersState {
  const TransfersState(
      {this.items = const [],
      this.accounts = const [],
      this.loading = false,
      this.filter = const TransferFilter(),
      this.error});

  final TransferFilter filter;
  final List<Transfer> items;
  final List<Account> accounts;
  final bool loading;
  final String? error;
}

class TransfersCubit extends Cubit<TransfersState> {
  TransfersCubit(this._transfers, this._accounts, {DateTime? month})
      : super(TransfersState(
            filter: TransferFilter(
                from: month == null ? null : DateTime(month.year, month.month),
                to: month == null
                    ? null
                    : DateTime(month.year, month.month + 1, 0)))) {
    load();
  }

  int _request = 0;
  final TransfersRepository _transfers;
  final AccountsRepository _accounts;

  Future<void> load([TransferFilter? filter]) async {
    final request = ++_request;
    final selected = filter ?? state.filter;
    emit(TransfersState(
        items: state.items,
        accounts: state.accounts,
        filter: selected,
        loading: true));
    try {
      final items = await _transfers.list();
      final accounts = await _accounts.list();
      if (!isClosed && request == _request) {
        emit(TransfersState(
            items: items.where(selected.matches).toList(),
            accounts: accounts,
            filter: selected));
      }
    } catch (_) {
      if (!isClosed && request == _request) {
        emit(TransfersState(
            filter: selected,
            items: state.items,
            accounts: state.accounts,
            error: 'Não foi possível carregar as transferências.'));
      }
    }
  }

  Future<void> save(TransferDraft draft, {String? id}) async {
    if (id == null) {
      await _transfers.create(draft);
    } else {
      await _transfers.update(id, draft);
    }
    if (!isClosed) await load();
  }

  Future<void> updateAmount(String id,
      {required int expectedAmountMinor,
      required int amountMinor,
      SeriesScope scope = SeriesScope.onlyThis}) async {
    await _transfers.updateAmount(id,
        expectedAmountMinor: expectedAmountMinor,
        amountMinor: amountMinor,
        scope: scope);
    if (!isClosed) await load();
  }

  Future<void> delete(String id,
      {SeriesScope scope = SeriesScope.onlyThis}) async {
    await _transfers.delete(id, scope: scope);
    if (!isClosed) await load();
  }

  Future<void> setEffective(String id,
      {required bool effective, DateTime? effectiveDate}) async {
    await _transfers.setEffective(id,
        effective: effective, effectiveDate: effectiveDate);
    if (!isClosed) await load();
  }

  Future<void> changeEffectiveDate(String id,
      {required DateTime expectedDate, DateTime? effectiveDate}) async {
    await _transfers.changeEffectiveDate(id,
        expectedDate: expectedDate, effectiveDate: effectiveDate);
    if (!isClosed) await load();
  }
}
