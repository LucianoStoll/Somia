import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MovementTag {
  const MovementTag(this.label, this.color);
  final String label;
  final Color color;
}

/// Áreas de toque separadas para status, edição, valor e menu.
class MovementListRow extends StatelessWidget {
  const MovementListRow({
    super.key,
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
    this.leadingIcon,
    this.pendingIcon = Icons.radio_button_unchecked,
    this.busy = false,
    this.onAmount,
    this.onAttachments,
    this.detailsBuilder,
    this.onPending,
    this.effectiveLabel = 'Efetivar hoje',
    this.pendingLabel = 'Marcar como pendente',
  });
  final String id, description, account, amount, effectiveLabel, pendingLabel;
  final DateTime dueDate;
  final DateTime? effectiveDate;
  final bool effective, busy;
  final Color color;
  final List<String> tags;
  final List<MovementTag> categoryTags;
  final String? highlightLabel;
  final IconData? leadingIcon;
  final IconData pendingIcon;
  final VoidCallback onEdit, onEffective;
  final VoidCallback? onAmount, onPending, onAttachments;
  final Widget menu;
  final WidgetBuilder? detailsBuilder;

  String _date(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  Future<void> _details(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheet) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(description, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(
                amount,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 16),
              Text(account),
              if (highlightLabel != null) Text(highlightLabel!),
              const SizedBox(height: 8),
              Text(
                effective
                    ? 'Efetivado'
                    : effectiveDate != null
                        ? 'Agendado'
                        : 'Previsto',
              ),
              Text('Vencimento: ${_date(dueDate)}'),
              if (effectiveDate != null)
                Text('Efetivação: ${_date(effectiveDate!)}'),
              for (final category in categoryTags)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    category.label,
                    style: TextStyle(color: category.color),
                  ),
                ),
              for (final tag in tags)
                Padding(
                    padding: const EdgeInsets.only(top: 8), child: Text(tag)),
              if (detailsBuilder != null) detailsBuilder!(sheet),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        Navigator.pop(sheet);
                        onEdit();
                      },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar lançamento'),
              ),
              if (onAttachments != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(sheet);
                    onAttachments!();
                  },
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Anexos'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(sheet),
                child: const Text('Fechar'),
              ),
            ],
          ),
        ),
      );

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final status = effective
        ? 'Efetivado'
        : effectiveDate != null
            ? 'Agendado'
            : 'Pendente';
    final statusColor = effective ? SomiaColors.green : SomiaColors.yellow;
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
        disabledBackgroundColor: statusColor.withValues(alpha: 0.12),
      ),
      icon: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              effective
                  ? Icons.check_circle_outline
                  : effectiveDate != null
                      ? Icons.schedule
                      : pendingIcon,
              color: statusColor,
              size: 22,
            ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 2),
        Text(
          account,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: SomiaColors.muted, fontSize: 12),
        ),
        if (highlightLabel != null) ...[
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: SomiaColors.blue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              highlightLabel!,
              style: const TextStyle(color: SomiaColors.sidebar, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
    Widget badge(MovementTag tag) => Tooltip(
          message: tag.label,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: tag.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              tag.label,
              style: TextStyle(fontSize: 11, color: tag.color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
    final labels = <Widget>[
      if (categoryTags.isNotEmpty) ...[
        const SizedBox(height: 5),
        Row(
          children: [
            for (var index = 0; index < categoryTags.length; index++) ...[
              if (index > 0) const SizedBox(width: 5),
              Flexible(child: badge(categoryTags[index])),
            ],
          ],
        ),
      ],
      if (tags.isNotEmpty) ...[
        const SizedBox(height: 5),
        Wrap(
          spacing: 5,
          runSpacing: 4,
          children: [
            for (final tag in tags) badge(MovementTag(tag, SomiaColors.muted)),
          ],
        ),
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
                child: Text(
                  _date(effectiveDate ?? dueDate),
                  style: const TextStyle(
                    fontSize: 11,
                    color: SomiaColors.muted,
                  ),
                ),
              ),
              Text(
                amount,
                softWrap: true,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (MediaQuery.sizeOf(context).width < 600) {
      final edit = InkWell(
        key: ValueKey('movement-edit-$id'),
        onTap: busy ? null : () => _details(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                account,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: SomiaColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(15) / 15;
                  final amountWidth = _textWidth(
                    context,
                    amount,
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  );
                  final rightWidth = amountWidth
                      .clamp(
                        92.0,
                        (constraints.maxWidth * 0.42).clamp(92.0, 180.0),
                      )
                      .toDouble();
                  final compact = constraints.maxWidth < 340 || scale > 1.3;
                  final badgeColor = effective
                      ? SomiaColors.green
                      : effectiveDate != null
                          ? SomiaColors.blue
                          : SomiaColors.purple;
                  final leadingButton = IconButton(
                    key: ValueKey('movement-status-$id'),
                    tooltip: statusButton.tooltip,
                    onPressed: statusButton.onPressed,
                    icon: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(leadingIcon ?? pendingIcon, color: color),
                    style: IconButton.styleFrom(
                      backgroundColor: color.withValues(alpha: 0.16),
                      minimumSize: const Size(44, 44),
                    ),
                  );
                  final amountButton = Semantics(
                    button: true,
                    label: 'Valor $amount',
                    child: InkWell(
                      key: ValueKey('movement-amount-$id'),
                      onTap: busy ? null : onAmount ?? onEdit,
                      child: Tooltip(
                        message: 'Vencimento ${_date(dueDate)}',
                        child: Text(
                          amount,
                          maxLines: compact ? 2 : 1,
                          softWrap: true,
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: color,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  );
                  final badge = Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                  if (compact) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            leadingButton,
                            const SizedBox(width: 6),
                            Expanded(child: edit),
                            menu,
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [amountButton, badge],
                          ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      leadingButton,
                      const SizedBox(width: 6),
                      Expanded(child: edit),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: rightWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            amountButton,
                            const SizedBox(height: 7),
                            badge,
                          ],
                        ),
                      ),
                      menu,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                statusButton,
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final amountWidth = _textWidth(
                        context,
                        amount,
                        const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                      final dateWidth = _textWidth(
                        context,
                        _date(effectiveDate ?? dueDate),
                        const TextStyle(fontSize: 11),
                      );
                      final valueWidth =
                          (amountWidth > dateWidth ? amountWidth : dateWidth) +
                              2;
                      final stacked = constraints.maxWidth < 210 ||
                          MediaQuery.textScalerOf(context).scale(14) > 21 ||
                          valueWidth > constraints.maxWidth * 0.65;
                      final edit = InkWell(
                        key: ValueKey('movement-edit-$id'),
                        onTap: busy ? null : () => _details(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: details,
                        ),
                      );
                      if (stacked) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [edit, value, ...labels],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: edit),
                              const SizedBox(width: 8),
                              SizedBox(width: valueWidth, child: value),
                            ],
                          ),
                          ...labels,
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 4),
                menu,
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
        ],
      ),
    );
  }
}
