import '../../transfers/domain/transfer.dart';
import 'financial_transaction.dart';

/// Transferências não possuem categoria, estabelecimento nem tags.
bool matchesTransferMovement(Transfer item, TransactionFilter filter) {
  if (filter.type != null ||
      filter.categoryId != null ||
      filter.tag != null ||
      filter.establishment != null) {
    return false;
  }
  if (filter.accountId != null &&
      item.sourceAccountId != filter.accountId &&
      item.destinationAccountId != filter.accountId) {
    return false;
  }
  if (filter.status == TransactionStatus.effective && !item.isEffective ||
      filter.status == TransactionStatus.pending && item.isEffective) {
    return false;
  }
  return TransferFilter(
          from: filter.from,
          to: filter.to,
          accountId: filter.accountId,
          dateField: switch (filter.dateField) {
            TransactionDateField.posted => TransferDateField.posted,
            TransactionDateField.due => TransferDateField.due,
            TransactionDateField.effective => TransferDateField.effective,
            TransactionDateField.activity => TransferDateField.activity,
          })
      .matches(item);
}
