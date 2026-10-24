import 'package:flutter/material.dart';

import '../filters/reference_month.dart';

const monthNames = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

class MonthSelector extends StatelessWidget {
  const MonthSelector(
      {super.key,
      required this.month,
      required this.onChanged,
      this.compact = false,
      this.header = false,
      this.arrows = true,
      this.centered = false});
  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  final bool compact;
  final bool header;
  final bool arrows;
  final bool centered;

  Future<void> _choose(BuildContext context) async {
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (_) => _MonthDialog(month: month),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment:
                centered ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              if (arrows)
                IconButton(
                    tooltip: 'Mês anterior',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () =>
                        onChanged(DateTime(month.year, month.month - 1))),
              Flexible(
                  child: TextButton(
                onPressed: () => _choose(context),
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: centered
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      if (!header)
                        const Icon(Icons.calendar_month_outlined, size: 18),
                      if (!compact || header) ...[
                        if (!header) const SizedBox(width: 8),
                        Flexible(
                            child: Text(
                                '${header ? monthNames[month.month - 1].substring(0, 3) : monthNames[month.month - 1]} ${month.year}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                        if (!header) const Icon(Icons.expand_more, size: 18),
                      ],
                    ]),
              )),
              if (arrows)
                IconButton(
                    tooltip: 'Próximo mês',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () =>
                        onChanged(DateTime(month.year, month.month + 1))),
            ]),
      );
}

class _MonthDialog extends StatefulWidget {
  const _MonthDialog({required this.month});
  final DateTime month;
  @override
  State<_MonthDialog> createState() => _MonthDialogState();
}

class _MonthDialogState extends State<_MonthDialog> {
  late int _year = widget.month.year;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Escolher mês'),
        content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  IconButton(
                      tooltip: 'Ano anterior',
                      icon: const Icon(Icons.chevron_left),
                      onPressed:
                          _year > 2000 ? () => setState(() => _year--) : null),
                  Expanded(
                      child: Center(
                          child: Text('$_year',
                              style: Theme.of(context).textTheme.titleLarge))),
                  IconButton(
                      tooltip: 'Próximo ano',
                      icon: const Icon(Icons.chevron_right),
                      onPressed:
                          _year < 2100 ? () => setState(() => _year++) : null),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (var i = 0; i < monthNames.length; i++)
                    SizedBox(
                        width: 96,
                        child: TextButton(
                          style: TextButton.styleFrom(
                              backgroundColor: widget.month.year == _year &&
                                      widget.month.month == i + 1
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : null),
                          onPressed: () =>
                              Navigator.pop(context, DateTime(_year, i + 1)),
                          child:
                              Text(monthNames[i], textAlign: TextAlign.center),
                        )),
                ]),
              ],
            ))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(
                  context, ReferenceMonth.monthOnly(DateTime.now())),
              child: const Text('Mês atual')),
        ],
      );
}
