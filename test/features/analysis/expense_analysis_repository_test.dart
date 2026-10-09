import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/analysis/data/expense_analysis_repository.dart';

int at(int month, [int day = 10]) =>
    DateTime.utc(2026, month, day).millisecondsSinceEpoch;
Future<void> seedAnalysis(AppDatabase db) async {
  await db.customStatement(
      "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES('a','Banco','checking','BRL',100000,0,0)");
  await db.customStatement(
      "INSERT INTO categories(id,name,type,created_at,updated_at) VALUES('food','Alimentação','expense',0,0)");
  await db.customStatement(
      "INSERT INTO categories(id,name,type,parent_id,created_at,updated_at) VALUES('market','Mercado','expense','food',0,0)");
  await db.customStatement(
      "INSERT INTO credit_cards(id,name,payment_account_id,closing_day,due_day,created_at,updated_at) VALUES('c','Cartão','a',5,10,0,0)");
}

Future<void> tx(AppDatabase db, String id, int amount, int month,
        {bool effective = false,
        String account = 'a',
        String category = 'market',
        String allocations = '[]'}) =>
    db.customStatement('''
  INSERT INTO transactions(id,description,type,planned_amount_minor,actual_amount_minor,competence_at,posted_at,due_at,effective_at,account_id,category_id,allocations_json,created_at,updated_at)
  VALUES(?,?,'expense',?,?,?,?,?,?,?,?,?,0,0)''', [
      id,
      id,
      amount,
      effective ? amount : null,
      at(month),
      at(month),
      at(month),
      effective ? at(month) : null,
      account,
      category,
      allocations
    ]);
Future<void> invoice(AppDatabase db, String id, int month, int amount) =>
    db.transaction(() async {
      await db.customStatement(
          'INSERT INTO card_invoices(id,card_id,month_at,closing_at,due_at,created_at,updated_at) VALUES(?,?,?,?,?,0,0)',
          [id, 'c', at(month, 1), at(month, 5), at(month)]);
      await db.customStatement(
          "INSERT INTO card_entries(id,card_id,invoice_id,purchase_id,description,category_id,kind,amount_minor,posted_at,created_at,updated_at) VALUES(?,'c',?,?,'Compra cartão','market','purchase',?,?,0,0)",
          ['${id}entry', id, '${id}purchase', amount, at(month)]);
    });
void main() {
  late AppDatabase db;
  late ExpenseAnalysisRepository repo;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ExpenseAnalysisRepository(db, now: () => DateTime(2026, 10, 9));
    await seedAnalysis(db);
  });
  tearDown(() => db.close());
  test(
      'categorias, três meses completos, rateio, estorno e fatura sem duplicar pagamento',
      () async {
    await tx(db, 'jul', 3000, 7, effective: true);
    await tx(db, 'sep', 6000, 9, effective: true);
    await tx(db, 'oct', 10000, 10,
        allocations:
            '[{"categoryId":"market","amountMinor":6000},{"categoryId":"food","amountMinor":4000}]');
    await invoice(db, 'octi', 10, 2000);
    await db.customStatement(
        "INSERT INTO card_entries(id,card_id,invoice_id,purchase_id,description,category_id,kind,amount_minor,posted_at,created_at,updated_at) VALUES('refund','c','octi','refund','Estorno','market','refund',-500,?,0,0)",
        [at(10)]);
    await db.customStatement(
        "INSERT INTO card_payments(id,invoice_id,account_id,amount_minor,effective_at,created_at,updated_at) VALUES('p','octi','a',1000,?,0,0)",
        [at(10, 1)]);
    final result = await repo.load(DateTime(2026, 10));
    final c = result.comparisons('BRL').single;
    expect(c.category, 'Alimentação');
    expect(c.current, 11500);
    expect(c.previous, 6000);
    expect(c.average, 3000);
    expect(c.difference, 5500);
    expect(c.changePercent, closeTo(91.666, 0.01));
    expect(
        result
            .inMonth('BRL', DateTime(2026, 10))
            .where((e) => e.subcategory == 'Mercado')
            .fold<int>(0, (s, e) => s + e.amount),
        7500);
    expect(
        (await db
                .customSelect('SELECT COUNT(*) n FROM card_invoices')
                .getSingle())
            .read<int>('n'),
        1);
  });
  test(
      'baixas aparecem no pagamento e restante no vencimento, exclusões e flags respeitadas',
      () async {
    await tx(db, 'partial', 10000, 11);
    await db.customStatement(
        "INSERT INTO transaction_settlements(id,transaction_id,account_id,amount_minor,effective_at,created_at,updated_at) VALUES('s','partial','a',3000,?,0,0)",
        [at(10, 1)]);
    await tx(db, 'hidden', 99000, 10);
    await db.customStatement(
        "UPDATE transactions SET ignore_analytics=1 WHERE id='hidden'");
    await tx(db, 'deleted', 99000, 10);
    await db.customStatement(
        "UPDATE transactions SET deleted_at=1 WHERE id='deleted'");
    final result = await repo.load(DateTime(2026, 10));
    expect(result.comparisons('BRL').single.current, 3000);
    expect(result.commitments['BRL']!.first.expenseTotal, 7000);
    expect(result.comparisons('BRL').single.changePercent, isNull);
  });
  test(
      'compromissos deduzem pagamento real e crédito, sem repetir dívida antiga',
      () async {
    await invoice(db, 'sep', 9, 10000);
    await invoice(db, 'nov', 11, 8000);
    await invoice(db, 'dec', 12, 9000);
    await db.customStatement(
        "INSERT INTO card_payments(id,invoice_id,account_id,amount_minor,effective_at,created_at,updated_at) VALUES('p','nov','a',3000,?,0,0)",
        [at(10, 1)]);
    await db.customStatement(
        "INSERT INTO card_payments(id,invoice_id,account_id,amount_minor,effective_at,created_at,updated_at) VALUES('scheduled','dec','a',2000,?,0,0)",
        [at(12)]);
    final r = await repo.load(DateTime(2026, 10));
    expect(r.commitments['BRL']![0].cardTotal, 5000);
    expect(r.commitments['BRL']![1].cardTotal, 9000);
    expect(r.commitments['BRL']!.length, 6);
    await db.customStatement(
        "INSERT INTO card_payments(id,invoice_id,account_id,amount_minor,effective_at,created_at,updated_at) VALUES('credit','sep','a',12000,?,0,0)",
        [at(10, 1)]);
    expect(
        (await repo.load(DateTime(2026, 10)))
            .commitments['BRL']!
            .first
            .cardTotal,
        3000);
  });
  test(
      'saldo por tipo inclui investimento fora do saldo mensal, negativos e moedas separadas',
      () async {
    await db.customStatement(
        "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,include_in_balance,is_archived,created_at,updated_at) VALUES('i','CDB','investment','BRL',20000,0,0,0,0),('w','Carteira','cash','BRL',-5000,1,0,0,0),('old','Antiga','checking','BRL',90000,1,1,0,0),('usd','Exterior','checking','USD',1000,1,0,0,0)");
    await tx(db, 'future', 5000, 12, effective: true);
    final r = await repo.load(DateTime(2026, 10));
    expect(r.balances('BRL')[AccountType.checking], 100000);
    expect(r.balances('BRL')[AccountType.investment], 20000);
    expect(r.balances('BRL')[AccountType.cash], -5000);
    expect(r.balances('USD')[AccountType.checking], 1000);
    expect(r.currencies, ['BRL', 'USD']);
  });
}
