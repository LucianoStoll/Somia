import 'account.dart';

enum StatementKind {
  income,
  expense,
  transferIn,
  transferOut,
  cardPayment,
  invoice,
  adjustment
}

class StatementEntry {
  const StatementEntry(
      {required this.id,
      required this.description,
      required this.date,
      required this.amountMinor,
      required this.kind,
      required this.effective,
      this.detail});
  final String id, description;
  final String? detail;
  final DateTime date;
  final int amountMinor;
  final StatementKind kind;
  final bool effective;
}

class StatementDay {
  const StatementDay(
      {required this.date, required this.entries, required this.closingMinor});
  final DateTime date;
  final List<StatementEntry> entries;
  final int closingMinor;
}

class StatementSection {
  const StatementSection(
      {required this.openingMinor,
      required this.closingMinor,
      required this.days,
      required this.dailyBalances});
  final int openingMinor, closingMinor;
  final List<StatementDay> days;
  final List<int> dailyBalances;
  Iterable<StatementEntry> get entries => days.expand((d) => d.entries);
  int total(StatementKind kind) => entries
      .where((e) => e.kind == kind)
      .fold(0, (a, e) => a + e.amountMinor.abs());
  int get adjustmentsMinor => entries
      .where((e) => e.kind == StatementKind.adjustment)
      .fold(0, (a, e) => a + e.amountMinor);
  int get incomingMinor =>
      total(StatementKind.income) + total(StatementKind.transferIn);
  int get outgoingMinor =>
      total(StatementKind.expense) +
      total(StatementKind.transferOut) +
      total(StatementKind.cardPayment) +
      total(StatementKind.invoice);
}

class AccountStatement {
  const AccountStatement(
      {required this.account,
      required this.month,
      required this.realized,
      required this.projected});
  final Account account;
  final DateTime month;
  final StatementSection realized, projected;
}
