import '../../../balances/domain/balance_details.dart';

class DashboardCurrencySummary {
  const DashboardCurrencySummary(
      {required this.currencyCode,
      required this.currentBalanceMinor,
      required this.projectedBalanceMinor,
      required this.incomeMinor,
      required this.expenseMinor,
      this.expensesByCategory = const [],
      this.history = const [],
      this.accounts = const [],
      this.balanceDetails});

  final BalanceDetails? balanceDetails;
  final String currencyCode;
  final int currentBalanceMinor;
  final int projectedBalanceMinor;
  final int incomeMinor;
  final int expenseMinor;
  final List<DashboardCategoryExpense> expensesByCategory;
  final List<DashboardMonthTotal> history;
  final List<DashboardAccountBalance> accounts;
  int get monthlyResultMinor => incomeMinor - expenseMinor;
}

class DashboardMonthTotal {
  const DashboardMonthTotal(this.month, this.incomeMinor, this.expenseMinor);
  final DateTime month;
  final int incomeMinor;
  final int expenseMinor;
}

class DashboardAccountBalance {
  const DashboardAccountBalance(
      this.name, this.typeLabel, this.currencyCode, this.currentMinor);
  final String name;
  final String typeLabel;
  final String currencyCode;
  final int currentMinor;
}

class DashboardCategoryExpense {
  const DashboardCategoryExpense(this.name, this.amountMinor);
  final String name;
  final int amountMinor;
}

enum DashboardActivityType { income, expense, transfer }

class DashboardActivity {
  const DashboardActivity(
      {required this.id,
      required this.type,
      required this.description,
      required this.accountLabel,
      required this.currencyCode,
      required this.amountMinor,
      required this.date,
      required this.isEffective});

  final String id;
  final DashboardActivityType type;
  final String description;
  final String accountLabel;
  final String currencyCode;
  final int amountMinor;
  final DateTime date;
  final bool isEffective;
}

class DashboardSummary {
  const DashboardSummary(
      {required this.month, required this.currencies, required this.recent});

  final DateTime month;
  final List<DashboardCurrencySummary> currencies;
  final List<DashboardActivity> recent;

  bool get isEmpty => currencies.isEmpty && recent.isEmpty;
}
