enum AccountType {
  checking('Conta corrente'),
  savings('Poupança'),
  cash('Carteira / dinheiro'),
  investment('Investimento'),
  other('Outra');

  const AccountType(this.label);
  final String label;
}

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.currencyCode,
    required this.initialBalanceMinor,
    required this.currentBalanceMinor,
    required this.projectedBalanceMinor,
    required this.isArchived,
    required this.includeInAnalytics,
    this.includeInBalance = true,
    this.institutionId,
  });

  final String id;
  final String name;
  final AccountType type;
  final String currencyCode;
  final int initialBalanceMinor;
  final int currentBalanceMinor;
  final int projectedBalanceMinor;
  final bool isArchived;
  final bool includeInAnalytics;
  final bool includeInBalance;
  final String? institutionId;
}

class AccountDraft {
  const AccountDraft({
    required this.name,
    required this.type,
    required this.currencyCode,
    required this.initialBalanceMinor,
    required this.includeInAnalytics,
    this.includeInBalance = true,
    this.institutionId,
  });

  final String name;
  final AccountType type;
  final String currencyCode;
  final int initialBalanceMinor;
  final bool includeInAnalytics;
  final bool includeInBalance;
  final String? institutionId;
}
