/// Recebimentos e pagamentos efetivos das contas incluídas no consolidado.
class MonthlyCashFlow {
  const MonthlyCashFlow(
      {this.incomeMinor = 0,
      this.expenseMinor = 0,
      this.cardPaymentsMinor = 0});
  final int incomeMinor, expenseMinor, cardPaymentsMinor;
  int get paidMinor => expenseMinor + cardPaymentsMinor;
}

abstract interface class MonthlyCashFlowRepository {
  Future<Map<String, MonthlyCashFlow>> load(DateTime month);
}
