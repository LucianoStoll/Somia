class MonthlySpend {
  const MonthlySpend(this.categoryId, this.parentId, this.currency, this.type,
      this.realized, this.projected);
  final String? categoryId, parentId;
  final String currency, type;
  final int realized, projected;
  bool matches(String id) => categoryId == id || parentId == id;
}

/// Resultado do fluxo mensal; não é o saldo acumulado das contas.
class PlanningMonthIndicators {
  const PlanningMonthIndicators(this.income, this.expense);
  final int income, expense;
  int get result => income - expense;
  double? get savingRate => income <= 0 ? null : result * 100 / income;

  factory PlanningMonthIndicators.fromSpending(List<MonthlySpend> spending,
      {required String currency, required bool projected}) {
    var income = 0, expense = 0;
    for (final row in spending.where((s) => s.currency == currency)) {
      final value = projected ? row.projected : row.realized;
      if (row.type == 'income') income += value;
      if (row.type == 'expense') expense += value;
    }
    return PlanningMonthIndicators(income, expense);
  }
}

class BudgetLimit {
  const BudgetLimit(this.id, this.categoryId, this.name, this.currency,
      this.amount, this.realized, this.projected);
  final String id, categoryId, name, currency;
  final int amount, realized, projected;
}

class PlanningGoal {
  const PlanningGoal(
      {required this.id,
      required this.name,
      required this.kind,
      required this.currency,
      required this.target,
      required this.saved,
      required this.months,
      required this.essential,
      required this.accounts,
      required this.archived,
      this.deadline,
      required this.monthlyEssential});
  final String id, name, kind, currency;
  final int target, saved, months, monthlyEssential;
  final List<String> essential, accounts;
  final bool archived;
  final DateTime? deadline;
}

class GoalDraft {
  const GoalDraft(
      {required this.name,
      required this.kind,
      required this.currency,
      required this.target,
      required this.accounts,
      this.deadline,
      this.months = 6,
      this.essential = const []});
  final String name, kind, currency;
  final int target, months;
  final DateTime? deadline;
  final List<String> accounts, essential;
}

/// Valor atribuído à categoria consultada, que pode ser só parte de um rateio.
class PlanningEntry {
  const PlanningEntry({
    required this.id,
    required this.description,
    required this.source,
    required this.date,
    required this.amount,
    required this.fullAmount,
    required this.isCard,
  });
  final String id, description, source;
  final DateTime date;
  final int amount, fullAmount;
  final bool isCard;
}

typedef PlanningEntriesLoader = Future<List<PlanningEntry>> Function(
    DateTime month, String type, String currency, String? categoryId);

class PlanningCategoryChange {
  const PlanningCategoryChange(this.categoryId, this.current, this.previous);
  final String? categoryId;
  final int current, previous;
  int get difference => current - previous;
  double? get percent => previous <= 0 ? null : difference * 100 / previous;
}

class PlanningCategoryComparison {
  const PlanningCategoryComparison(this.total, this.changes);
  final PlanningCategoryChange total;
  final List<PlanningCategoryChange> changes;

  factory PlanningCategoryComparison.fromSpending({
    required List<MonthlySpend> current,
    required List<MonthlySpend> previous,
    required String? categoryId,
    required String currency,
    required String type,
  }) {
    Map<String?, int> group(List<MonthlySpend> rows) {
      final result = <String?, int>{};
      for (final row in rows.where((r) =>
          r.currency == currency &&
          r.type == type &&
          (r.parentId ?? r.categoryId) == categoryId)) {
        result.update(row.categoryId, (v) => v + row.projected,
            ifAbsent: () => row.projected);
      }
      return result;
    }

    final now = group(current), before = group(previous);
    final changes = [
      for (final id in {...now.keys, ...before.keys})
        PlanningCategoryChange(id, now[id] ?? 0, before[id] ?? 0),
    ].where((c) => c.difference != 0).toList()
      ..sort((a, b) {
        final diff = b.difference.abs().compareTo(a.difference.abs());
        return diff != 0
            ? diff
            : (a.categoryId ?? '').compareTo(b.categoryId ?? '');
      });
    return PlanningCategoryComparison(
        PlanningCategoryChange(
            categoryId,
            now.values.fold<int>(0, (sum, v) => sum + v),
            before.values.fold<int>(0, (sum, v) => sum + v)),
        changes);
  }
}
