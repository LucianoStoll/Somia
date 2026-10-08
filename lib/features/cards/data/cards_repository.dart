import '../../transactions/domain/transaction_tags.dart';
import '../../reimbursements/data/reimbursements_repository.dart';
import '../../../core/database/reimbursement_integrity.dart';
import '../../../core/allocations/category_allocation.dart';
import '../../../core/allocations/allocation_store.dart';

import 'dart:math' as math;
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/entity_metadata.dart';
import '../../../core/series/movement_series.dart';
import '../../transactions/domain/financial_transaction.dart';
import '../domain/credit_card.dart';

/// Ledger separado das contas. Cada encargo/crédito aparece uma vez;
/// carry-over é derivado, sem copiar dívida entre faturas.
class CardsRepository {
  const CardsRepository(this.db);
  final AppDatabase db;
  static const maxMoney = 9000000000000000;
  Future<List<QueryRow>> _rows(String sql, [List<Object> args = const []]) => db
      .customSelect(sql,
          variables: args
              .map((v) => v is int
                  ? Variable.withInt(v)
                  : Variable.withString(v as String))
              .toList())
      .get();
  Future<QueryRow> _one(String table, String id) async {
    final rows = await _rows('SELECT * FROM $table WHERE id = ?', [id]);
    if (rows.isEmpty) throw StateError('Registro não encontrado.');
    return rows.single;
  }

  void _money(int value, {bool zero = false, bool signed = false}) {
    if ((!signed && value < (zero ? 0 : 1)) ||
        value.abs() > maxMoney ||
        (!zero && value == 0)) {
      throw const FormatException('Valor monetário inválido.');
    }
  }

  void _date(DateTime date) {
    if (date.year < 2000 || date.year > 2100) {
      throw const FormatException('Use uma data entre 2000 e 2100.');
    }
  }

  Future<void> _account(String id) async {
    final rows = await _rows(
        "SELECT id FROM accounts WHERE id = ? AND deleted_at IS NULL AND is_archived = 0 AND currency_code = 'BRL'",
        [id]);
    if (rows.isEmpty) throw StateError('Selecione uma conta ativa em BRL.');
  }

  Future<void> _category(String? id) async {
    if (id == null) return;
    final rows = await _rows(
        "SELECT id FROM categories WHERE id = ? AND type = 'expense' AND deleted_at IS NULL AND is_archived = 0",
        [id]);
    if (rows.isEmpty) {
      throw StateError('Selecione uma categoria de despesa ativa.');
    }
  }

  Future<List<CreditCard>> list() async {
    final end = cardDay(DateTime.now().add(const Duration(days: 1)));
    final rows = await _rows('''SELECT c.*,
      COALESCE((SELECT SUM(e.amount_minor) FROM card_entries e WHERE e.card_id = c.id AND e.deleted_at IS NULL),0)
      - COALESCE((SELECT SUM(p.amount_minor) FROM card_payments p JOIN card_invoices i ON i.id = p.invoice_id
        WHERE i.card_id = c.id AND p.deleted_at IS NULL AND p.effective_at < ?),0) AS net_minor
      FROM credit_cards c WHERE c.deleted_at IS NULL ORDER BY c.is_archived, lower(c.name), c.id''',
        [end]);
    return rows.map((r) {
      final net = r.read<int>('net_minor');
      return CreditCard(
          id: r.read<String>('id'),
          name: r.read<String>('name'),
          institutionId: r.readNullable<String>('institution_id'),
          colorArgb: r.readNullable<int>('color_argb'),
          paymentAccountId: r.read<String>('payment_account_id'),
          closingDay: r.read<int>('closing_day'),
          dueDay: r.read<int>('due_day'),
          limitMinor: r.readNullable<int>('limit_minor'),
          isArchived: r.read<int>('is_archived') == 1,
          committedMinor: math.max(0, net),
          creditMinor: math.max(0, -net));
    }).toList();
  }

