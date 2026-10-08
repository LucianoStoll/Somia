class Establishment {
  static String normalize(String value) {
    final result = value.trim().replaceAll(RegExp(r' +'), ' ');
    if (result.length > 100 || result.contains(RegExp(r'[\r\n\t]'))) {
      throw const FormatException(
          'O estabelecimento deve ter até 100 caracteres e uma única linha.');
    }
    return result;
  }

  static String key(String value) => normalize(value).toLowerCase();
}
