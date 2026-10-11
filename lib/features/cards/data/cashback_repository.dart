import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/entity_metadata.dart';
import '../../../core/database/card_rewards_integrity.dart';
import '../domain/cashback_calculator.dart';
import '../domain/cashback_rule_codec.dart';
import '../domain/credit_card.dart';

class CashbackSettings {
  CashbackSettings(this.id, this.kind, this.cardId, this.accountId,
      this.categoryId, this.returnCategoryId, this.enabled, this.rule);
  final String id, kind, cardId, accountId;
  final String? categoryId, returnCategoryId;
  final bool enabled;
  final CashbackRule rule;
}

class CashbackReceipt {
  const CashbackReceipt(
      {required this.id,
      required this.claimId,
      required this.cardName,
      required this.description,
      required this.kind,
      required this.reason,
      required this.amountMinor,
      required this.accountId,
      required this.date,
      required this.confirmed,
      required this.revision,
      this.categoryId});
  final String id,
      claimId,
      cardName,
      description,
      kind,
      reason,
      accountId,
      revision;
  final int amountMinor, confirmed;
  final DateTime date;
  final String? categoryId;
}

class CashbackRepository {
  const CashbackRepository(this.db);
  final AppDatabase db;
  Future<List<QueryRow>> rows(String sql, [List<Object?> values = const []]) =>
      db
          .customSelect(sql,
              variables: values
                  .map((v) => v is int
                      ? Variable.withInt(v)
                      : v == null
                          ? const Variable<String>(null)
                          : Variable.withString(v as String))
                  .toList())
          .get();
  Future<CashbackSettings?> settings(String kind, String cardId) async {
    final result = await rows(
        'SELECT * FROM cashback_rules WHERE card_kind=? AND card_id=? AND deleted_at IS NULL',
        [kind, cardId]);
    if (result.isEmpty) return null;
    final r = result.single;
    return CashbackSettings(
        r.read<String>('id'),
        kind,
        cardId,
        r.read<String>('account_id'),
        r.readNullable<String>('category_id'),
        r.readNullable<String>('return_category_id'),
        r.read<int>('enabled') == 1,
        decodeCashbackRule(r.read<String>('rule_json')));
  }

  Future<void> _account(String id) async {
    if ((await rows(
            "SELECT id FROM accounts WHERE id=? AND is_archived=0 AND deleted_at IS NULL AND currency_code='BRL'",
            [id]))
        .isEmpty) throw StateError('Selecione uma conta ativa em BRL.');
  }

  Future<void> _category(String? id, String type) async {
    if (id == null) return;
    if ((await rows(
            '''SELECT c.id FROM categories c LEFT JOIN categories p ON p.id=c.parent_id
      WHERE c.id=? AND c.type=? AND c.is_archived=0 AND c.deleted_at IS NULL
      AND (p.id IS NULL OR (p.is_archived=0 AND p.deleted_at IS NULL))''',
            [id, type]))
        .isEmpty) throw StateError('Selecione uma categoria ativa de $type.');
  }

  Future<void> saveSettings(
          {required String kind,
          required String cardId,
          required bool enabled,
          required String accountId,
          String? categoryId,
          String? returnCategoryId,
          required CashbackRule rule}) =>
      db.transaction(() async {
        if (!['credit', 'debit'].contains(kind))
          throw const FormatException('Tipo de cartão inválido.');
        final table = kind == 'credit' ? 'credit_cards' : 'debit_cards';
        if ((await rows(
                'SELECT id FROM $table WHERE id=? AND deleted_at IS NULL',
                [cardId]))
            .isEmpty) throw StateError('Cartão não encontrado.');
        await _account(accountId);
        await _category(categoryId, 'income');
        await _category(returnCategoryId, 'expense');
        final id = 'cashback-$kind-$cardId',
            now = EntityMetadata.nowUtcMillis();
        await db.customStatement(
            '''INSERT INTO cashback_rules(id,card_kind,card_id,enabled,account_id,category_id,return_category_id,rule_json,created_at,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(card_kind,card_id) DO UPDATE SET enabled=excluded.enabled,account_id=excluded.account_id,
      category_id=excluded.category_id,return_category_id=excluded.return_category_id,rule_json=excluded.rule_json,
      updated_at=excluded.updated_at,deleted_at=NULL,sync_version=cashback_rules.sync_version+1''',
            [
              id,
              kind,
              cardId,
              enabled ? 1 : 0,
              accountId,
              categoryId,
              returnCategoryId,
              encodeCashbackRule(rule),
              now,
              now
            ]);
        await reconcile();
        await validateCardRewards(db);
      });