  Future<CreditCard> find(String id) async =>
      (await list()).firstWhere((c) => c.id == id,
          orElse: () => throw StateError('Cartão não encontrado.'));
  Future<String> save(CardDraft draft, {String? id}) =>
      db.transaction(() async {
        if (draft.name.trim().isEmpty ||
            draft.closingDay < 1 ||
            draft.closingDay > 31 ||
            draft.dueDay < 1 ||
            draft.dueDay > 31) {
          throw const FormatException('Informe nome e dias entre 1 e 31.');
        }
        if (draft.colorArgb != null &&
            (draft.colorArgb! < 0xff000000 || draft.colorArgb! > 0xffffffff)) {
          throw const FormatException('Cor do cartão inválida.');
        }
        if (draft.limitMinor != null) _money(draft.limitMinor!, zero: true);
        final old = id == null ? null : await find(id);
        if (old == null || old.paymentAccountId != draft.paymentAccountId) {
          await _account(draft.paymentAccountId);
        }
        final now = EntityMetadata.nowUtcMillis();
        final key = id ?? EntityMetadata.newId();
        if (id == null) {
          await db.customStatement(
              '''INSERT INTO credit_cards (id,name,institution_id,color_argb,payment_account_id,limit_minor,closing_day,due_day,created_at,updated_at)
        VALUES (?,?,?,?,?,?,?,?,?,?)''',
              [
                key,
                draft.name.trim(),
                draft.institutionId,
                draft.colorArgb,
                draft.paymentAccountId,
                draft.limitMinor,
                draft.closingDay,
                draft.dueDay,
                now,
                now
              ]);
        } else {
          await db.customStatement(
              '''UPDATE credit_cards SET name=?,institution_id=?,color_argb=?,payment_account_id=?,limit_minor=?,closing_day=?,due_day=?,updated_at=?,sync_version=sync_version+1 WHERE id=?''',
              [
                draft.name.trim(),
                draft.institutionId,
                draft.colorArgb,
                draft.paymentAccountId,
                draft.limitMinor,
                draft.closingDay,
                draft.dueDay,
                now,
                key
              ]);
        }
        if (old == null || old.limitMinor != draft.limitMinor) {
          await db.customStatement(
              'INSERT INTO card_limit_history (id,card_id,limit_minor,changed_at) VALUES (?,?,?,?)',
              [EntityMetadata.newId(), key, draft.limitMinor, now]);
        }
        // Faturas materializadas preservam suas datas; novos ciclos usam novos dias.
        return key;
      });
  Future<List<(DateTime, int?)>> limitHistory(String id) async => (await _rows(
              'SELECT * FROM card_limit_history WHERE card_id=? ORDER BY changed_at,id',
              [
            id
          ]))
          .map((r) => (
                cardDate(r.read<int>('changed_at')),
                r.readNullable<int>('limit_minor')
              ))
          .toList();
  Future<void> archive(String id, bool value) async {
    await find(id);
    await db.customStatement(
        'UPDATE credit_cards SET is_archived=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
        [value ? 1 : 0, EntityMetadata.nowUtcMillis(), id]);
  }

  Future<String> ensureInvoice(String cardId, DateTime month) async {
    _date(month);
    final key = cardDay(DateTime.utc(month.year, month.month));
    final found = await _rows(
        'SELECT id FROM card_invoices WHERE card_id=? AND month_at=?',
        [cardId, key]);
    if (found.isNotEmpty) return found.single.read<String>('id');
    final card = await find(cardId);
    // A mesma fatura criada offline nos dois dispositivos tem uma identidade.
    final id =
            const Uuid().v5(Namespace.url.value, 'somia/invoice/$cardId/$key'),
        now = EntityMetadata.nowUtcMillis();
    await db.customStatement(
        '''INSERT INTO card_invoices(id,card_id,month_at,closing_at,due_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?)''',
        [
          id,
          cardId,
          key,
          cardDay(card.closingFor(month)),
          cardDay(card.dueFor(month)),
          now,
          now
        ]);
    return id;
  }

  Future<String> invoiceForPurchase(String cardId, DateTime date) async {
    final card = await find(cardId);
    // Respeita fechamento real alterado, inclusive quando o próximo ciclo
    // ainda não tem compras. Preenche apenas a janela necessária.
    final nominal = card.invoiceMonthFor(date);
    for (var offset = -1; offset <= 2; offset++) {
      final month = DateTime.utc(nominal.year, nominal.month + offset);
      if (month.year >= 2000 && month.year <= 2100) {
        await ensureInvoice(cardId, month);
      }
    }
    final rows = await _rows(
        'SELECT id FROM card_invoices WHERE card_id=? AND closing_at>? ORDER BY closing_at,month_at LIMIT 1',
        [cardId, cardDay(date)]);
    if (rows.isEmpty) throw StateError('Fatura fora do período permitido.');
    return rows.single.read<String>('id');
  }

