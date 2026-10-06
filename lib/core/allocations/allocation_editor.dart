import 'package:flutter/material.dart';

import '../../features/categories/domain/category.dart';
import '../../features/accounts/domain/money_minor.dart';
import '../widgets/monetary_calculator.dart';
import 'category_allocation.dart';

class AllocationEditor extends StatefulWidget {
  const AllocationEditor({
    super.key,
    required this.categories,
    required this.type,
    required this.total,
    required this.initial,
    required this.onChanged,
    this.currencyCode = 'BRL',
  });
  final List<FinanceCategory> categories;
  final String type;
  final int total;
  final String currencyCode;
  final List<CategoryAllocation> initial;
  final ValueChanged<List<CategoryAllocation>> onChanged;
  @override
  State<AllocationEditor> createState() => _AllocationEditorState();
}

class _AllocationEditorState extends State<AllocationEditor> {
  bool percentage = false;
  late final List<_Part> rows;
  late final Set<String> historical;
  @override
  void initState() {
    super.initState();
    percentage = widget.initial.isNotEmpty &&
        widget.initial.every((p) => p.percentageBasisPoints != null);
    historical = widget.initial.map((p) => p.categoryId).toSet();
    rows = widget.initial.isEmpty
        ? [_Part(null, 0), _Part(null, 0)]
        : [
            for (final p in widget.initial)
              _Part(p.categoryId,
                  percentage ? p.percentageBasisPoints! : p.amountMinor)
          ];
    for (final r in rows) {
      r.value.addListener(changed);
    }
  }

  @override
  void didUpdateWidget(AllocationEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.total != widget.total) {
      try {
        widget.onChanged(parts);
      } on FormatException {
        widget.onChanged(weights);
      }
    }
  }

  @override
  void dispose() {
    for (final r in rows) {
      r.value.dispose();
    }
    super.dispose();
  }

  int _parse(String text) {
    try {
      return MoneyMinor.parse(text);
    } on FormatException {
      return 0;
    }
  }

  List<CategoryAllocation> get weights => [
        for (final r in rows)
          CategoryAllocation(r.category ?? '', _parse(r.value.text),
              percentageBasisPoints: percentage ? _parse(r.value.text) : null),
      ];
  List<CategoryAllocation> get parts =>
      percentage && weights.fold(0, (s, p) => s + p.amountMinor) == 10000
          ? CategoryAllocation.distribute(weights, widget.total)
          : weights;
  void changed() {
    try {
      widget.onChanged(parts);
    } on FormatException {
      widget.onChanged(weights);
    }
    setState(() {});
  }

  String? error() {
    try {
      for (final r in rows) {
        MoneyMinor.parse(r.value.text);
      }
      if (percentage && weights.fold(0, (s, p) => s + p.amountMinor) != 10000) {
        return 'Os percentuais devem somar 100%.';
      }
      CategoryAllocation.validate(parts, widget.total);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  @override
  Widget build(BuildContext context) => FormField<void>(
        validator: (_) => error(),
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Por valor')),
                ButtonSegment(value: true, label: Text('Por percentual')),
              ],
              selected: {percentage},
              onSelectionChanged: (v) {
                try {
                  final converted = CategoryAllocation.distribute(
                    weights,
                    v.first ? 10000 : widget.total,
                  );
                  for (var i = 0; i < rows.length; i++) {
                    rows[i].value.text =
                        MoneyMinor.plain(converted[i].amountMinor);
                  }
                } on FormatException {
                  for (final r in rows) {
                    r.value.text = '0,00';
                  }
                }
                percentage = v.first;
                changed();
              },
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < rows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(rows[i]),
                      isExpanded: true,
                      initialValue: rows[i].category,
                      decoration: InputDecoration(
                        labelText: 'Categoria da parte ${i + 1}',
                      ),
                      items: [
                        for (final c in widget.categories.where(
                          (c) =>
                              c.type.name == widget.type &&
                              (!c.isArchived || historical.contains(c.id)) &&
                              (c.parentId == null ||
                                  widget.categories.any(
                                    (p) =>
                                        p.id == c.parentId &&
                                        (!p.isArchived ||
                                            historical.contains(c.id)),
                                  )),
                        ))
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              c.parentId == null
                                  ? c.name
                                  : '${widget.categories.where((p) => p.id == c.parentId).first.name} / ${c.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        rows[i].category = v;
                        changed();
                      },
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: percentage
                              ? TextFormField(
                                  controller: rows[i].value,
                                  decoration: const InputDecoration(
                                    labelText: 'Percentual (%)',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                )
                              : MonetaryCalculatorField(
                                  controller: rows[i].value,
                                  labelText: 'Valor da parte ${i + 1}',
                                  currencyCode: widget.currencyCode,
                                ),
                        ),
                        IconButton(
                          tooltip: 'Remover parte',
                          onPressed: rows.length <= 2
                              ? null
                              : () {
                                  final r = rows.removeAt(i);
                                  r.value.dispose();
                                  changed();
                                },
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            Text(
              percentage
                  ? 'Distribuído: ${MoneyMinor.plain(weights.fold(0, (s, p) => s + p.amountMinor))}% / 100%'
                  : 'Distribuído: ${MoneyMinor.display(weights.fold(0, (s, p) => s + p.amountMinor), widget.currencyCode)} / ${MoneyMinor.display(widget.total, widget.currencyCode)}',
            ),
            if (field.hasError)
              Text(
                field.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: rows.length >= 100
                      ? null
                      : () {
                          final r = _Part(null, 0);
                          r.value.addListener(changed);
                          rows.add(r);
                          changed();
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar parte'),
                ),
                if (!percentage)
                  TextButton(
                    onPressed: () {
                      try {
                        final scaled = CategoryAllocation.distribute(
                          weights,
                          widget.total,
                        );
                        for (var i = 0; i < rows.length; i++) {
                          rows[i].value.text = MoneyMinor.plain(
                            scaled[i].amountMinor,
                          );
                        }
                        changed();
                      } on FormatException catch (e) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    },
                    child: const Text('Redistribuir pelo total'),
                  ),
              ],
            ),
          ],
        ),
      );
}

class _Part {
  _Part(this.category, int amount)
      : value = TextEditingController(text: MoneyMinor.plain(amount));
  String? category;
  final TextEditingController value;
}
