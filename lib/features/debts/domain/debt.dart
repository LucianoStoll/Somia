enum DebtKind {
  loan('Empréstimo'),
  financing('Financiamento'),
  other('Outra dívida');

  const DebtKind(this.label);
  final String label;
}

class DebtPayment {
  const DebtPayment(
      {required this.id,
      required this.transactionId,
      required this.description,
      required this.amountMinor,
      required this.principalMinor,
      required this.date,
      required this.effective,
      required this.deleted,
      required this.unlinked});
  final String id, transactionId, description;
  final int amountMinor, principalMinor;
  final DateTime date;
  final bool effective, deleted, unlinked;
  bool get active => !deleted && !unlinked;
  int get chargesMinor => amountMinor - principalMinor;
}

class Debt {
  const Debt(
      {required this.id,
      required this.name,
      required this.creditor,
      required this.kind,
      required this.initialMinor,
      required this.referenceAt,
      required this.payments,
      this.assetId,
      this.notes = ''});
  final String id, name, creditor, notes;
  final String? assetId;
  final DebtKind kind;
  final int initialMinor;
  final DateTime referenceAt;
  final List<DebtPayment> payments;
  int get paidPrincipalMinor => payments
      .where((p) => p.active && p.effective)
      .fold(0, (s, p) => s + p.principalMinor);
  int get reservedPrincipalMinor =>
      payments.where((p) => p.active).fold(0, (s, p) => s + p.principalMinor);
  int get balanceMinor => initialMinor - paidPrincipalMinor;
  int get projectedMinor => initialMinor - reservedPrincipalMinor;
}

class DebtDraft {
  const DebtDraft(
      {required this.name,
      required this.creditor,
      required this.kind,
      required this.balanceMinor,
      required this.referenceAt,
      this.assetId,
      this.notes = ''});
  final String name, creditor, notes;
  final DebtKind kind;
  final int balanceMinor;
  final DateTime referenceAt;
  final String? assetId;
}

class DebtExpense {
  const DebtExpense(
      {required this.id,
      required this.description,
      required this.amountMinor,
      required this.date,
      required this.effective});
  final String id, description;
  final int amountMinor;
  final DateTime date;
  final bool effective;
}

abstract interface class DebtsRepository {
  Future<List<Debt>> load();
  Future<String> save(DebtDraft draft, {String? id});
  Future<List<DebtExpense>> expenses(String debtId);
  Future<void> link(String debtId, String transactionId, int principalMinor);
  Future<void> unlink(String paymentId);
}
