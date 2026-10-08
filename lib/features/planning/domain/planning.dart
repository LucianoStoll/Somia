class MonthlySpend {
  const MonthlySpend(this.categoryId, this.parentId, this.currency, this.type,
      this.realized, this.projected);
  final String? categoryId, parentId;
  final String currency, type;
  final int realized, projected;
  bool matches(String id) => categoryId == id || parentId == id;
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
