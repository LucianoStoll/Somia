import 'package:flutter/material.dart';

import '../../features/accounts/domain/money_minor.dart';
import 'movement_series.dart';

class SeriesFormController extends ChangeNotifier {
  SeriesKind kind = SeriesKind.single;
  SeriesUnit unit = SeriesUnit.month;
  bool amountIsTotal = true;
  final count = TextEditingController(text: '2');
  final interval = TextEditingController(text: '1');
  bool get active => kind != SeriesKind.single;
  Object get snapshot => (kind, unit, amountIsTotal, count.text, interval.text);
  SeriesPlan? get plan => !active
      ? null
      : SeriesPlan(
          kind: kind,
          unit: unit,
          count: int.parse(count.text),
          interval: int.parse(interval.text),
          amountIsTotal: amountIsTotal);
  void change(VoidCallback change) {
    change();
    notifyListeners();
  }

  @override
  void dispose() {
    count.dispose();
    interval.dispose();
    super.dispose();
  }
}

class SeriesFormFields extends StatelessWidget {
  const SeriesFormFields(
      {super.key,
      required this.controller,
      required this.amount,
      required this.dueDate,
      required this.currencyCode,
      this.cardMode = false,
      this.existing});
  final SeriesFormController controller;
  final TextEditingController amount;
  final DateTime dueDate;
  final String currencyCode;
  final SeriesInfo? existing;
  final bool cardMode;

  String? _integer(String? value, int min) {
    final n = int.tryParse(value ?? '');
    return n == null || n < min || n > 1000 ? 'Informe de $min a 1000.' : null;
  }

  @override
  Widget build(BuildContext context) {
    if (existing != null) {
      return Text('${existing!.label} · ${existing!.plan.unit.label}'
          '\nO valor informado é por ocorrência.');
    }
    return Column(mainAxisSize: MainAxisSize.min, spacing: 16, children: [
      DropdownButtonFormField<SeriesKind>(
        key: const ValueKey('series-kind'),
        isExpanded: true,
        initialValue: controller.kind,
        decoration: const InputDecoration(labelText: 'Lançamento'),
        items: [
          for (final kind in SeriesKind.values)
            if (!cardMode || kind != SeriesKind.recurring)
              DropdownMenuItem(value: kind, child: Text(kind.label))
        ],
        onChanged: (kind) {
          if (kind != null) controller.change(() => controller.kind = kind);
        },
      ),
      if (controller.active) ...[
        if (!cardMode) ...[
          DropdownButtonFormField<SeriesUnit>(
            key: const ValueKey('series-unit'),
            isExpanded: true,
            initialValue: controller.unit,
            decoration: const InputDecoration(labelText: 'Frequência'),
            items: [
              for (final unit in SeriesUnit.values)
                DropdownMenuItem(value: unit, child: Text(unit.label))
            ],
            onChanged: (unit) {
              if (unit != null) controller.change(() => controller.unit = unit);
            },
          ),
          TextFormField(
              key: const ValueKey('series-interval'),
              controller: controller.interval,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                  labelText: 'A cada (${controller.unit.intervalLabel})'),
              validator: (value) => _integer(value, 1)),
        ],
        TextFormField(
            key: const ValueKey('series-count'),
            controller: controller.count,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
                labelText: 'Quantidade (inclui o primeiro)'),
            validator: (value) => _integer(value, 2)),
        if (controller.kind == SeriesKind.installments)
          DropdownButtonFormField<bool>(
              key: const ValueKey('series-amount-mode'),
              isExpanded: true,
              initialValue: controller.amountIsTotal,
              decoration: const InputDecoration(labelText: 'Valor informado'),
              items: const [
                DropdownMenuItem(value: true, child: Text('Valor total')),
                DropdownMenuItem(value: false, child: Text('Valor por parcela'))
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.change(() => controller.amountIsTotal = value);
                }
              }),
        AnimatedBuilder(
            animation: Listenable.merge(
                [controller.count, controller.interval, amount]),
            builder: (context, _) {
              try {
                final plan = controller.plan!;
                final amounts = plan.amounts(MoneyMinor.parse(amount.text));
                final last = plan.dateAt(dueDate, plan.count - 1);
                final total = amounts.fold(0, (sum, value) => sum + value);
                return Text(
                    '${plan.count} ocorrências pendentes · Total: ${MoneyMinor.display(total, currencyCode)}'
                    '\nPrimeira: ${MoneyMinor.display(amounts.first, currencyCode)}'
                    '${amounts.last != amounts.first ? ' · Última: ${MoneyMinor.display(amounts.last, currencyCode)}' : ''}'
                    '\nÚltimo vencimento: ${last.day.toString().padLeft(2, '0')}/${last.month.toString().padLeft(2, '0')}/${last.year}');
              } on FormatException {
                return const Text(
                    'Informe valor, quantidade e intervalo para conferir a série.');
              }
            }),
        Text(cardMode
            ? 'Parcelas mensais. O pagamento será registrado pela fatura.'
            : 'As ocorrências serão criadas como pendentes. Você efetiva cada uma quando acontecer.'),
      ],
    ]);
  }
}

Future<SeriesScope?> chooseSeriesScope(BuildContext context,
        {required bool deleting}) =>
    showDialog<SeriesScope>(
        context: context,
        builder: (dialog) => AlertDialog(
              title:
                  Text(deleting ? 'Excluir ocorrência' : 'Editar ocorrência'),
              content: const Text(
                  'A ação em série preserva as anteriores e as já efetivadas, incluindo efetivações agendadas.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('Cancelar')),
                TextButton(
                    onPressed: () =>
                        Navigator.pop(dialog, SeriesScope.onlyThis),
                    child: const Text('Somente esta')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(dialog, SeriesScope.thisAndNext),
                    child: const Text('Esta e as próximas'))
              ],
            ));