  Future<void> _insertEntry(
      {required String cardId,
      required String invoiceId,
      required String purchaseId,
      required String description,
      required int amount,
      required DateTime date,
      String? categoryId,
      List<CategoryAllocation> allocations = const [],
      List<String> tags = const [],
      String kind = 'purchase',
      int index = 0,
      int count = 1,
      String? sourceId,
      String? id}) async {
    CategoryAllocation.validate(allocations, amount.abs());
    _money(amount, signed: true);
    _date(date);
    final invoice = await _one('card_invoices', invoiceId);
    if (invoice.read<String>('card_id') != cardId) {
      throw StateError('Fatura pertence a outro cartão.');
    }
    final now = EntityMetadata.nowUtcMillis();
    await db.customStatement(
        '''INSERT INTO card_entries(id,card_id,invoice_id,purchase_id,installment_index,installment_count,description,category_id,kind,amount_minor,posted_at,source_id,created_at,updated_at,allocations_json,tags_json)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
        [
          id ?? EntityMetadata.newId(),
          cardId,
          invoiceId,
          purchaseId,
          index,
          count,
          description.trim(),
          categoryId,
          kind,
          amount,
          cardDay(date),
          sourceId,
          now,
          now,
          CategoryAllocation.encode(allocations),
          TransactionTags.encode(tags),
        ]);
  }

  Future<String> createPurchase(TransactionDraft draft) =>
      db.transaction(() async {
        final cardId = draft.cardId!;
        final card = await find(cardId);
        if (card.isArchived) throw StateError('Cartão arquivado.');
        if (draft.type != TransactionType.expense ||
            draft.description.trim().isEmpty) {
          throw const FormatException('Informe uma despesa válida.');
        }
        CategoryAllocation.validate(draft.allocations, draft.amountMinor);
        if (draft.allocations.isNotEmpty && draft.categoryId != null) {
          throw const FormatException('Use categoria única ou rateio.');
        }
        await validateAllocationReferences(db, draft.allocations, 'expense');
        await _category(draft.categoryId);
        _money(draft.amountMinor);
        _date(draft.date);
        final plan = draft.seriesPlan;
        if (plan != null &&
            (plan.kind != SeriesKind.installments ||
                plan.unit != SeriesUnit.month ||
                plan.interval != 1)) {
          throw const FormatException('No cartão, use parcelas mensais.');
        }
        final amounts = plan?.amounts(draft.amountMinor) ?? [draft.amountMinor];
        final firstInvoice = draft.cardInvoiceMonth == null
            ? await invoiceForPurchase(cardId, draft.date)
            : await ensureInvoice(cardId, draft.cardInvoiceMonth!);
        final invoice = await _one('card_invoices', firstInvoice);
        final month = cardDate(invoice.read<int>('month_at'));
        final purchaseId = EntityMetadata.newId(),
            firstId = EntityMetadata.newId();
        final firstIndex = draft.cardFirstInstallment;
        if (firstIndex < 1 || firstIndex + amounts.length - 1 > 1000) {
          throw const FormatException('Numeração de parcelas inválida.');
        }
        for (var index = 0; index < amounts.length; index++) {
          final target = index == 0
              ? firstInvoice
              : await ensureInvoice(
                  cardId, DateTime.utc(month.year, month.month + index));
          await _insertEntry(
              cardId: cardId,
              invoiceId: target,
              purchaseId: purchaseId,
              description: draft.description,
              tags: draft.tags,
              amount: amounts[index],
              date: draft.date,
              categoryId: draft.categoryId,
              allocations: CategoryAllocation.distribute(
                draft.allocations,
                amounts[index],
              ),
              index: firstIndex - 1 + index,
              count: firstIndex - 1 + amounts.length,
              id: index == 0 ? firstId : null);
        }
        if (draft.reimbursements != null) {
          await ReimbursementsRepository(db)
              .replace('purchase:$purchaseId', draft.reimbursements!);
        }
        return firstId;
      });
  Future<List<CardEntry>> entries({String? cardId, String? invoiceId}) async {
    final rows = await _rows(
        '''SELECT e.*,i.due_at,i.month_at,c.name AS category_name FROM card_entries e
      JOIN card_invoices i ON i.id=e.invoice_id LEFT JOIN categories c ON c.id=e.category_id
      WHERE e.deleted_at IS NULL ${cardId == null ? '' : 'AND e.card_id=?'} ${invoiceId == null ? '' : 'AND e.invoice_id=?'}
      ORDER BY i.month_at,e.installment_index,e.created_at,e.id''',
        [if (cardId != null) cardId, if (invoiceId != null) invoiceId]);
    return rows
        .map((r) => CardEntry(
            id: r.read<String>('id'),
            cardId: r.read<String>('card_id'),
            invoiceId: r.read<String>('invoice_id'),
            purchaseId: r.read<String>('purchase_id'),
            index: r.read<int>('installment_index'),
            count: r.read<int>('installment_count'),
            description: r.read<String>('description'),
            kind: r.read<String>('kind'),
            amountMinor: r.read<int>('amount_minor'),
            postedAt: cardDate(r.read<int>('posted_at')),
            dueAt: cardDate(r.read<int>('due_at')),
            invoiceMonth: cardDate(r.read<int>('month_at')),
            categoryId: r.readNullable<String>('category_id'),
            tags: TransactionTags.decode(r.read<String>('tags_json')),
            allocations: CategoryAllocation.decode(
              r.read<String>('allocations_json'),
            ),
            categoryName: r.readNullable<String>('category_name'),
            sourceId: r.readNullable<String>('source_id')))
        .toList();
  }

  Future<CardEntry> entry(String id) async =>
      (await entries()).firstWhere((e) => e.id == id,
          orElse: () => throw StateError('Compra não encontrada.'));
  Future<List<CardInvoice>> invoices(String cardId, {DateTime? selected}) =>
      db.transaction(() async {
        if (selected != null) {
          await ensureInvoice(cardId, selected);
          // Mantém a próxima disponível para mostrar a passagem do saldo parcial.
          if (selected.year < 2100 || selected.month < 12) {
            await ensureInvoice(
                cardId, DateTime.utc(selected.year, selected.month + 1));
          }
        }
        final rows = await _rows(
            'SELECT * FROM card_invoices WHERE card_id=? ORDER BY month_at',
            [cardId]);
        final end = cardDay(DateTime.now().add(const Duration(days: 1)));
        var carry = 0;
        final result = <CardInvoice>[];
        for (final r in rows) {
          final id = r.read<String>('id');
          final lines = await entries(invoiceId: id);
          final payRows = await _rows(
              '''SELECT p.*,a.name AS account_name FROM card_payments p JOIN accounts a ON a.id=p.account_id
        WHERE p.invoice_id=? AND p.deleted_at IS NULL ORDER BY p.effective_at,p.created_at,p.id''',
              [id]);
          final payments = payRows
              .map((p) => CardPayment(
                  id: p.read<String>('id'),
                  amountMinor: p.read<int>('amount_minor'),
                  date: cardDate(p.read<int>('effective_at')),
                  accountName: p.read<String>('account_name')))
              .toList();
          final paid = payments
              .where((p) => cardDay(p.date) < end)
              .fold(0, (a, p) => a + p.amountMinor);
          final scheduled = payments
              .where((p) => cardDay(p.date) >= end)
              .fold(0, (a, p) => a + p.amountMinor);
          final charges = lines.fold(0, (a, e) => a + e.amountMinor);
          result.add(CardInvoice(
              id: id,
              cardId: cardId,
              month: cardDate(r.read<int>('month_at')),
              closingAt: cardDate(r.read<int>('closing_at')),
              dueAt: cardDate(r.read<int>('due_at')),
              previousMinor: carry,
              chargesMinor: charges,
              paidMinor: paid,
              scheduledMinor: scheduled,
              entries: lines,
              payments: payments));
          carry += charges - paid;
        }
        return result;
      });
  Future<CardInvoice> invoice(String id) async {
    final r = await _one('card_invoices', id);
    return (await invoices(r.read<String>('card_id')))
        .firstWhere((i) => i.id == id);
  }

  Future<void> adjustDates(String id, DateTime closing, DateTime due) =>
      db.transaction(() async {
        _date(closing);
        _date(due);
        if (cardDay(closing) > cardDay(due)) {
          throw const FormatException(
              'Fechamento deve ocorrer até o vencimento.');
        }
        final row = await _one('card_invoices', id);
        final adjacent = await _rows(
            'SELECT month_at,closing_at FROM card_invoices WHERE card_id=? AND id<>?',
            [row.read<String>('card_id'), id]);
        for (final other in adjacent) {
          if ((other.read<int>('month_at') < row.read<int>('month_at') &&
                  other.read<int>('closing_at') >= cardDay(closing)) ||
              (other.read<int>('month_at') > row.read<int>('month_at') &&
                  other.read<int>('closing_at') <= cardDay(closing))) {
            throw const FormatException(
                'Fechamento deve manter a ordem das faturas.');
          }
        }
        await db.customStatement(
            'UPDATE card_invoices SET closing_at=?,due_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
            [
              cardDay(closing),
              cardDay(due),
              EntityMetadata.nowUtcMillis(),
              id
            ]);
      });
  Future<void> pay(
          String invoiceId, String accountId, int amount, DateTime date,
          {int fee = 0, int discount = 0}) =>
      db.transaction(() async {
        _money(amount);
        _money(fee, zero: true);
        _money(discount, zero: true);
        _date(date);
        await _account(accountId);
        final inv = await invoice(invoiceId);
        final id = EntityMetadata.newId(), now = EntityMetadata.nowUtcMillis();
        await db.customStatement(
            'INSERT INTO card_payments(id,invoice_id,account_id,amount_minor,effective_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',
            [id, invoiceId, accountId, amount, cardDay(date), now, now]);
        if (fee > 0) {
          await _insertEntry(
              cardId: inv.cardId,
              invoiceId: invoiceId,
              purchaseId: id,
              description: 'Juros / multa / acréscimos',
              amount: fee,
              date: date,
              kind: 'fee',
              sourceId: id);
        }
        if (discount > 0) {
          await _insertEntry(
              cardId: inv.cardId,
              invoiceId: invoiceId,
              purchaseId: id,
              description: 'Desconto na liquidação',
              amount: -discount,
              date: date,
              kind: 'discount',
              sourceId: id);
        }
      });
  Future<void> undoPayment(String id) => db.transaction(() async {
        await _one('card_payments', id);
        final now = EntityMetadata.nowUtcMillis();
        await db.customStatement(
            'UPDATE card_payments SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=? AND deleted_at IS NULL',
            [now, now, id]);
        await db.customStatement(
            'UPDATE card_entries SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE source_id=? AND kind IN (\'fee\',\'discount\') AND deleted_at IS NULL',
            [now, now, id]);
      });
  Future<bool> _locked(String invoiceId) async => (await _rows(
          'SELECT id FROM card_payments WHERE invoice_id=? AND deleted_at IS NULL LIMIT 1',
          [invoiceId]))
      .isNotEmpty;
  Future<List<CardEntry>> _targets(String id, SeriesScope scope) async {
    final original = await entry(id);
    if (original.kind != 'purchase') {
      throw StateError('Use ajustes da fatura para este registro.');
    }
    if (scope == SeriesScope.onlyThis) {
      return [original];
    }
    final found = <CardEntry>[];
    for (final e in await entries(cardId: original.cardId)) {
      if (e.purchaseId == original.purchaseId &&
          e.index >= original.index &&
          e.kind == 'purchase') {
        found.add(e);
      }
    }
    return found;
  }

  /// A correction changes purchases, never the invoice's cash payments.
  Future<bool> purchaseHasPayments(String id, SeriesScope scope,
      {DateTime? invoiceMonth, DateTime? purchaseDate}) async {
    final original = await entry(id);
    final targetMonth = invoiceMonth ??
        (await find(original.cardId))
            .invoiceMonthFor(purchaseDate ?? original.postedAt);
    for (final e in await _targets(id, scope)) {
      if (await _locked(e.invoiceId)) return true;
      final month = DateTime.utc(
          targetMonth.year, targetMonth.month + e.index - original.index);
      final paid = await _rows(
          'SELECT p.id FROM card_payments p JOIN card_invoices i ON i.id=p.invoice_id WHERE i.card_id=? AND i.month_at=? AND p.deleted_at IS NULL LIMIT 1',
          [e.cardId, cardDay(month)]);
      if (paid.isNotEmpty) return true;
    }
    return false;
  }

  Future<void> _validateRefundCoverage(
      List<CardEntry> targets, int amount) async {
    for (final purchase in targets.map((e) => e.purchaseId).toSet()) {
      final rows = await _rows(
          "SELECT COALESCE(SUM(CASE WHEN kind='purchase' AND purchase_id=? THEN amount_minor ELSE 0 END),0) AS bought, COALESCE(SUM(CASE WHEN kind='refund' AND source_id=? THEN -amount_minor ELSE 0 END),0) AS refunded FROM card_entries WHERE deleted_at IS NULL",
          [purchase, purchase]);
      final edited = targets.where((e) => e.purchaseId == purchase);
      final total = rows.single.read<int>('bought') +
          edited.fold(0, (sum, e) => sum + amount - e.amountMinor);
      if (total < rows.single.read<int>('refunded')) {
        throw StateError(
            'O valor da compra não pode ficar abaixo do total já estornado.');
      }
    }
  }

  Future<void> editPurchase(String id, TransactionDraft draft) =>
      db.transaction(() async {
        final original = await entry(id);
        CategoryAllocation.validate(draft.allocations, draft.amountMinor);
        if (draft.allocations.isNotEmpty && draft.categoryId != null) {
          throw const FormatException('Use categoria única ou rateio.');
        }
        await validateAllocationReferences(
          db,
          draft.allocations,
          'expense',
          historicalIds: original.allocations.map((p) => p.categoryId).toSet(),
        );
        if (draft.type != TransactionType.expense ||
            draft.cardId != original.cardId ||
            draft.description.trim().isEmpty) {
          throw const FormatException(
              'Mantenha o cartão e informe uma despesa válida.');
        }
        _money(draft.amountMinor);
        _date(draft.date);
        if (draft.categoryId != original.categoryId) {
          await _category(draft.categoryId);
        }
        final targets = await _targets(id, draft.scope);
        await _validateRefundCoverage(targets, draft.amountMinor);
        final month = draft.cardInvoiceMonth ??
            (await find(original.cardId)).invoiceMonthFor(draft.date);
        final now = EntityMetadata.nowUtcMillis();
        for (final e in targets) {
          var target = e.invoiceId;
          if (cardDay(month) != cardDay(original.invoiceMonth)) {
            target = await ensureInvoice(
                e.cardId,
                DateTime.utc(
                    month.year, month.month + e.index - original.index));
          }
          await _history(e, 'edit', target, draft.amountMinor);
          await db.customStatement(
              'UPDATE card_entries SET tags_json=?,allocations_json=?,description=?,amount_minor=?,posted_at=?,category_id=?,invoice_id=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
              [
                TransactionTags.encode(draft.tags),
                CategoryAllocation.encode(draft.allocations),
                draft.description.trim(),
                draft.amountMinor,
                cardDay(draft.date),
                draft.categoryId,
                target,
                now,
                e.id
              ]);
        }
        if (draft.reimbursements != null) {
          await ReimbursementsRepository(db).replace(
              'purchase:${original.purchaseId}', draft.reimbursements!);
        }
        await validateReimbursements(db);
      });
  Future<void> updateAmount(
          String id, int expected, int amount, SeriesScope scope) =>
      db.transaction(() async {
        _money(amount);
        if ((await entry(id)).amountMinor != expected) {
          throw StateError('O valor mudou. Atualize a lista.');
        }
        final targets = await _targets(id, scope);
        await _validateRefundCoverage(targets, amount);
        final now = EntityMetadata.nowUtcMillis();
        for (final e in targets) {
          await _history(e, 'edit', e.invoiceId, amount);
          await db.customStatement(
              'UPDATE card_entries SET allocations_json=?,amount_minor=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
              [
                CategoryAllocation.encode(
                  CategoryAllocation.distribute(e.allocations, amount),
                ),
                amount,
                now,
                e.id
              ]);
        }
        await validateReimbursements(db);
      });
  Future<void> deletePurchase(String id, SeriesScope scope) =>
      db.transaction(() async {
        final now = EntityMetadata.nowUtcMillis();
        final targets = await _targets(id, scope);
        for (final e in targets) {
          final linked = await _rows(
              "SELECT id FROM card_entries WHERE kind='refund' AND source_id=? AND deleted_at IS NULL LIMIT 1",
              [e.purchaseId]);
          final moved = await _rows(
              "SELECT id FROM card_entry_history WHERE entry_id=? AND action='anticipate' LIMIT 1",
              [e.id]);
          if (linked.isNotEmpty || moved.isNotEmpty) {
            throw StateError(
                'Compra possui estorno ou antecipação. Preserve o histórico e use um estorno para cancelar o saldo restante.');
          }
          await _history(e, 'delete', e.invoiceId, 0);
          await db.customStatement(
              'UPDATE card_entries SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
              [now, now, e.id]);
        }
        await validateReimbursements(db);
      });
  Future<void> refund(String id, int amount, String invoiceId, DateTime date) =>
      db.transaction(() async {
        _money(amount);
        _date(date);
        final original = await entry(id);
        if (original.kind != 'purchase') {
          throw StateError('Selecione uma compra para estornar.');
        }
        final all = await entries(cardId: original.cardId);
        final total = all
            .where((e) =>
                e.purchaseId == original.purchaseId && e.kind == 'purchase')
            .fold(0, (a, e) => a + e.amountMinor);
        final prior = await _rows(
            "SELECT COALESCE(SUM(-amount_minor),0) AS total FROM card_entries WHERE source_id=? AND kind='refund' AND deleted_at IS NULL",
            [original.purchaseId]);
        if (amount > total - prior.single.read<int>('total')) {
          throw StateError(
              'Estorno excede o valor ainda não estornado da compra.');
        }
        await _insertEntry(
            cardId: original.cardId,
            invoiceId: invoiceId,
            purchaseId: EntityMetadata.newId(),
            description: 'Estorno: ${original.description}',
            amount: -amount,
            date: date,
            categoryId: original.categoryId,
            allocations:
                CategoryAllocation.distribute(original.allocations, amount),
            kind: 'refund',
            sourceId: original.purchaseId);
      });
  Future<void> anticipate(List<String> ids, String invoiceId, int discount) =>
      db.transaction(() async {
        if (ids.isEmpty || ids.toSet().length != ids.length) {
          throw const FormatException('Selecione parcelas distintas.');
        }
        _money(discount, zero: true);
        final target = await invoice(invoiceId);
        if (await _locked(invoiceId)) {
          throw StateError('Antecipe para uma fatura sem pagamentos.');
        }
        final selected = <CardEntry>[];
        for (final id in ids) {
          final e = await entry(id);
          if (e.kind != 'purchase' ||
              e.cardId != target.cardId ||
              cardDay(e.invoiceMonth) <= cardDay(target.month) ||
              await _locked(e.invoiceId)) {
            throw StateError(
                'Selecione parcelas futuras sem pagamentos do mesmo cartão.');
          }
          selected.add(e);
        }
        final total = selected.fold(0, (a, e) => a + e.amountMinor);
        if (discount >= total) {
          throw const FormatException(
              'Desconto deve ser menor que o total antecipado.');
        }
        final now = EntityMetadata.nowUtcMillis();
        for (final e in selected) {
          await _history(e, 'anticipate', invoiceId, e.amountMinor);
          await db.customStatement(
              'UPDATE card_entries SET invoice_id=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
              [invoiceId, now, e.id]);
        }
        if (discount > 0) {
          await _insertEntry(
              cardId: target.cardId,
              invoiceId: invoiceId,
              purchaseId: EntityMetadata.newId(),
              description: 'Desconto por antecipação',
              amount: -discount,
              date: DateTime.now(),
              kind: 'discount');
        }
      });
  Future<void> opening(String cardId, DateTime month, int amount) =>
      db.transaction(() async {
        _money(amount, signed: true);
        final invoiceId = await ensureInvoice(cardId, month);
        await _insertEntry(
            cardId: cardId,
            invoiceId: invoiceId,
            purchaseId: EntityMetadata.newId(),
            description: 'Saldo inicial de fatura',
            amount: amount,
            date: month,
            kind: 'opening');
      });

  Future<void> _history(
          CardEntry entry, String action, String invoiceId, int amount) =>
      db.customStatement(
          'INSERT INTO card_entry_history(id,entry_id,action,previous_invoice_id,invoice_id,previous_amount_minor,amount_minor,changed_at) VALUES(?,?,?,?,?,?,?,?)',
          [
            EntityMetadata.newId(),
            entry.id,
            action,
            entry.invoiceId,
            invoiceId,
            entry.amountMinor,
            amount,
            EntityMetadata.nowUtcMillis()
          ]);
  Future<List<String>> entryHistory(String id) async {
    final rows = await _rows(
        'SELECT h.*,i.month_at FROM card_entry_history h LEFT JOIN card_invoices i ON i.id=h.invoice_id WHERE h.entry_id=? ORDER BY h.changed_at,h.id',
        [id]);
    return rows.map((r) {
      final date = cardDate(r.read<int>('changed_at'));
      final month = cardDate(r.read<int>('month_at'));
      final action = switch (r.read<String>('action')) {
        'anticipate' => 'Antecipação',
        'delete' => 'Exclusão',
        _ => 'Edição',
      };
      return '${date.day}/${date.month}/${date.year}: $action para ${month.month}/${month.year}';
    }).toList();
  }

  Future<void> removeAdjustment(String id) => db.transaction(() async {
        final e = await entry(id);
        if (e.kind == 'purchase' ||
            e.kind == 'fee' ||
            (await _one('card_entries', id))
                        .readNullable<String>('source_id') !=
                    null &&
                e.kind == 'discount') {
          throw StateError(
              'Use a compra ou o pagamento vinculado para desfazer.');
        }
        final now = EntityMetadata.nowUtcMillis();
        await db.customStatement(
            'UPDATE card_entries SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
            [now, now, id]);
      });

  FinancialTransaction movement(CardEntry e, CreditCard c) =>
      FinancialTransaction(
          id: 'card:${e.id}',
          cardId: c.id,
          cardInvoiceMonth: e.invoiceMonth,
          description: e.description,
          tags: e.tags,
          type: TransactionType.expense,
          amountMinor: e.amountMinor,
          date: e.postedAt,
          dueDate: e.dueAt,
          isEffective: false,
          accountId: c.id,
          accountName: 'Cartão ${c.name}',
          categoryId: e.categoryId,
          allocations: e.allocations,
          categoryName: e.categoryName,
          currencyCode: 'BRL',
          series: e.count > 1
              ? SeriesInfo(
                  id: e.purchaseId,
                  index: e.index,
                  plan:
                      SeriesPlan(kind: SeriesKind.installments, count: e.count))
              : null);
  Future<FinancialTransaction> findMovement(String id) async {
    final e = await entry(id);
    return movement(e, await find(e.cardId));
  }

  static String paymentSignature(CardInvoice invoice) => invoice.payments
      .map((p) => '${p.id}:${cardDay(p.date)}:${p.amountMinor}')
      .join('|');

  /// Completa só o saldo em aberto. Agendamentos são contabilizados hoje,
  /// preservando os registros; não cria um segundo débito para eles.
  Future<CardSettlement> settleInvoice(String id,
          {required int expectedBalance,
          required int expectedScheduled,
          required String expectedSignature,
          required String expectedAccountId,
          required DateTime date}) =>
      db.transaction(() async {
        _date(date);
        final bill = await invoice(id);
        final card = await find(bill.cardId);
        if (bill.balanceMinor != expectedBalance ||
            bill.scheduledMinor != expectedScheduled ||
            paymentSignature(bill) != expectedSignature ||
            card.paymentAccountId != expectedAccountId) {
          throw StateError('A fatura mudou. Atualize a lista antes de pagar.');
        }
        if (bill.balanceMinor <= 0) {
          throw StateError('Esta fatura já está quitada.');
        }
        final todayEnd = cardDay(DateTime.now().add(const Duration(days: 1)));
        final shifted = <(String, DateTime, int)>[];
        final now = EntityMetadata.nowUtcMillis();
        for (final p
            in bill.payments.where((p) => cardDay(p.date) >= todayEnd)) {
          final row = await _one('card_payments', p.id);
          await _account(row.read<String>('account_id'));
          shifted.add((p.id, p.date, p.amountMinor));
          await db.customStatement(
              'UPDATE card_payments SET effective_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
              [cardDay(date), now, p.id]);
        }
        final amount = math.max(0, bill.balanceMinor - bill.scheduledMinor);
        String? newId;
        if (amount > 0) {
          _money(amount);
          await _account(card.paymentAccountId);
          newId = EntityMetadata.newId();
          await db.customStatement(
              'INSERT INTO card_payments(id,invoice_id,account_id,amount_minor,effective_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',
              [
                newId,
                id,
                card.paymentAccountId,
                amount,
                cardDay(date),
                now,
                now
              ]);
        }
        return CardSettlement(
            invoiceId: id,
            date: date,
            shifted: List.unmodifiable(shifted),
            newPaymentId: newId,
            newAmountMinor: amount);
      });
  Future<void> _checkSettlement(CardSettlement action) async {
    for (final (id, amount) in [
      if (action.newPaymentId != null)
        (action.newPaymentId!, action.newAmountMinor),
      for (final s in action.shifted) (s.$1, s.$3)
    ]) {
      final p = await _one('card_payments', id);
      if (p.readNullable<int>('deleted_at') != null ||
          p.read<String>('invoice_id') != action.invoiceId ||
          p.read<int>('effective_at') != cardDay(action.date) ||
          p.read<int>('amount_minor') != amount) {
        throw StateError(
            'O pagamento mudou. Atualize a fatura antes de desfazer ou ajustar.');
      }
    }
  }

  Future<void> undoSettlement(CardSettlement action) =>
      db.transaction(() async {
        await _checkSettlement(action);
        if (action.newPaymentId != null) {
          await undoPayment(action.newPaymentId!);
        }
        final now = EntityMetadata.nowUtcMillis();
        for (final s in action.shifted) {
          await db.customStatement(
              'UPDATE card_payments SET effective_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
              [cardDay(s.$2), now, s.$1]);
        }
      });
  Future<void> changeSettlementDate(CardSettlement action, DateTime date) =>
      db.transaction(() async {
        _date(date);
        await _checkSettlement(action);
        final now = EntityMetadata.nowUtcMillis();
        for (final id in [
          if (action.newPaymentId != null) action.newPaymentId!,
          for (final s in action.shifted) s.$1
        ]) {
          await db.customStatement(
              'UPDATE card_payments SET effective_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
              [cardDay(date), now, id]);
        }
      });
  Future<void> undoInvoicePayment(
          String invoiceId, String paymentId, String signature) =>
      db.transaction(() async {
        final bill = await invoice(invoiceId);
        if (paymentSignature(bill) != signature ||
            !bill.payments.any((p) =>
                p.id == paymentId &&
                cardDay(p.date) <= cardDay(DateTime.now()))) {
          throw StateError(
              'A fatura mudou. Atualize a lista antes de desfazer.');
        }
        await undoPayment(paymentId);
      });

  Future<List<FinancialTransaction>> movements(TransactionFilter filter) =>
      db.transaction(() async {
        if (filter.type == TransactionType.income) return [];
        final result = <FinancialTransaction>[];
        final accountRows = await _rows(
            'SELECT id,name FROM accounts WHERE deleted_at IS NULL');
        final names = {
          for (final a in accountRows)
            a.read<String>('id'): a.read<String>('name')
        };
        final categoryRows = filter.categoryId == null
            ? <QueryRow>[]
            : await _rows('SELECT id FROM categories WHERE id=? OR parent_id=?',
                [filter.categoryId!, filter.categoryId!]);
        final categories =
            categoryRows.map((r) => r.read<String>('id')).toSet();
        final today = cardDay(DateTime.now());
        for (final c in await list()) {
          if (filter.accountId != null &&
              filter.accountId != c.paymentAccountId) {
            continue;
          }
          // A lista mensal mostra também dívida trazida de ciclos anteriores,
          // mesmo quando não há uma nova compra naquele mês.
          if (filter.dateField != TransactionDateField.effective &&
              filter.from != null &&
              filter.to != null) {
            var month = DateTime.utc(filter.from!.year, filter.from!.month);
            final last = DateTime.utc(
                filter.to!.year,
                filter.to!.month +
                    (filter.dateField == TransactionDateField.posted ? 1 : 0));
            while (!month.isAfter(last) &&
                month.year >= 2000 &&
                month.year <= 2100) {
              final key = cardDay(month), now = EntityMetadata.nowUtcMillis();
              await db.customStatement(
                  'INSERT OR IGNORE INTO card_invoices(id,card_id,month_at,closing_at,due_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',
                  [
                    EntityMetadata.newId(),
                    c.id,
                    key,
                    cardDay(c.closingFor(month)),
                    cardDay(c.dueFor(month)),
                    now,
                    now
                  ]);
              month = DateTime.utc(month.year, month.month + 1);
            }
          }
          for (final bill in await invoices(c.id)) {
            if (bill.chargesMinor <= 0) continue;
            if (bill.entries.isEmpty &&
                bill.payments.isEmpty &&
                bill.previousMinor <= 0) {
              continue;
            }
            if (filter.categoryId != null &&
                !bill.entries.any(
                  (e) =>
                      categories.contains(e.categoryId) ||
                      e.allocations
                          .any((p) => categories.contains(p.categoryId)),
                )) {
              continue;
            }
            if (filter.tag != null &&
                !bill.entries.any((e) => e.tags.any((tag) =>
                    TransactionTags.key(tag) ==
                    TransactionTags.key(filter.tag!)))) {
              continue;
            }
            final effective = bill.balanceMinor <= 0;
            if (filter.status == TransactionStatus.effective && !effective) {
              continue;
            }
            if (filter.status == TransactionStatus.pending && effective) {
              continue;
            }
            final actual =
                bill.payments.where((p) => cardDay(p.date) <= today).toList();
            final scheduled =
                bill.payments.where((p) => cardDay(p.date) > today).toList();
            final date = effective
                ? actual.lastOrNull?.date
                : scheduled.lastOrNull?.date;
            final filterDate = switch (filter.dateField) {
              TransactionDateField.posted => bill.closingAt,
              TransactionDateField.due => bill.dueAt,
              TransactionDateField.effective => effective ? date : null,
            };
            if (filterDate == null ||
                (filter.from != null &&
                    cardDay(filterDate) < cardDay(filter.from!)) ||
                (filter.to != null &&
                    cardDay(filterDate) > cardDay(filter.to!))) {
              continue;
            }
            result.add(FinancialTransaction(
                id: 'invoice:${bill.id}',
                cardId: c.id,
                cardInvoiceId: bill.id,
                cardInvoiceMonth: bill.month,
                cardBalanceMinor: bill.balanceMinor,
                cardPreviousMinor: bill.previousMinor,
                cardScheduledMinor: bill.scheduledMinor,
                cardEntryCount: bill.entries.length,
                cardLastPaymentId: actual.lastOrNull?.id,
                cardPaymentSignature: paymentSignature(bill),
                description: 'Cartão - ${c.name}',
                type: TransactionType.expense,
                amountMinor: math.max(0, bill.chargesMinor),
                date: bill.closingAt,
                dueDate: bill.dueAt,
                effectiveDate: date,
                isEffective: effective,
                accountId: c.paymentAccountId,
                accountName: names[c.paymentAccountId] ?? 'Conta do cartão',
                categoryId: null,
                categoryName: null,
                currencyCode: 'BRL'));
          }
        }
        return result;
      });
}
