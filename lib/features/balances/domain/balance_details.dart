/// Composição do saldo consolidado de uma única moeda no corte mensal.
class BalanceDetails {
  const BalanceDetails(
      {required this.openingMinor,
      this.incomeMinor = 0,
      this.expenseMinor = 0,
      this.transferInMinor = 0,
      this.transferOutMinor = 0,
      this.cardPaymentsMinor = 0,
      this.pendingIncomeMinor = 0,
      this.pendingExpenseMinor = 0,
      this.pendingTransferInMinor = 0,
      this.pendingTransferOutMinor = 0,
      this.pendingInvoicesMinor = 0});
  final int openingMinor,
      incomeMinor,
      expenseMinor,
      transferInMinor,
      transferOutMinor,
      cardPaymentsMinor;
  final int pendingIncomeMinor,
      pendingExpenseMinor,
      pendingTransferInMinor,
      pendingTransferOutMinor,
      pendingInvoicesMinor;
  int get currentMinor =>
      openingMinor +
      incomeMinor -
      expenseMinor +
      transferInMinor -
      transferOutMinor -
      cardPaymentsMinor;
  int get projectedMinor =>
      currentMinor +
      pendingIncomeMinor -
      pendingExpenseMinor +
      pendingTransferInMinor -
      pendingTransferOutMinor -
      pendingInvoicesMinor;
}
