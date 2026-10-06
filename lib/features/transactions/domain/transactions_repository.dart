import '../../../core/series/movement_series.dart';
import 'financial_transaction.dart';

abstract interface class TransactionsRepository {
  Future<List<FinancialTransaction>> list([TransactionFilter filter]);
  Future<FinancialTransaction> create(TransactionDraft draft);
  Future<FinancialTransaction> update(String id, TransactionDraft draft);
  Future<void> setEffective(String id,
      {required bool effective, DateTime? effectiveDate});

  /// Altera apenas a efetivação se a data ainda corresponder à ação original.
  Future<void> changeEffectiveDate(String id,
      {required DateTime expectedDate, DateTime? effectiveDate});

  /// Atualiza só o valor; rejeita uma edição baseada em um valor antigo.
  Future<void> updateAmount(String id,
      {required int expectedAmountMinor,
      required int amountMinor,
      SeriesScope scope = SeriesScope.onlyThis});
  Future<void> delete(String id, {SeriesScope scope = SeriesScope.onlyThis});
}