  /// Generated pending rows have stable identities; unchanged calculations write
  /// nothing. Confirmed rows are historical facts and never rewritten here.
  Future<void> reconcile({DateTime? asOf}) => db.transaction(() async {
        final today = asOf ?? DateTime.now();
        for (final rule in await rows(
            'SELECT * FROM cashback_rules WHERE deleted_at IS NULL')) {
          await _reconcileRule(rule, today);
        }
      });

  Future<void> _reconcileRule(QueryRow setting, DateTime today) async {
    final ruleId = setting.read<String>('id'),
        cardId = setting.read<String>('card_id');
    final enabled = setting.read<int>('enabled') == 1;
    final currentJson = setting.read<String>('rule_json');
    final facts = <String, _PurchaseFact>{};
    final payments = <CashbackPayment>[];
    final cutoff = cardDay(today);
    if (setting.read<String>('card_kind') == 'credit') {
      for (final row in await rows(
          "SELECT * FROM card_entries WHERE card_id=? AND kind='purchase' ORDER BY posted_at,id",
          [cardId])) {
        final id = row.read<String>('purchase_id');
        final f = facts.putIfAbsent(
            id, () => _PurchaseFact(id, row.read<String>('description')));
        f.original += row.read<int>('amount_minor');
        if (row.readNullable<int>('deleted_at') == null)
          f.total += row.read<int>('amount_minor');
      }
      for (final row in await rows(
          "SELECT source_id,SUM(-amount_minor) AS amount FROM card_entries WHERE card_id=? AND kind='refund' AND deleted_at IS NULL AND posted_at<=? GROUP BY source_id",
          [cardId, cutoff])) {
        facts[row.read<String>('source_id')]?.refund = row.read<int>('amount');
      }
      for (final row in await rows(
          '''SELECT e.purchase_id,a.amount_minor,p.effective_at FROM card_payment_allocations a
        JOIN card_payments p ON p.id=a.payment_id JOIN card_entries e ON e.id=a.entry_id
        WHERE e.card_id=? AND a.deleted_at IS NULL AND p.deleted_at IS NULL ORDER BY p.effective_at,p.id,a.id''',
          [cardId])) {
        payments.add(CashbackPayment(
            row.read<String>('purchase_id'),
            row.read<int>('amount_minor'),
            cardDate(row.read<int>('effective_at'))));
      }
    } else {
      for (final row in await rows(
          '''SELECT t.*,l.deleted_at AS link_deleted FROM debit_card_links l JOIN transactions t ON t.id=l.id WHERE l.card_id=?''',
          [cardId])) {
        final id = row.read<String>('id');
        final f =
            facts[id] = _PurchaseFact(id, row.read<String>('description'));
        f.original = row.read<int>('planned_amount_minor');
        if (row.readNullable<int>('deleted_at') == null &&
            row.readNullable<int>('link_deleted') == null) f.total = f.original;
        final effective = row.readNullable<int>('effective_at');
        if (effective != null)
          payments.add(CashbackPayment(
              id,
              row.readNullable<int>('actual_amount_minor') ?? f.original,
              cardDate(effective)));
        for (final s in await rows(
            'SELECT amount_minor,effective_at FROM transaction_settlements WHERE transaction_id=? AND deleted_at IS NULL ORDER BY effective_at,id',
            [id])) {
          payments.add(CashbackPayment(id, s.read<int>('amount_minor'),
              cardDate(s.read<int>('effective_at'))));
        }
      }
    }
    final existing =
        await rows('SELECT * FROM cashback_claims WHERE rule_id=?', [ruleId]);
    final claims = {
      for (final row in existing) row.read<String>('purchase_id'): row
    };
    // A moved/removed debit association still reconciles its old claim to zero.
    for (final claim in existing) {
      final id = claim.read<String>('purchase_id');
      if (!facts.containsKey(id)) {
        final f = facts[id] = _PurchaseFact(id, 'Compra corrigida ou removida');
        f.original = claim.read<int>('accepted_base_minor');
        if (f.original == 0) f.original = 1;
        payments.add(CashbackPayment(
            id, f.original, cardDate(claim.read<int>('first_payment_at'))));
      }
    }
    final paid = <String, int>{};
    final eligible = <CashbackPayment>[];
    final first = <String, DateTime>{};
    for (final p in payments) {
      if (cardDay(p.date) > cutoff) continue;
      final f = facts[p.purchaseId];
      if (f == null) continue;
      final limit = f.total > 0 ? f.total : f.original;
      final available = limit - (paid[f.id] ?? 0);
      final amount = p.amountMinor > available ? available : p.amountMinor;
      if (amount <= 0) continue;
      paid[f.id] = (paid[f.id] ?? 0) + amount;
      first.putIfAbsent(f.id, () => p.date);
      eligible.add(CashbackPayment(f.id, amount, p.date));
    }
    final now = EntityMetadata.nowUtcMillis();
    for (final f in facts.values) {
      if (!enabled ||
          f.total <= 0 ||
          first[f.id] == null ||
          claims.containsKey(f.id)) continue;
      final id = 'claim-$ruleId-${f.id}';
      await db.customStatement(
          '''INSERT INTO cashback_claims(id,rule_id,purchase_id,first_payment_at,rule_json,accepted_base_minor,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)''',
          [
            id,
            ruleId,
            f.id,
            cardDay(first[f.id]!),
            currentJson,
            f.total,
            now,
            now
          ]);
    }
    final live = await rows(
        'SELECT * FROM cashback_claims WHERE rule_id=? AND deleted_at IS NULL',
        [ruleId]);
    final liveIds = {for (final c in live) c.read<String>('purchase_id')};
    final purchases = <CashbackPurchase>[];
    final refunds = <CashbackTierRefund>[];
    for (final claim in live) {
      final f = facts[claim.read<String>('purchase_id')]!;
      final total = f.total > 0 ? f.total : f.original;
      final refund =
          f.total == 0 ? total : (f.refund > total ? total : f.refund);
      purchases.add(CashbackPurchase(
          id: f.id,
          totalMinor: total,
          refundedMinor: refund,
          confirmedRateBasisPoints: claim.read<int>('confirmed_rate')));
      var remaining = refund;
      for (final p in eligible.where((p) => p.purchaseId == f.id)) {
        final amount = remaining > p.amountMinor ? p.amountMinor : remaining;
        if (amount > 0) {
          refunds.add(CashbackTierRefund(f.id, amount, p.date));
          remaining -= amount;
        }
      }
    }
    final allPayments =
        eligible.where((p) => liveIds.contains(p.purchaseId)).toList();
    for (final claim in live) {
      final id = claim.read<String>('id'),
          purchaseId = claim.read<String>('purchase_id');
      final confirmed = await rows(
          '''SELECT r.*,t.account_id,t.actual_amount_minor,t.planned_amount_minor FROM cashback_receipts r JOIN transactions t ON t.id=r.id
        WHERE r.claim_id=? AND r.confirmed<>0 AND r.deleted_at IS NULL ORDER BY r.updated_at,r.id''',
          [id]);
      final originalFirst = cardDate(claim.read<int>('first_payment_at'));
      var ruleJson = claim.read<String>('rule_json');
      if (confirmed.isEmpty &&
          originalFirst.year == today.year &&
          originalFirst.month == today.month &&
          ruleJson != currentJson) {
        ruleJson = currentJson;
        await db.customStatement(
            'UPDATE cashback_claims SET rule_json=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
            [ruleJson, now, id]);
      }
      final rule = decodeCashbackRule(ruleJson);
      final targets = const CashbackCalculator().calculate(
          rule: rule,
          purchases: purchases,
          payments: allPayments,
          tierRefunds: refunds,
          asOf: today);
      final target =
          targets.where((t) => t.purchaseId == purchaseId).firstOrNull;
      final theory = target?.amountMinor ?? 0;
      final f = facts[purchaseId]!;
      final base = target == null
          ? 0
          : f.total > f.refund
              ? f.total - f.refund
              : 0;
      var net = 0;
      for (final r in confirmed) {
        final actual = r.read<int>('confirmed') == 2
            ? 0
            : r.readNullable<int>('actual_amount_minor') ??
                r.read<int>('planned_amount_minor');
        net += r.read<String>('kind') == 'return' ? -actual : actual;
      }
      final accepted = claim.read<int>('accepted_difference_minor');
      final acceptedBase = claim.read<int>('accepted_base_minor');
      final offset = acceptedBase > 0
          ? roundedRatio(accepted.abs(), base, acceptedBase) *
              (accepted < 0 ? -1 : 1)
          : accepted;
      final desired = theory + offset;
      final delta = (!enabled && confirmed.isEmpty) ? 0 : desired - net;
      final pending = await rows(
          'SELECT r.id FROM cashback_receipts r WHERE r.claim_id=? AND confirmed=0 AND deleted_at IS NULL',
          [id]);
      if (delta == 0) {
        if (pending.isNotEmpty)
          await _cancel(pending.single.read<String>('id'), now);
        continue;
      }
      final kind = delta < 0
          ? 'return'
          : confirmed.isEmpty
              ? 'original'
              : 'complement';
      final reason = kind == 'original'
          ? 'forecast'
          : base < claim.read<int>('accepted_base_minor')
              ? 'refund'
              : (target?.rateBasisPoints ?? 0) >
                      claim.read<int>('confirmed_rate')
                  ? 'tier'
                  : 'cap';
      final receiptId = pending.isNotEmpty
          ? pending.single.read<String>('id')
          : 'cashback-receipt-$id-${confirmed.length}';
      var account = setting.read<String>('account_id');
      if (kind == 'return')
        account = confirmed
                .where((r) =>
                    r.read<String>('kind') != 'return' &&
                    r.read<int>('confirmed') == 1)
                .lastOrNull
                ?.read<String>('account_id') ??
            account;
      final category = setting.readNullable<String>(
          kind == 'return' ? 'return_category_id' : 'category_id');
      var due = target?.receiptDate ?? rule.receiptFor(originalFirst);
      if (kind != 'original') {
        due = cardDate(cutoff);
        if (rule.schedule == CashbackSchedule.nextMonth) {
          due = calendarDay(today.year, today.month, rule.receiptDay);
          if (due.isBefore(cardDate(cutoff)))
            due = calendarDay(today.year, today.month + 1, rule.receiptDay);
        }
      }
      await _pending(
          receiptId,
          id,
          kind,
          reason,
          delta.abs(),
          theory,
          base,
          target?.rateBasisPoints ?? claim.read<int>('confirmed_rate'),
          account,
          category,
          due,
          f.description,
          now);
    }
  }

