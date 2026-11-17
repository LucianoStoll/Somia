import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
  Widget build(BuildContext context) {
    final t = context.somia;
    Widget arrow(String tooltip, IconData icon, int delta) => SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            tooltip: tooltip,
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              foregroundColor: t.ink,
              shape: CircleBorder(side: BorderSide(color: t.outline)),
            ),
            icon: Icon(icon, size: 20),
            onPressed: () =>
                onChanged(DateTime(month.year, month.month + delta)),
          ),
        );
    final label = TextButton(
      onPressed: () => _choose(context),
      style: TextButton.styleFrom(
        foregroundColor: t.ink,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: arrows
            ? const StadiumBorder()
            : StadiumBorder(side: BorderSide(color: t.outline)),
        textStyle: const TextStyle(
            fontFamily: somiaFontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700),
      ),
      child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment:
              centered ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            if (!header)
              Icon(Icons.calendar_month_outlined, size: 18, color: t.muted),
            if (!compact || header) ...[
              if (!header) const SizedBox(width: 8),
              Flexible(
                  child: Text(
                      '${header ? monthNames[month.month - 1].substring(0, 3) : monthNames[month.month - 1]} ${month.year}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              if (!header) Icon(Icons.expand_more, size: 18, color: t.muted),
            ],
          ]),
    );
    return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            centered ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          if (arrows) arrow('Mês anterior', Icons.chevron_left, -1),
          if (arrows) const SizedBox(width: 2),
          Flexible(child: label),
          if (arrows) const SizedBox(width: 2),
          if (arrows) arrow('Próximo mês', Icons.chevron_right, 1),
        ]);
  }
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
