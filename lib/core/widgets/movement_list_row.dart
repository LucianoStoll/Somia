import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MovementTag {
  const MovementTag(this.label, this.color);
  final String label;
  final Color color;
}

/// Áreas de toque separadas para status, edição, valor e menu.
class MovementListRow extends StatelessWidget {
  const MovementListRow(
      {super.key,
      required this.id,
      required this.description,
      required this.account,
      required this.amount,
      required this.dueDate,
      required this.effectiveDate,
      required this.effective,
      required this.color,
      required this.onEdit,
      required this.onEffective,
      required this.menu,
      this.tags = const [],
      this.categoryTags = const [],
      this.highlightLabel,
      this.pendingIcon = Icons.radio_button_unchecked,
      this.busy = false,
      this.onAmount,
      this.onPending,
      this.effectiveLabel = 'Efetivar hoje',
      this.pendingLabel = 'Marcar como pendente'});
  final String id, description, account, amount, effectiveLabel, pendingLabel;
  final DateTime dueDate;
  final DateTime? effectiveDate;
  final bool effective, busy;
  final Color color;
  final List<String> tags;
  final List<MovementTag> categoryTags;
  final String? highlightLabel;
  final IconData pendingIcon;
  final VoidCallback onEdit, onEffective;
  final VoidCallback? onAmount, onPending;
  final Widget menu;

  String _date(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  @override
  Widget build(BuildContext context) {
    final status = effective
        ? 'Efetivado'
        : effectiveDate != null
            ? 'Agendado'
            : 'Pendente';
    final statusColor = effective ? color : SomiaColors.yellow;
    final statusButton = IconButton(
      key: ValueKey('movement-status-$id'),
      tooltip: busy
          ? 'Salvando'
          : effective
              ? (onPending == null ? status : pendingLabel)
              : effectiveLabel,
      onPressed: busy
          ? null
          : effective
              ? onPending
              : onEffective,
      style: IconButton.styleFrom(
          backgroundColor: statusColor.withValues(alpha: 0.12),
          disabledBackgroundColor: statusColor.withValues(alpha: 0.12)),
      icon: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(
              effective
                  ? Icons.check_circle_outline
                  : effectiveDate != null
                      ? Icons.schedule
                      : pendingIcon,
              color: statusColor,
              size: 22),
    );
    final details =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(account,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: SomiaColors.muted, fontSize: 12)),
      const SizedBox(height: 2),
      Text(description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      if (highlightLabel != null) ...[
        const SizedBox(height: 5),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: SomiaColors.blue,
                borderRadius: BorderRadius.circular(12)),
            child: Text(highlightLabel!,
                style:
                    const TextStyle(color: SomiaColors.sidebar, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis)),
      ],
    ]);
    final labels = <Widget>[
      if (tags.isNotEmpty || categoryTags.isNotEmpty) ...[
        const SizedBox(height: 5),
        Wrap(spacing: 5, runSpacing: 4, children: [
          for (final tag in [
            ...categoryTags,
            ...tags.map((label) => MovementTag(label, SomiaColors.muted))
          ])
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: tag.color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(5)),
                child: Text(tag.label,
                    style: TextStyle(fontSize: 11, color: tag.color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis))
        ]),
      ],
    ];
    final value = Semantics(
        button: true,
        label: 'Valor $amount',
        child: InkWell(
            key: ValueKey('movement-amount-$id'),
            onTap: busy ? null : onAmount ?? onEdit,
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Tooltip(
                          message:
                              'Vencimento ${_date(dueDate)}${effectiveDate == null ? '' : ' · $status ${_date(effectiveDate!)}'}',
                          child: Text(_date(effectiveDate ?? dueDate),
                              style: const TextStyle(
                                  fontSize: 11, color: SomiaColors.muted))),
                      Text(amount,
                          softWrap: true,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: color,
                              fontSize: 15)),
                    ]))));
    return Material(
        color: Colors.transparent,
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                statusButton,
                const SizedBox(width: 8),
                Expanded(child: LayoutBuilder(builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 210 ||
                      MediaQuery.textScalerOf(context).scale(14) > 21;
                  final edit = InkWell(
                      key: ValueKey('movement-edit-$id'),
                      onTap: busy ? null : onEdit,
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: details));
                  if (stacked) {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [edit, value, ...labels]);
                  }
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: edit),
                              const SizedBox(width: 12),
                              Expanded(flex: 2, child: value)
                            ]),
                        ...labels
                      ]);
                })),
                const SizedBox(width: 4),
                menu,
              ])),
          const Divider(height: 1, thickness: 0.5),
        ]));
  }
}
