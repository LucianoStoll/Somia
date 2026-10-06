enum AssetKind {
  vehicle('Veículo'),
  property('Imóvel'),
  other('Outro bem');

  const AssetKind(this.label);
  final String label;
}

class AssetValuation {
  const AssetValuation(
      {required this.id,
      required this.date,
      required this.valueMinor,
      required this.debtMinor,
      this.creditor = '',
      this.notes = ''});
  final String id, creditor, notes;
  final DateTime date;
  final int valueMinor, debtMinor;
}

class Asset {
  const Asset(
      {required this.id,
      required this.name,
      required this.kind,
      required this.acquiredAt,
      required this.acquisitionMinor,
      required this.history,
      this.notes = '',
      this.archived = false});
  final String id, name, notes;
  final AssetKind kind;
  final DateTime acquiredAt;
  final int acquisitionMinor;
  final bool archived;
  final List<AssetValuation> history;
  AssetValuation? get current => history.firstOrNull;
  int get valueMinor => current?.valueMinor ?? 0;
  int get debtMinor => current?.debtMinor ?? 0;
}

class AssetDraft {
  const AssetDraft(
      {required this.name,
      required this.kind,
      required this.acquiredAt,
      required this.acquisitionMinor,
      this.notes = ''});
  final String name, notes;
  final AssetKind kind;
  final DateTime acquiredAt;
  final int acquisitionMinor;
}

class AssetValuationDraft {
  const AssetValuationDraft(
      {required this.date,
      required this.valueMinor,
      required this.debtMinor,
      this.creditor = '',
      this.notes = ''});
  final DateTime date;
  final int valueMinor, debtMinor;
  final String creditor, notes;
}

class AssetOverview {
  const AssetOverview(this.assets,
      {this.accountsMinor = 0,
      this.cardDebtMinor = 0,
      this.cardCreditMinor = 0});
  final List<Asset> assets;
  final int accountsMinor, cardDebtMinor, cardCreditMinor;
  Iterable<Asset> get active => assets.where((a) => !a.archived);
  int get assetsMinor => active.fold(0, (s, a) => s + a.valueMinor);
  int get assetDebtMinor => assets.fold(0, (s, a) => s + a.debtMinor);
  int get netMinor =>
      accountsMinor +
      cardCreditMinor +
      assetsMinor -
      assetDebtMinor -
      cardDebtMinor;
}

abstract interface class AssetsRepository {
  Future<AssetOverview> load();
  Future<String> save(AssetDraft draft,
      {String? id, AssetValuationDraft? initial});
  Future<void> assess(String id, AssetValuationDraft draft,
      {String? expectedLatestId});
  Future<void> archive(String id, bool archived);
}
