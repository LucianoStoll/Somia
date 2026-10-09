import '../../accounts/domain/account.dart';

class AnalysisExpense {
  const AnalysisExpense(
      {required this.id,
      required this.description,
      required this.source,
      required this.currency,
      required this.date,
      required this.category,
      required this.subcategory,
      required this.amount});
  final String id, description, source, currency, category, subcategory;
  final DateTime date;
  final int amount;
}

class ExpenseComparison {
  const ExpenseComparison(
      this.category, this.current, this.previous, this.average);
  final String category;
  final int current, previous, average;
  int get difference => current - previous;
  double? get changePercent =>
      previous == 0 ? null : difference * 100 / previous.abs();
}

class FutureCommitment {
  const FutureCommitment(this.month, this.expenses, this.cards);
  final DateTime month;
  final List<AnalysisExpense> expenses, cards;
  int get expenseTotal => expenses.fold(0, (s, e) => s + e.amount);
  int get cardTotal => cards.fold(0, (s, e) => s + e.amount);
  int get total => expenseTotal + cardTotal;
}

class ExpenseAnalysis {
  const ExpenseAnalysis(
      this.month, this.expenses, this.commitments, this.accounts);
  final DateTime month;
  final List<AnalysisExpense> expenses;
  final Map<String, List<FutureCommitment>> commitments;
  final List<Account> accounts;
  List<String> get currencies => ({
        ...expenses.map((e) => e.currency),
        ...accounts.map((a) => a.currencyCode),
        ...commitments.keys
      }.toList()
        ..sort());
  List<AnalysisExpense> inMonth(String currency, DateTime period) => expenses
      .where((e) =>
          e.currency == currency &&
          e.date.year == period.year &&
          e.date.month == period.month)
      .toList();
  List<ExpenseComparison> comparisons(String currency) {
    final maps = <Map<String, int>>[];
    for (var i = 0; i < 4; i++) {
      final values = <String, int>{};
      for (final e
          in inMonth(currency, DateTime(month.year, month.month - i))) {
        values.update(e.category, (v) => v + e.amount,
            ifAbsent: () => e.amount);
      }
      maps.add(values);
    }
    final keys = maps.expand((m) => m.keys).toSet();
    return [
      for (final key in keys)
        ExpenseComparison(
            key,
            maps[0][key] ?? 0,
            maps[1][key] ?? 0,
            ((maps[1][key] ?? 0) + (maps[2][key] ?? 0) + (maps[3][key] ?? 0)) ~/
                3)
    ]..sort((a, b) => b.current.compareTo(a.current));
  }

  Map<AccountType, int> balances(String currency) {
    final values = <AccountType, int>{};
    for (final a
        in accounts.where((a) => a.currencyCode == currency && !a.isArchived)) {
      values.update(a.type, (v) => v + a.currentBalanceMinor,
          ifAbsent: () => a.currentBalanceMinor);
    }
    return values;
  }
}
