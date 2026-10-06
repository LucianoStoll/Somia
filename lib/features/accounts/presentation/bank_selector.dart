import 'package:flutter/material.dart';

import '../../../core/widgets/movement_form_frame.dart';
import '../domain/bank_institution.dart';
import 'account_identity.dart';

Future<String?> showBankSelector(BuildContext context, String? selected) =>
    showMovementForm<String>(context, (_) => BankSelector(selected: selected));

class BankSelector extends StatefulWidget {
  const BankSelector({super.key, this.selected});
  final String? selected;

  @override
  State<BankSelector> createState() => _BankSelectorState();
}

class _BankSelectorState extends State<BankSelector> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = BankInstitution.search(_query);
    final content = Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          decoration: const InputDecoration(
              labelText: 'Buscar banco', prefixIcon: Icon(Icons.search)),
          onChanged: (value) => setState(() => _query = value),
        ),
      ),
      Expanded(
          child: ListView(children: [
        ListTile(
          leading: const AccountAvatar(),
          title: const Text('Sem instituição / ícone padrão'),
          subtitle: const Text('Dinheiro, carteira ou banco ausente'),
          trailing: widget.selected == null ? const Icon(Icons.check) : null,
          onTap: () => Navigator.pop(context, ''),
        ),
        if (results.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child:
                Text('Nenhum banco encontrado. Você pode usar o ícone padrão.'),
          ),
        for (final bank in results)
          ListTile(
            key: ValueKey('bank-${bank.id}'),
            leading: AccountAvatar(institutionId: bank.id),
            title: Text(bank.name),
            trailing:
                widget.selected == bank.id ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, bank.id),
          ),
      ])),
    ]);
    if (usesFullScreenMovementForm(context)) {
      return Scaffold(
          appBar: AppBar(title: const Text('Escolher instituição')),
          body: SafeArea(child: content));
    }
    return AlertDialog(
      title: const Text('Escolher instituição'),
      content: SizedBox(width: 480, height: 420, child: content),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'))
      ],
    );
  }
}
