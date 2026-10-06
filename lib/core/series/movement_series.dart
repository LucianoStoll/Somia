import 'dart:math' as math;

enum SeriesKind {
  single('Único'),
  recurring('Recorrente'),
  installments('Parcelado');

  const SeriesKind(this.label);
  final String label;
}

enum SeriesUnit {
  day('Diária', 'dia(s)'),
  week('Semanal', 'semana(s)'),
  month('Mensal', 'mês(es)'),
  year('Anual', 'ano(s)');

  const SeriesUnit(this.label, this.intervalLabel);
  final String label;
  final String intervalLabel;
}

enum SeriesScope { onlyThis, thisAndNext }

class SeriesPlan {
  const SeriesPlan(
      {required this.kind,
      required this.count,
      this.unit = SeriesUnit.month,
      this.interval = 1,
      this.amountIsTotal = true});
  final SeriesKind kind;
  final int count;
  final SeriesUnit unit;
  final int interval;
  final bool amountIsTotal;

  void validate() {
    if (kind == SeriesKind.single ||
        count < 2 ||
        count > 1000 ||
        interval < 1 ||
        interval > 1000) {
      throw const FormatException(
          'Use de 2 a 1000 ocorrências e intervalo de 1 a 1000.');
    }
  }

  /// Cada data parte da âncora, evitando 31/jan → 28/fev → 28/mar.
  DateTime dateAt(DateTime anchor, int index) {
    final steps = index * interval;
    if (unit == SeriesUnit.day || unit == SeriesUnit.week) {
      return DateTime.utc(anchor.year, anchor.month,
          anchor.day + steps * (unit == SeriesUnit.week ? 7 : 1));
    }
    final month = DateTime.utc(anchor.year,
        anchor.month + (unit == SeriesUnit.year ? steps * 12 : steps));
    return DateTime.utc(month.year, month.month,
        math.min(anchor.day, DateTime.utc(month.year, month.month + 1, 0).day));
  }

  List<int> amounts(int enteredMinor) {
    validate();
    if (enteredMinor <= 0 || enteredMinor > 9000000000000000) {
      throw const FormatException(
          'Informe um valor positivo dentro do limite.');
    }
    if (kind != SeriesKind.installments || !amountIsTotal) {
      if (enteredMinor * count > 9000000000000000) {
        throw const FormatException(
            'O total da série ultrapassa o limite permitido.');
      }
      return List.filled(count, enteredMinor);
    }
    if (enteredMinor < count) {
      throw const FormatException(
          'O total deve permitir ao menos um centavo por parcela.');
    }
    final base = enteredMinor ~/ count;
    final remainder = enteredMinor % count;
    return List.generate(count, (i) => base + (i < remainder ? 1 : 0));
  }
}

class SeriesInfo {
  const SeriesInfo({required this.id, required this.index, required this.plan});
  final String id;

  /// Índice baseado em zero; a identificação apresentada começa em 1.
  final int index;
  final SeriesPlan plan;
  String get label => '${plan.kind.label} ${index + 1}/${plan.count}';
}