  Future<void> _cancel(String id, int now) async {
    await db.customStatement(
        'UPDATE cashback_receipts SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
        [now, now, id]);
    await db.customStatement(
        'UPDATE transactions SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
        [now, now, id]);
  }

  Future<void> _pending(
      String id,
      String claim,
      String kind,
      String reason,
      int amount,
      int theory,
      int base,
      int rate,
      String account,
      String? category,
      DateTime due,
      String description,
      int now) async {
    final old = await rows(
        'SELECT r.*,t.planned_amount_minor,t.account_id,t.category_id,t.due_at,t.description,t.type,t.deleted_at AS transaction_deleted FROM cashback_receipts r JOIN transactions t ON t.id=r.id WHERE r.id=?',
        [id]);
    final label =
        '${kind == 'return' ? 'Devolução de cashback' : kind == 'complement' ? 'Complemento de cashback' : 'Cashback'} · $description';
    final type = kind == 'return' ? 'expense' : 'income';
    if (old.isNotEmpty) {
      final r = old.single;
      if (r.read<int>('confirmed') != 0)
        throw StateError(
            'Previsão de cashback já confirmada. Atualize a lista.');
      if (r.read<int>('planned_amount_minor') == amount &&
          r.read<int>('theory_minor') == theory &&
          r.read<int>('base_minor') == base &&
          r.read<int>('rate') == rate &&
          r.read<String>('kind') == kind &&
          r.read<String>('reason') == reason &&
          r.read<String>('account_id') == account &&
          r.readNullable<String>('category_id') == category &&
          r.read<int>('due_at') == cardDay(due) &&
          r.read<String>('description') == label &&
          r.readNullable<int>('deleted_at') == null &&
          r.readNullable<int>('transaction_deleted') == null) return;
      await db.customStatement(
          '''UPDATE transactions SET description=?,type=?,planned_amount_minor=?,account_id=?,category_id=?,competence_at=?,posted_at=?,due_at=?,deleted_at=NULL,trash_state='active',updated_at=?,sync_version=sync_version+1 WHERE id=?''',
          [
            label,
            type,
            amount,
            account,
            category,
            cardDay(due),
            cardDay(due),
            cardDay(due),
            now,
            id
          ]);
      await db.customStatement(
          '''UPDATE cashback_receipts SET kind=?,reason=?,theory_minor=?,base_minor=?,rate=?,deleted_at=NULL,updated_at=?,sync_version=sync_version+1 WHERE id=?''',
          [kind, reason, theory, base, rate, now, id]);
    } else {
      await db.customStatement(
          '''INSERT INTO transactions(id,description,type,planned_amount_minor,competence_at,posted_at,due_at,account_id,category_id,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
          [
            id,
            label,
            type,
            amount,
            cardDay(due),
            cardDay(due),
            cardDay(due),
            account,
            category,
            now,
            now
          ]);
      await db.customStatement(
          '''INSERT INTO cashback_receipts(id,claim_id,kind,reason,theory_minor,base_minor,rate,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)''',
          [id, claim, kind, reason, theory, base, rate, now, now]);
    }
  }

  Future<List<CashbackReceipt>> list({String? kind, String? cardId}) async {
    await reconcile();
    return (await rows(
            '''SELECT r.*,t.description,t.account_id,t.category_id,t.due_at,t.effective_at,t.updated_at AS t_updated,t.sync_version AS t_version,
      t.planned_amount_minor,t.actual_amount_minor,COALESCE(k.name,d.name,'Cartão removido') AS card_name
      FROM cashback_receipts r JOIN transactions t ON t.id=r.id JOIN cashback_claims c ON c.id=r.claim_id JOIN cashback_rules s ON s.id=c.rule_id
      LEFT JOIN credit_cards k ON s.card_kind='credit' AND k.id=s.card_id LEFT JOIN debit_cards d ON s.card_kind='debit' AND d.id=s.card_id
      WHERE r.deleted_at IS NULL ${cardId == null ? '' : 'AND s.card_id=? AND s.card_kind=?'} ORDER BY COALESCE(t.effective_at,t.due_at) DESC,r.id''',
            cardId == null ? [] : [cardId, kind]))
        .map((r) => CashbackReceipt(
            id: r.read<String>('id'),
            claimId: r.read<String>('claim_id'),
            cardName: r.read<String>('card_name'),
            description: r.read<String>('description'),
            kind: r.read<String>('kind'),
            reason: r.read<String>('reason'),
            amountMinor: r.read<int>('confirmed') == 2
                ? 0
                : r.readNullable<int>('actual_amount_minor') ??
                    r.read<int>('planned_amount_minor'),
            accountId: r.read<String>('account_id'),
            categoryId: r.readNullable<String>('category_id'),
            date: cardDate(
                r.readNullable<int>('effective_at') ?? r.read<int>('due_at')),
            confirmed: r.read<int>('confirmed'),
            revision:
                '${r.read<int>('t_updated')}:${r.read<int>('t_version')}:${r.read<int>('updated_at')}:${r.read<int>('sync_version')}'))
        .toList();
  }

  Future<void> confirm(List<CashbackReceipt> selected,
          {required int totalMinor,
          required String accountId,
          required DateTime date,
          String? categoryId}) =>
      db.transaction(() async {
        if (selected.isEmpty ||
            selected.map((r) => r.id).toSet().length != selected.length)
          throw StateError('Selecione receitas sem duplicatas.');
        if (totalMinor < 0 ||
            totalMinor > 9000000000000000 ||
            date.year < 2000 ||
            date.year > 2100)
          throw const FormatException('Valor ou data inválidos.');
        final returns = selected.first.kind == 'return';
        if (selected
            .any((r) => (r.kind == 'return') != returns || r.confirmed != 0))
          throw StateError(
              'Confirme recebimentos e devoluções em lotes separados.');
        await _account(accountId);
        await _category(categoryId, returns ? 'expense' : 'income');
        final current = {for (final r in await list()) r.id: r};
        for (final r in selected)
          if (current[r.id]?.revision != r.revision)
            throw StateError(
                'O cashback mudou. Atualize a lista antes de confirmar.');
        final amounts = distributeMinor(
            totalMinor, {for (final r in selected) r.id: r.amountMinor});
        final now = EntityMetadata.nowUtcMillis();
        for (final receipt in selected) {
          final amount = amounts[receipt.id]!;
          final waived = amount == 0;
          final row = (await rows(
                  'SELECT * FROM cashback_receipts WHERE id=?', [receipt.id]))
              .single;
          final snapshot = jsonEncode({
            'amount': amount,
            'account': accountId,
            'category': categoryId,
            'date': cardDay(date)
          });
          await db.customStatement(
              '''UPDATE transactions SET actual_amount_minor=?,effective_at=?,account_id=?,category_id=?,deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?''',
              [
                waived ? null : amount,
                waived ? null : cardDay(date),
                accountId,
                categoryId,
                waived ? now : null,
                now,
                receipt.id
              ]);
          await db.customStatement(
              'UPDATE cashback_receipts SET confirmed=?,confirmation_json=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
              [waived ? 2 : 1, snapshot, now, receipt.id]);
          await _baseline(receipt.claimId, row.read<int>('theory_minor'),
              row.read<int>('base_minor'), row.read<int>('rate'), now);
        }
        await reconcile();
        await validateCardRewards(db);
      });
  Future<void> _baseline(
      String claim, int theory, int base, int rate, int now) async {
    final sum = (await rows(
            '''SELECT COALESCE(SUM(CASE WHEN r.confirmed=2 THEN 0 WHEN r.kind='return' THEN -t.actual_amount_minor ELSE t.actual_amount_minor END),0) AS net
      FROM cashback_receipts r JOIN transactions t ON t.id=r.id WHERE r.claim_id=? AND r.deleted_at IS NULL AND r.confirmed<>0''',
            [claim]))
        .single
        .read<int>('net');
    await db.customStatement(
        '''UPDATE cashback_claims SET confirmed_theory_minor=?,accepted_difference_minor=?,accepted_base_minor=?,confirmed_rate=MAX(confirmed_rate,?),updated_at=?,sync_version=sync_version+1 WHERE id=?''',
        [theory, sum - theory, base, rate, now, claim]);
  }

  Future<bool> isReceipt(String id) async => (await rows(
          'SELECT id FROM cashback_receipts WHERE id=? AND deleted_at IS NULL',
          [id]))
      .isNotEmpty;
  Future<void> confirmDefault(String id, DateTime date) async {
    final receipt = (await list()).firstWhere((r) => r.id == id);
    await confirm([receipt],
        totalMinor: receipt.amountMinor,
        accountId: receipt.accountId,
        categoryId: receipt.categoryId,
        date: date);
  }

  Future<void> undo(String id) => db.transaction(() async {
        final receipt = (await rows(
                'SELECT * FROM cashback_receipts WHERE id=? AND deleted_at IS NULL',
                [id]))
            .single;
        if (receipt.read<int>('confirmed') == 0)
          throw StateError('Recebimento ainda previsto.');
        final claim = receipt.read<String>('claim_id');
        final others = await rows(
            'SELECT * FROM cashback_receipts WHERE claim_id=? AND confirmed<>0 AND deleted_at IS NULL AND id<>? ORDER BY updated_at DESC,id DESC',
            [claim, id]);
        if (others.any((r) =>
            int.parse(r.read<String>('id').split('-').last) >
            int.parse(id.split('-').last)))
          throw StateError('Desfaça primeiro o último ajuste deste cashback.');
        final now = EntityMetadata.nowUtcMillis();
        for (final pending in await rows(
            'SELECT id FROM cashback_receipts WHERE claim_id=? AND confirmed=0 AND deleted_at IS NULL',
            [claim])) {
          await _cancel(pending.read<String>('id'), now);
        }
        await db.customStatement(
            'UPDATE transactions SET actual_amount_minor=NULL,effective_at=NULL,deleted_at=NULL,updated_at=?,sync_version=sync_version+1 WHERE id=?',
            [now, id]);
        await db.customStatement(
            'UPDATE cashback_receipts SET confirmed=0,confirmation_json=NULL,updated_at=?,sync_version=sync_version+1 WHERE id=?',
            [now, id]);
        final prior = others.firstOrNull;
        await _baseline(
            claim,
            prior?.read<int>('theory_minor') ?? 0,
            prior?.read<int>('base_minor') ?? 0,
            prior?.read<int>('rate') ?? 0,
            now);
        await db.customStatement(
            'UPDATE cashback_claims SET confirmed_rate=? WHERE id=?', [
          others.fold<int>(
              0, (v, r) => r.read<int>('rate') > v ? r.read<int>('rate') : v),
          claim
        ]);
        await reconcile();
        await validateCardRewards(db);
      });
}

class _PurchaseFact {
  _PurchaseFact(this.id, this.description);
  final String id, description;
  int total = 0, original = 0, refund = 0;
}
