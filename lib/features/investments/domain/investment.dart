import '../../accounts/domain/account.dart';

enum InvestmentKind {
  cdb('CDB'),
  cdi('Conta remunerada / CDI'),
  savings('Poupança');

  const InvestmentKind(this.label);
  final String label;
}

class Investment {
  const Investment({
    required this.id,
    required this.name,
    required this.kind,
    required this.institution,
    required this.notes,
    this.maturityDate,
    required this.account,
  });
  final String id, name, institution, notes;
  final InvestmentKind kind;
  final DateTime? maturityDate;
  final Account account;
}

class InvestmentDraft {
  const InvestmentDraft({
    required this.name,
    required this.kind,
    this.institution = '',
    this.notes = '',
    this.accountId,
    this.maturityDate,
    this.initialBalanceMinor = 0,
  });
  final String name, institution, notes;
  final InvestmentKind kind;
  final String? accountId;
  final DateTime? maturityDate;
  final int initialBalanceMinor;
}

class InvestmentOverview {
  const InvestmentOverview(this.investments, this.accounts);
  final List<Investment> investments;
  final List<Account> accounts;
  int get investedMinor => investments.fold(
        0,
        (total, item) => total + item.account.currentBalanceMinor,
      );
  int get financialAssetsMinor => accounts
      .where((a) => a.currencyCode == 'BRL')
      .fold(0, (total, account) => total + account.currentBalanceMinor);
}

abstract interface class InvestmentsRepository {
  Future<InvestmentOverview> load({DateTime? date});
  Future<void> save(InvestmentDraft draft, {String? id});
  Future<void> transfer(
    String id, {
    required String otherAccountId,
    required bool deposit,
    required int amountMinor,
    required DateTime date,
  });
  Future<void> recordReturn(
    String id, {
    required int amountMinor,
    required DateTime date,
  });
  Future<void> reconcile(
    String id, {
    required int targetMinor,
    required int expectedBalanceMinor,
    required DateTime date,
  });
  Future<void> setArchived(String id, bool archived);
}
