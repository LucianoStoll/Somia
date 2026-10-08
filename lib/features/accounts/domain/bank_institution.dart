/// Identificadores estáveis: os backups guardam a escolha, não o caminho do asset.
class BankInstitution {
  const BankInstitution(this.id, this.name, {this.aliases = ''});

  final String id;
  final String name;
  final String aliases;
  String get assetPath => 'assets/institutions/$id.png';

  static const catalog = [
    BankInstitution('banco-do-brasil', 'Banco do Brasil', aliases: 'BB'),
    BankInstitution('mercado-pago', 'Mercado Pago', aliases: 'MercadoPago'),
    BankInstitution('bradesco', 'Bradesco'),
    BankInstitution('btg', 'BTG Pactual', aliases: 'BTG Banking'),
    BankInstitution('inter', 'Inter', aliases: 'Banco Inter'),
    BankInstitution('itau', 'Itaú', aliases: 'Itau Unibanco'),
    BankInstitution('nubank', 'Nubank', aliases: 'Nu'),
    BankInstitution('santander', 'Santander'),
    BankInstitution('sicoob', 'Sicoob'),
    BankInstitution('sicredi', 'Sicredi'),
  ];

  static BankInstitution? find(String? id) {
    for (final bank in catalog) {
      if (bank.id == id) return bank;
    }
    return null;
  }

  static String _normalize(String value) {
    const accented = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const plain = 'aaaaaeeeeiiiiooooouuuuc';
    var result = value.trim().toLowerCase();
    for (var i = 0; i < accented.length; i++) {
      result = result.replaceAll(accented[i], plain[i]);
    }
    return result;
  }

  static List<BankInstitution> search(String query) {
    final words = _normalize(query).split(RegExp(r'\s+'));
    return catalog.where((bank) {
      final text = _normalize('${bank.name} ${bank.aliases}');
      return words.every(text.contains);
    }).toList();
  }
}
