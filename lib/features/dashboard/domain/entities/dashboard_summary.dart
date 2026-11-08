import '../../../balances/domain/balance_details.dart';

class DashboardCurrencySummary {
  const DashboardCurrencySummary(
      {required this.currencyCode,
      required this.currentBalanceMinor,
      required this.projectedBalanceMinor,
      required this.incomeMinor,
      required this.expenseMinor,
      this.realizedIncomeMinor = 0,
      this.realizedExpenseMinor = 0,
      this.realizedExpensesByCategory = const [],
      this.transferCount = 0,
      this.transferredMinor = 0,
      this.pendingTransferMinor = 0,
      this.expensesByCategory = const [],
      this.history = const [],
      this.accounts = const [],
      this.balanceDetails,
      this.dailyBalances = const [],
      this.upcoming = const []});

  final List<DashboardDailyBalance> dailyBalances;
  final List<DashboardDue> upcoming;
  final BalanceDetails? balanceDetails;
  final String currencyCode;
  final int currentBalanceMinor;
  final int projectedBalanceMinor;
  final int realizedIncomeMinor, realizedExpenseMinor;
  final List<DashboardCategoryExpense> realizedExpensesByCategory;
  final int incomeMinor;
  final int expenseMinor;
  final int transferCount, transferredMinor, pendingTransferMinor;
  final List<DashboardCategoryExpense> expensesByCategory;
  final List<DashboardMonthTotal> history;
  final List<DashboardAccountBalance> accounts;
  int get monthlyResultMinor => incomeMinor - expenseMinor;

  /// Analytics follow the same date/category rules as the projected charts.
  /// Cash balances and invoice payments are not reclassified by this view.
  DashboardCurrencySummary forAnalysis({required bool realized}) =>
      DashboardCurrencySummary(
        currencyCode: currencyCode,
        currentBalanceMinor: currentBalanceMinor,
        projectedBalanceMinor: projectedBalanceMinor,
        incomeMinor: realized ? realizedIncomeMinor : incomeMinor,
        expenseMinor: realized ? realizedExpenseMinor : expenseMinor,
        expensesByCategory:
            realized ? realizedExpensesByCategory : expensesByCategory,
        history: [
          for (final item in history)
            DashboardMonthTotal(
              item.month,
              realized ? item.realizedIncomeMinor : item.incomeMinor,
              realized ? item.realizedExpenseMinor : item.expenseMinor,
            ),
        ],
      );
}

class DashboardMonthTotal {
  const DashboardMonthTotal(this.month, this.incomeMinor, this.expenseMinor,
      {this.realizedIncomeMinor = 0, this.realizedExpenseMinor = 0});
  final int realizedIncomeMinor, realizedExpenseMinor;
  final DateTime month;
  final int incomeMinor;
  final int expenseMinor;
}

class DashboardAccountBalance {
  const DashboardAccountBalance(
      this.name, this.typeLabel, this.currencyCode, this.currentMinor,
      {this.id,
      this.institutionId,
      this.includeInBalance = true,
      this.isInvestment = false});
  final String? id, institutionId;
  final bool includeInBalance, isInvestment;
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
      required this.isEffective,
      this.cardId});

  final String id;
  final DashboardActivityType type;
  final String description;
  final String accountLabel;
  final String currencyCode;
  final int amountMinor;
  final DateTime date;
  final bool isEffective;

  /// Identifica compras no cartão separadamente das despesas de conta.
  final String? cardId;
}

class DashboardSummary {
  const DashboardSummary(
      {required this.month, required this.currencies, required this.recent});

  final DateTime month;
  final List<DashboardCurrencySummary> currencies;
  final List<DashboardActivity> recent;

  bool get isEmpty => currencies.isEmpty && recent.isEmpty;
}

class DashboardDailyBalance {
  const DashboardDailyBalance(
      this.date, this.currentMinor, this.projectedMinor);
  final DateTime date;
  final int currentMinor, projectedMinor;
}

class DashboardDue {
  const DashboardDue(
      {required this.id,
      required this.description,
      required this.date,
      required this.amountMinor,
      required this.kind,
      this.canSettle = false,
      this.cardId});
  final String id, description, kind;
  final String? cardId;
  final DateTime date;
  final int amountMinor;
  final bool canSettle;
  bool isOverdue(DateTime today) =>
      DateTime.utc(date.year, date.month, date.day)
          .isBefore(DateTime.utc(today.year, today.month, today.day));
}

enum DashboardAnalysisMode { realized, projected, both }
