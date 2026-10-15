import 'dart:convert';

/// Parts belong to their parent movement and never create another cash entry.
class CategoryAllocation {
  const CategoryAllocation(this.categoryId, this.amountMinor,
      {this.percentageBasisPoints});
  final int? percentageBasisPoints;
  final String categoryId;
  final int amountMinor;

  static String encode(List<CategoryAllocation> parts) => jsonEncode([
        for (final p in parts)
          {
            'categoryId': p.categoryId,
            'amountMinor': p.amountMinor,
            if (p.percentageBasisPoints != null)
              'percentageBasisPoints': p.percentageBasisPoints
          },
      ]);

  static List<CategoryAllocation> decode(String raw) {
    final data = jsonDecode(raw);
    if (data is! List || data.length > 100) {
      throw const FormatException('Rateio inválido (máximo de 100 partes).');
    }
    return data.map((p) {
      if (p is! Map ||
          (p.length != 2 && p.length != 3) ||
          p.keys.any((k) => ![
                'categoryId',
                'amountMinor',
                'percentageBasisPoints'
              ].contains(k)) ||
          (p.containsKey('percentageBasisPoints') &&
              p['percentageBasisPoints'] is! int) ||
          p['categoryId'] is! String ||
          (p['categoryId'] as String).isEmpty ||
          p['amountMinor'] is! int) {
        throw const FormatException('Parte de rateio inválida.');
      }
      return CategoryAllocation(
        p['categoryId'] as String,
        p['amountMinor'] as int,
        percentageBasisPoints: p['percentageBasisPoints'] as int?,
      );
    }).toList();
  }

  static void validate(List<CategoryAllocation> parts, int total) {
    if (parts.isEmpty) return;
    if (parts.any((p) => p.percentageBasisPoints != null) &&
        (parts.any((p) =>
                p.percentageBasisPoints == null ||
                p.percentageBasisPoints! < 0 ||
                p.percentageBasisPoints! > 10000) ||
            parts.fold(0, (s, p) => s + (p.percentageBasisPoints ?? 0)) !=
                10000)) {
      throw const FormatException('Os percentuais devem somar 100%.');
    }
    if (parts.length < 2 ||
        parts.length > 100 ||
        parts.map((p) => p.categoryId).toSet().length != parts.length ||
        parts.any((p) => p.categoryId.isEmpty || p.amountMinor < 0) ||
        parts.fold<BigInt>(
              BigInt.zero,
              (s, p) => s + BigInt.from(p.amountMinor),
            ) !=
            BigInt.from(total)) {
      throw const FormatException(
        'Distribua o valor completo entre pelo menos duas categorias distintas.',
      );
    }
    if (parts.first.percentageBasisPoints != null) {
      final expected = _amounts(parts, total);
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].amountMinor != expected[i]) {
          throw const FormatException(
              'Valores incompatíveis com os percentuais do rateio.');
        }
      }
    }
  }

  /// Largest remainder, with stable row order as tie-breaker; BigInt prevents
  /// overflow at the maximum supported monetary amount.
  static List<CategoryAllocation> distribute(
    List<CategoryAllocation> weights,
    int total,
  ) {
    if (weights.isEmpty) return const [];
    final amounts = _amounts(weights, total);
    final result = [
      for (var i = 0; i < weights.length; i++)
        CategoryAllocation(weights[i].categoryId, amounts[i],
            percentageBasisPoints: weights[i].percentageBasisPoints),
    ];
    validate(result, total);
    return result;
  }

  static List<int> _amounts(List<CategoryAllocation> weights, int total) {
    if (total <= 0 ||
        weights.any((p) => (p.percentageBasisPoints ?? p.amountMinor) < 0)) {
      throw const FormatException('Informe partes e total maiores que zero.');
    }
    final sum = weights.fold<BigInt>(
      BigInt.zero,
      (s, p) => s + BigInt.from(p.percentageBasisPoints ?? p.amountMinor),
    );
    if (sum == BigInt.zero) {
      throw const FormatException('Informe uma distribuição maior que zero.');
    }
    final products = [
      for (final p in weights)
        BigInt.from(p.percentageBasisPoints ?? p.amountMinor) *
            BigInt.from(total),
    ];
    final amounts = [for (final p in products) (p ~/ sum).toInt()];
    final order = List.generate(weights.length, (i) => i)
      ..sort((a, b) {
        final cmp = (products[b] % sum).compareTo(products[a] % sum);
        return cmp == 0 ? a.compareTo(b) : cmp;
      });
    final remaining = total - amounts.fold(0, (a, b) => a + b);
    for (var i = 0; i < remaining; i++) {
      amounts[order[i]]++;
    }
    return amounts;
  }
}
