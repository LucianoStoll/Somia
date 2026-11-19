import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/monetary_calculator.dart';
import '../../accounts/domain/money_minor.dart';
import '../../transactions/domain/financial_transaction.dart';
import '../domain/debt.dart';

/// Em "Mais opções" de uma despesa nova: vincula a despesa a uma dívida
/// já ao lançar, com a amortização (principal) desta parcela.
class DebtLinkEditor extends StatefulWidget {
  const DebtLinkEditor({
    super.key,
    required this.repo,
    required this.amountMinor,
    required this.onChanged,
  });
  final DebtsRepository repo;

  /// Valor atual da despesa, para mostrar juros e encargos.
  final int amountMinor;
  final ValueChanged<DebtLinkDraft?> onChanged;

  @override
  State<DebtLinkEditor> createState() => _DebtLinkEditorState();
}

class _DebtLinkEditorState extends State<DebtLinkEditor> {
  final _principal = TextEditingController(text: '0,00');
  bool _enabled = false;
  bool _loading = false;
  List<Debt>? _debts;
  String? _debtId;

  @override
  void initState() {
    super.initState();
    _principal.addListener(_emit);
  }

  @override
  void dispose() {
    _principal.dispose();
    super.dispose();
  }

  int get _principalMinor {
    try {
      return MoneyMinor.parse(_principal.text);
    } catch (_) {
      return 0;
    }
  }

  void _emit() {
    if (mounted) setState(() {});
    widget.onChanged(_enabled && _debtId != null
        ? DebtLinkDraft(debtId: _debtId!, principalMinor: _principalMinor)
        : null);
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    if (value && _debts == null) {
      setState(() => _loading = true);
      try {
        final debts = (await widget.repo.load())
            .where((d) => d.projectedMinor > 0)
            .toList();
        if (!mounted) return;
        setState(() {
          _debts = debts;
          _debtId = debts.length == 1 ? debts.single.id : null;
        });
      } catch (_) {
        if (mounted) setState(() => _debts = const []);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
    _emit();
  }

  String _money(int minor) => MoneyMinor.display(minor, 'BRL')
      .replaceAllMapped(RegExp(r'\d{1,3}(?=(\d{3})+,)'), (m) => '${m[0]}.');

  @override
  Widget build(BuildContext context) {
    final t = context.somia;
    final debts = _debts ?? const <Debt>[];
    final selected = debts.where((d) => d.id == _debtId).firstOrNull;
    final charges = widget.amountMinor - _principalMinor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('transaction-debt-link'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Vincular a uma dívida'),
          subtitle: const Text('A amortização reduz o saldo da dívida.'),
          value: _enabled,
          onChanged: _toggle,
        ),
        if (_enabled && _loading) const LinearProgressIndicator(),
        if (_enabled && !_loading && debts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
                'Nenhuma dívida com saldo. Cadastre em Patrimônio › Dívidas.',
                style: TextStyle(color: t.muted)),
          ),
        if (_enabled && !_loading && debts.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('transaction-debt-select'),
            initialValue: _debtId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Dívida'),
            items: [
              for (final d in debts)
                DropdownMenuItem(
                    value: d.id,
                    child: Text(d.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (value) {
              _debtId = value;
              _emit();
            },
          ),
          const SizedBox(height: 12),
          MonetaryCalculatorField(
            key: const ValueKey('transaction-debt-principal'),
            controller: _principal,
            labelText: 'Amortização (principal)',
            minimumMinor: 0,
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (selected != null)
                'Pode amortizar até ${_money(selected.projectedMinor)}.',
              if (widget.amountMinor > 0)
                charges >= 0
                    ? 'Juros e encargos ${_money(charges)}.'
                    : 'A amortização passa do valor da despesa.',
            ].join(' '),
            style: TextStyle(
                fontSize: 12, color: charges < 0 ? t.expense : t.muted),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
