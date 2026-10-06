import 'package:finapp/core/series/movement_series.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mensal mantém dia 31, com fevereiro e ano bissexto', () {
    const p = SeriesPlan(kind: SeriesKind.recurring, count: 3);
    expect(List.generate(3, (i) => p.dateAt(DateTime(2026, 1, 31), i)), [
      DateTime.utc(2026, 1, 31),
      DateTime.utc(2026, 2, 28),
      DateTime.utc(2026, 3, 31)
    ]);
    expect(p.dateAt(DateTime(2024, 1, 31), 1), DateTime.utc(2024, 2, 29));
  });
  test('anual retoma 29/fevereiro em anos bissextos', () {
    const p =
        SeriesPlan(kind: SeriesKind.recurring, count: 5, unit: SeriesUnit.year);
    expect(p.dateAt(DateTime(2024, 2, 29), 1), DateTime.utc(2025, 2, 28));
    expect(p.dateAt(DateTime(2024, 2, 29), 4), DateTime.utc(2028, 2, 29));
  });
  test('intervalos personalizados respeitam virada do ano e unidades', () {
    for (final (unit, expected) in [
      (SeriesUnit.day, DateTime.utc(2027, 1, 2)),
      (SeriesUnit.week, DateTime.utc(2027, 1, 14)),
      (SeriesUnit.month, DateTime.utc(2027, 2, 28)),
      (SeriesUnit.year, DateTime.utc(2028, 12, 31))
    ]) {
      final p = SeriesPlan(
          kind: SeriesKind.recurring, count: 2, unit: unit, interval: 2);
      expect(p.dateAt(DateTime(2026, 12, 31), 1), expected);
    }
  });
  test(
      'parcelas reconciliam todos os centavos; valor por parcela e recorrência',
      () {
    const total = SeriesPlan(kind: SeriesKind.installments, count: 3);
    expect(total.amounts(10000), [3334, 3333, 3333]);
    expect(total.amounts(3), [1, 1, 1]);
    for (var count = 2; count <= 60; count++) {
      final values = SeriesPlan(kind: SeriesKind.installments, count: count)
          .amounts(99999);
      expect(values.fold(0, (sum, amount) => sum + amount), 99999);
      expect(values.first - values.last, lessThanOrEqualTo(1));
    }
    expect(
        const SeriesPlan(
                kind: SeriesKind.installments, count: 3, amountIsTotal: false)
            .amounts(10000),
        [10000, 10000, 10000]);
    expect(
        const SeriesPlan(kind: SeriesKind.recurring, count: 3).amounts(10000),
        [10000, 10000, 10000]);
    expect(() => total.amounts(2), throwsFormatException);
    expect(
        () =>
            const SeriesPlan(kind: SeriesKind.recurring, count: 0).amounts(100),
        throwsFormatException);
    expect(
        () => const SeriesPlan(kind: SeriesKind.recurring, count: 1001)
            .amounts(100),
        throwsFormatException);
    expect(
        () =>
            const SeriesPlan(kind: SeriesKind.recurring, count: 2, interval: 0)
                .amounts(100),
        throwsFormatException);
    expect(() => total.amounts(9000000000000001), throwsFormatException);
  });
}
