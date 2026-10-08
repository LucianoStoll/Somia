import 'package:flutter/material.dart';
import '../../../core/database/app_database.dart';
import '../../../core/di/injection.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../accounts/domain/money_minor.dart';
import '../data/transaction_settlements_repository.dart';
import '../domain/financial_transaction.dart';

class TransactionSettlementsPage extends StatefulWidget {
  const TransactionSettlementsPage({super.key, required this.item});
  final FinancialTransaction item;
  @override
  State<TransactionSettlementsPage> createState() =>
      _TransactionSettlementsPageState();
}

class _TransactionSettlementsPageState
    extends State<TransactionSettlementsPage> {
  late final repo = TransactionSettlementsRepository(getIt<AppDatabase>());
  List<TransactionSettlement> rows = [];
  List<Account> accounts = [];
  final amount = TextEditingController();
  String? accountId;
  DateTime date = DateTime.now();
  bool busy = true;
  String? error;
  int get remaining =>
      widget.item.amountMinor - rows.fold(0, (s, r) => s + r.amountMinor);
  String money(int v) => MoneyMinor.display(v, widget.item.currencyCode);
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final payments = await repo.list(widget.item.id);
      final all = await getIt<AccountsRepository>().list();
      if (!mounted) return;
      setState(() {
        rows = payments;
        accounts = all
            .where((a) =>
                !a.isArchived && a.currencyCode == widget.item.currencyCode)
            .toList();
        accountId ??= accounts
                .where((a) => a.id == widget.item.accountId)
                .firstOrNull
                ?.id ??
            accounts.firstOrNull?.id;
        busy = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          busy = false;
          error = e.toString();
        });
    }
  }

  Future<void> _save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = MoneyMinor.parse(amount.text);
      if (accountId == null)
        throw const FormatException('Selecione uma conta.');
      await repo.add(widget.item.id,
          accountId: accountId!, amountMinor: value, date: date);
      amount.clear();
      await _load();
    } catch (e) {
      if (mounted)
        setState(() {
          busy = false;
          error = e.toString().replaceFirst('FormatException: ', '');
        });
    }
  }

  Future<void> _remove(TransactionSettlement row) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Desfazer baixa?'),
                content: Text(
                    '${money(row.amountMinor)} retornará ao saldo pendente.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Desfazer'))
                ]));
    if (yes != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repo.remove(widget.item.id, row.id);
      await _load();
    } catch (e) {
      if (mounted)
        setState(() {
          busy = false;
          error = e.toString();
        });
    }
  }

  String label(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Baixas e histórico')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text(widget.item.description,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text('Total: ${money(widget.item.amountMinor)}'),
          Text('Restante para baixar: ${money(remaining)}'),
          if (error != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (busy) const LinearProgressIndicator(),
          if (widget.item.effectiveDate != null)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                    'Este lançamento está efetivado integralmente. Marque como pendente antes de adicionar baixas.')),
          if (remaining > 0 && widget.item.effectiveDate == null) ...[
            const SizedBox(height: 20),
            TextField(
                controller: amount,
                enabled: !busy,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor da baixa')),
            DropdownButtonFormField<String>(
                initialValue: accountId,
                decoration: const InputDecoration(labelText: 'Conta'),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name))
                ],
                onChanged: busy ? null : (v) => setState(() => accountId = v)),
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: const Text('Data do pagamento / recebimento'),
                subtitle: Text(label(date)),
                onTap: busy
                    ? null
                    : () async {
                        final picked = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2200));
                        if (picked != null && mounted)
                          setState(() => date = picked);
                      }),
            FilledButton(
                onPressed: busy ? null : _save,
                child: Text(widget.item.type == TransactionType.income
                    ? 'Registrar recebimento'
                    : 'Registrar pagamento')),
          ],
          const SizedBox(height: 24),
          Text('Histórico', style: Theme.of(context).textTheme.titleMedium),
          if (rows.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Nenhuma baixa registrada.')),
          for (final row in rows)
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(money(row.amountMinor)),
                subtitle: Text('${row.accountName} · ${label(row.date)}'),
                trailing: IconButton(
                    tooltip: 'Desfazer baixa',
                    onPressed: busy ? null : () => _remove(row),
                    icon: const Icon(Icons.undo))),
        ]),
      );
}
