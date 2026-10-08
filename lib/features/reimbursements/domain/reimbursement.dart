class Person {
  const Person(this.id, this.name, this.aliases, this.archived);
  final String id, name, aliases;
  final bool archived;
}

class ReimbursementDraft {
  const ReimbursementDraft(this.personId, this.amountMinor, {this.id});
  final String personId;
  final int amountMinor;
  final String? id;
  String get signature => '$id:$personId:$amountMinor';
}

class ReimbursementReceipt {
  const ReimbursementReceipt(this.id, this.transactionId, this.description,
      this.amountMinor, this.date, this.effective, this.deleted);
  final String id, transactionId, description;
  final int amountMinor;
  final DateTime date;
  final bool effective, deleted;
}

class Reimbursement {
  const Reimbursement(this.id, this.personId, this.personName, this.description,
      this.currency, this.amountMinor, this.receipts);
  final String id, personId, personName, description, currency;
  final int amountMinor;
  final List<ReimbursementReceipt> receipts;
  int get received => receipts
      .where((r) => r.effective && !r.deleted)
      .fold(0, (a, r) => a + r.amountMinor);
  int get scheduled => receipts
      .where((r) => !r.effective && !r.deleted)
      .fold(0, (a, r) => a + r.amountMinor);
  int get pending => amountMinor - received;
  int get available => pending - scheduled;
}
