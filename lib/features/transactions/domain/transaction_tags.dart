import 'dart:convert';

/// Labels are trimmed and compared without case; first spelling is preserved.
class TransactionTags {
  static String key(String tag) => tag.trim().toLowerCase();
  static List<String> normalize(Iterable<String> tags) {
    final unique = <String, String>{};
    for (final raw in tags) {
      final tag = raw.trim();
      if (tag.isEmpty) continue;
      if (tag.length > 40 || tag.contains(RegExp(r'[\r\n]'))) {
        throw const FormatException(
            'Cada tag deve ter até 40 caracteres e uma única linha.');
      }
      unique.putIfAbsent(key(tag), () => tag);
    }
    if (unique.length > 20) {
      throw const FormatException('Use no máximo 20 tags por lançamento.');
    }
    return unique.values.toList();
  }

  static String encode(Iterable<String> tags) => jsonEncode(normalize(tags));
  static List<String> decode(String value) {
    final parsed = jsonDecode(value);
    if (parsed is! List || parsed.any((v) => v is! String)) {
      throw const FormatException('Tags inválidas.');
    }
    return normalize(parsed.cast<String>());
  }
}
