import 'package:flutter/material.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../../core/widgets/monetary_calculator.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../accounts/domain/money_minor.dart';
import '../domain/credit_card.dart';
import '../domain/cashback_calculator.dart';
import 'card_forms.dart';

class PaymentCoverageForm extends StatefulWidget {
  const PaymentCoverageForm(
      {super.key,
      required this.payment,
      required this.entries,
      required this.available,
      required this.selected});
  final CardPayment payment;
  final List<CardEntry> entries;
  final Map<String, int> available, selected;
  @override
  State<PaymentCoverageForm> createState() => _PaymentCoverageFormState();
}

class _PaymentCoverageFormState extends State<PaymentCoverageForm> {
  final form = GlobalKey<FormState>();
  final controllers = <String, TextEditingController>{};
  @override
  void initState() {
    super.initState();
    for (final e in widget.available.entries.where((e) => e.value > 0)) {
      controllers[e.key] = TextEditingController(
          text: MoneyMinor.plain(widget.selected[e.key] ?? 0));
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void save() {
    if (!form.currentState!.validate()) return;
    try {
      final chosen = {
        for (final e in controllers.entries)
          if (MoneyMinor.parse(e.value.text) > 0)
            e.key: MoneyMinor.parse(e.value.text)
      };
      validatePaymentCoverage(
          paymentMinor: widget.payment.amountMinor,
          allocationByEntry: chosen,
          availableByEntry: widget.available);
      Navigator.pop(context, chosen);
    } catch (e) {
      cardError(
          context, e is ArgumentError ? StateError(e.message.toString()) : e);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      value: () => [for (final c in controllers.values) c.text],
      builder: (context, cancel) => MovementFormFrame(
          title: 'Compras cobertas',
          onSave: save,
          onCancel: cancel,
          saveLabel: 'Salvar cobertura',
          child: Form(
              key: form,
              child: Column(spacing: 16, children: [
                Text(
                    'Pagamento ${cardMoney(widget.payment.amountMinor)} · ${cardDateLabel(widget.payment.date)}'),
                const Text(
                    'Conta, data e valor do pagamento permanecem iguais. Informe quanto dele cobriu cada compra; o restante pode cobrir dívida anterior ou encargos.'),
                if (widget.selected.keys
                    .any((id) => !controllers.containsKey(id)))
                  const Text(
                      'A cobertura anterior de compras movidas ou removidas será retirada ao salvar esta nova seleção.'),
                for (final e in widget.entries
                    .where((e) => controllers.containsKey(e.id)))
                  MonetaryCalculatorField(
                      controller: controllers[e.id]!,
                      labelText:
                          '${e.description} · até ${cardMoney(widget.available[e.id]!)}',
                      currencyCode: 'BRL',
                      minimumMinor: 0),
                if (controllers.isEmpty)
                  const Text('Nenhuma compra elegível nesta fatura.'),
              ]))));
}
