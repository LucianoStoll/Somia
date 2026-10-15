import '../../transfers/domain/transfer.dart';
import 'financial_transaction.dart';

enum MovementKind { transaction, transfer, cardEntry }

class MovementReference {
  const MovementReference(this.kind, this.id, this.revision);
  factory MovementReference.transaction(FinancialTransaction item) {
    if (item.id.startsWith('invoice:')) {
      throw StateError('Selecione as compras dentro da fatura.');
    }
    return MovementReference(
        item.cardId == null ? MovementKind.transaction : MovementKind.cardEntry,
        item.cardId == null ? item.id : item.id.substring(5),
        item.revision);
  }
  factory MovementReference.transfer(Transfer item) =>
      MovementReference(MovementKind.transfer, item.id, item.revision);
  final MovementKind kind;
  final String id, revision;
  String get table => switch (kind) {
        MovementKind.transaction => 'transactions',
        MovementKind.transfer => 'transfers',
        MovementKind.cardEntry => 'card_entries'
      };
  String get key => '${kind.name}/$id';
}

class BulkMovementPatch {
  const BulkMovementPatch(
      {this.description,
      this.amountMinor,
      this.accountId,
      this.destinationAccountId,
      this.changeCategory = false,
      this.categoryId,
      this.dueDate,
      this.postedDate,
      this.effective,
      this.effectiveDate,
      this.establishment,
      this.addTags = const [],
      this.removeTags = const []});
  final String? description,
      accountId,
      destinationAccountId,
      categoryId,
      establishment;
  final int? amountMinor;
  final bool changeCategory;
  final DateTime? dueDate, postedDate, effectiveDate;
  final bool? effective;
  final List<String> addTags, removeTags;
  bool get isEmpty =>
      description == null &&
      amountMinor == null &&
      accountId == null &&
      destinationAccountId == null &&
      !changeCategory &&
      dueDate == null &&
      postedDate == null &&
      effective == null &&
      establishment == null &&
      addTags.isEmpty &&
      removeTags.isEmpty;
}

class TrashedMovement {
  const TrashedMovement(
      {required this.ref,
      required this.description,
      required this.amountMinor,
      required this.currencyCode,
      required this.deletedAt,
      required this.contextLabel});
  final MovementReference ref;
  final String description, currencyCode, contextLabel;
  final int amountMinor;
  final DateTime deletedAt;
}
