import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/series/movement_series.dart';
import '../../../core/series/series_form.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/effectuation_feedback.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../../core/widgets/movement_list_row.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/money_minor.dart';
import '../../attachments/presentation/attachments_page.dart';
import '../../transactions/domain/movement_management.dart';
import '../domain/transfer.dart';
import '../domain/transfers_repository.dart';
import 'transfers_page.dart';

/// A transferência é exibida uma vez e continua usando seu formulário próprio.
class TransferFeedRow extends StatefulWidget {
  const TransferFeedRow(
      {super.key,
      required this.item,
      required this.accounts,
      required this.repository,
      required this.onChanged});
  final Transfer item;
  final List<Account> accounts;
  final TransfersRepository repository;
  final Future<void> Function() onChanged;
  @override
  State<TransferFeedRow> createState() => _TransferFeedRowState();
}

class _TransferFeedRowState extends State<TransferFeedRow> {
  bool busy = false;
  Future<void> run(Future<void> Function() action) async {
    if (!mounted || busy) return;
    setState(() => busy = true);
    try {
      await action();
      await widget.onChanged();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is FormatException
                ? error.message
                : 'Não foi possível salvar a transferência.')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit() async {
    if (!mounted || busy) return;
    final item = widget.item;
    final scope = item.series == null
        ? SeriesScope.onlyThis
        : await chooseSeriesScope(context, deleting: false);
    if (!mounted || scope == null) return;
    final draft = await showMovementForm<TransferDraft>(
        context,
        (_) =>
            TransferForm(item: item, scope: scope, accounts: widget.accounts));
    if (!mounted || draft == null) return;
    await run(() async {
      await widget.repository.update(item.id, draft);
    });
  }

  Future<void> effective() async {
    final item = widget.item, repository = widget.repository;
    final today = DateUtils.dateOnly(DateTime.now());
    final changed = widget.onChanged;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Future<void> change(DateTime? date) async {
      try {
        await repository.changeEffectiveDate(item.id,
            expectedDate: today, effectiveDate: date);
        await changed();
      } catch (_) {
        if (messenger.mounted) {
          messenger.showSnackBar(const SnackBar(
              content: Text('Não foi possível alterar a efetivação.')));
        }
      }
    }

    await run(() async {
      await repository.setEffective(item.id,
          effective: true, effectiveDate: today);
      if (!mounted) return;
      showEffectuationFeedback(context,
          message: 'Transferência efetivada hoje.',
          undo: () => change(item.effectiveDate),
          adjustDate: () async {
            if (!navigator.mounted) return;
            final chosen = await showDatePicker(
                context: navigator.context,
                initialDate: today,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100, 12, 31));
            if (chosen != null) await change(chosen);
          });
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MovementListRow(
      id: 'transfer:${item.id}',
      description: item.description,
      account: '${item.sourceAccountName} → ${item.destinationAccountName}',
      amount: MoneyMinor.display(item.amountMinor, item.currencyCode)
          .replaceAllMapped(RegExp(r'\d{1,3}(?=(\d{3})+,)'), (m) => '${m[0]}.'),
      dueDate: item.dueDate ?? item.date,
      effectiveDate: item.effectiveDate,
      effective: item.isEffective,
      color: SomiaColors.blue,
      busy: busy,
      leadingIcon: Icons.swap_horiz,
      highlightLabel: 'Transferência',
      tags: [if (item.series != null) item.series!.label],
      onEdit: edit,
      onAmount: edit,
      onEffective: effective,
      onPending: item.effectiveDate == null
          ? null
          : () => run(() => widget.repository
              .changeEffectiveDate(item.id, expectedDate: item.effectiveDate!)),
      onAttachments: () =>
          showAttachments(context, MovementReference.transfer(item)),
      menu: PopupMenuButton<String>(
          enabled: !busy,
          onSelected: (value) {
            if (value == 'edit') {
              edit();
            } else {
              context.go('/transfers');
            }
          },
          itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'edit', child: Text('Editar transferência')),
                PopupMenuItem(value: 'all', child: Text('Ver transferências')),
              ]),
    );
  }
}
